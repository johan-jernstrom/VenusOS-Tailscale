#!/bin/sh
# VenusOS-Tailscale installer
# Copy this repo to the Venus OS device and run: sh install.sh

set -e

INSTALL_DIR="/data/VenusOS-Tailscale"
STATE_DIR="/data/conf/tailscale"
APP_DIR="/data/apps/available/VenusOS-Tailscale"
SERVICE_BACKEND="/service/VenusOS-Tailscale-backend"
SERVICE_CONTROL="/service/VenusOS-Tailscale"
VELIB="/opt/victronenergy/dbus-systemcalc-py/ext/velib_python"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[VenusOS-Tailscale] $*"; }
die() { log "ERROR: $*"; exit 1; }

# --- Architecture ---
ARCH=$(uname -m)
case "$ARCH" in
    armv7l|armv6l) TS_ARCH="arm" ;;
    aarch64)        TS_ARCH="arm64" ;;
    *) die "Unsupported architecture: $ARCH" ;;
esac
log "Architecture: $ARCH -> Tailscale arch: $TS_ARCH"

# --- Tailscale binary ---
if [ ! -f "$INSTALL_DIR/tailscaled" ]; then
    log "Fetching latest Tailscale version for $TS_ARCH..."
    LATEST_VERSION=$(curl -fsSL "https://pkgs.tailscale.com/stable/" | python3 -c "
import sys, re
html = sys.stdin.read()
pat = r'tailscale_(\d+\.\d+\.\d+)_${TS_ARCH}\.tgz'
versions = re.findall(pat, html)
if not versions:
    sys.exit(1)
print(sorted(versions, key=lambda v: [int(x) for x in v.split('.')])[-1])
") || die "Could not determine latest Tailscale version"

    log "Downloading Tailscale $LATEST_VERSION..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    URL="https://pkgs.tailscale.com/stable/tailscale_${LATEST_VERSION}_${TS_ARCH}.tgz"
    curl -fsSL "$URL" -o "$TMP/tailscale.tgz" || die "Download failed: $URL"
    tar -xzf "$TMP/tailscale.tgz" -C "$TMP"
    EXTRACTED="$TMP/tailscale_${LATEST_VERSION}_${TS_ARCH}"

    mkdir -p "$INSTALL_DIR"
    cp "$EXTRACTED/tailscale"  "$INSTALL_DIR/tailscale"
    cp "$EXTRACTED/tailscaled" "$INSTALL_DIR/tailscaled"
    chmod +x "$INSTALL_DIR/tailscale" "$INSTALL_DIR/tailscaled"
    log "Tailscale $LATEST_VERSION installed"
else
    log "Tailscale binaries already present at $INSTALL_DIR — skipping download"
    log "  Delete them and re-run to upgrade"
fi

# --- Control daemon ---
log "Installing control daemon..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/tailscale_control.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/tailscale_control.py"

# --- velib_python symlink ---
if [ ! -e "$INSTALL_DIR/velib_python" ]; then
    [ -d "$VELIB" ] || die "velib_python not found at $VELIB (Venus OS 3.x required)"
    ln -sfn "$VELIB" "$INSTALL_DIR/velib_python"
fi

# --- State directory ---
mkdir -p "$STATE_DIR"

# --- Daemontools services ---
log "Installing services..."

# backend
mkdir -p "$SERVICE_BACKEND/log"
cp "$SCRIPT_DIR/service/VenusOS-Tailscale-backend/run"     "$SERVICE_BACKEND/run"
cp "$SCRIPT_DIR/service/VenusOS-Tailscale-backend/log/run" "$SERVICE_BACKEND/log/run"
chmod +x "$SERVICE_BACKEND/run" "$SERVICE_BACKEND/log/run"
mkdir -p /var/log/VenusOS-Tailscale-backend

# control
mkdir -p "$SERVICE_CONTROL/log"
cp "$SCRIPT_DIR/service/VenusOS-Tailscale/run"     "$SERVICE_CONTROL/run"
cp "$SCRIPT_DIR/service/VenusOS-Tailscale/log/run" "$SERVICE_CONTROL/log/run"
chmod +x "$SERVICE_CONTROL/run" "$SERVICE_CONTROL/log/run"
mkdir -p /var/log/VenusOS-Tailscale

# --- GUI v2 plugin ---
COMPILER="/opt/victronenergy/gui-v2/gui-v2-plugin-compiler.py"
if [ -f "$COMPILER" ]; then
    log "Installing GUI v2 plugin..."
    mkdir -p "$APP_DIR/gui-v2"
    cp "$SCRIPT_DIR/gui-v2/"*.qml "$APP_DIR/gui-v2/"
    ( cd "$APP_DIR/gui-v2" && \
      python3 "$COMPILER" --name VenusOS-Tailscale \
        --settings VenusOS-Tailscale_PageTailscale.qml ) \
      || log "WARNING: GUI v2 compilation failed — page will not appear in UI"
    mkdir -p /data/apps/enabled
    ln -sfn "$APP_DIR" /data/apps/enabled/VenusOS-Tailscale
    svc -t /service/gui-v2 2>/dev/null || svc -t /service/gui 2>/dev/null || true
    log "GUI v2 plugin installed — open Settings > Integrations > Tailscale"
else
    log "WARNING: GUI v2 compiler not found — GUI installation skipped"
    log "  Configure via D-Bus: dbus -y com.victronenergy.settings /Settings/Tailscale/Enabled SetValue %1"
fi

# --- Start services ---
log "Starting services..."
svc -u "$SERVICE_BACKEND" 2>/dev/null || true
svc -u "$SERVICE_CONTROL" 2>/dev/null || true

log ""
log "Installation complete."
log "  Status:    svstat $SERVICE_CONTROL $SERVICE_BACKEND"
log "  Logs:      tail -F /var/log/VenusOS-Tailscale/current | tai64nlocal"
log "  D-Bus:     dbus -y com.victronenergy.tailscale / GetValue"
log ""
log "Enable via GUI (Settings > Integrations > Tailscale) or:"
log "  dbus -y com.victronenergy.settings /Settings/Tailscale/Enabled SetValue %1"
