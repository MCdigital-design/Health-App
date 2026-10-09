# Verity Sense recording stability: developer and independent QA

Scope: **MCdigital-design/Health-App only**. The production Android
application is at `apps/verity_dashboard`. The newer APK is built from
`cursor/session-data-charts-imu-b838`, **not** the old `main` branch.
Never operate on AlphaTrend or any other repository.

## Lane A: development agent / build owner

- Own the implementation on a feature branch; never overwrite or uninstall
  the existing phone application while debugging.
- Preserve `applicationId`, signing certificate and SQLite migrations, so
  an APK can be installed in-place without clearing existing recordings.
- Implement deterministic regression tests for data persistence, stopped
  recording after disconnect, failed SQLite start/write, and large exports.
- Keep full-fidelity samples in SQLite; bound in-memory queues and export
  chunks. Treat optional BLE stream failures independently of recording
  persistence, and surface errors instead of claiming "saved".
- Run `flutter analyze`, `flutter test --concurrency=1` and Android build;
  attach the commit and exit status. A clean build is not proof BLE works.
- Do not upload sensor samples, health information, ChatGPT tokens or device
  identifiers to GitHub Issues or CI logs.

## Lane B: independent QA/QC agent (no self-approval)

- Review each modified code path against the failures below; do not simply
  trust the developer's summary.
- Use GitHub Actions job `independent-qa` to install an APK in a **clean,
  headless Android x86_64 emulator**, check the process is alive, and capture
  screenshot/UI hierarchy/logcat artifacts. This catches startup/visual and
  install failures only.
- Check the **actual** phone and Polar Verity Sense separately. The cloud
  emulator cannot pair with the physical BLE sensor, verify stream
  characteristics, or reproduce a native BLE disconnect.
- Require evidence for each claim in the acceptance matrix. If physical
  hardware evidence is missing, mark `NOT VERIFIED`; never `PASS`.
- Do not approve release while a reproducible record/disconnect/export
  regression remains or when logs show uncaught exceptions.

## Acceptance matrix

| Scenario | Expected result | Validation |
| --- | --- | --- |
| Cold start, sensor absent | App opens, no crash; Record disabled | Emulator / phone |
| Connect sensor with SDK Mode OFF and optional PPI OFF | Live HR ~1 Hz, PPG appears | Real sensor only |
| Tap Record, 5 min, Stop | Session saved; HR and PPG counts non-zero; clear duration | Real sensor only |
| Tap Record twice rapidly | At most one session starts | Widget test / real sensor |
| Disconnect sensor while recording | Stop remains enabled, partial session saved | Widget test + real sensor |
| DB fails during start | No false recording state, error visibly reported | Widget regression |
| Storage write fails during stop | No false "saved" success, pending samples retained | Code review + injected DB failure |
| Force-stop/relaunch | Previously flushed rows survive, orphan session finalized | DB tests / phone |
| Reinstall over same app (do NOT uninstall) | Historic sessions still visible | Real phone only |
| Long multi-signal session (30+ min) | No out-of-memory, counts persist; CSV exports all rows | Phone / DB tests |
| Optional PPI ON | HR update frequency changes; no silent assumptions | Real sensor only |
| Background/lock screen | Errors are visible; no promise of sustained BLE without foreground service | Real sensor only |

Polar's official Verity Sense documentation warns that the separate PPI
algorithm slows HR reporting to ~5-second intervals and may take ~25 seconds
before initial PPI data. For a stability baseline, leave optional PPI OFF
and SDK Mode OFF; enable other streams one at a time after baseline passes.
Documentation: https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md

## On-device crash evidence

With Android platform tools installed on a computer and Samsung USB debugging
enabled, reproduce **once** while collecting a filtered log:

```bash
adb logcat -c
adb logcat -v time -s flutter:V AndroidRuntime:E SQLiteLog:E Polar:V '*:S'
```

If the above filter is too restrictive, use `adb logcat -d -v time` and
look for `FATAL EXCEPTION`, `AndroidRuntime`, `OutOfMemoryError`,
`SQLiteException`, `PlatformException` or Polar BLE `INVALID_STATE`.
Redact device identifiers, URLs with tokens, and any health values before
sharing outside the phone.

## Release gate

Do **not** merge these changes to `main` or update `dist/verity-dashboard.apk`
until CI passes **and** a physical Polar Verity Sense passes the acceptance
matrix. A cloud screenshot is useful QA evidence, but not a substitute for
a sensor-record-stop-save test.

Security follow-up: the current **public** repository tracks
`apps/verity_dashboard/sideload.jks` and signing passwords in
`android/app/build.gradle.kts`. This signing credential is already
exposed and should be treated as compromised; do not casually rotate it
without an in-place data-preserving migration plan. Restrict future APK
distribution to a trusted channel.
