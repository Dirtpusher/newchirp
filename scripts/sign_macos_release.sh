#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$PROJECT_DIR/build/macos/Build/Products/Release/NewChirp.app}"
IDENTITY="${MACOS_SIGN_IDENTITY:-Developer ID Application: Rick Lopez (52NU5RC5MZ)}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release app not found: $APP_PATH" >&2
  exit 1
fi

sign_code() {
  local path="$1"
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$IDENTITY" \
    "$path"
}

echo "Signing bundled Mach-O files..." >&2
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | /usr/bin/grep -q "Mach-O"; then
    sign_code "$file"
  fi
done < <(/usr/bin/find "$APP_PATH/Contents/Resources" -type f -print0)

echo "Signing embedded frameworks..." >&2
while IFS= read -r -d '' framework; do
  sign_code "$framework"
done < <(/usr/bin/find "$APP_PATH/Contents/Frameworks" -depth -type d -name "*.framework" -print0)

echo "Signing application bundle..." >&2
/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$IDENTITY" \
  "$APP_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Signed and verified: $APP_PATH" >&2
