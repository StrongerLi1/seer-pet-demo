#!/bin/zsh
set -euo pipefail

for action in attack sa cp hited; do
  count=$(find "frames/$action" -type f -name '*.png' | wc -l | tr -d ' ')
  (( count > 0 ))
done
idle_1_count=$(find "frames/idle" -type f -name '*.png' | wc -l | tr -d ' ')
(( idle_1_count == 16 ))
[[ -x SeerPetDemo.app/Contents/MacOS/SeerPetDemo ]]
[[ -x SeerPetDemo.app/Contents/Resources/runtime/bin/java ]]
SEER_PET_TEST_LAYOUT=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_SCALE=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_MOUSE=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_UNCONSTRAINED=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_MOVEMENT=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
SEER_PET_TEST_PET_ID=1 ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
for action in attack sa cp hited; do
  SEER_PET_TEST_ACTION="$action" ./SeerPetDemo.app/Contents/MacOS/SeerPetDemo
done
echo "OK: official nested SWF idle extraction, 16-frame bundled idle for 1, and 4 action playback tests"
