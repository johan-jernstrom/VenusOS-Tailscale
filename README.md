# VenusOS-Tailscale

A lightweight [Tailscale](https://tailscale.com) integration for [Venus OS](https://github.com/victronenergy/venus) on Raspberry Pi. Enables secure remote access to your Victron GX device via a Tailscale mesh VPN.

**Differences from [TailscaleGX](https://github.com/kwindrem/TailscaleGX):**
- No SetupHelper dependency — one shell script installs everything
- GUI v2 configuration page (Venus OS 3.x+) instead of patched GUI v1
- 5-second poll interval instead of 1-second (lower CPU overhead)
- `-no-logs-no-support` flag disables Tailscale telemetry

## Requirements

- Venus OS 3.x (GUI v2, Raspberry Pi 3B or newer)
- Internet access on the device during installation (to download Tailscale binaries)

## Installation

Copy this repository to the device and run the installer:

```sh
scp -r VenusOS-Tailscale root@<venus-ip>:/data/
ssh root@<venus-ip>
cd /data/VenusOS-Tailscale
sh install.sh
```

The installer will:
1. Download the latest Tailscale ARM binaries from pkgs.tailscale.com
2. Install the control daemon to `/data/VenusOS-Tailscale/`
3. Register two daemontools services (`/service/VenusOS-Tailscale{,-backend}`)
4. Compile and enable the GUI v2 settings page
5. Start both services

## Configuration

Open **Settings → Integrations → Tailscale** in the Venus OS GUI.

| Setting | Description |
|---------|-------------|
| Enable Tailscale | Master on/off switch |
| Auth Key | Pre-generated Tailscale auth key (from tailscale.com/admin) |
| Advertise Exit Node | Route other devices' traffic through this device |
| Accept Routes | Use routes advertised by other exit nodes |
| Custom Login Server | Optional: Headscale or other self-hosted login server URL |

### Authenticating

**Option A — Auth key (recommended for headless setup):**
1. Generate a key at [tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)
2. Paste it into the **Auth Key** field in the GUI
3. Enable Tailscale — the daemon will call `tailscale up` automatically

**Option B — Browser login:**
1. Enable Tailscale with no auth key set
2. A login URL appears in the **Login Link** field
3. Open the URL on any device to authenticate

## Status

The GUI displays the current state:

| State | Meaning |
|-------|---------|
| Disabled | Tailscale is turned off |
| Starting | `tailscaled` backend is launching |
| Logged out | Backend up, no credentials |
| Waiting for login | Awaiting browser authentication |
| Connecting | Credentials accepted, establishing tunnel |
| Connected | Active VPN session |
| Offline | No internet connectivity |
| Error | Unrecoverable error — check logs |

## Uninstallation

```sh
ssh root@<venus-ip>
cd /data/VenusOS-Tailscale
sh uninstall.sh
```

Tailscale state (`/data/conf/tailscale`) and settings are preserved — remove them manually if desired.

## Debugging

```sh
# Service status
svstat /service/VenusOS-Tailscale /service/VenusOS-Tailscale-backend

# Live logs
tail -F /var/log/VenusOS-Tailscale/current | tai64nlocal

# D-Bus status
dbus -y com.victronenergy.tailscale / GetValue

# Tailscale CLI
/data/VenusOS-Tailscale/tailscale status
```

## Architecture

Two daemontools services run on the device:

- **VenusOS-Tailscale-backend** — runs `tailscaled`, the Tailscale VPN daemon
- **VenusOS-Tailscale** — runs the Python control daemon, which:
  - Publishes status to D-Bus as `com.victronenergy.tailscale`
  - Reads persistent settings from `com.victronenergy.settings` (`/Settings/Tailscale/`)
  - Polls `tailscale status --json` every 5 seconds and updates D-Bus paths
  - Starts/stops the backend when Tailscale is enabled/disabled
  - Calls `tailscale up` when an auth key is configured

### D-Bus paths

| Path | Type | Description |
|------|------|-------------|
| `/State` | int | State code |
| `/StateText` | str | Human-readable state |
| `/Connected` | int | 1 when connected |
| `/Ip4` | str | IPv4 address on tailnet |
| `/Ip6` | str | IPv6 address on tailnet |
| `/HostName` | str | Device hostname on tailnet |
| `/TailnetName` | str | Tailnet account name |
| `/KeyExpiry` | str | Auth key expiry date |
| `/LoginLink` | str | Browser login URL |

## Performance notes (Raspberry Pi 3B)

The RPi 3B can run Tailscale but resources are limited:

- Idle overhead: ~72 MB RAM, ~20% CPU
- During VPN data transfer: up to 70% CPU (Go crypto is not optimised for 32-bit ARM)
- Heavy features (exit node, accept routes) are off by default to minimise load
