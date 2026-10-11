# On-device history, backup and recovery (Android)

## Actual storage guarantees

- Primary source: SQLite database verity_dashboard.db in Android app-private storage.
- Process restart and in-place signed APK upgrade with the same application ID preserve it.
- Uninstall, Clear Storage, phone reset or phone loss can delete app-private data.
- Android clears Storage Access Framework grants on uninstall. No app can silently reopen a private Documents folder after reinstall without renewed user authorization.
- Secondary source: encrypted complete SQLite snapshots in an **explicitly user-selected phone Documents subfolder**, outside the Android app-private directory.
- The backup folder is not a cloud service; the user must select a local phone folder rather than a cloud provider in the Android picker. Backups can still be lost if the phone itself is lost/damaged/reset.
- No data is sent to GitHub, a hosted backend, or Polar Flow by this feature.

## First installation

1. Settings > Local encrypted backup > Choose phone backup folder.
2. In Android Files, create/select a subfolder under internal Documents, such as Documents/VerityBackups. Grant access.
3. Set a strong recovery password (minimum eight characters) and record it separately in a password manager.
4. Tap Backup now / enable auto, and verify the app reports a completed verity-...vbak file.
5. Every successful Stop now completes the local SQLite transaction, then attempts a new complete encrypted snapshot. The two newest completed snapshots remain. Importing or deleting a session also refreshes the archive.
6. A FAILED backup warning means the last session exists in app-private SQLite but the external archive may be stale. Do not uninstall until a new backup succeeds.

## Upgrading

Install the new signed APK directly on top of the old one; **never uninstall first**. Both app-private data and SAF permission remain across a compatible update. Recheck the phone history and backup status afterward.

## Reinstall or new phone

1. Install the app; do not create a new backup first.
2. Settings > Local encrypted backup > Choose phone backup folder. Reselect the same existing phone folder (or copy the saved .vbak files from your old phone to a folder on the new phone).
3. Enter the ORIGINAL recovery password. This is required because Android removed the in-app Android Keystore key on uninstall.
4. Tap Restore after reinstall. Confirm database replacement.
5. The app validates the encrypted GCM tag, SQLite integrity, schema and required tables before replacing its primary database. If validation fails, it refuses replacement.
6. The restored password is rewrapped with this install's Android Keystore key, allowing subsequent automatic backups.

Restore **replaces** current app sessions with the backed-up set. Do not create new recordings before restoring, because the last completed archive is the restored state.

## Technical limitations / QA

- SQLite VACUUM INTO creates a consistent snapshot (Android system SQLite must support VACUUM INTO, available on modern Samsung Android versions).
- Kotlin Android SAF code streams AES-256-GCM authenticated encryption and PBKDF2-HMAC-SHA256 key derivation. The temporary plaintext snapshot is in app-private cache and deleted after use.
- The local automatic-backup password is wrapped with Android Keystore; it isn't stored plaintext in shared preferences or in the backup file.
- Recordings made only by the sensor's own button are not removed from the sensor by this app after import.
- Unit tests verify multi-signal SQLite roundtrip and that an invalid SQLite archive cannot replace the database.
- CI can build, run unit/widget tests, and install/launch on an Android emulator. CI **cannot** verify a real Polar Verity Sense Bluetooth recording, phone document-provider permissions, user-selected folder recovery, or physical reinstall. Those require a supervised phone acceptance test before claiming fully production validated.
- Existing signing keystore in this repo's history was exposed while repository was public; repository privacy and future signing migration remain separate concerns.
