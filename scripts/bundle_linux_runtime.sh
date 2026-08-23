#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="20260807"
PYTHON_VERSION="3.13.15"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_SUPPORT_DIR="${NEWCHIRP_BUILD_SUPPORT_DIR:-$PROJECT_DIR/build_support}"
CACHE_DIR="$BUILD_SUPPORT_DIR/cache"

case "$(uname -m)" in
  x86_64)
    LINUX_ARCH="x86_64-unknown-linux-gnu"
    FALLBACK_BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
    ;;
  aarch64)
    LINUX_ARCH="aarch64-unknown-linux-gnu"
    FALLBACK_BUNDLE_DIR="$PROJECT_DIR/build/linux/arm64/release/bundle"
    ;;
  *)
    echo "Unsupported host architecture: $(uname -m)" >&2
    exit 2
    ;;
esac

ASSET="cpython-${PYTHON_VERSION}+${RELEASE_TAG}-${LINUX_ARCH}-install_only_stripped.tar.gz"
ARCHIVE="$CACHE_DIR/$ASSET"
EXTRACT_DIR="$CACHE_DIR/python-${PYTHON_VERSION}-${LINUX_ARCH}"
RUNTIME_SRC="$EXTRACT_DIR/python"

BUNDLE_DIR=""
CHIRP_SOURCE="${CHIRP_SOURCE:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-dir)
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --chirp-source)
      CHIRP_SOURCE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$FALLBACK_BUNDLE_DIR"
fi
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Flutter release bundle not found: $BUNDLE_DIR" >&2
  echo "Run 'flutter build linux' first, or pass --bundle-dir." >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$BUNDLE_DIR"

if [[ ! -x "$RUNTIME_SRC/bin/python3" ]]; then
  if [[ ! -f "$ARCHIVE" ]]; then
    URL="https://github.com/astral-sh/python-build-standalone/releases/download/${RELEASE_TAG}/${ASSET//+/%2B}"
    echo "Downloading bundled Python runtime: $URL" >&2
    curl -fL --retry 3 -o "$ARCHIVE" "$URL"
  fi
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
fi

if [[ ! -x "$RUNTIME_SRC/bin/python3" ]]; then
  echo "Bundled Python runtime is missing: $RUNTIME_SRC/bin/python3" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR/python"
cp -a "$RUNTIME_SRC" "$BUNDLE_DIR/python"

if [[ -n "$CHIRP_SOURCE" ]]; then
  CHIRP_ROOT="$CHIRP_SOURCE"
elif [[ -d "$BUILD_SUPPORT_DIR/chirp-20260821" ]]; then
  CHIRP_ROOT="$BUILD_SUPPORT_DIR/chirp-20260821"
else
  echo "CHIRP source not found. Set CHIRP_SOURCE or run scripts/update_chirp.sh." >&2
  exit 1
fi

CHIRP_PACKAGE="$CHIRP_ROOT/chirp"
if [[ ! -d "$CHIRP_PACKAGE" ]]; then
  echo "CHIRP package not found: $CHIRP_PACKAGE" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR/chirp"
cp -a "$CHIRP_PACKAGE" "$BUNDLE_DIR/chirp"

if [[ -f "$CHIRP_ROOT/COPYING" ]]; then
  cp "$CHIRP_ROOT/COPYING" "$BUNDLE_DIR/chirp-COPYING.txt"
fi

if [[ -f "$BUILD_SUPPORT_DIR/chirp-version.txt" ]]; then
  cp "$BUILD_SUPPORT_DIR/chirp-version.txt" "$BUNDLE_DIR/chirp-version.txt"
else
  CHIRP_VERSION_LINE="$(sed -n 's/.*next-\([0-9]\{8\}\).*/\1/p' \
    "$CHIRP_ROOT/chirp/__init__.py" 2>/dev/null | head -1)"
  if [[ -n "$CHIRP_VERSION_LINE" ]]; then
    printf '%s\n' "$CHIRP_VERSION_LINE" > "$BUNDLE_DIR/chirp-version.txt"
  fi
fi

echo "Bundled Python and CHIRP into $BUNDLE_DIR"
