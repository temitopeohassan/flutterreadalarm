import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/models/reading_alarm.dart';
import 'package:readalarm/services/alarm_scheduler.dart';
import 'package:readalarm/services/billing_service.dart';
import 'package:readalarm/services/book_importer.dart';
import 'package:readalarm/state/app_state.dart';

import 'support/fakes.dart';
import 'support/sample_files.dart';

void main() {
  group('AppState', () {
    test('free tier limits books and alarms, premium lifts them', () async {
      final (state, _) = await demoState();
      expect(state.books.length, AppState.freeBookLimit);
      expect(state.canAddBook, isFalse);

      // Free users get 1 alarm; the demo has 2 (from Premium).
      expect(AppState.freeAlarmLimit, 1);
      expect(state.canAddAlarm, isFalse);
      await state.deleteAlarm(state.alarms.last);
      expect(state.canAddAlarm, isFalse);
      await state.deleteAlarm(state.alarms.last);
      expect(state.canAddAlarm, isTrue);

      state.setPremium(true);
      expect(state.canAddBook, isTrue);
      expect(state.canAddAlarm, isTrue);
      expect(state.has60MinAccess, isTrue);
      state.dispose();
    });

    test('rewarded unlock grants 60-minute access', () async {
      final (state, _) = await demoState();
      expect(state.has60MinAccess, isFalse);
      state.unlockRewarded();
      expect(state.has60MinAccess, isTrue);
      state.dispose();
    });

    test('everything survives a restart', () async {
      final (state, fakes) = await demoState();
      state
        ..setPremium(true)
        ..setSpeed(1.5)
        ..setVoice(FakeSpeech.voiceList[1])
        ..renameBook(state.books.first, 'Renamed')
        ..updatePosition(state.books.first.id, 555);
      await state.toggleAlarm(state.alarms.last, true);
      await pumpEventQueue();
      state.dispose();

      final restored = await AppState.load(fakes.services);
      expect(restored.isPremium, isTrue);
      expect(restored.speed, 1.5);
      expect(restored.voice, FakeSpeech.voiceList[1]);
      expect(restored.books.first.title, 'Renamed');
      expect(restored.books.first.position, 555);
      expect(restored.books.first.chapter, 'Chapter 6');
      expect(restored.alarms.first.book.title, 'Renamed');
      expect(restored.alarms.every((a) => a.enabled), isTrue);
      expect(restored.sessions.length, state.sessions.length);
      restored.dispose();
    });

    test('a second app instance never saves over the first one\'s progress',
        () async {
      // On Android an alarm can start a second copy of the app.
      final (first, fakes) = await demoState(premium: true);
      final second = await AppState.load(fakes.services);

      // The alarm copy reads on and adds a book; the first copy is stale.
      second.updatePosition('b2', 400);
      final (format, extracted) = await fakes.importer
          .extract(PickedBook(name: 'x.epub', read: () async => buildEpub()));
      await second.addExtractedBook(
          fileName: 'x.epub', format: format, extracted: extracted);
      await pumpEventQueue();

      // Back in the first copy: it reloads before doing anything.
      await first.reloadFromStorage();
      expect(first.bookById('b2').position, 400);
      expect(first.books.map((b) => b.title), contains('The Quiet Morning'));

      first.updatePosition('b1', 500);
      await pumpEventQueue();
      final saved = await AppState.load(fakes.services);
      expect(saved.bookById('b1').position, 500);
      expect(saved.bookById('b2').position, 400,
          reason: 'the first copy must not restore its stale position');
      expect(saved.books, hasLength(4));
      for (final s in [first, second, saved]) {
        s.dispose();
      }
    });

    test('reloading leaves an active reading session alone', () async {
      final (state, fakes) = await demoState();
      await state.reader.start(state.books.first);
      final other = await AppState.load(fakes.services);
      other.updatePosition(state.books.first.id, 1);
      await pumpEventQueue();

      await state.reloadFromStorage();
      expect(state.bookById(state.books.first.id).position, isNot(1));
      await state.reader.finish('stop');
      state.dispose();
      other.dispose();
    });

    test('alarms for different books each read their own book', () async {
      final (state, _) = await demoState(premium: true);
      final [a1, a2] = state.alarms;
      expect(a1.book.id, isNot(a2.book.id));
      for (final (alarm, from) in [(a2, 180), (a1, 420), (a2, 180)]) {
        await state.reader.start(state.bookById(alarm.book.id), durationMin: 1);
        expect(state.reader.bookId, alarm.book.id);
        expect(state.reader.index, from);
        await state.reader.finish('stop');
      }
      state.dispose();
    });

    test('alarms are scheduled with the OS and cancelled on delete', () async {
      final (state, fakes) = await demoState(premium: true);
      final enabled = state.alarms.where((a) => a.enabled).map((a) => a.id);
      expect(fakes.alarms.scheduled.keys, unorderedEquals(enabled));

      final alarm = ReadingAlarm(
        id: 'new',
        time: const TimeOfDay(hour: 6, minute: 30),
        book: state.books[2],
        durationMin: 15,
        repeatDays: const {},
      );
      await state.upsertAlarm(alarm);
      expect(fakes.alarms.scheduled['new'], same(alarm));

      await state.toggleAlarm(alarm, false);
      expect(fakes.alarms.scheduled.containsKey('new'), isFalse);

      await state.deleteAlarm(state.alarms.first);
      expect(fakes.alarms.scheduled.containsKey('a1'), isFalse);
      state.dispose();
    });

    test('one-off alarms that already rang are switched off at startup',
        () async {
      final (state, fakes) = await demoState(premium: true);
      await state.upsertAlarm(ReadingAlarm(
        id: 'once',
        time: const TimeOfDay(hour: 6, minute: 0),
        book: state.books.first,
        durationMin: 15,
        repeatDays: const {},
      ));
      await pumpEventQueue();
      state.dispose();
      fakes.alarms.scheduled.remove('once'); // It rang.

      final restored = await AppState.load(fakes.services);
      expect(
          restored.alarms.firstWhere((a) => a.id == 'once').enabled, isFalse);
      restored.dispose();
    });

    test('deleting a book removes its alarms and text', () async {
      final (state, fakes) = await demoState();
      final book = state.alarms.first.book;
      await state.deleteBook(book);
      expect(state.books, isNot(contains(book)));
      expect(state.alarms.where((a) => a.book == book), isEmpty);
      expect(fakes.storage.texts.containsKey(book.id), isFalse);
      expect(fakes.alarms.scheduled.containsKey('a1'), isFalse);
      state.dispose();
    });

    test('nextAlarm is the enabled alarm that rings soonest', () async {
      final (state, _) = await demoState();
      final next = state.nextAlarm!;
      final now = DateTime.now();
      for (final a in state.alarms.where((a) => a.enabled)) {
        expect(
            next.nextOccurrence(now).isAfter(a.nextOccurrence(now)), isFalse);
      }
      state.dispose();
    });

    test('permissions come from the device; auto-start from the user',
        () async {
      final (state, fakes) = await demoState();
      expect(state.allPermissionsGranted, isFalse);
      for (final key in state.permissions.keys.toList()) {
        await state.requestPermission(key);
      }
      expect(fakes.permissions.requested,
          ['notifications', 'exactAlarm', 'battery']);
      expect(state.autoStartConfirmed, isTrue);
      expect(state.allPermissionsGranted, isTrue);
      state.dispose();
    });

    test('imported books keep their text, title and author', () async {
      final (state, fakes) = await demoState(emptyLibrary: true);
      final (format, extracted) = await fakes.importer
          .extract(PickedBook(name: 'x.epub', read: () async => buildEpub()));
      final book = await state.addExtractedBook(
          fileName: 'x.epub', format: format, extracted: extracted);

      expect(book.title, 'The Quiet Morning');
      expect(book.author, 'Ada Writer');
      expect(book.format, 'EPUB');
      expect(book.sentenceCount, 7);
      expect(book.chapter, 'One: The Kettle');
      expect((await fakes.storage.loadBookText(book.id))!.sentences.length, 7);
      state.dispose();
    });

    test('a book without a title is named after its file', () async {
      final (state, fakes) = await demoState(emptyLibrary: true);
      final (format, extracted) = await fakes.importer.extract(PickedBook(
          name: 'Field Notes.pdf', read: () async => buildPdf(title: '')));
      final book = await state.addExtractedBook(
          fileName: 'Field Notes.pdf', format: format, extracted: extracted);
      expect(book.title, 'Field Notes');
      expect(book.format, 'PDF');
      state.dispose();
    });

    test('the test alarm rings in a minute with the last-read book', () async {
      final (state, fakes) = await demoState();
      expect(await state.scheduleTestAlarm(), isTrue);
      final (payload, at) = fakes.alarms.once.single;
      expect(payload.bookId, state.lastReadBook!.id);
      expect(payload.durationMin, 1);
      expect(at.difference(DateTime.now()).inSeconds, closeTo(60, 2));
      state.dispose();

      final (empty, _) = await demoState(emptyLibrary: true);
      expect(await empty.scheduleTestAlarm(), isFalse);
      empty.dispose();
    });

    test('opening a ringing alarm switches off a one-off alarm', () async {
      final (state, fakes) = await demoState(premium: true);
      final once = ReadingAlarm(
        id: 'once',
        time: const TimeOfDay(hour: 6, minute: 0),
        book: state.books.first,
        durationMin: 15,
        repeatDays: const {},
      );
      await state.upsertAlarm(once);
      fakes.alarms.onLaunch!(
          AlarmLaunch(AlarmPayload.forAlarm(once), AlarmAction.open));

      final (alarm, action) = state.pendingAlarm.value!;
      expect(alarm.id, 'once');
      expect(action, AlarmAction.open);
      expect(state.alarms.firstWhere((a) => a.id == 'once').enabled, isFalse);

      await state.snoozeAlarm(alarm);
      expect(fakes.alarms.dismissed, ['once']);
      expect(fakes.alarms.once.single.$1.alarmId, 'once');
      state.dispose();
    });
  });

  group('free daily reading', () {
    test('resets at local midnight', () async {
      final (state, _) = await demoState();
      final evening = DateTime(2026, 11, 10, 23, 50);
      withClock(Clock.fixed(evening), () {
        state.countFreeReading(const Duration(minutes: 15));
        expect(state.dailyLimitReached, isTrue);
        expect(state.untilFreeReset, const Duration(minutes: 10));
      });
      withClock(Clock.fixed(DateTime(2026, 11, 11, 0, 1)), () {
        expect(state.freeReadingLeft, AppState.freeDailyReading);
        state.countFreeReading(const Duration(minutes: 1));
        expect(state.freeReadingLeft!.inMinutes, 14);
      });
      state.dispose();
    });
  });

  group('saving alarms', () {
    ReadingAlarm alarmAt(String id, int hour, int minute,
            {Set<int> days = const {}, DateTime? date, String book = 'b3'}) =>
        ReadingAlarm(
          id: id,
          time: TimeOfDay(hour: hour, minute: minute),
          book: SampleData.books.firstWhere((b) => b.id == book),
          durationMin: 15,
          repeatDays: days,
          date: date,
        );
    final tomorrow =
        DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));

    test('free users are stopped at 1 alarm however the save happens',
        () async {
      final (state, fakes) = await demoState();
      for (final a in List.of(state.alarms)) {
        await state.deleteAlarm(a);
      }
      expect((await state.saveAlarm(alarmAt('3', 21, 0))).status,
          AlarmSaveStatus.saved);
      expect((await state.saveAlarm(alarmAt('4', 22, 0))).status,
          AlarmSaveStatus.limitReached);
      expect(state.alarms, hasLength(1));
      expect(fakes.alarms.scheduled.containsKey('4'), isFalse);

      // Editing an existing alarm is still allowed at the limit.
      expect(
          (await state.saveAlarm(state.alarms.first
                  .copyWith(time: const TimeOfDay(hour: 6, minute: 0))))
              .status,
          AlarmSaveStatus.saved);

      state.setPremium(true);
      expect((await state.saveAlarm(alarmAt('4', 22, 0))).status,
          AlarmSaveStatus.saved);
      state.dispose();
    });

    test('two repeating alarms clash only on a shared day', () async {
      final (state, _) = await demoState(premium: true);
      // a1 rings 7:00 Mon, Wed, Fri.
      final clash = await state.saveAlarm(alarmAt('x', 7, 0, days: {2, 6}));
      expect(clash.status, AlarmSaveStatus.clash);
      expect(clash.clash!.id, 'a1');

      expect((await state.saveAlarm(alarmAt('y', 7, 0, days: {1, 3}))).status,
          AlarmSaveStatus.saved,
          reason: 'Tue, Thu: no shared day');
      expect((await state.saveAlarm(alarmAt('z', 7, 1, days: {0}))).status,
          AlarmSaveStatus.saved,
          reason: 'a minute later');
      state.dispose();
    });

    test('one-off alarms clash by date and time', () async {
      final (state, _) = await demoState(premium: true);
      final day = tomorrow.add(const Duration(days: 30));
      expect((await state.saveAlarm(alarmAt('o1', 16, 0, date: day))).status,
          AlarmSaveStatus.saved);

      final same = await state.saveAlarm(alarmAt('o2', 16, 0, date: day));
      expect(same.status, AlarmSaveStatus.clash);
      expect(same.clash!.id, 'o1');

      final nextDay = day.add(const Duration(days: 1));
      expect(
          (await state.saveAlarm(alarmAt('o3', 16, 0, date: nextDay))).status,
          AlarmSaveStatus.saved);

      // A repeating alarm on that weekday at that time clashes too.
      final weekly =
          await state.saveAlarm(alarmAt('w', 16, 0, days: {day.weekday - 1}));
      expect(weekly.status, AlarmSaveStatus.clash);
      state.dispose();
    });

    test('an alarm never clashes with itself when edited', () async {
      final (state, _) = await demoState();
      final a1 = state.alarms.first;
      expect((await state.saveAlarm(a1.copyWith(durationMin: 15))).status,
          AlarmSaveStatus.saved);
      state.dispose();
    });

    test('a one-off alarm in the past is refused', () async {
      final (state, _) = await demoState(premium: true);
      final yesterday = tomorrow.subtract(const Duration(days: 2));
      expect(
          (await state.saveAlarm(alarmAt('p', 9, 0, date: yesterday))).status,
          AlarmSaveStatus.inPast);
      state.dispose();
    });

    test('a dated one-off is scheduled for its day and survives a restart',
        () async {
      final (state, fakes) = await demoState(premium: true);
      final day = tomorrow.add(const Duration(days: 5));
      await state.saveAlarm(alarmAt('o', 16, 0, date: day));
      expect(fakes.alarms.scheduled['o']!.nextOccurrence(DateTime.now()),
          DateTime(day.year, day.month, day.day, 16));
      await pumpEventQueue();
      state.dispose();

      final restored = await AppState.load(fakes.services);
      final o = restored.alarms.firstWhere((a) => a.id == 'o');
      expect(o.date, day);
      expect(o.scheduleLabel, 'Once · ${formatDay(day)}');
      restored.dispose();
    });

    test('switching a past one-off back on moves it to its next time',
        () async {
      final (state, _) = await demoState(premium: true);
      final old = alarmAt('old', 6, 0,
          date: tomorrow.subtract(const Duration(days: 10)));
      await state.upsertAlarm(old.copyWith(enabled: false));
      await state.toggleAlarm(state.alarms.last, true);
      final moved = state.alarms.last;
      expect(moved.onceAt!.isAfter(DateTime.now()), isTrue);
      expect(moved.onceAt!.difference(DateTime.now()).inHours, lessThan(25));
      state.dispose();
    });
  });

  group('alarms the system dropped', () {
    test('are scheduled again when the app starts', () async {
      final (state, fakes) = await demoState();
      expect(fakes.alarms.scheduled.keys, ['a1']);
      state.dispose();

      // The phone stopped the app: its alarms are gone, though the plugin
      // still lists them as pending.
      fakes.alarms.dropAll();
      final restored = await AppState.load(fakes.services);
      expect(fakes.alarms.scheduled.keys, ['a1']);
      expect(restored.alarms.first.enabled, isTrue);
      restored.dispose();
    });

    test('are scheduled again on resync', () async {
      final (state, fakes) = await demoState();
      fakes.alarms.dropAll();
      await state.resyncAlarms();
      expect(fakes.alarms.scheduled.keys, ['a1']);
      state.dispose();
    });

    test('a dated one-off whose time passed is switched off', () async {
      final (state, fakes) = await demoState(premium: true);
      final past = DateTime.now().subtract(const Duration(days: 1));
      await state.upsertAlarm(ReadingAlarm(
        id: 'gone',
        time: TimeOfDay(hour: past.hour, minute: past.minute),
        book: state.books.first,
        durationMin: 15,
        repeatDays: const {},
        date: DateUtils.dateOnly(past),
      ));
      fakes.alarms.dropAll();
      await state.resyncAlarms();
      expect(state.alarms.firstWhere((a) => a.id == 'gone').enabled, isFalse);
      expect(fakes.alarms.scheduled.containsKey('gone'), isFalse);
      state.dispose();
    });
  });

  group('Google Play subscription', () {
    test('is checked at start-up; a lapsed one ends Premium', () async {
      final (state, fakes) = await demoState(premium: true);
      await state.toggleAlarm(state.alarms.last, true);
      await pumpEventQueue();
      state.dispose();

      // Offline: Premium stays as last known.
      var restored = await AppState.load(fakes.services);
      await pumpEventQueue();
      expect(restored.isPremium, isTrue);
      restored.dispose();

      // Play says the subscription ended: back to the free tier, with one
      // alarm on.
      fakes.billing.available = true;
      restored = await AppState.load(fakes.services);
      await pumpEventQueue();
      expect(restored.isPremium, isFalse);
      expect([for (final a in restored.alarms) a.enabled], [true, false]);
      restored.dispose();

      // An active subscription is picked up too.
      fakes.billing.owned.add(PremiumPlans.yearly);
      restored = await AppState.load(fakes.services);
      await pumpEventQueue();
      expect(restored.isPremium, isTrue);
      restored.dispose();
    });

    test('a failed purchase is reported and changes nothing', () async {
      final (state, fakes) = await demoState();
      fakes.billing
        ..available = true
        ..nextPurchase = BillingEventKind.failed;
      expect(await state.buyPremium(PremiumPlans.yearly), BuyResult.started);
      await pumpEventQueue();
      expect(state.isPremium, isFalse);
      expect(state.billingNotice.value, contains('didn\'t go through'));
      state.dispose();
    });
  });

  group('free alarms', () {
    test('without Premium, alarms beyond the free one are switched off',
        () async {
      // Set up with Premium (or an earlier version's 3 free alarms).
      final (state, fakes) = await demoState(premium: true);
      expect(await state.toggleAlarm(state.alarms.last, true),
          AlarmSaveStatus.saved);
      expect(state.alarms.every((a) => a.enabled), isTrue);
      state.setPremium(false);
      await pumpEventQueue();
      state.dispose();

      final restored = await AppState.load(fakes.services);
      expect([for (final a in restored.alarms) a.enabled], [true, false]);
      expect(fakes.alarms.scheduled.keys, ['a1']);
      // Switching the other back on needs Premium.
      expect(await restored.toggleAlarm(restored.alarms.last, true),
          AlarmSaveStatus.limitReached);
      expect(restored.alarms.last.enabled, isFalse);
      restored.dispose();
    });
  });

  group('ReadingAlarm', () {
    test('nextOccurrence honours the time and repeat days', () {
      final alarm = ReadingAlarm(
        id: 'x',
        time: const TimeOfDay(hour: 7, minute: 0),
        book: SampleData.books.first,
        durationMin: 15,
        repeatDays: const {0, 2}, // Mon, Wed
      );
      // Monday 2026-09-28 06:00 → same day 07:00.
      expect(alarm.nextOccurrence(DateTime(2026, 9, 28, 6)),
          DateTime(2026, 9, 28, 7));
      // Monday 08:00 → Wednesday 07:00.
      expect(alarm.nextOccurrence(DateTime(2026, 9, 28, 8)),
          DateTime(2026, 9, 30, 7));
      // Wednesday 07:00 exactly → next Monday.
      expect(alarm.nextOccurrence(DateTime(2026, 9, 30, 7)),
          DateTime(2026, 10, 5, 7));
      // One-off: tomorrow if today's time has passed.
      expect(
          alarm.copyWith(
              repeatDays: const {}).nextOccurrence(DateTime(2026, 9, 28, 8)),
          DateTime(2026, 9, 29, 7));
    });
  });
}
