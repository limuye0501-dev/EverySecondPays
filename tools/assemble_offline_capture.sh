#!/bin/bash
# Builds the debug offline capture and turns its fixed-timestep frames into 60 fps video.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FINAL="$ROOT/footage/final"
mkdir -p "$FINAL"

PICK="$(mktemp)"
python3 - >"$PICK" << 'PY'
import json, re, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "runtimes", "-j"])
data = json.loads(raw)

def ver(text):
    return tuple(int(x) for x in re.findall(r"\d+", text or ""))[:4]

runtimes = [r for r in data.get("runtimes", []) if r.get("isAvailable") and "iOS" in r.get("name", "") and "beta" not in r.get("name", "").lower()]
runtimes.sort(key=lambda r: ver(r.get("version") or r["name"]))
runtime = runtimes[-1]
types = [t for t in data.get("devicetypes", []) if "iPhone" in t.get("name", "") and "Pro Max" in t.get("name", "")]
types.sort(key=lambda t: ver(t["name"]))
supported = runtime.get("supportedDeviceTypes") or []
if supported and isinstance(supported[0], dict):
    supported = [s.get("identifier") for s in supported]
if supported:
    usable = [t for t in types if t["identifier"] in supported]
    if usable:
        types = usable
chosen = types[-1]
print(chosen["identifier"])
print(runtime["identifier"])
print(chosen["name"] + " / " + runtime.get("name", ""))
PY
TYPE="$(sed -n '1p' "$PICK")"
RUNTIME="$(sed -n '2p' "$PICK")"
echo "Device $(sed -n '3p' "$PICK")"
rm -f "$PICK"

xcrun simctl shutdown all || true
UDID="$(xcrun simctl create "ESPOffline" "$TYPE" "$RUNTIME")"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

run_test() {
  local scheme="$1" only="$2"
  set -o pipefail
  xcodebuild test-without-building \
    -project "$ROOT/EverySecondPays.xcodeproj" \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$ROOT/build" \
    -only-testing:"$only" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$ROOT/footage/test-${scheme}.log"
  set +o pipefail
}

echo "=== Offline frame capture ==="
run_test OfflineCaptureTests OfflineCaptureTests
echo "=== Widget stills ==="
run_test EverySecondPays EverySecondPaysWidgetTests/WidgetRenderTests/testMarketingHomeWidgets

find "$HOME/Library/Developer/CoreSimulator/Devices/$UDID" -type d -name esp-marketing > "$ROOT/footage/capture-dirs.txt"
echo "Capture directories:"
cat "$ROOT/footage/capture-dirs.txt"
if [ ! -s "$ROOT/footage/capture-dirs.txt" ]; then
  echo "No capture output"
  exit 1
fi

encode_clip() {
  local name="$1" frames="$2" out="$3"
  local dir=""
  while IFS= read -r candidate; do
    if [ -f "$candidate/$name/frame-00001.jpg" ]; then dir="$candidate/$name"; break; fi
  done < "$ROOT/footage/capture-dirs.txt"
  if [ -z "$dir" ]; then echo "Missing frames for $name"; exit 1; fi
  local count
  count="$(find "$dir" -name 'frame-*.jpg' | wc -l | tr -d ' ')"
  echo "$name has $count frames, expected $frames"
  if [ "$count" -ne "$frames" ]; then exit 1; fi
  ffmpeg -y -framerate 60 -start_number 1 -i "$dir/frame-%05d.jpg" \
    -frames:v "$frames" -an -c:v libx264 -profile:v high -pix_fmt yuv420p \
    -crf 17 -preset medium -movflags +faststart "$out" </dev/null
  local bytes nb dur
  bytes="$(stat -f%z "$out")"
  if [ "$bytes" -ge 15000000 ]; then
    ffmpeg -y -i "$out" -an -c:v libx264 -profile:v high -pix_fmt yuv420p \
      -crf 23 -preset medium -movflags +faststart "$out.small.mp4" </dev/null
    mv "$out.small.mp4" "$out"
    bytes="$(stat -f%z "$out")"
  fi
  nb="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$out")"
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")"
  echo "$out frames=$nb duration=$dur bytes=$bytes"
  if [ "$nb" -ne "$frames" ]; then echo "Encoded frame count mismatch"; exit 1; fi
  cp "$dir/landings.json" "$FINAL/${name}-landings.json"
  # Consecutive frames in the coin section must differ. A held slideshow fails this.
  python3 - "$dir" "$name" << 'PY'
import subprocess, sys
directory, name = sys.argv[1], sys.argv[2]
# Frame 40 and 41 are during the first coin's fall on main clips.
# The settings clip's coins start after the 8s lead, so use a later pair.
pair = (500, 501) if name.startswith("03") else (40, 41)
def rgb(n):
    path = f"{directory}/frame-{n:05d}.jpg"
    return subprocess.check_output(["ffmpeg","-i",path,"-f","rawvideo","-pix_fmt","rgb24","-"], stderr=subprocess.DEVNULL)
a, b = rgb(pair[0]), rgb(pair[1])
diff = sum(abs(x - y) for x, y in zip(a, b))
print(f"motion {name} frames {pair} absdiff {diff}")
if diff < 1000:
    raise SystemExit(f"{name} frames {pair} are effectively identical")
PY
}

encode_clip 01-en-main 1800 "$FINAL/01-en-main-coins-dropping.mp4"
encode_clip 02-zh-Hans-main 1200 "$FINAL/02-zh-Hans-main-coins-dropping.mp4"
encode_clip 03-en-settings 1200 "$FINAL/03-en-settings-then-coins.mp4"

while IFS= read -r candidate; do
  find "$candidate" -maxdepth 1 -type f \( -name 'share-card-*.png' -o -name 'widget-en-*.png' \) -exec cp {} "$FINAL/" \;
done < "$ROOT/footage/capture-dirs.txt"

cp "$ROOT/EverySecondPays/Resources/Sounds/penny_slot.wav" "$FINAL/sound-penny-slot-coin-into-slot.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/empty_pig.wav" "$FINAL/sound-empty-pig.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/coin_pile.wav" "$FINAL/sound-coin-pile.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/ceramic_pig.wav" "$FINAL/sound-ceramic-pig.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/glass_bowl.wav" "$FINAL/sound-glass-bowl.wav"
cp "$ROOT/EverySecondPays/Resources/Assets.xcassets/AppIcon.appiconset/icon.png" "$FINAL/app-icon-1024.png"

echo "=== Final ==="
ls -lh "$FINAL"
test -f "$FINAL/share-card-en.png"
test -f "$FINAL/share-card-zh.png"
test -f "$FINAL/widget-en-small.png"
test -f "$FINAL/widget-en-medium.png"
echo DONE
