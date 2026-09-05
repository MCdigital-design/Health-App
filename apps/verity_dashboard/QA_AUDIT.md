# Verity Dashboard — Production Readiness Audit

This document maps the full data pipeline end to end, records what was
found broken, what was fixed and how, and what still needs manual
validation on real hardware (this environment has no physical BLE access,
so hardware-dependent behavior is documented as a test checklist rather
than "verified").

Pipeline audited:

```
sensor → BLE connection → packet ingestion → decoding → buffering →
live UI → recording → persistence → history → replay/import → error recovery
```

## 1. Sensor → BLE connection

**Implementation:** `PolarRepository` wraps the `polar` Flutter plugin,
which wraps Polar's official Android BLE SDK.

**Bugs found and fixed:**

- Connecting from one screen (Settings) and controlling streams from
  another (Live) caused `Start HR`/`Start PPG` to hang forever. Root
  cause: the SDK's "feature ready" event fires exactly once per connection
  and is not replayed to late subscribers. Fixed by caching ready-features
  per device in the repository (constructed once, alive for the app's
  lifetime) instead of relying on ad hoc per-call listeners.
- No reconnect logic existed at all — a dropped connection just showed
  "disconnected" forever. Added exponential backoff reconnection
  (3s/6s/12s/20s/30s, 5 attempts) triggered on unexpected disconnects,
  gated by a new "Auto Reconnect" setting that is now actually wired to
  behavior (previously the toggle only wrote to preferences and did
  nothing).
- No persistence of "last connected device," so app restart always
  required manually re-scanning. Now persisted and used both for
  auto-reconnect-on-launch and as the reconnect target after a drop.

**Remaining risk / manual test checklist:**

- [ ] Power off the sensor while connected — confirm a "Connection lost.
      Reconnecting in Ns..." status appears and the app reconnects when
      the sensor is powered back on.
- [ ] Walk out of BLE range (~10m+) and back — same expectation.
- [ ] Toggle phone Bluetooth off/on while connected.
- [ ] Force-stop and relaunch the app with Auto Reconnect on — it should
      reconnect to the last device without user action.

## 2. Packet ingestion / decoding

**Implementation:** the `polar` plugin decodes Polar's binary PMD protocol
into typed Dart objects (`PolarHrSample`, `PolarPpgSample`, etc.) before
they reach this app's code — this app does not parse raw BLE bytes itself.

**Bug found and fixed:** none of the streaming subscriptions had error
handlers. If the native side threw (e.g. HR streaming rejected because SDK
Mode was on), the failure was silently dropped — the app just showed
nothing, with no diagnostic. Every stream now has `onError`/`onDone`
handlers that clear internal state and surface a message via
`errorStream`.

**Genuine reliability gap found:** a BLE notification stream can go silent
(no more samples) without the platform channel ever firing `onError` or
`onDone` — this is how the reported HR stream "died" without any error.
This is now handled by the stream-health watchdog (§3).

**Second bug found and fixed (after further real-device testing):** a
12-minute recording captured 42,363 PPG samples but zero HR samples for
the entire session — not a transient stall (the watchdog would have
caught and recovered from that within seconds), but HR never running at
all, for the whole recording. Root cause: **Polar devices reject SDK Mode
changes while any online stream is active** (`INVALID_STATE`, documented
by Polar), and `enableSdkMode()` had no error handling — calling "Turn
off SDK Mode" while PPG was already streaming (which auto-starts on
connect) likely had the sensor silently reject the change, while the
app's UI still showed the toggle as changed and gave no error. Fixed by
having `enableSdkMode()` stop all active streams first, attempt the
change, then **always re-query the sensor's actual reported state**
afterward instead of trusting the request succeeded, surface a clear
error if the device didn't end up where requested, and restart whatever
was running before. Also added continuous retry (every 20s) for HR/PPG
when they *should* be running but aren't currently active — not just for
streams that go stale after being healthy — plus a persistent "Heart rate
is not active" banner on the Live screen with a manual retry button,
closing the gap where a single failed start attempt could go unnoticed
for an entire recording.

