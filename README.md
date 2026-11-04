# 每秒都在赚 · Every Second Pays

SwiftUI iOS 17+ app: enter monthly salary + schedule → earnings per second; a gold coin drops into a glass piggy bank every working second, with a rolling odometer, soothing sound + soft haptics, home/lock-screen widgets, and a Live Activity / Dynamic Island.

## Build
```
brew install xcodegen && xcodegen generate && open EverySecondPays.xcodeproj
```
CI: `.github/workflows/build.yml` (macos-15) builds for simulator and an unsigned .ipa artifact.

## Change bundle id / team
Edit `BUNDLE_ID`, `APP_GROUP`, `DEVELOPMENT_TEAM` in `project.yml` (widget = `$(BUNDLE_ID).widget`). Register the App Group in the Apple Developer portal.

## Layout
- `EverySecondPays/` app (App, Views, Model, Resources: assets, Sounds/*.wav, zh-Hans/en strings)
- `Widget/` WidgetKit + ActivityKit extension
- `Shared/` settings (App Group UserDefaults), earnings math, ActivityAttributes
- `tools/make_sounds.py` cuts the CC0 recordings into app sounds; see SOUND_CREDITS.md

## Formula
per second = monthly salary ÷ (workdays/week × 52/12) ÷ (end − start − lunch). Lunch is 12:00 + N minutes.
