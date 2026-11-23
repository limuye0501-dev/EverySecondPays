#!/bin/bash
# Records portrait simulator clips of the shipping app.
# -ESPDemo seeds a $20,000 / ¥20,000 all-day salary so a coin drops every
# second. The host clock is moved so the counter shows a real workday;
# the status bar stays at 9:41.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FINAL="$ROOT/footage/final"
DEBUG="$ROOT/footage/debug"
RAW="$ROOT/footage/raw"
mkdir -p "$FINAL" "$DEBUG" "$RAW"

BUNDLE="com.limuye.everysecondpays"
APP="$ROOT/build/Build/Products/Debug-iphonesimulator/EverySecondPays.app"
BASE_UDID=""
ORIG_DATE="$(date +%m%d%H%M%Y.%S)"
ORIG_YEAR="$(date +%Y)"
CAFF_PID=""

restore_clock() {
  echo "Restoring clock to $ORIG_DATE (now $(date))"
  sudo date "$ORIG_DATE" || sudo sntp -sS time.apple.com || true
  if [ -n "$CAFF_PID" ]; then
    kill "$CAFF_PID" 2>/dev/null || true
  fi
  echo "Clock restored: $(date)"
}
trap restore_clock EXIT

cp "$ROOT/EverySecondPays/Resources/Sounds/penny_slot.wav" "$FINAL/sound-penny-slot-coin-into-slot.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/empty_pig.wav" "$FINAL/sound-empty-pig.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/coin_pile.wav" "$FINAL/sound-coin-pile.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/ceramic_pig.wav" "$FINAL/sound-ceramic-pig.wav"
cp "$ROOT/EverySecondPays/Resources/Sounds/glass_bowl.wav" "$FINAL/sound-glass-bowl.wav"
cp "$ROOT/EverySecondPays/Resources/Assets.xcassets/AppIcon.appiconset/icon.png" "$FINAL/app-icon-1024.png"

set_clock() {
  local hhmm="$1" stamp want hour year
  stamp="$(date +%m%d)${hhmm}$(date +%Y).00"
  want="${hhmm:0:2}"
  echo "Setting clock via $stamp"
  sudo date "$stamp"
  hour="$(date +%H)"
  year="$(date +%Y)"
  echo "Clock is now $(date)"
  if [ "$year" != "$ORIG_YEAR" ] || [ "$hour" != "$want" ]; then
    echo "Clock did not land on ${ORIG_YEAR} ${want}:00"
    return 1
  fi
}

apply_chrome() {
  xcrun simctl status_bar "$BASE_UDID" override --time "9:41" --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100 || true
}

focus_simulator() {
  open -a Simulator --args -CurrentDeviceUDID "$BASE_UDID" || true
  sleep 1
  # A Pro Max window at full scale is taller than the runner's display, so
  # CoreSimulator treats it as occluded and paints a fraction of a frame per
  # second. Fit it on screen before capturing.
  osascript <<'APPLESCRIPT' || true
tell application "Simulator" to activate
tell application "System Events"
  tell process "Simulator"
    set frontmost to true
    try
      set value of attribute "AXMinimized" of window 1 to false
    end try
    try
      click menu item "Fit Screen" of menu 1 of menu bar item "Window" of menu bar 1
    end try
    try
      set position of window 1 to {40, 30}
      set size of window 1 to {420, 900}
    end try
  end tell
end tell
APPLESCRIPT
}

# SIGINT only. kill -9 leaves an mp4 with no moov atom.
stop_record() {
  local pid="$1" out="$2"
  kill -INT "$pid" 2>/dev/null || true
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    if ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" >/dev/null 2>&1; then
      if ! kill -0 "$pid" 2>/dev/null; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "Recording did not finalize: $out"
  ls -lh "$out" || true
  return 1
}

