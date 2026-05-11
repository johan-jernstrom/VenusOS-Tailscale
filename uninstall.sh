#!/bin/sh
# VenusOS-Tailscale uninstaller

set -e

INSTALL_DIR="/data/VenusOS-Tailscale"
APP_DIR="/data/apps/available/VenusOS-Tailscale"
SERVICE_BACKEND="/service/VenusOS-Tailscale-backend"
SERVICE_CONTROL="/service/VenusOS-Tailscale"

log() { echo "[VenusOS-Tailscale] $*"; }

log "Stopping services..."
svc -d "$SERVICE_CONTROL"  2>/dev/null || true
svc -d "$SERVICE_BACKEND"  2>/dev/null || true
sleep 2

log "Removing service directories..."
rm -rf "$SERVICE_CONTROL" "$SERVICE_BACKEND"

log "Removing app..."
rm -f /data/apps/enabled/VenusOS-Tailscale
rm -rf "$APP_DIR"
rm -rf "$INSTALL_DIR"

log "Restarting GUI..."
svc -t /service/gui-v2 2>/dev/null || svc -t /service/gui 2>/dev/null || true

log ""
log "Uninstall complete."
log "  Tailscale state preserved at /data/conf/tailscale — remove manually if desired:"
log "    rm -rf /data/conf/tailscale"
log "  Settings preserved in com.victronenergy.settings — remove manually if desired:"
log "    dbus -y com.victronenergy.settings /Settings/Tailscale RemoveSetting"
