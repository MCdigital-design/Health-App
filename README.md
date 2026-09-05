# Health-App

Dedicated home for Polar Verity Sense work, moved out of [alphatrend-mt5-qa#1](https://github.com/MCdigital-design/alphatrend-mt5-qa/pull/1). This repository is not an AlphaTrend / MT5 project.

## Polar Verity Sense Android app (primary)

Flutter dashboard you sideload on a Samsung phone. Live HR/PPG, recording, history, CSV export, optional Polar Flow import. No Play Store.

- App source: [`apps/verity_dashboard`](apps/verity_dashboard)
- Sideload APK: [`dist/verity-dashboard.apk`](dist/verity-dashboard.apk) (28 MB, SHA256 `3553f8ead2deceb61bf5f1d6a0d231fef432872f071987e850e700a210c27092`)
- Install notes: [`dist/INSTALL.txt`](dist/INSTALL.txt)
- QA audit: [`apps/verity_dashboard/QA_AUDIT.md`](apps/verity_dashboard/QA_AUDIT.md)

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
