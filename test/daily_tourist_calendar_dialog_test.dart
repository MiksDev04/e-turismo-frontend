import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/admin/models/daily_tourist_models.dart';
import 'package:app/ui/admin/widgets/daily_tourist_calendar_dialog.dart';

void main() {
  testWidgets('calendar marks today and shows the daily count', (tester) async {
    final now = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDailyTouristCalendarDialog(
                  context: context,
                  title: 'Daily Tourist Record',
                  fetch: (m, y) async => DailyTouristsResult(
                    year: y,
                    month: m,
                    byDay: {now.day: 7},
                    total: 7,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Today's cell carries the pill and its tourist count is rendered.
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data == '7' &&
            w.style?.fontSize == 15,
      ),
      findsOneWidget,
    );

    // Tapping a date must not close the dialog.
    await tester.tap(find.text('Today'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data == '7' &&
            w.style?.fontSize == 15,
      ),
      findsOneWidget,
    );
  });
}
