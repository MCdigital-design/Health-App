import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:verity_dashboard/main.dart';
import 'package:verity_dashboard/storage/local_db.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.databaseFileName = 'verity_widget_test.db';
  });

  testWidgets('App shell renders bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const VerityDashboardApp());
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Recordings'), findsWidgets);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('AI'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });
}
