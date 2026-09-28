import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/state/app_state.dart';

void main() {
  group('AppState', () {
    test('free tier limits books and alarms, premium lifts them', () {
      final state = AppState();
      while (state.books.length < AppState.freeBookLimit) {
        state.addBook(state.books.first.copyWith(title: 'extra'));
      }
      expect(state.canAddBook, isFalse);

      state.setPremium(true);
      expect(state.canAddBook, isTrue);
      expect(state.canAddAlarm, isTrue);
      expect(state.has60MinAccess, isTrue);
    });

    test('rewarded unlock grants 60-minute access', () {
      final state = AppState();
      expect(state.has60MinAccess, isFalse);
      state.unlockRewarded();
      expect(state.has60MinAccess, isTrue);
    });

    test('deleting a book disables alarms that use it', () {
      final state = AppState();
      final alarm = state.alarms.firstWhere((a) => a.enabled);
      state.deleteBook(alarm.book);
      expect(state.books, isNot(contains(alarm.book)));
      expect(
        state.alarms
            .where((a) => a.book == alarm.book)
            .every((a) => !a.enabled),
        isTrue,
      );
    });

    test('upsertAlarm replaces by id and toggleAlarm flips enabled', () {
      final state = AppState();
      final alarm = state.alarms.first;
      final count = state.alarms.length;

      state.toggleAlarm(alarm, !alarm.enabled);
      expect(state.alarms.length, count);
      expect(state.alarms.first.enabled, !alarm.enabled);

      state.deleteAlarm(alarm);
      expect(state.alarms.length, count - 1);
    });

    test('nextAlarm is the earliest enabled alarm', () {
      final state = AppState();
      final next = state.nextAlarm;
      expect(next, isNotNull);
      int minutes(ReadingAlarm a) => a.time.hour * 60 + a.time.minute;
      for (final a in state.alarms.where((a) => a.enabled)) {
        expect(minutes(next!), lessThanOrEqualTo(minutes(a)));
      }
    });

    test('grantPermission marks a permission granted', () {
      final state = AppState();
      for (final key in state.permissions.keys.toList()) {
        state.grantPermission(key);
      }
      expect(state.allPermissionsGranted, isTrue);
    });
  });
}
