#!/bin/bash
# Records portrait simulator clips of the shipping app.
# -ESPDemo seeds a $20,000 / ¥20,000 all-day salary so a coin drops every
# second no matter when CI runs. The host clock is moved to 12:30 (then
# 22:15) so the counter shows a real workday; the status bar stays at 9:41.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FINAL="$ROOT/footage/final"
DEBUG="$ROOT/footage/debug"
RAW="$ROOT/footage/raw"
mkdir -p "$FINAL" "$DEBUG" "$RAW"

BUNDLE="com.limuye.everysecondpays"
APP="$ROOT/build/Build/Products/Debug-iphonesimulator/EverySecondPays.app"
UDID=""
ORIG_DATE="$(date +%m%d%H%M%Y.%S)"
ORIG_YEAR="$(date +%Y)"

restore_clock() {
  echo "Restoring clock to $ORIG_DATE (now $(date))"
  sudo date "$ORIG_DATE" || sudo sntp -sS time.apple.com || true
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
  local hhmm="$1"
  local stamp want hour year
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

stop_pid() {
  local pid="$1"
  kill -INT "$pid" 2>/dev/null || true
  kill -INT -- "-$pid" 2>/dev/null || true
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 1
  done
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

apply_chrome() {
  local id="$1"
  xcrun simctl status_bar "$id" override --time "9:41" --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100 || true
}

# Prefer a test clone if Xcode made one, so the recording follows the UI test.
record_udid() {
  UDID="$BASE_UDID" python3 - << 'PY'
import json, os, subprocess, sys
base = os.environ["UDID"]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "booted", "-j"]))
booted = []
for devs in data.get("devices", {}).values():
    for d in devs:
        if d.get("state") == "Booted":
            booted.append((d["udid"], d.get("name", "")))
print("booted " + ", ".join(n + "=" + u for u, n in booted), file=sys.stderr)
clones = [u for u, n in booted if u != base]
print(clones[-1] if clones else base)
PY
}

record_for() {
  local out="$1" secs="$2" id
  id="$(record_udid)"
  apply_chrome "$id"
  rm -f "$out"
  echo "Recording $secs s on $id -> $out"
  xcrun simctl io "$id" recordVideo --codec=h264 --force --mask=ignored "$out" &
  local pid=$!
  sleep "$secs"
  stop_pid "$pid"
  if [ ! -s "$out" ]; then
    echo "h264 record empty, retrying default codec"
    xcrun simctl io "$id" recordVideo --force "$out" &
    pid=$!
    sleep "$secs"
    stop_pid "$pid"
  fi
  ls -lh "$out"
  [ -s "$out" ]
}

shot() {
  local name="$1" id
  id="$(record_udid)"
  xcrun simctl io "$id" screenshot "$DEBUG/${name}.png" || true
}

launch_demo() {
  local lang="$1" loc="$2"
  xcrun simctl terminate "$BASE_UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 0.4
  xcrun simctl launch "$BASE_UDID" "$BUNDLE" -ESPDemo main -AppleLanguages "($lang)" -AppleLocale "$loc"
  sleep 8
}

encode() {
  local in="$1" out="$2" crf bytes w h
  crf=18
  while [ "$crf" -le 33 ]; do
    ffmpeg -y -i "$in" -an -c:v libx264 -profile:v high -pix_fmt yuv420p \
      -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
      -crf "$crf" -preset medium -movflags +faststart "$out" </dev/null
    bytes=$(stat -f%z "$out")
    echo "encoded $(basename "$out") crf=$crf bytes=$bytes"
    if [ "$bytes" -lt 15000000 ]; then
      w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$out")
      h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$out")
      echo "size ${w}x${h}"
      ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$out"
      if [ "$h" -le "$w" ]; then
        echo "ERROR $out is not portrait"
        return 1
      fi
      return 0
    fi
    crf=$((crf + 3))
  done
  echo "ERROR $out still over 15MB"
  return 1
}

saw_signal() {
  local name="$1" log="$2"
  local base="$HOME/Library/Developer/CoreSimulator/Devices/$BASE_UDID/data"
  if [ -f "$log" ] && grep -q "ESP_SIGNAL ${name}" "$log"; then
    return 0
  fi
  if [ -f "$base/tmp/esp-signal-${name}" ] || [ -f "$base/private/tmp/esp-signal-${name}" ]; then
    return 0
  fi
  return 1
}