## 3. Buffering (the flatlining/flicker bugs)

**Bug found and fixed — the flatline:** the original Live screen appended
new points using `list.length` as the x-coordinate, then evicted the
oldest point once the list exceeded a fixed size. Once eviction started,
`list.length` stopped increasing, so every subsequent point was plotted at
the *same* x position — the line visually collapsed into a vertical
streak instead of scrolling. Root-caused and fixed by replacing the
list-based buffer with `TimeSeriesBuffer`
(`lib/models/time_series_buffer.dart`), which stores real timestamps and
computes x as actual elapsed seconds. Regression-tested in
`test/time_series_buffer_test.dart` (`x-axis stays monotonic and never
collides after eviction`).

**Bug found and fixed — the flicker:** `setState()` was called on every
single incoming sample, including PPG at up to ~176 Hz in SDK Mode — up to
176 full widget rebuilds per second. Decoupled ingestion from rendering:
samples are written into the buffer at full native rate, but the UI polls
the buffer on a fixed 500ms timer. Chart animation duration is set to zero
so each throttled redraw is instant rather than competing with the next
tick's animation.

**New feature — timeframe selector:** `ChartTimeframe` chips name the
*visible window* (Real-time / 30s / 2m / 10m / 30m / 2h). The old labels
(1s / 5s / 30s / 1m / 5m) were bucket sizes, so a selected "30s" chip
drew a 10-minute chart. Larger windows still average raw samples into
buckets (`TimeSeriesBuffer.spotsForTimeframe`). Tested in
`time_series_buffer_test.dart`.

**Live screenshot follow-up (v1.2.1):** Y ticks no longer append the raw
sample max (`164`, `360680`); X uses `now` / `-10m` instead of `-600s`;
the last sample's full value sits in a colored chip; PPG watchdog uses
phone wall-clock so it does not restart a healthy stream and raise
`ERROR_ALREADY_IN_STATE`.

**New feature — adaptive chart:** `LiveChart` uses `LayoutBuilder` to size
itself relative to available width (clamped 140–260px), switches to a
side-by-side layout above 700px width (tablets/landscape) via the Live
screen's own `LayoutBuilder`, and computes Y-axis min/max with padding
from the currently visible window (`yRangeForTimeframe`) instead of
autoscaling every frame, which is what previously caused visible jumping.

**Manual test checklist:**

- [ ] Leave the Live tab open for 10+ minutes with the sensor worn
      continuously — HR/PPG lines should keep scrolling, not flatten.
- [ ] Switch timeframes while data is streaming — chart should redraw
      cleanly at each zoom level.
- [ ] Rotate the phone to landscape — charts should reflow side-by-side.

## 4. Live UI → recording → persistence

**Confirmed: data was never actually lost.** `LocalDb` (sqflite) writes to
the app's private SQLite database, which survives app restarts and
in-place APK updates. It is only cleared if the app is uninstalled or the
user manually clears app storage in Android settings. The session shown
with "866 samples" in the bug report was genuinely on disk the whole time.

**Bug found and fixed — sessions "disappearing":** `MainShell` keeps all
four tabs alive simultaneously via `IndexedStack`, so each screen's
`initState()` (where data was loaded) runs exactly once, at app launch.
Finishing a recording on the Live tab had no way to tell the already-
mounted Recordings tab to reload — and the Recordings tab's refresh button
only rescanned on-device Polar exercises, not local phone sessions at all.
Fixed by adding `PolarRepository.sessionsChanged`, a broadcast stream
fired after every session start/stop/import/delete; Recordings and
Dashboard both subscribe to it and reload automatically.

