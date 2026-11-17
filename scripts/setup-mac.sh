#!/bin/bash
# ResusIGD — one-shot setup on a Mac: checks Xcode, gets XcodeGen (no Homebrew required),
# generates ResusIGD.xcodeproj and opens it in Xcode.
# Usage (from the repo root):  bash scripts/setup-mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Memeriksa Xcode…"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ Xcode belum terpasang / belum dipilih."
  echo "   Pasang Xcode dari App Store, buka sekali (setujui lisensi), lalu jalankan:"
  echo "   sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi
xcodebuild -version | head -n 1

echo "==> Menyiapkan XcodeGen…"
if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN="xcodegen"
else
  TOOLS_DIR=".tools/xcodegen"
  if [ ! -x "$TOOLS_DIR/bin/xcodegen" ]; then
    mkdir -p .tools
    curl -fsSL -o .tools/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
    unzip -q -o .tools/xcodegen.zip -d .tools
    rm .tools/xcodegen.zip
  fi
  XCODEGEN="$TOOLS_DIR/bin/xcodegen"
fi
"$XCODEGEN" --version

echo "==> Membuat ResusIGD.xcodeproj…"
"$XCODEGEN" generate

echo "==> Membuka Xcode…"
open ResusIGD.xcodeproj
echo "✅ Selesai. Lanjutkan langkah 4 di docs/PASANG_DI_IPHONE.md (pilih Team, colok iPhone, tekan Run)."
