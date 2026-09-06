# Health-App

Dedicated home for Polar Verity Sense work, moved out of [alphatrend-mt5-qa#1](https://github.com/MCdigital-design/alphatrend-mt5-qa/pull/1). This repository is not an AlphaTrend / MT5 project.

## Polar Verity Sense Android app (primary)

Flutter dashboard you sideload on a Samsung phone. Live HR/PPG, recording, history, CSV export, optional Polar Flow import. No Play Store.

- App source: [`apps/verity_dashboard`](apps/verity_dashboard)
- Sideload APK: [`dist/verity-dashboard.apk`](dist/verity-dashboard.apk) (30 MB, SHA256 `223f248eb9dbba1d768c302b35e06313d22726245feb2424c21444af53c74103`)
- Install notes: [`dist/INSTALL.txt`](dist/INSTALL.txt)
- QA audit: [`apps/verity_dashboard/QA_AUDIT.md`](apps/verity_dashboard/QA_AUDIT.md)

Live recordings stay on the phone as a full-resolution SQLite table (not
compressed, not uploaded to GitHub, not synced to Polar Flow). Delete a
session from its detail screen, or clear all recordings in Settings.

Direct download (this repo is public):

https://github.com/MCdigital-design/Health-App/raw/main/dist/verity-dashboard.apk

Confirm the file is about **28 MB** before installing. Then open it from **My Files**, not Chrome.

```bash
cd apps/verity_dashboard
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Browser companion (secondary)

A Next.js Web Bluetooth dashboard for desktop Chrome/Edge. Demo mode works without a sensor.

```bash
npm install
npm run dev
```

Listens on [http://127.0.0.1:43147](http://127.0.0.1:43147).
