#!/bin/sh
# Installs Pixora for the current user and registers .pixora files.
# Run from the extracted folder:  ./install.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/pixora"
mkdir -p "$DEST" "$HOME/.local/bin" "$HOME/.local/share/applications" \
         "$HOME/.local/share/mime/packages" "$HOME/.local/share/icons/hicolor/256x256/apps"
cp -r "$HERE/bundle/." "$DEST/"
ln -sf "$DEST/pixora" "$HOME/.local/bin/pixora"
cp "$HERE/pixora.png" "$HOME/.local/share/icons/hicolor/256x256/apps/pixora.png"
sed "s|^Exec=pixora|Exec=$DEST/pixora|" "$HERE/pixora.desktop" > "$HOME/.local/share/applications/pixora.desktop"
cp "$HERE/pixora-mime.xml" "$HOME/.local/share/mime/packages/pixora.xml"
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
xdg-mime default pixora.desktop application/vnd.pixora.project+zip 2>/dev/null || true
echo "Pixora installed. Launch it from your app menu or run: pixora"
