#!/usr/bin/env python3

import json
import logging
import subprocess
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

sys.path.insert(1, '/data/VenusOS-Tailscale/velib_python')
from vedbus import VeDbusService
from settingsdevice import SettingsDevice

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(name)s %(levelname)s: %(message)s',
)
logger = logging.getLogger(__name__)

TAILSCALE_CMD   = '/data/VenusOS-Tailscale/tailscale'
BACKEND_SERVICE = '/service/VenusOS-Tailscale-backend'
STATE_DISABLED   = 0
STATE_STARTING   = 1
STATE_LOGGED_OUT = 2
STATE_LOGIN_WAIT = 3
STATE_CONNECTING = 4
STATE_CONNECTED  = 5
STATE_OFFLINE    = 10
STATE_ERROR      = 20

STATE_TEXTS = {
    STATE_DISABLED:   'Disabled',
    STATE_STARTING:   'Starting',
    STATE_LOGGED_OUT: 'Logged out',
    STATE_LOGIN_WAIT: 'Waiting for login',
    STATE_CONNECTING: 'Connecting',
    STATE_CONNECTED:  'Connected',
    STATE_OFFLINE:    'Offline',
    STATE_ERROR:      'Error',
}

def run_cmd(cmd, timeout=10):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 124, '', 'timeout'
    except Exception as e:
        return -1, '', str(e)


def svc(action, service):
    run_cmd(['svc', action, service], timeout=5)


def backend_running():
    rc, out, _ = run_cmd(['svstat', BACKEND_SERVICE], timeout=5)
    return rc == 0 and ': up ' in out



