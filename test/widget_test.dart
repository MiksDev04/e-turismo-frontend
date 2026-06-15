import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app.dart';

void main() {
  testWidgets('App launches and renders dashboard route', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle(); // wait for fade transition to complete

    // The dashboard placeholder (or real page) should be visible.
    // Update the finder below once your real DashboardPage has a stable widget.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}