**Bug found and fixed — "No HR data" was undiagnosable:** a session could
show a nonzero total sample count with zero HR samples (e.g. because HR
was disabled by SDK Mode, or the HR stream stalled, while PPG kept
flowing), and the UI gave no way to tell what actually happened.
`LocalDb.getSampleTypeCounts()` now returns per-signal counts (HR, PPG,
PPI, ACC, gyro, mag), surfaced in the new session detail screen with an
explicit explanation when HR is zero but other signals aren't.

**Storage answers (requested explicitly):**

| Question | Answer |
|---|---|
| Is anything actually saved? | Yes — SQLite, on disk, since before this audit. |
| Only held in memory? | No. Flushed every 2s during recording and on stop. |
| Can sessions be stored locally? | Yes, already the only mechanism. |
| Estimated storage per hour | HR only (~1 Hz): ~150–200 KB/hour. PPG (~42–55 Hz): ~6–18 MB/hour — this dominates total size. ACC @50 Hz adds roughly ~15 MB/hour if enabled. Gyro/mag similar if they actually stream. |
| Condensed or full table? | Full table. One SQLite row per sample, text-encoded channel lists. Charts downsample only for drawing. |
| Need a backend/VPS/DB? | No. This is single-user, single-device. A server only becomes justified for multi-device sync, multi-user access, or off-device backup — none apply here. |
| Upload to GitHub? | No. Heart-rate and PPG are health data. This repo is public. CSV export stays on the phone. |
| Sync to Polar official app? | No. Live recordings are a one-way BLE stream into this app. Polar Flow only sees button-press exercises if the sensor is paired with a Polar account. |
| How to delete | Session detail trash icon, Settings → Delete all recordings, or uninstall / clear app storage. |
| Local-first, sync later? | Recommended as-is. If cross-device access is ever needed, Polar Flow's own cloud (already integrated, §6) or a simple file-sync of the SQLite database is far less work than standing up a backend. |

**New feature:** session detail screen
(`lib/screens/session_detail_screen.dart`) — interactive time charts
(pinch/drag/zoom with elapsed-time X and adaptive Y), per-type sample
counts, an on-disk size estimate with hourly projection, delete, and CSV
export (written to the app's external files directory, path shown to the
user).

**Bug found and fixed — session HR chart said "No data" while counts showed
hundreds of HR samples:** `getSamples` silently limited to 5,000 rows
ordered by timestamp. Polar PPG timestamps can sort entirely before
phone-clock HR rows, so the first page was all PPG. Charts now query each
signal separately and plot elapsed seconds, not row index.

**Manual test checklist:**

- [ ] Record a session, switch to Recordings without restarting the app —
      it must appear immediately (this was the reported bug).
- [ ] Record a session, force-stop the app entirely (not just background),
      relaunch, check Recordings — session must still be there.
- [ ] Record 30+ minutes continuously; confirm the app doesn't slow down
      or run out of storage on a typical device (multi-GB free is normal;
      watch for low-storage devices specifically if PPG is recorded for
      hours).

## 5. App backgrounding / screen lock / lifecycle

**Bug found and fixed:** nothing previously reacted to the app being
backgrounded or resumed. Android can throttle or silently drop BLE
callbacks while backgrounded or the screen is locked. Added a
`WidgetsBindingObserver` in `MainShell` that calls
`PolarRepository.onAppResumed()` on `AppLifecycleState.resumed`, which
immediately re-checks stream health (rather than waiting for the next
5-second watchdog tick) and kicks a reconnect attempt if the connection
was dropped while backgrounded.

**Manual test checklist:**

- [ ] Start HR streaming, lock the screen for 60+ seconds, unlock — HR
      should resume promptly, not stay flatlined.
- [ ] Background the app (home button) for a few minutes, return — same
      expectation.
- [ ] Background during an active local recording — confirm the recording
      buffer still flushes and the session isn't truncated silently.

## 6. History / replay / import

Three distinct sources now exist, tagged via `SessionSource` and shown
with a badge in the UI:

1. **`live_app`** — recorded directly through this app (Live tab →
   Record). This is the primary, always-available path and requires no
   Polar account.