class TailscaleControl:
    def __init__(self):
        self._state = STATE_DISABLED
        self._pending_auth = False

        self._settings = SettingsDevice(
            bus=dbus.SystemBus(),
            supportedSettings={
                'Enabled':           ['/Settings/Tailscale/Enabled',           0,  0, 1],
                'AuthKey':           ['/Settings/Tailscale/AuthKey',           '', 0, 0],
                'AdvertiseExitNode': ['/Settings/Tailscale/AdvertiseExitNode', 0,  0, 1],
                'LoginServer':       ['/Settings/Tailscale/LoginServer',       '', 0, 0],
                'AcceptRoutes':      ['/Settings/Tailscale/AcceptRoutes',      0,  0, 1],
            },
            eventCallback=self._on_setting_changed,
        )

        version = self._get_tailscale_version()
        self._dbus = VeDbusService('com.victronenergy.tailscale', bus=dbus.SystemBus(), register=False)
        self._dbus.add_path('/Mgmt/ProcessName',    'VenusOS-Tailscale')
        self._dbus.add_path('/Mgmt/ProcessVersion', 'v1.0')
        self._dbus.add_path('/Mgmt/Connection',     'Tailscale VPN')
        self._dbus.add_path('/DeviceInstance',      0)
        self._dbus.add_path('/ProductId',           0xFFFF)
        self._dbus.add_path('/ProductName',         'Tailscale')
        self._dbus.add_path('/FirmwareVersion',     version)
        self._dbus.add_path('/Connected',           0)
        self._dbus.add_path('/State',               STATE_DISABLED)
        self._dbus.add_path('/StateText',           STATE_TEXTS[STATE_DISABLED])
        self._dbus.add_path('/Ip4',                 '')
        self._dbus.add_path('/Ip6',                 '')
        self._dbus.add_path('/HostName',            '')
        self._dbus.add_path('/TailnetName',         '')
        self._dbus.add_path('/KeyExpiry',           '')
        self._dbus.add_path('/LoginLink',           '')
        self._dbus.register()

    def _get_tailscale_version(self):
        rc, out, _ = run_cmd([TAILSCALE_CMD, 'version'], timeout=5)
        if rc == 0:
            return out.strip().split('\n')[0]
        return 'unknown'

    def _set_state(self, state):
        if self._state == state:
            return
        logger.info('State: %s → %s', STATE_TEXTS.get(self._state), STATE_TEXTS.get(state))
        self._state = state
        self._dbus['/State'] = state
        self._dbus['/StateText'] = STATE_TEXTS.get(state, 'Unknown')
        self._dbus['/Connected'] = 1 if state == STATE_CONNECTED else 0

    def _clear_status(self):
        for path in ('/Ip4', '/Ip6', '/HostName', '/TailnetName', '/KeyExpiry', '/LoginLink'):
            self._dbus[path] = ''

    def _on_setting_changed(self, setting, old_value, new_value):
        if setting == 'Enabled':
            self._tick()
        elif setting == 'AdvertiseExitNode':
            if backend_running():
                svc('-t', BACKEND_SERVICE)

    def _build_up_args(self):
        args = [TAILSCALE_CMD, 'up', '--reset=false']
        auth_key = self._settings['AuthKey'].strip()
        if auth_key:
            args.append('--auth-key=' + auth_key)
        login_server = self._settings['LoginServer'].strip()
        if login_server:
            args.append('--login-server=' + login_server)
        if self._settings['AdvertiseExitNode']:
            args.append('--advertise-exit-node')
        if self._settings['AcceptRoutes']:
            args.append('--accept-routes')
        return args

    def _tick(self):
        enabled = int(self._settings['Enabled'])

        if not enabled:
            if backend_running():
                svc('-d', BACKEND_SERVICE)
            self._set_state(STATE_DISABLED)
            self._clear_status()
            self._pending_auth = False
            return

        if not backend_running():
            self._set_state(STATE_STARTING)
            svc('-u', BACKEND_SERVICE)
            return

        rc, out, err = run_cmd([TAILSCALE_CMD, 'status', '--json'], timeout=10)
        if rc != 0:
            logger.warning('tailscale status failed (rc=%d): %s', rc, err)
            self._set_state(STATE_STARTING)
            return

        try:
            status = json.loads(out)
        except json.JSONDecodeError:
            logger.warning('Failed to parse tailscale status JSON')
            self._set_state(STATE_ERROR)
            return

        backend_state = status.get('BackendState', 'NoState')
        auth_url      = status.get('AuthURL') or ''
        self_info     = status.get('Self') or {}
        online        = self_info.get('Online', False)
        ips           = self_info.get('TailscaleIPs') or []
        hostname      = self_info.get('HostName') or ''
        key_expiry    = self_info.get('KeyExpiry') or ''
        tailnet_name  = (status.get('CurrentTailnet') or {}).get('Name') or status.get('MagicDNSSuffix') or ''

        self._dbus['/HostName']   = hostname
        self._dbus['/TailnetName'] = tailnet_name
        self._dbus['/KeyExpiry']  = key_expiry
        self._dbus['/LoginLink']  = auth_url
        self._dbus['/Ip4']        = next((ip for ip in ips if ':' not in ip), '')
        self._dbus['/Ip6']        = next((ip for ip in ips if ':' in ip), '')

        if backend_state in ('NeedsLogin', 'NeedsMachineAuth'):
            self._set_state(STATE_LOGIN_WAIT if auth_url else STATE_LOGGED_OUT)
            auth_key = self._settings['AuthKey'].strip()
            if auth_key and not self._pending_auth:
                self._pending_auth = True
                logger.info('Running tailscale up with auth key')
                rc, _, err = run_cmd(self._build_up_args(), timeout=30)
                if rc != 0:
                    logger.warning('tailscale up failed (rc=%d): %s', rc, err)
                self._pending_auth = False
        elif backend_state == 'Running':
            self._set_state(STATE_CONNECTED if online else STATE_OFFLINE)
            self._pending_auth = False
        elif backend_state in ('Starting', 'NoState'):
            self._set_state(STATE_STARTING)
        elif backend_state == 'Stopped':
            self._set_state(STATE_STARTING)
            svc('-u', BACKEND_SERVICE)
        else:
            self._set_state(STATE_CONNECTING)

    def _on_timer(self):
        try:
            self._tick()
        except Exception:
            logger.exception('Unexpected error in poll loop')
        return True

    def start(self):
        GLib.timeout_add(5000, self._on_timer)
        try:
            self._tick()
        except Exception:
            logger.exception('Error on startup tick')


def main():
    DBusGMainLoop(set_as_default=True)
    controller = TailscaleControl()
    controller.start()
    GLib.MainLoop().run()


if __name__ == '__main__':
    main()
