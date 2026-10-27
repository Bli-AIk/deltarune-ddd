#!/usr/bin/env python3
"""Run a command on a reserved high Xvfb display without touching the desktop.

Usage: python3 .github/scripts/safe-xvfb.py -- command [arguments...]
Based on the reviewed safe-xvfb launcher; normal X11 locks stay enabled.
"""

import fcntl
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time


def occupied(number):
    paths = (f'/tmp/.X{number}-lock', f'/tmp/.X11-unix/X{number}',
             f'/tmp/.X11-unix/X{number}_')
    if any(os.path.lexists(path) for path in paths):
        return True
    # Include abstract sockets, which do not have filesystem directory entries.
    names = {line.split()[-1] for line in Path('/proc/net/unix').read_text().splitlines()[1:]
             if len(line.split()) >= 8}
    return any(path in names or '@' + path in names for path in paths[1:])


def ready(number):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(.2)
            client.connect(f'/tmp/.X11-unix/X{number}')
            client.sendall(struct.pack('<BBHHHHH', ord('l'), 0, 11, 0, 0, 0, 0))
            return client.recv(1) == b'\x01'
    except OSError:
        return False


def stop(_signum, _frame):
    raise SystemExit(0)


def desktop_state():
    sockets = {}
    for path in Path('/tmp/.X11-unix').glob('X*'):
        suffix = path.name[1:].rstrip('_')
        if suffix.isdigit() and int(suffix) < 100:
            stat = path.lstat()
            sockets[str(path)] = (stat.st_dev, stat.st_ino)
    pids = set()
    for process in Path('/proc').glob('[0-9]*'):
        try:
            if (process / 'comm').read_text().strip() == 'Xwayland':
                # Include process start time so a reused PID cannot hide a restart.
                stat = (process / 'stat').read_text().rsplit(')', 1)[1].split()
                pids.add((int(process.name), stat[19]))
        except (OSError, ProcessLookupError):
            pass
    return sockets, pids


def terminate(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def main():
    command = sys.argv[1:]
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise SystemExit('Usage: safe-xvfb.py -- command [arguments...]')
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    before = desktop_state()
    server = child = None
    reservation = Path(tempfile.gettempdir()) / f'codex-xvfb-{os.getuid()}.lock'
    try:
        with reservation.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            number = next((n for n in range(100, 1000) if not occupied(n)), None)
            if number is None:
                raise SystemExit('No unoccupied test display in :100..:999.')
            server = subprocess.Popen(
                ['Xvfb', f':{number}', '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
                stdout=subprocess.DEVNULL)
            deadline = time.monotonic() + 10
            while True:
                try:
                    owns_display = Path(f'/tmp/.X{number}-lock').read_text().strip() == str(server.pid)
                except OSError:
                    owns_display = False
                if server.poll() is not None:
                    raise SystemExit(f'Xvfb :{number} exited during startup.')
                if owns_display and ready(number):
                    break
                if time.monotonic() >= deadline:
                    raise SystemExit(f'Xvfb :{number} did not become ready.')
                time.sleep(.05)
            fcntl.flock(lock, fcntl.LOCK_UN)
        environment = os.environ.copy()
        environment['DISPLAY'] = f':{number}'
        environment.pop('WAYLAND_DISPLAY', None)
        environment['SDL_VIDEODRIVER'] = 'x11'
        child = subprocess.Popen(command, env=environment)
        return child.wait()
    finally:
        terminate(child)
        terminate(server)
        if desktop_state() != before:
            raise SystemExit('Desktop X11 socket identities or Xwayland PIDs changed during the test.')


if __name__ == '__main__':
    sys.exit(main())
