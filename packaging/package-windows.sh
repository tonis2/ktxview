#!/usr/bin/env bash
#
# Build dist/ktxview-windows-x64.zip from build/ktxview.exe: a portable
# folder. Unzip anywhere and run ktxview.exe; there is nothing to install.
#
#     c3c build ktxview && packaging/package-windows.sh
source "$(dirname "$0")/common.sh"

name="ktxview-windows-x64"
out="dist/$name"
rm -rf "$out"
mkdir -p "$out"

cp build/ktxview.exe "$out/"
stage_licenses "$out" .txt

cd dist
rm -f "$name.zip"
if command -v zip >/dev/null 2>&1; then
	zip -qr "$name.zip" "$name"
else
	# Git Bash on Windows has no zip, and its tar is GNU tar, which cannot write one.
	powershell -NoProfile -Command "Compress-Archive -Path '$name' -DestinationPath '$name.zip'"
fi
echo "dist/$name.zip"
