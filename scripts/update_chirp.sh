#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_SUPPORT_DIR="${NEWCHIRP_BUILD_SUPPORT_DIR:-$PROJECT_DIR/build_support}"
CACHE_DIR="$BUILD_SUPPORT_DIR/cache"
DEFAULT_SOURCE="${CHIRP_SOURCE:-${NEWCHIRP_CHIRP_SOURCE:-$PROJECT_DIR/../chirp-20260626}}"
CURRENT_VERSION_FILE="$BUILD_SUPPORT_DIR/chirp-version.txt"

mkdir -p "$BUILD_SUPPORT_DIR" "$CACHE_DIR"

apply_newchirp_patches() {
  local target="$1"
  "${NEWCHIRP_PYTHON:-python3}" - "$target" <<'PY'
import sys

path = sys.argv[1] + "/chirp/drivers/baofeng_uv17Pro.py"
try:
    text = open(path, encoding="utf-8").read()
except FileNotFoundError:
    return

if "UV5G_GMRS_PRESETS" in text:
    return

anchor = 'MSTRING_BFK6 = b"PROGRAMBF-K6PROU"\n'
insert = (
    anchor
    + "\nUV5G_GMRS_PRESETS = (\n"
    + "    bandplan_na.GMRS_LOW +\n"
    + "    bandplan_na.GMRS_HHONLY +\n"
    + "    bandplan_na.GMRS_HIRPT +\n"
    + "    bandplan_na.GMRS_HIRPT\n"
    + ")\n"
)
if anchor not in text:
    return
text = text.replace(anchor, insert, 1)

old = (
    "        if mem.number >= 1 and mem.number <= 30:\n"
    "            mem.immutable = ['freq', 'duplex', 'offset']\n"
)
new = (
    "        if mem.number >= 1 and mem.number <= 30:\n"
    "            mem.freq = UV5G_GMRS_PRESETS[mem.number - 1]\n"
    "            if mem.number >= 15:\n"
    "                mem.duplex = '+'\n"
    "                mem.offset = 5000000\n"
    "            else:\n"
    "                mem.duplex = ''\n"
    "                mem.offset = 0\n"
    "            mem.immutable = ['freq', 'duplex', 'offset']\n"
)
if old not in text:
    return
text = text.replace(old, new, 1)

open(path, "w", encoding="utf-8").write(text)
PY
}

LATEST_LOCATION="$(curl -fsSI -o /dev/null -w '%{redirect_url}' \
  'https://archive.chirpmyradio.com/download?stream=next' 2>/dev/null || true)"
if [[ -z "$LATEST_LOCATION" ]]; then
  LATEST_LOCATION="$(curl -sI \
    'https://archive.chirpmyradio.com/download?stream=next' 2>/dev/null \
    | tr -d '\r' \
    | awk 'tolower($1) == "location:" {print $2}' \
    | head -1)"
fi

LATEST_VERSION="$(printf '%s\n' "$LATEST_LOCATION" \
  | sed -n 's#.*next-\([0-9]\{8\}\).*#\1#p')"
if [[ -z "$LATEST_VERSION" ]]; then
  echo "Unable to determine the latest CHIRP version from upstream." >&2
  exit 1
fi

if [[ -s "$CURRENT_VERSION_FILE" ]]; then
  CURRENT_VERSION="$(cat "$CURRENT_VERSION_FILE")"
else
  CURRENT_VERSION="$(sed -n 's/.*next-\([0-9]\{8\}\).*/\1/p' \
    "$DEFAULT_SOURCE/chirp/__init__.py" 2>/dev/null | head -1)"
  CURRENT_VERSION="${CURRENT_VERSION:-20260626}"
fi

if [[ "$LATEST_VERSION" -le "$CURRENT_VERSION" ]]; then
  if [[ -d "$BUILD_SUPPORT_DIR/chirp-$CURRENT_VERSION/chirp" ]]; then
    echo "$BUILD_SUPPORT_DIR/chirp-$CURRENT_VERSION"
  else
    echo "$DEFAULT_SOURCE"
  fi
  exit 0
fi

TARGET_DIR="$BUILD_SUPPORT_DIR/chirp-$LATEST_VERSION"
if [[ ! -d "$TARGET_DIR/chirp" ]]; then
  ARCHIVE="$CACHE_DIR/chirp-master.tar.gz"
  echo "Downloading CHIRP master source for next-$LATEST_VERSION..." >&2
  curl -fL --retry 3 -o "$ARCHIVE" \
    "https://codeload.github.com/kk7ds/chirp/tar.gz/refs/heads/master"

  TMP_DIR="$(mktemp -d "$BUILD_SUPPORT_DIR/chirp-extract.XXXXXX")"
  tar -xzf "$ARCHIVE" -C "$TMP_DIR" --strip-components=1
  rm -rf "$TARGET_DIR"
  mv "$TMP_DIR" "$TARGET_DIR"
fi

apply_newchirp_patches "$TARGET_DIR"

if [[ ! -d "$TARGET_DIR/chirp" ]]; then
  echo "Downloaded CHIRP source is missing the chirp package." >&2
  exit 1
fi

printf '%s\n' "$LATEST_VERSION" > "$CURRENT_VERSION_FILE"
echo "Updated CHIRP to next-$LATEST_VERSION" >&2
echo "$TARGET_DIR"
