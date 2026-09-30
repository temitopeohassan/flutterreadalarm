import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/services/playback_service.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('reads aloud from the saved position and saves progress',
      (tester) async {
    final (state, fakes) = await demoState();
    final book = state.books.first; // position 420
    expect(await state.reader.start(book), isTrue);
    await tester.pump();

    expect(state.reader.playing, isTrue);
    expect(fakes.speech.spoken.single, demoText().sentences[420]);
    expect(fakes.playback.visible, isTrue);

    // Each demo sentence takes about a second to "speak".
    await tester.pump(const Duration(seconds: 5));
    expect(fakes.speech.spoken.length, greaterThan(3));
    expect(state.bookById(book.id).position, greaterThan(420));
    expect(state.reader.elapsed.inSeconds, 5);

    await state.reader.finish('stop');
    expect(fakes.playback.visible, isFalse);
    expect(state.sessions.first.bookTitle, book.title);
    expect(state.sessions.first.endReason, 'stop');
    state.dispose();
  });

  testWidgets('pause, resume and skip', (tester) async {
    final (state, fakes) = await demoState();
    final reader = state.reader;
    await reader.start(state.books.first);
    await tester.pump();

    await reader.pause();
    final spoken = fakes.speech.spoken.length;
    await tester.pump(const Duration(seconds: 5));
    expect(fakes.speech.spoken.length, spoken, reason: 'silent while paused');
    expect(reader.elapsed, Duration.zero, reason: 'clock stops while paused');

    await reader.skip(-2);
    expect(reader.index, 418);
    reader.resume();
    await tester.pump();
    expect(fakes.speech.spoken.last, demoText().sentences[418]);

    await reader.skip(3);
    await tester.pump();
    expect(reader.index, 421);
    expect(fakes.speech.spoken.last, demoText().sentences[421]);

    await reader.finish('stop');
    state.dispose();
  });

  testWidgets('an alarm session ends by itself when its time is up',
      (tester) async {
    final (state, _) = await demoState();
    await state.reader.start(state.books.first, durationMin: 1);
    await tester.pump(const Duration(seconds: 61));

    expect(state.reader.active, isFalse);
    final done = state.reader.lastCompleted!;
    expect(done.reason, 'duration');
    expect(done.minutes, 1);
    expect(state.sessions.first.minutes, 1);
    state.dispose();
  });

  testWidgets('finishing the book ends the session', (tester) async {
    final (state, _) = await demoState();
    final book = state.books.first;
    state.updatePosition(book.id, 998);
    await state.reader.start(state.bookById(book.id));
    await tester.pump(const Duration(seconds: 5));

    expect(state.reader.lastCompleted!.reason, 'finished');
    expect(state.bookById(book.id).isFinished, isTrue);

    // Starting a finished book again begins at the start.
    await state.reader.start(state.bookById(book.id));
    expect(state.reader.index, 0);
    await state.reader.finish('stop');
    state.dispose();
  });

  testWidgets('lock-screen buttons pause and stop', (tester) async {
    final (state, fakes) = await demoState();
    await state.reader.start(state.books.first);
    await tester.pump();

    fakes.playback.onCommand!(playbackToggle);
    await tester.pump();
    expect(state.reader.playing, isFalse);
    expect(fakes.playback.text, startsWith('Paused'));

    fakes.playback.onCommand!(playbackToggle);
    await tester.pump();
    expect(state.reader.playing, isTrue);

    fakes.playback.onCommand!(playbackStop);
    await tester.pump();
    expect(state.reader.active, isFalse);
    state.dispose();
  });

  testWidgets('voice settings apply; Premium-only ones need Premium',
      (tester) async {
    final (state, fakes) = await demoState();
    state
      ..setSpeed(1.5)
      ..setPitch(1.3)
      ..setVoice(FakeSpeech.voiceList.first);
    await state.reader.start(state.books.first);
    await tester.pump();
    expect(fakes.speech.speed, 1.5);
    expect(fakes.speech.pitch, 1.0);
    expect(fakes.speech.voice, isNull);

    state.setPremium(true);
    state.setSpeed(1.25);
    await tester.pump();
    expect(fakes.speech.speed, 1.25);
    expect(fakes.speech.pitch, 1.3);
    expect(fakes.speech.voice, FakeSpeech.voiceList.first);

    await state.reader.finish('stop');
    state.dispose();
  });
}