# Drives one UI test and grabs a real framebuffer image as fast as the
# simulator will serve them for `keep` seconds after the ready signal.
# simctl recordVideo only receives the throttled present rate on this runner.
# $1 test method  $2 signal name  $3 keep seconds  $4 destination mp4
run_flow() {
  local test="$1" ready="$2" keep="$3" dest="$4"
  local log="$ROOT/footage/uitest-${test}.log"
  local marks="$ROOT/footage/marks-${test}.txt"
  local frames="$RAW/${test}-frames"
  rm -rf "$frames" "$log" "$marks" "$dest"
  mkdir -p "$frames"
  apply_chrome
  focus_simulator
  echo "Starting $test, capture ${keep}s after $ready"
  python3 "$ROOT/tools/ptylog.py" "$log" "$marks" \
    xcodebuild test-without-building \
    -project "$ROOT/EverySecondPays.xcodeproj" \
    -scheme MarketingCapture \
    -destination "platform=iOS Simulator,id=$BASE_UDID" \
    -derivedDataPath "$ROOT/build" \
    -only-testing:"MarketingCapture/MarketingCaptureTests/${test}" \
    -parallel-testing-enabled NO \
    -maximum-concurrent-test-simulator-destinations 1 \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 220 \
    -maximum-test-execution-time-allowance 260 \
    CODE_SIGNING_ALLOWED=NO &
  local xpid=$!
  local i found=0
  for i in $(seq 1 200); do
    if [ -f "$marks" ] && awk -v n="$ready" '$1==n {found=1} END{exit !found}' "$marks"; then
      found=1
      break
    fi
    if ! kill -0 "$xpid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if [ "$found" -ne 1 ]; then
    echo "Missing signal $ready"
    tail -n 40 "$log" || true
    kill -INT "$xpid" 2>/dev/null || true
    wait "$xpid" 2>/dev/null || true
    return 1
  fi
  focus_simulator
  apply_chrome
  echo "Capturing frames for ${keep}s"
  local n=0 start now
  start=$SECONDS
  while [ $((SECONDS - start)) -lt "$keep" ]; do
    n=$((n + 1))
    xcrun simctl io "$BASE_UDID" screenshot "$frames/$(printf '%05d' "$n").png" >/dev/null || true
  done
  echo "Captured $n frames in $((SECONDS - start))s"
  kill -INT "$xpid" 2>/dev/null || true
  wait "$xpid" 2>/dev/null || true
  if [ "$n" -lt 8 ]; then
    echo "Too few frames ($n)"
    return 1
  fi
  local rate
  rate="$(python3 -c "print(max(1.0, $n / float($keep)))")"
  ffmpeg -y -framerate "$rate" -i "$frames/%05d.png" -an -c:v libx264 -profile:v high -pix_fmt yuv420p \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -crf 18 -preset medium -movflags +faststart "$dest" </dev/null
  local mid
  mid="$(printf '%05d' $((n / 2)))"
  cp "$frames/00001.png" "$DEBUG/${test}-a.png" || true
  cp "$frames/${mid}.png" "$DEBUG/${test}-b.png" || true
  rm -rf "$frames"
  local bytes w h dur
  bytes=$(stat -f%z "$dest")
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$dest")
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$dest")
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dest")
  echo "$(basename "$dest") ${w}x${h} dur=${dur}s frames=$n rate=$rate bytes=$bytes"
  if [ "$h" -le "$w" ]; then
    echo "ERROR not portrait"
    return 1
  fi
  if [ "$bytes" -ge 15000000 ]; then
    echo "Re-encoding smaller"
    ffmpeg -y -i "$dest" -an -c:v libx264 -profile:v high -pix_fmt yuv420p \
      -crf 26 -preset medium -movflags +faststart "$dest.small.mp4" </dev/null
    mv "$dest.small.mp4" "$dest"
    bytes=$(stat -f%z "$dest")
    echo "shrunk to $bytes"
  fi
}

echo "Selecting the largest iPhone Pro Max"
PICK="$(mktemp)"
python3 - >"$PICK" << 'PY'
import json, re, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "runtimes", "-j"])
data = json.loads(raw)

def ver(text):
    return tuple(int(x) for x in re.findall(r"\d+", text or ""))[:4]

runtimes = [r for r in data.get("runtimes", []) if r.get("isAvailable") and "iOS" in r.get("name", "") and "beta" not in r.get("name", "").lower()]
if not runtimes:
    sys.exit("no iOS runtime")
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
if not types:
    sys.exit("no Pro Max device type")
chosen = types[-1]
print(chosen["identifier"])
print(runtime["identifier"])
print(chosen["name"] + " / " + runtime.get("name", ""))
PY
TYPE="$(sed -n '1p' "$PICK")"
RUNTIME="$(sed -n '2p' "$PICK")"
echo "Device $(sed -n '3p' "$PICK") type=$TYPE runtime=$RUNTIME"
rm -f "$PICK"

defaults write NSGlobalDomain NSAppSleepDisabled -bool YES || true
defaults write com.apple.iphonesimulator NSAppSleepDisabled -bool YES || true
caffeinate -dimsu &
CAFF_PID=$!

xcrun simctl shutdown all || true
BASE_UDID="$(xcrun simctl create "ESPFootage" "$TYPE" "$RUNTIME")"
echo "Created $BASE_UDID"
# Open the Simulator app before boot so the device window is on screen and
# CoreSimulator does not throttle the framebuffer down to a fraction of a frame.
open -a Simulator --args -CurrentDeviceUDID "$BASE_UDID" || true
set_clock 1230

xcrun simctl boot "$BASE_UDID"
xcrun simctl bootstatus "$BASE_UDID" -b
xcrun simctl spawn "$BASE_UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false || true
xcrun simctl ui "$BASE_UDID" appearance dark || true
apply_chrome
focus_simulator
sleep 2
apply_chrome

if [ ! -d "$APP" ]; then
  echo "Missing app at $APP"
  find "$ROOT/build/Build/Products" -name 'EverySecondPays.app' -maxdepth 3 || true
  exit 1
fi
xcrun simctl install "$BASE_UDID" "$APP"

echo "=== English main ==="
run_flow testMainEnglish main-en-ready 36 "$FINAL/01-en-main-coins-dropping.mp4"

echo "=== Simplified Chinese main ==="
run_flow testMainChinese main-zh-ready 26 "$FINAL/02-zh-Hans-main-coins-dropping.mp4"

echo "=== English settings, then coins ==="
run_flow testSettingsFlow settings-ready 30 "$FINAL/03-en-settings-then-coins.mp4"

echo "=== English share card, late-day amount ==="
set_clock 2215
run_flow testShareCard share-ready 16 "$FINAL/04-en-full-day-share-card.mp4"

echo "=== Home-screen widget, best effort ==="
set_clock 1230
if run_flow testHomeWidget widget-visible 10 "$FINAL/05-en-home-widget.mp4"; then
  echo "Widget clip recorded"
else
  echo "Widget clip skipped"
  rm -f "$FINAL/05-en-home-widget.mp4"
fi

echo "=== Final ==="
ls -lh "$FINAL"
echo "DONE"
