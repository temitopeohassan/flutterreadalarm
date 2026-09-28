import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps the widget showing [text], scrolling it into view first. Lazily built
/// lists only create on-screen children, so a plain `find.text` can miss it.
Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(text), 200,
        scrollable: find.byType(Scrollable).last);
  }
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
