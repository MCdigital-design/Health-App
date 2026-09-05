# Verity Dashboard

A personal, offline-first Android app for Polar Verity Sense. Sideload the APK on your Samsung phone. No Play Store and no hosted URL.

This app lives in [Health-App](https://github.com/MCdigital-design/Health-App). It was moved here from [alphatrend-mt5-qa#1](https://github.com/MCdigital-design/alphatrend-mt5-qa/pull/1) so Polar sensor work is not mixed with AlphaTrend / MT5.

## Install this APK

Use this file only:

- [`dist/verity-dashboard.apk`](../../dist/verity-dashboard.apk) (28 MB, SHA256 `3553f8ead2deceb61bf5f1d6a0d231fef432872f071987e850e700a210c27092`)
- Direct: https://github.com/MCdigital-design/Health-App/raw/main/dist/verity-dashboard.apk

This build is signed with the same key as before, so it installs as an **update** over a previous install — no need to uninstall first.

This repository is **public**, so the raw APK link should download the real 28 MB file. If Android says "package appears to be invalid", the download was truncated or was an HTML page — check the file size before installing.

Do **not** install a debug APK. Debug builds are marked `testOnly` and Samsung’s installer rejects them.

### Samsung steps (this is what usually blocks install)

1. Copy `verity-dashboard.apk` to the phone (USB, Drive, or Files).
2. Open **My Files** (not Chrome if you can avoid it) and tap the APK.
3. If asked, allow **Install unknown apps** for **My Files**.
4. Turn **off Auto Blocker** (One UI 6+). This is the most common install failure on recent Samsung phones:
   - Settings → Security and privacy → Auto Blocker → Off
5. If Play Protect says the app is unsafe: **More details → Install anyway**.
6. If a previous Verity Dashboard attempt exists: uninstall it, then retry.

The app supports **Android 8.0+** (API 26). The previous APK required Android 13, which caused “App not installed” on older Samsung models.

## First use

1. Turn on Verity Sense and keep it nearby. Use **sensor mode** (heart icon, blue side LED).
2. Open **Verity Dashboard** → **Settings** → **Scan** → **Connect**.
3. Grant Bluetooth permission.
4. Go to **Live**. Heart rate starts automatically once connected.

### If heart rate never shows a number

Go to **Settings** and check the **SDK Mode** toggle. Verity Sense **disables Heart Rate and PPI entirely while SDK Mode is on** (this is sensor firmware behavior, not an app bug). Turn SDK Mode **off**, then reconnect. SDK Mode is only useful for higher-rate PPG/accelerometer capture, not for live BPM.

### Chart timeframes

The Live tab has a row of chips (Real-time / 1s / 5s / 30s / 1m / 5m) above the charts. Larger windows automatically average samples into buckets instead of plotting every point, so a 5-minute view stays fast and readable even for high-rate PPG data.

### Recording data

- **Live tab → Record** button: records whatever is currently streaming (HR/PPG) into local storage on the phone. This is the primary recording path for this app. Sessions are saved to a local SQLite database that survives app restarts and updates — they are only lost if the app is uninstalled or its storage is manually cleared.
- **Recordings tab → On Device**: lists exercises recorded using the sensor's own physical button and synced through a Polar Flow account. This only works if the sensor has been paired with Polar Flow and used in recording/swimming mode — it is a Polar Verity Sense limitation, not something this app can bypass.
- **Recordings tab → Polar Flow import**: pulls exercises already uploaded to your Polar Flow account, including ones no longer on the sensor itself. Requires a one-time setup in **Settings → Polar Flow** using your own free API client from [admin.polaraccesslink.com](https://admin.polaraccesslink.com) — see that section in Settings for the exact steps (this cannot be pre-configured, since it needs your Polar account login).
- Tap any session in **Recordings** or **Dashboard** to see a full breakdown: per-signal sample counts, estimated storage size, and CSV export.

See [`QA_AUDIT.md`](QA_AUDIT.md) for the full production-readiness audit, including exactly what was broken, what was fixed, storage estimates, and a manual hardware test checklist.

## If the APK download looks wrong

Confirm the file is **~28 MB**, not a few hundred KB. If it is tiny, you
got an error page instead of the APK. Re-download from the link above on
a computer, then transfer to the phone via USB, Drive, or email.

## If install still fails

Check Settings → About phone → Android version:

- Android 7 or older: this APK will not install.
- Android 8+: send the exact installer message (Play Protect, Auto Blocker, parse error, or “app not installed”).

## Build from source

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`
