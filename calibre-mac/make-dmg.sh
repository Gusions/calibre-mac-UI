#!/bin/zsh
# Crea l'installer "Calibre Mac.dmg" (trascina l'app in Applicazioni).
set -e
cd "$(dirname "$0")"
./build.sh
STAGE=build/dmg; rm -rf $STAGE; mkdir -p $STAGE
cp -R "build/Calibre Mac.app" $STAGE/
ln -s /Applications $STAGE/Applications
cat > $STAGE/LEGGIMI.txt <<T
Calibre Mac - interfaccia nativa per Calibre

1. Trascina "Calibre Mac" in Applicazioni.
2. Serve Calibre installato (https://calibre-ebook.com/download_osx): viene usato solo come motore, la sua interfaccia Qt non parte.
3. Alla prima apertura: "Gatekeeper" puo' chiedere conferma (app non notarizzata). Clic destro sull'app > Apri.
T
rm -f "build/Calibre Mac.dmg"
hdiutil create -volname "Calibre Mac" -srcfolder $STAGE -ov -format UDZO "build/Calibre Mac.dmg" >/dev/null
echo "Creato: build/Calibre Mac.dmg ($(du -h "build/Calibre Mac.dmg" | cut -f1))"
