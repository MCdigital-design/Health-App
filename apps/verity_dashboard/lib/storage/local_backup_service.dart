import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'local_db.dart';

/// Local-only backup. Android Storage Access Framework is used to write an
/// AES-GCM encrypted snapshot to a user-selected Documents folder.
class LocalBackupService {
  LocalBackupService._();
  static final LocalBackupService instance = LocalBackupService._();
  static const channel = MethodChannel('verity_dashboard/local_backup');

  Future<bool> get hasFolder async =>
      await channel.invokeMethod<String>('folderStatus') != null;

  Future<bool> get hasPassword async =>
      await channel.invokeMethod<bool>('hasSecret') ?? false;

  /// Android keeps selected folder permission on updates, not on uninstall.
  Future<bool> chooseFolder() async =>
      await channel.invokeMethod<String>('chooseFolder') != null;

  Future<void> savePassword(String password) async {
    if (password.length < 8) {
      throw ArgumentError('Recovery password must be at least 8 characters');
    }
    await channel.invokeMethod<bool>('saveSecret', {'password': password});
  }

  Future<bool> get isConfigured async => await hasFolder && await hasPassword;

  Future<String> backupNow() async {
    if (!await isConfigured) {
      throw StateError('Choose a backup folder and recovery password first');
    }
    final temp = await getTemporaryDirectory();
    final snapshot = File('${temp.path}/verity-snapshot-${const Uuid().v4()}.db');
    try {
      await LocalDb.instance.createConsistentSnapshot(snapshot.path);
      return await channel.invokeMethod<String>(
            'backup', {'snapshotPath': snapshot.path},
          ) ??
          (throw StateError('Android did not confirm the backup'));
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// Returns false when backups are not configured. Propagates storage
  /// errors rather than reporting that samples were backed up successfully.
  Future<bool> backupIfConfigured() async {
    if (!await isConfigured) return false;
    await backupNow();
    return true;
  }

  /// Reinstalled apps must reselect their phone folder and provide the
  /// ORIGINAL password: Android destroys its Keystore keys at uninstall.
  Future<String> restoreLatest(String password) async {
    if (password.isEmpty) throw ArgumentError('Enter recovery password');
    if (!await hasFolder) throw StateError('Select your original backup folder');
    final temp = await getTemporaryDirectory();
    final snapshot = File('${temp.path}/verity-restore-${const Uuid().v4()}.db');
    try {
      final name = await channel.invokeMethod<String>('restore', {
        'destinationPath': snapshot.path,
        'password': password,
      });
      if (name == null) throw StateError('No archive was restored');
      await LocalDb.instance.restoreConsistentSnapshot(snapshot.path);
      await savePassword(password);
      return name;
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }
}
