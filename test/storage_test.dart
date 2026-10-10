import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/services/book_text.dart';
import 'package:readalarm/services/storage.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('readalarm'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('loading waits for saves still being written', () async {
    final storage = FileAppStorage.at(dir);
    for (var i = 0; i < 30; i++) {
      storage.saveState({'n': i}); // Not awaited, like AppState.
    }
    expect(await storage.loadState(), {'n': 29});
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), ['state.json'],
        reason: 'no temp files left behind');
  });

  test('a failed save does not block later saves', () async {
    final storage = FileAppStorage.at(dir);
    // A directory where the temp file should go makes this write fail.
    Directory('${dir.path}/state.json.tmp').createSync();
    await expectLater(storage.saveState({'n': 1}), throwsA(anything));
    Directory('${dir.path}/state.json.tmp').deleteSync();

    await storage.saveState({'n': 2});
    expect(await storage.loadState(), {'n': 2});
  });

  test('book text round-trips and is deleted with the book', () async {
    final storage = FileAppStorage.at(dir);
    await storage.saveBookText(
        'b1', const BookText(sentences: ['One.', 'Two.']));
    expect((await storage.loadBookText('b1'))!.sentences, ['One.', 'Two.']);
    await storage.deleteBook('b1');
    expect(await storage.loadBookText('b1'), isNull);
  });

  test('a corrupt state file starts fresh instead of crashing', () async {
    File('${dir.path}/state.json').writeAsStringSync('{not json');
    expect(await FileAppStorage.at(dir).loadState(), isNull);
  });
}
