# Looped

Record your screen, play it back, trim it, and export a video on your own computer.
Looped runs in your browser and stores recordings on your disk. No account or cloud
storage is required. This repository contains installers and compiled releases.

## Install on Linux

Use a desktop Linux session with systemd, on x86-64 or ARM64. Run this as your normal
user, not as root:

```sh
curl -fsSL https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.sh | bash
```

The installer needs curl and sha256sum. If FFmpeg or ffprobe is missing, it offers to
install FFmpeg through apt, dnf, or pacman with sudo. On other distributions, install
both commands first. Looped starts as a user service and starts again when you sign in.
Open **Looped** in your app launcher or visit <http://localhost:4747>.

The installer asks you to choose a password for Looped. Type it twice. Nothing shows
while you type. Remember it, because you need it to sign in.

## Install on Windows

Use Windows 10 or 11 on x86-64 or ARM64. Open PowerShell as your normal user and run:

```powershell
irm https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.ps1 | iex
```

On x86-64, the installer uses winget to install FFmpeg if needed. Without winget,
install FFmpeg yourself and add its bin directory to PATH. On ARM64, supply compatible
FFmpeg and ffprobe yourself. Open a new PowerShell window after changing PATH.
Looped adds Start menu and sign-in shortcuts. Open **Looped** or visit
<http://localhost:4747>.

The installer asks you to choose a password for Looped. Type it twice. Nothing shows
while you type. Remember it, because you need it to sign in.

Both installers download a release-specific binary, check its SHA-256 checksum and
version, and then replace the installed program. These checks detect corruption or
mixed release files. They do not authenticate a publisher independently of GitHub.

To install without the password prompt, for example from a script, set `LOOPED_PASSWORD`
first. On Linux:

```sh
curl -fsSL https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.sh | LOOPED_PASSWORD='your password' bash
```

On Windows:

```powershell
$env:LOOPED_PASSWORD = 'your password'; irm https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.ps1 | iex
```

The password prompt appears only on a new install. Updates keep the password you already
have, and the installer ignores `LOOPED_PASSWORD` then. If no password can be asked for
and `LOOPED_PASSWORD` is not set, the installer stops and changes nothing.

## Make your first recording

1. Open Looped and sign in with the password you chose during installation.
2. Choose **New recording**, then **Tab** or **Full screen**. Add a microphone or camera if you want them and allow browser access.
3. Choose **Start recording**, then select a source in the browser's sharing dialog.
4. If the browser offers an audio checkbox, enable it to include the shared audio.
5. Use the recording controls to pause, resume, or stop. Keep Looped open until processing finishes.
6. Open the recording to play it. Use the trim editor to remove the ends or cut a section out.
7. Download the video to export the result, then send that file to someone else.

Chrome and Edge offer the fullest recording controls, including the camera bubble
and floating controls. Audio capture depends on your browser, operating system, and
chosen source. Other desktop browsers can record with fewer controls. If the floating
controls appear in a whole-screen recording, close that window and use the Looped tab.

A copied `localhost` link works only on your computer. To send a recording to another
person, export the video file. The local installer binds to `127.0.0.1` and forces
local storage. It does not publish your recordings on the internet.

## Update or install a specific version

Finish active recordings, then rerun the install command. Updates preserve your
recordings, password, session secret, and configured port. If the new version fails
to start, the installer restores the previous executable and startup files.

To pin a release, download its installer rather than the latest installer:

```sh
curl -fsSL https://github.com/mfbaltaza/looped-releases/releases/download/v0.1.2/install.sh | bash
```

```powershell
irm https://github.com/mfbaltaza/looped-releases/releases/download/v0.1.2/install.ps1 | iex
```

Replace `v0.1.2` with the release you want. An installer always uses its own release's
binary and checksums, even if a newer release appears during installation.

## Find your recordings and password

On Linux, recordings and credentials live in `~/.local/share/looped` by default.
If `XDG_DATA_HOME` is set during installation, they live in `$XDG_DATA_HOME/looped`.
The selected path and port are saved in `~/.config/looped/data` and
`~/.config/looped/port`, or under `$XDG_CONFIG_HOME` when set.
The executable is `~/.local/bin/looped`.

On Windows, the executable and launcher live in `%LOCALAPPDATA%\Looped`.
Recordings and credentials live in `%LOCALAPPDATA%\Looped\data`.
`settings.json` in the installation directory records the data path and port.

To see or change your password, open the `password` file inside your data directory.
It holds the password on one line. To change it, edit the file and save it, then restart
Looped. On Linux, run `systemctl --user restart looped`. On Windows, sign out and back in,
or rerun the installer. Keep this file and the session secret private. To back up, stop Looped and copy the
entire data directory to another disk. Restore that directory before starting Looped.
Exported video files can be backed up independently.

## Uninstall

On Linux:

```sh
curl -fsSL https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.sh | bash -s -- --uninstall
```

On Windows:

```powershell
& ([scriptblock]::Create((irm https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.ps1))) -Uninstall
```

Uninstall removes the program and startup integration. It keeps recordings and
credentials. Reinstalling uses the retained data at the default location. If you used
a custom location, save that path before uninstalling and restore the configuration
before starting the app. Delete your data directory yourself only when you no longer
want the recordings or credentials.

## Fix startup or recording problems

If port 4747 is already in use, choose another port on the first installation:

```sh
curl -fsSL https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.sh | LOOPED_PORT=4748 bash
```

```powershell
$env:LOOPED_PORT = '4748'; irm https://github.com/mfbaltaza/looped-releases/releases/latest/download/install.ps1 | iex
```

An update preserves the existing port. Open the address printed by the installer.

On Linux, inspect `systemctl --user status looped` and
`journalctl --user -u looped -n 100`. Use `systemctl --user restart looped` after
repairing dependencies. On Windows, run `%LOCALAPPDATA%\Looped\start.ps1` from
PowerShell to restart the app. If startup still fails, stop the Looped process in
Task Manager and run these commands in PowerShell to see its errors:

```powershell
$env:LOOPED_ADDR = '127.0.0.1:4747'
$env:LOOPED_STORAGE = 'local'
$env:LOOPED_DATA = "$env:LOCALAPPDATA\Looped\data"
& "$env:LOCALAPPDATA\Looped\looped.exe"
```

Use your saved data path and port if you changed them.

If FFmpeg is missing, make both `ffmpeg` and `ffprobe` available on PATH, then rerun
the installer to refresh the startup environment. If capture is blocked, open
`http://localhost`, review browser permissions, and choose a source in the sharing
dialog. Keep the browser open while the video finishes processing. Check free disk
space if recordings or exports fail.

For download or checksum errors, rerun the installer. The previous executable is
retained until the downloaded binary passes verification.
