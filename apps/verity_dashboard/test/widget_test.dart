import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:verity_dashboard/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App shell renders bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const VerityDashboardApp());
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Recordings'), findsWidgets);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });
}
