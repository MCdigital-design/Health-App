import 'dart:async';

import '../storage/local_db.dart';
import 'studio_spec.dart';

class SavedStudioDashboard {
  const SavedStudioDashboard({
    required this.id,
    required this.title,
    required this.specJson,
    required this.createdMs,
    this.accountHint,
  });

  final int id;
  final String title;
  final String specJson;
  final int createdMs;
  final String? accountHint;

  StudioDashboardSpec? get spec => StudioDashboardSpec.tryParse(specJson);
}

class StudioDashboardStore {
  StudioDashboardStore([LocalDb? db]) : _db = db ?? LocalDb.instance;

  final LocalDb _db;

  static final StreamController<void> _changes = StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;

  Future<List<SavedStudioDashboard>> list() async {
    final db = await _db.database;
    final rows = await db.query('ai_dashboards', orderBy: 'created_ms DESC');
    return rows
        .map(
          (row) => SavedStudioDashboard(
            id: row['id'] as int,
            title: row['title'] as String,
            specJson: row['spec_json'] as String,
            createdMs: row['created_ms'] as int,
            accountHint: row['account_hint'] as String?,
          ),
        )
        .toList();
  }

  Future<int> insert({
    required String title,
    required String specJson,
    String? accountHint,
  }) async {
    final db = await _db.database;
    final id = await db.insert('ai_dashboards', {
      'title': title,
      'spec_json': specJson,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'account_hint': accountHint,
    });
    _changes.add(null);
    return id;
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('ai_dashboards', where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }
}
