#!/bin/zsh
set -euo pipefail

test_home=$(mktemp -d /tmp/seer-pet-verify.XXXXXX)
trap 'rm -rf "$test_home"' EXIT
export CFFIXED_USER_HOME="$test_home"

for action in attack sa cp hited; do
  count=$(find "frames/$action" -type f -name '*.png' | wc -l | tr -d ' ')
  (( count > 0 ))
done
idle_1_count=$(find "frames/idle" -type f -name '*.png' | wc -l | tr -d ' ')
(( idle_1_count == 16 ))
for direction in left right; do
  walk_count=$(find "frames/walk-$direction" -type f -name '*.png' | wc -l | tr -d ' ')
  (( walk_count == 8 ))
done
[[ -f "frames/bag-front/1.png" ]]
[[ -f "SeerPetDemo.app/Contents/Resources/frames/bag-front/1.png" ]]
walk_width=$(sips -g pixelWidth frames/walk-left/*.png 2>/dev/null | awk '/pixelWidth/{print $2; exit}')
(( walk_width >= 150 ))
[[ -x SeerPetDemo.app/Contents/MacOS/SeerPetDemo ]]
[[ -x SeerPetDemo.app/Contents/Resources/runtime/bin/java ]]
[[ -f SeerPetDemo.app/Contents/Resources/Documentation/DEPENDENCY_LICENSES.md ]]
[[ -f SeerPetDemo.app/Contents/Resources/Documentation/THIRD_PARTY_ASSETS.md ]]
[[ -f SeerPetDemo.app/Contents/Resources/PetBagLegacy.png ]]
[[ -f PetStats.plist ]]
[[ -f SeerPetDemo.app/Contents/Resources/PetStats.plist ]]
[[ -f PetNames.plist ]]
[[ -f SeerPetDemo.app/Contents/Resources/PetNames.plist ]]
for data in PetMeta PetMoves PetTypes; do
  [[ -f "$data.plist" ]]
  [[ -f "SeerPetDemo.app/Contents/Resources/$data.plist" ]]
done
for type in 1 2 16 223 prop; do
  [[ -f "PetTypeIcons/$type.png" ]]
  [[ -f "SeerPetDemo.app/Contents/Resources/PetTypeIcons/$type.png" ]]
done
(( $(find PetTypeIcons -type f -name '*.png' | wc -l | tr -d ' ') == 119 ))
for gender in 0 1 2; do
  [[ -f "PetGenderIcons/$gender.png" ]]
  [[ -f "SeerPetDemo.app/Contents/Resources/PetGenderIcons/$gender.png" ]]
done
[[ "$(plutil -extract 95 json -o - PetStats.plist)" == '[78,60,41,68,40,85]' ]]
[[ "$(plutil -extract 300 json -o - PetStats.plist)" == '[110,100,120,100,110,120]' ]]
[[ "$(plutil -extract 95 raw PetNames.plist)" == '尼布' ]]
[[ "$(plutil -extract 300 raw PetNames.plist)" == '谱尼' ]]
[[ "$(plutil -extract 5000 raw PetNames.plist)" == '圣灵谱尼' ]]
[[ "$(plutil -extract 95.0 raw PetMeta.plist)" == '2' ]]
[[ "$(plutil -extract 95.1 raw PetMeta.plist)" == '1' ]]
[[ "$(plutil -extract 95.2 raw PetMeta.plist)" == '96' ]]
[[ "$(plutil -extract 31140 json -o - PetMoves.plist)" == '["神灵之触",90,10,2,223,""]' ]]
[[ "$(plutil -extract 223 raw PetTypes.plist)" == '神灵' ]]
for asset in panel skill-up close-up close-over; do
  [[ -f "PetBagInfo/$asset.png" ]]
  [[ -f "SeerPetDemo.app/Contents/Resources/PetBagInfo/$asset.png" ]]
done
cmp -s PetBagInfo/panel.png SeerPetDemo.app/Contents/Resources/PetBagInfo/panel.png
for button in follow-show follow-hide default skill-stone countermark pet-storage storage item cure; do
  [[ -f "SeerPetDemo.app/Contents/Resources/PetBagButtons/$button-up.png" ]]
  [[ -f "SeerPetDemo.app/Contents/Resources/PetBagButtons/$button-over.png" ]]
  ! cmp -s "PetBagButtons/$button-up.png" "PetBagButtons/$button-over.png"
done
for slot in blue-normal blue-selected yellow-normal yellow-selected; do
  [[ -f "SeerPetDemo.app/Contents/Resources/PetBagSlots/$slot.png" ]]
done
[[ "$(plutil -extract LSUIElement raw Info.plist)" == "true" ]]
SEER_PET_TEST_STATUS_ITEM=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_SKILL_MENU=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_LONG_NAME=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_LAYOUT=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_SCALE=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_MOUSE=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_UNCONSTRAINED=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_MOVEMENT=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_RANDOM_ATTACK=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_INPUT=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_MODAL_CALLBACK=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_MULTI=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
[[ -s /tmp/seer-manager-render.png ]]
SEER_PET_TEST_PET_ID=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
for action in attack sa cp hited; do
  SEER_PET_TEST_ACTION="$action" ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
done
echo "OK: original PetDataPanel fields/type icons/evolution/skills, creation date, portraits, idle/walk, and action tests"
