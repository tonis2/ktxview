#!/usr/bin/env bash
#
# Build dist/ktxview-x86_64.AppImage from build/ktxview.
#
#     c3c build ktxview && packaging/package-linux.sh
#
# Nothing but the executable and its licences goes in: Vulkan, X11 and Wayland
# are all dlopened from the system at runtime, the same as an unpackaged build.
source "$(dirname "$0")/common.sh"

appdir="dist/ktxview.AppDir"
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/ktxview"

cp build/ktxview "$appdir/usr/bin/"
strip "$appdir/usr/bin/ktxview" || true
stage_licenses "$appdir/usr/share/ktxview"

ln -s usr/bin/ktxview "$appdir/AppRun"
cp packaging/ktxview.png "$appdir/ktxview.png"
ln -s ktxview.png "$appdir/.DirIcon"
cat > "$appdir/ktxview.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=ktxview
Comment=View KTX2 textures
Exec=ktxview %f
Icon=ktxview
Categories=Graphics;Viewer;
MimeType=image/ktx2;
Terminal=false
DESKTOP

tool="${APPIMAGETOOL:-dist/appimagetool}"
if [ ! -x "$tool" ]; then
	curl -fsSL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
	chmod +x "$tool"
fi

out="dist/ktxview-x86_64.AppImage"
# Extract-and-run: CI runners have no FUSE to mount the tool itself.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$appdir" "$out"
echo "$out"