run_flow() {
  local test="$1" ready="$2" raw="$3"
  local log="$ROOT/footage/uitest-${test}.log"
  local xpid rpid i n id
  rm -f "$log"
  echo "UI test $test, record after $ready"
  script -q "$log" xcodebuild test-without-building \
    -project "$ROOT/EverySecondPays.xcodeproj" \
    -scheme MarketingCapture \
    -destination "platform=iOS Simulator,id=$BASE_UDID" \
    -derivedDataPath "$ROOT/build" \
    -only-testing:"MarketingCapture/MarketingCaptureTests/${test}" \
    -parallel-testing-enabled NO \
    -maximum-concurrent-test-simulator-destinations 1 \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 150 \
    -maximum-test-execution-time-allowance 180 \
    CODE_SIGNING_ALLOWED=NO &
  xpid=$!
  i=0
  while kill -0 "$xpid" 2>/dev/null; do
    if saw_signal "$ready" "$log"; then
      break
    fi
    i=$((i + 1))
    if [ "$i" -gt 200 ]; then
      break
    fi
    sleep 1
  done
  if ! saw_signal "$ready" "$log"; then
    echo "No signal $ready"
    tail -n 80 "$log" || true
    stop_pid "$xpid"
    return 1
  fi
  id="$(record_udid)"
  apply_chrome "$id"
  rm -f "$raw"
  echo "Signal $ready, recording $raw on $id"
  xcrun simctl io "$id" recordVideo --codec=h264 --force --mask=ignored "$raw" &
  rpid=$!
  n=0
  local shot_settings=0 shot_share=0 shot_widget=0
  while kill -0 "$xpid" 2>/dev/null; do
    n=$((n + 1))
    if [ "$shot_settings" -eq 0 ] && saw_signal "settings-open" "$log"; then
      shot "${test}-settings" || true
      shot_settings=1
    fi
    if [ "$shot_share" -eq 0 ] && saw_signal "share-tapped" "$log"; then
      sleep 1
      shot "${test}-share" || true
      shot_share=1
    fi
    if [ "$shot_widget" -eq 0 ] && saw_signal "widget-visible" "$log"; then
      shot "${test}-widget" || true
      shot_widget=1
    fi
    if [ "$n" -gt 100 ]; then
      echo "Test overtime"
      stop_pid "$xpid"
      break
    fi
    sleep 1
  done
  wait "$xpid" || echo "xcodebuild exit $?"
  sleep 0.4
  stop_pid "$rpid"
  ls -lh "$raw" || true
  tail -n 30 "$log" || true
  [ -s "$raw" ]
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

xcrun simctl shutdown all || true
BASE_UDID="$(xcrun simctl create "ESPFootage" "$TYPE" "$RUNTIME")"
UDID="$BASE_UDID"
echo "Created $BASE_UDID"
set_clock 1230

xcrun simctl boot "$BASE_UDID"
xcrun simctl bootstatus "$BASE_UDID" -b
xcrun simctl spawn "$BASE_UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false || true
xcrun simctl ui "$BASE_UDID" appearance dark || true
apply_chrome "$BASE_UDID"
open -a Simulator --args -CurrentDeviceUDID "$BASE_UDID" || true
sleep 2
apply_chrome "$BASE_UDID"

if [ ! -d "$APP" ]; then
  echo "Missing app at $APP"
  find "$ROOT/build/Build/Products" -name 'EverySecondPays.app' -maxdepth 3 || true
  exit 1
fi
xcrun simctl install "$BASE_UDID" "$APP"

echo "=== English main ==="
launch_demo en en_US
shot "01-before"
record_for "$RAW/01-en-main.mp4" 36
shot "01-after"

echo "=== Simplified Chinese main ==="
launch_demo zh-Hans zh_CN
shot "02-before"
record_for "$RAW/02-zh-main.mp4" 26
shot "02-after"

echo "=== English settings, then back to falling coins ==="
set_clock 1230
xcrun simctl terminate "$BASE_UDID" "$BUNDLE" >/dev/null 2>&1 || true
run_flow testSettingsFlow settings-ready "$RAW/03-en-settings.mp4"

echo "=== English share card over a late-day total ==="
set_clock 2215
xcrun simctl terminate "$BASE_UDID" "$BUNDLE" >/dev/null 2>&1 || true
run_flow testShareCard share-ready "$RAW/04-en-share.mp4"

echo "=== Home-screen widget, best effort ==="
set_clock 1230
xcrun simctl terminate "$BASE_UDID" "$BUNDLE" >/dev/null 2>&1 || true
if run_flow testHomeWidget widget-visible "$RAW/05-en-widget.mp4"; then
  echo "Widget clip recorded"
else
  echo "Widget clip skipped"
  rm -f "$RAW/05-en-widget.mp4"
fi

echo "=== Encode ==="
encode "$RAW/01-en-main.mp4" "$FINAL/01-en-main-coins-dropping.mp4"
encode "$RAW/02-zh-main.mp4" "$FINAL/02-zh-Hans-main-coins-dropping.mp4"
encode "$RAW/03-en-settings.mp4" "$FINAL/03-en-settings-then-coins.mp4"
encode "$RAW/04-en-share.mp4" "$FINAL/04-en-full-day-share-card.mp4"
if [ -s "$RAW/05-en-widget.mp4" ]; then
  encode "$RAW/05-en-widget.mp4" "$FINAL/05-en-home-widget.mp4" || rm -f "$FINAL/05-en-home-widget.mp4"
fi

echo "=== Final ==="
ls -lh "$FINAL"
echo "DONE"
