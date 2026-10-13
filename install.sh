#!/usr/bin/env bash
set -euo pipefail
main() {
release_tag='v0.1.3' # The release builder stamps this value.
repo=mfbaltaza/looped-releases
base=${LOOPED_RELEASE_BASE:-https://github.com/$repo/releases}
bin=$HOME/.local/bin/looped
data=${XDG_DATA_HOME:-$HOME/.local/share}/looped
config=${XDG_CONFIG_HOME:-$HOME/.config}/looped
unit=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/looped.service
launcher=${XDG_DATA_HOME:-$HOME/.local/share}/applications/Looped.desktop
icon=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/looped.svg
no_start=${LOOPED_NO_START:-0}
die() { printf 'Looped: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Linux ]] || die 'This installer requires Linux.'
if [[ ${1:-} == --uninstall ]]; then
  if [[ $no_start != 1 ]]; then
    systemctl --user disable --now looped.service >/dev/null 2>&1 || true
  fi
  rm -f "$bin" "$unit" "$launcher" "$icon" "$config/port" "$config/data"
  if [[ $no_start != 1 ]]; then systemctl --user daemon-reload; fi
  printf 'Looped removed. Recordings and credentials remain in %s\n' "$data"
  exit 0
fi
[[ $# == 0 ]] || die 'Supported argument: --uninstall'
case $(uname -m) in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; *) die 'Unsupported processor.';; esac
for tool in curl sha256sum; do command -v "$tool" >/dev/null || die "Install $tool first."; done
if [[ $no_start != 1 ]]; then
  command -v systemctl >/dev/null || die 'A systemd user session is required.'
  systemctl --user show-environment >/dev/null || die 'Run this in your desktop user session.'
fi
port=${LOOPED_PORT:-4747}
if [[ -f $config/port ]]; then port=$(cat "$config/port");
elif [[ -f $unit ]]; then
  previous=$(sed -n 's/.*LOOPED_ADDR=127\.0\.0\.1:\([0-9]*\).*/\1/p' "$unit" | head -1)
  port=${previous:-$port}
fi
if [[ -f $config/data ]]; then data=$(cat "$config/data");
elif [[ -f $unit ]]; then
  previous=$(sed -n 's/^Environment=LOOPED_DATA=//p' "$unit" | head -1)
  data=${previous:-$data}
fi
[[ $port =~ ^[0-9]{1,5}$ ]] && ((10#$port > 0 && 10#$port < 65536)) || die 'LOOPED_PORT must be 1 through 65535.'
[[ $data == /* && $HOME == /* && $data != *$'\n'* && $HOME != *$'\n'* ]] || die 'Use absolute paths without newlines.'
pwfile=$data/password
password=
wrote_password=0
trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
if [[ ! -s $pwfile ]]; then
  if [[ -n ${LOOPED_PASSWORD:-} ]]; then
    [[ $LOOPED_PASSWORD != *$'\n'* ]] || die 'LOOPED_PASSWORD must not contain a newline.'
    password=$(trim "$LOOPED_PASSWORD")
  else
    local first second
    ( exec 3<>/dev/tty ) 2>/dev/null || die 'Looped needs a password. Set LOOPED_PASSWORD and rerun this command.'
    while :; do
      read -rsp 'Choose a password for Looped: ' first </dev/tty || die 'No password was entered.'
      printf '\n' >&2
      read -rsp 'Repeat it: ' second </dev/tty || die 'No password was entered.'
      printf '\n' >&2
      first=$(trim "$first"); second=$(trim "$second")
      if [[ -z $first ]]; then printf 'The password cannot be blank. Try again.\n' >&2
      elif [[ $first != "$second" ]]; then printf 'The passwords do not match. Try again.\n' >&2
      else password=$first; break; fi
    done
  fi
  [[ -n $password ]] || die 'LOOPED_PASSWORD must not be blank.'
fi
url=http://localhost:$port
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  printf 'Installing FFmpeg. sudo may ask for your password.\n'
  [[ -r /dev/tty ]] || die 'Install ffmpeg and ffprobe first, then rerun this command.'
  if command -v pacman >/dev/null; then sudo pacman -S --noconfirm --needed ffmpeg </dev/tty
  elif command -v apt-get >/dev/null; then sudo apt-get install -y ffmpeg </dev/tty
  elif command -v dnf >/dev/null; then sudo dnf install -y ffmpeg </dev/tty
  else die 'Install ffmpeg and ffprobe first.'; fi
fi
for tool in ffmpeg ffprobe; do command -v "$tool" >/dev/null || die "$tool is missing after installation."; done
if [[ $release_tag == @* ]]; then
  release_tag=${LOOPED_VERSION:-}
  if [[ -z $release_tag ]]; then
    effective=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$base/latest")
    release_tag=${effective##*/}
  fi
fi
[[ $release_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || die 'Could not resolve a release. Set LOOPED_VERSION=vX.Y.Z.'
mkdir -p "$(dirname "$bin")"
stage=$(mktemp -d "$(dirname "$bin")/.looped-install.XXXXXX")
replacing=0
restore() {
  local file
  if [[ $no_start != 1 ]]; then systemctl --user stop looped.service >/dev/null 2>&1 || true; fi
  for file in "$bin" "$unit" "$launcher" "$icon" "$config/port" "$config/data"; do
    local key=${file##*/}
    if [[ -f $stage/backup/$key ]]; then cp -p "$stage/backup/$key" "$file"; else rm -f "$file"; fi
  done
  if [[ $no_start != 1 ]]; then
    systemctl --user daemon-reload || true
    if [[ -f $stage/backup/looped ]]; then systemctl --user start looped.service || true; fi
  fi
}
cleanup() { local status=$?; if ((replacing && status != 0)); then restore; printf 'Previous installation restored.\n' >&2; fi; if ((status != 0 && wrote_password)); then rm -f "$pwfile"; fi; rm -rf "$stage"; }
trap cleanup EXIT
asset=looped-linux-$arch
curl -fsSL "$base/download/$release_tag/$asset" -o "$stage/looped"
curl -fsSL "$base/download/$release_tag/SHA256SUMS" -o "$stage/SHA256SUMS"
expected=$(awk -v name="$asset" '$2 == name { print $1 }' "$stage/SHA256SUMS")
[[ $expected =~ ^[a-fA-F0-9]{64}$ ]] || die 'The checksum manifest must contain exactly one entry for this binary.'
actual=$(sha256sum "$stage/looped"); actual=${actual%% *}
[[ ${actual,,} == ${expected,,} ]] || die 'Checksum mismatch. Existing installation was not changed.'
chmod 755 "$stage/looped"
[[ $("$stage/looped" --version) == "$release_tag" ]] || die 'The downloaded binary has the wrong version.'
if [[ $no_start != 1 ]] && curl -fsS --max-time 2 -o /dev/null "$url/api/me" 2>/dev/null; then
  pid=$(systemctl --user show looped.service -p MainPID --value)
  [[ $pid =~ ^[1-9][0-9]*$ && $(readlink "/proc/$pid/exe") == "$bin" ]] || die "Port $port belongs to another app. Set LOOPED_PORT on your first install."
fi
mkdir -p "$stage/backup" "$config" "$data" "$(dirname "$unit")" "$(dirname "$launcher")"
if [[ -n $password ]]; then (umask 077; printf '%s' "$password" > "$pwfile"); wrote_password=1; fi
for file in "$bin" "$unit" "$launcher" "$icon" "$config/port" "$config/data"; do [[ ! -f $file ]] || cp -p "$file" "$stage/backup/${file##*/}"; done
replacing=1
if [[ $no_start != 1 && -f $stage/backup/looped.service ]]; then systemctl --user stop looped.service; fi
mv "$stage/looped" "$bin"
printf '%s\n' "$port" > "$config/port"
printf '%s\n' "$data" > "$config/data"
systemd_quote() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//%/%%}; printf '"%s"' "$s"; }
{
  printf '[Unit]\nDescription=Looped local screen recorder\n\n[Service]\nExecStart=/usr/bin/env '
  systemd_quote "$bin"
  printf '\nEnvironment='
  systemd_quote "LOOPED_ADDR=127.0.0.1:$port"
  printf '\nEnvironment='
  systemd_quote "LOOPED_DATA=$data"
  printf '\nEnvironment=LOOPED_STORAGE=local\nEnvironment='
  systemd_quote "PATH=$PATH"
  printf '\nUnsetEnvironment=LOOPED_PASSWORD LOOPED_S3_ENDPOINT LOOPED_S3_BUCKET LOOPED_S3_ACCESS_KEY LOOPED_S3_SECRET_KEY LOOPED_S3_REGION\nRestart=on-failure\n\n[Install]\nWantedBy=default.target\n'
} > "$unit"
open=$(command -v omarchy-launch-webapp || command -v xdg-open || true)
if [[ -n $open ]]; then
  escaped=${open//\\/\\\\}; escaped=${escaped//\"/\\\"}; escaped=${escaped//\$/\\\$}; escaped=${escaped//\`/\\\`}; escaped=${escaped//%/%%}
  mkdir -p "$(dirname "$icon")"
  cat > "$icon" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect width="32" height="32" rx="8" fill="#ff4a1c"/>
  <path d="M16 16c-2.2-3.3-4-4.6-6.1-4.6a4.6 4.6 0 1 0 0 9.2c2.100 0 3.900-1.300 6.100-4.600Zm0 0c2.200 3.300 4 4.600 6.100 4.600a4.600 4.600 0 1 0 0-9.200c-2.100 0-3.900 1.300-6.100 4.600Z" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
SVG
  printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=Looped\nComment=Record your screen locally\nExec="%s" %s\nIcon=looped\nTerminal=false\n' "$escaped" "$url" > "$launcher"
  if command -v gtk-update-icon-cache >/dev/null; then gtk-update-icon-cache -q -t -f "${icon%/scalable/apps/*}" >/dev/null 2>&1 || true; fi
  if command -v update-desktop-database >/dev/null; then update-desktop-database "$(dirname "$launcher")" >/dev/null 2>&1 || true; fi
fi
if [[ $no_start != 1 ]]; then
  systemctl --user daemon-reload
  systemctl --user enable --now looped.service
  ready=0
  for ((i=0;i<50;i++)); do
    pid=$(systemctl --user show looped.service -p MainPID --value)
    if [[ $pid =~ ^[1-9][0-9]*$ && $(readlink "/proc/$pid/exe") == "$bin" ]] && kill -0 "$pid" 2>/dev/null && curl -fsS --max-time 1 -o /dev/null "$url/api/me" 2>/dev/null; then ready=1; break; fi
    sleep 0.2
  done
  ((ready)) || die "Startup failed. Inspect journalctl --user -u looped."
fi
replacing=0
printf 'Looped %s installed. Open %s\nRecordings: %s\n' "$release_tag" "$url" "$data"
if ((wrote_password)); then printf 'Sign in with the password you chose.\n'; fi
}
main "$@"
