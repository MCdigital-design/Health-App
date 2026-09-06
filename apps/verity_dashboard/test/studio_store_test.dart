import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:verity_dashboard/ai/studio_dashboard_store.dart';
import 'package:verity_dashboard/storage/local_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.databaseFileName = 'verity_studio_store_test.db';
  });

  test('ai_dashboards persist custom views across list/delete', () async {
    final store = StudioDashboardStore();
    for (final row in await store.list()) {
      await store.delete(row.id);
    }

    final id = await store.insert(
      title: 'Recovery',
      specJson: '{"title":"Recovery","widgets":[{"type":"metric","title":"RMSSD","value":"12","unit":"ms"}]}',
      accountHint: 'anyone@example.com',
    );
    final rows = await store.list();
    expect(rows.single.id, id);
    expect(rows.single.title, 'Recovery');
    expect(rows.single.spec?.widgets.single.value, '12');
    expect(rows.single.accountHint, 'anyone@example.com');

    await store.delete(id);
    expect(await store.list(), isEmpty);
  });
}
