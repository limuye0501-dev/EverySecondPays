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
  # Keep the device window on the visible desktop. Resizing before the test
  # runner attaches makes accessibility time out, so this only activates.
  osascript <<'APPLESCRIPT' || true
tell application "Simulator" to activate
tell application "System Events"
  tell process "Simulator"
    set frontmost to true
    try
      set value of attribute "AXMinimized" of window 1 to false
    end try
    try
      set position of window 1 to {40, 30}
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

# Drives one UI test. After the app signals it is on screen, grab framebuffer
# stills for `keep` seconds and turn them into the clip.
# $1 test method  $2 signal name  $3 keep seconds  $4 destination mp4
run_flow() {
  local test="$1" ready="$2" keep="$3" dest="$4"
  local attempt
  for attempt in 1 2; do
    if run_flow_once "$test" "$ready" "$keep" "$dest"; then
      return 0
    fi
    echo "Attempt $attempt failed for $test"
    if [ "$attempt" = "1" ]; then
      echo "Rebooting simulator and retrying"
      xcrun simctl shutdown "$BASE_UDID" || true
      xcrun simctl boot "$BASE_UDID"
      xcrun simctl bootstatus "$BASE_UDID" -b
      xcrun simctl spawn "$BASE_UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false || true
      apply_chrome
      focus_simulator
      xcrun simctl install "$BASE_UDID" "$APP"
    fi
  done
  return 1
}

run_flow_once() {
  local test="$1" ready="$2" keep="$3" dest="$4"
  local log="$ROOT/footage/uitest-${test}.log"
  local marks="$ROOT/footage/marks-${test}.txt"
  local raw="$RAW/${test}.mp4"
  local reclog="$ROOT/footage/rec-${test}.log"
  rm -f "$raw" "$log" "$marks" "$reclog" "$dest"
  apply_chrome
  focus_simulator
  echo "Recording $test from $ready for ${keep}s"
  xcrun simctl io "$BASE_UDID" recordVideo --codec=h264 --force --mask=ignored "$raw" >"$reclog" 2>&1 &
  local rpid=$!
  local i started=0
  for i in $(seq 1 20); do
    if grep -q "Recording started" "$reclog" 2>/dev/null; then started=1; break; fi
    sleep 0.5
  done
  if [ "$started" -ne 1 ]; then
    echo "recordVideo did not start"; cat "$reclog" || true
    kill -INT "$rpid" 2>/dev/null || true
    return 1
  fi
  local rec_start
  rec_start="$(python3 -c 'import time; print(f"{time.time():.3f}")')"
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
    -default-test-execution-time-allowance 240 \
    -maximum-test-execution-time-allowance 300 \
    CODE_SIGNING_ALLOWED=NO &
  local xpid=$!
  local found=0
  for i in $(seq 1 300); do
    if [ -f "$marks" ] && awk -v n="$ready" '$1==n {found=1} END{exit !found}' "$marks"; then
      found=1
      break
    fi
    if ! kill -0 "$xpid" 2>/dev/null; then
      echo "Test ended before $ready"
      break
    fi
    sleep 1
  done
  if [ "$found" -ne 1 ]; then
    echo "Missing signal $ready"
    tail -n 40 "$log" || true
    kill -INT "$xpid" 2>/dev/null || true
    kill -INT "$rpid" 2>/dev/null || true
    wait "$xpid" 2>/dev/null || true
    return 1
  fi
  local ready_at
  ready_at="$(awk -v n="$ready" '$1==n {print $2; exit}' "$marks")"
  # Let the on-screen hold finish, then stop. The test keeps the app up.
  local elapsed now_ts remain
  now_ts="$(python3 -c 'import time; print(f"{time.time():.3f}")')"
  elapsed="$(python3 -c "print(max(0.0, float('$now_ts') - float('$ready_at')))")"
  remain="$(python3 -c "print(max(0.0, float('$keep') - float('$elapsed')))")"
  echo "Holding ${remain}s more (already ${elapsed}s after $ready)"
  python3 -c "import time; time.sleep(float('$remain'))"
  kill -INT "$xpid" 2>/dev/null || true
  wait "$xpid" 2>/dev/null || true
  stop_record "$rpid" "$raw"
  local offset
  offset="$(python3 -c "print(max(0.0, float('$ready_at') - float('$rec_start')))")"
  echo "Trim offset=${offset}s keep=${keep}s"
  ffmpeg -y -i "$raw" -ss "$offset" -t "$keep" -an -c:v libx264 -profile:v high -pix_fmt yuv420p \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -crf 18 -preset medium -movflags +faststart "$dest" </dev/null
  local bytes w h dur fps
  bytes=$(stat -f%z "$dest")
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$dest")
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$dest")
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dest")
  fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$dest")
  echo "$(basename "$dest") ${w}x${h} dur=${dur}s fps=${fps} bytes=${bytes}"
  if [ "$h" -le "$w" ]; then
    echo "ERROR not portrait"
    return 1
  fi
  # A usable coin fall needs more than a frame every couple of seconds.
  python3 - << PY
fps = "$fps"
num, den = (fps.split("/", 1) + ["1"])[:2]
rate = float(num) / (float(den) or 1)
print(f"fps_check {rate:.2f}")
raise SystemExit(0 if rate >= 2.0 else 1)
PY
  if [ "$bytes" -ge 15000000 ]; then
    ffmpeg -y -i "$dest" -an -c:v libx264 -profile:v high -pix_fmt yuv420p \
      -crf 26 -preset medium -movflags +faststart "$dest.small.mp4" </dev/null
    mv "$dest.small.mp4" "$dest"
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
