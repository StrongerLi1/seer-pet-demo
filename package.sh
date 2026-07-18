#!/bin/zsh
set -euo pipefail

root=${0:A:h}
cd "$root"

app="$root/SeerPetDemo.app"
resources="$app/Contents/Resources"
dist="$root/dist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
arch=$(lipo -archs "$app/Contents/MacOS/SeerPetDemo" 2>/dev/null || uname -m)
dmg="$dist/赛尔号桌宠-${version}-macOS-${arch}.dmg"
staging=$(mktemp -d /tmp/seer-pet-dmg.XXXXXX)
trap 'rm -rf "$staging"' EXIT

find "$root" -name .DS_Store -delete
mkdir -p "$app/Contents/MacOS" "$resources" "$dist"
cp Info.plist "$app/Contents/Info.plist"

for directory in PetBagButtons PetBagInfo PetBagSlots PetGenderIcons PetTypeIcons frames; do
  rm -rf "$resources/$directory"
  ditto "$directory" "$resources/$directory"
done
for file in AppIcon.icns PetBagLegacy.png PetMeta.plist PetMoves.plist PetNames.plist PetStats.plist PetTypes.plist; do
  cp "$file" "$resources/$file"
done
rm -rf "$resources/Documentation"
mkdir -p "$resources/Documentation"
cp DEPENDENCY_LICENSES.md THIRD_PARTY_ASSETS.md "$resources/Documentation/"

[[ -x "$resources/runtime/bin/java" ]]
[[ -f "$resources/ffdec/ffdec.jar" ]]
xcrun clang -fobjc-arc -framework Cocoa -framework QuartzCore -framework ImageIO \
  SeerPetDemo.m -o "$app/Contents/MacOS/SeerPetDemo"
codesign --force --deep --sign - "$app"
./verify.sh
codesign --verify --deep --strict "$app"

ditto "$app" "$staging/赛尔号桌宠.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname "赛尔号桌宠 $version" -srcfolder "$staging" -ov -format UDZO "$dmg"
hdiutil verify "$dmg" >/dev/null

echo "$dmg"