2. **`device_exercise`** — sessions recorded using the sensor's own
   physical button (recording/swimming mode) and still stored in the
   sensor's onboard memory. Retrieved via the BLE SDK's
   `listExercises()`/`fetchExercise()`. **Verity Sense requires the
   sensor to be registered to a Polar Flow account for this to work at
   all** — this is a Polar hardware/firmware limitation, not something
   this app can bypass.
3. **`polar_flow`** — sessions already uploaded to Polar Flow's cloud,
   including ones no longer physically on the sensor (which is almost
   certainly why "sessions I can see in the Polar app" weren't showing up
   here — the BLE SDK can only see what's still on the sensor). Retrieved
   via Polar's AccessLink REST API
   (`lib/polar/accesslink_service.dart`), which is a completely separate
   system from the BLE SDK.

**AccessLink integration status:** implemented end-to-end (OAuth2
authorization-code flow, token exchange, user registration, exercise
listing with samples, HR sample parsing, dedup on import) but **not
validated against a live Polar account**, because it requires a real
Polar API client (client ID/secret), which only the account holder can
create at admin.polaraccesslink.com — this cannot be provisioned by an
agent on the user's behalf. The exact request/response shapes are
implemented per Polar's published OpenAPI schema and JSON examples, with
defensive parsing (both underscore and hyphen key variants) since Polar's
own docs are inconsistent about naming.

**Duplicate-import protection:** both device-exercise sync and Polar Flow
import use a *deterministic* session ID derived from the exercise's own
identifier (`device:<deviceId>:<entryId>` / `polarflow:<exerciseId>`)
rather than a random UUID, and check `sessionExistsForExternalId()` before
inserting. Re-syncing or re-importing the same exercise updates/skips
rather than duplicating it.

**Manual test checklist (requires a real Polar account with existing Flow
history):**

- [ ] Create an AccessLink API client at admin.polaraccesslink.com.
- [ ] In Settings > Polar Flow, enter client ID/secret/redirect URI, tap
      Save, then Open Authorization Page, approve, copy the resulting URL
      back into the app, tap Connect.
- [ ] On Recordings, tap Import — verify exercises appear with correct
      dates and (if `samples=true` returned HR data) a working HR chart in
      the session detail view.
- [ ] Import a second time — verify no duplicates are created.
- [ ] On-device sync: record a session directly on the sensor (physical
      button, sensor registered to Flow), then sync it from the "On
      Device" section — verify it appears tagged "From sensor" and is
      removed from the sensor after sync.

## 7. Error recovery summary

| Failure mode | Safeguard |
|---|---|
| Feature-ready event missed | Cached per-device; late callers return immediately instead of hanging |
| Stream silently stops emitting | 5s watchdog checks staleness (12s threshold) per stream, cancels and restarts |
| Unexpected BLE disconnect | Exponential backoff reconnect (5 attempts), opt-in via Auto Reconnect |
| App backgrounded/screen locked | `onAppResumed()` immediately re-validates and restarts stalled streams |
| App fully restarted | Last device ID persisted; auto-reconnect-on-launch if enabled |
| Stream throws an error | `onError` handlers clear state and surface a message instead of silently doing nothing |
| Duplicate exercise/import sync | Deterministic IDs + existence check before insert |
| SDK Mode conflicting with HR | Real device state queried and surfaced; HR auto-restarts when SDK Mode is turned off |

## Known limitations / explicitly out of scope

- This was audited and unit-tested for logic correctness (buffer math, DB
  migration, dedup) but **not validated against physical Polar Verity
  Sense hardware** in this environment — the checklists above are the
  concrete steps to close that gap on your device.
- AccessLink (Polar Flow) import needs your own API credentials and has
  not been exercised against Polar's live servers.
- The Polar `polar` Flutter plugin does not expose Verity Sense's native
  offline-recording file API (2.1.0+ firmware feature); on-device history
  import is limited to the exercise-entry API, which is what Polar Flow
  itself also uses for this sensor.
