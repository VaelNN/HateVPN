#!/usr/bin/env bash










set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Leadaxe/sing-box-lx"
VER="${1:-$(tr -d '[:space:]' < app/android/libbox.version)}"
DEST="app/android/app/libs"
AAR="libbox-${VER#v}.aar"
BASE_URL="https://github.com/$REPO/releases/download/$VER"

if [ -f "$DEST/libbox.aar" ] && [ -f "$DEST/.libbox.version" ] \
   && [ "$(cat "$DEST/.libbox.version")" = "$VER" ]; then
  echo "✓ libbox.aar already $VER — skipping"
  exit 0
fi

echo "→ Fetching $AAR ($REPO @ $VER)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --retry 3 -o "$TMP/$AAR" "$BASE_URL/$AAR"
curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" "$BASE_URL/SHA256SUMS"


if command -v sha256sum >/dev/null 2>&1; then
  SHACMD="sha256sum"
else
  SHACMD="shasum -a 256"
fi
(
  cd "$TMP"
  grep -E "  ?$AAR\$" SHA256SUMS > expected.sum
  $SHACMD -c expected.sum
)

mkdir -p "$DEST"
mv "$TMP/$AAR" "$DEST/libbox.aar"
printf '%s' "$VER" > "$DEST/.libbox.version"
echo "✅ $DEST/libbox.aar ← $VER"
