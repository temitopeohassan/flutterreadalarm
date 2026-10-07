import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/services/book_extractor.dart';
import 'package:readalarm/services/book_text.dart';

import 'support/sample_files.dart';

void main() {
  group('splitSentences', () {
    test('splits on sentence punctuation followed by a capital', () {
      expect(
        splitSentences('One two.  Three four!\nFive? "Six," she said. e.g. no'),
        ['One two.', 'Three four!', 'Five?', '"Six," she said. e.g. no'],
      );
    });

    test('breaks very long sentences into speakable chunks', () {
      final long = List.filled(120, 'word,').join(' ');
      final parts = splitSentences(long);
      expect(parts.length, greaterThan(1));
      expect(parts.every((s) => s.length <= maxSentenceLength + 1), isTrue);
      expect(parts.join(' ').replaceAll(' ', ''), long.replaceAll(' ', ''));
    });

    test('returns nothing for blank text', () {
      expect(splitSentences('  \n\t '), isEmpty);
    });
  });

  group('EPUB', () {
    test('reads metadata, spine order, chapter titles and body text', () {
      final progress = <double>[];
      final book = extractBook(buildEpub(), 'EPUB', onProgress: progress.add);

      expect(book.title, 'The Quiet Morning');
      expect(book.author, 'Ada Writer');
      expect(book.text.sentences, [
        'Chapter One.',
        'The morning light came in low.',
        'She had promised herself one chapter!',
        'The kettle clicked off, and the house went quiet.',
        'Chapter Two.',
        'Somewhere outside, a bus pulled away.',
        'She turned the page?',
      ]);
      expect(book.text.chapters.map((c) => (c.title, c.start)), [
        ('One: The Kettle', 0),
        ('Two: The Bus', 4),
      ]);
      expect(book.text.chapterAt(5), 'Two: The Bus');
      expect(progress.last, 1.0);
    });

    test('rejects DRM-protected books', () {
      expect(
        () => extractBook(buildEpub(drm: true), 'EPUB'),
        throwsA(isA<BookImportException>()
            .having((e) => e.message, 'message', contains('DRM'))),
      );
    });

    test('rejects files that are not EPUBs', () {
      expect(
        () => extractBook(Uint8List.fromList([1, 2, 3]), 'EPUB'),
        throwsA(isA<BookImportException>()),
      );
    });
  });

  group('PDF', () {
    test('reads text page by page with page chapters', () {
      final book = extractBook(buildPdf(), 'PDF');

      expect(book.title, 'Pocket Guide');
      expect(book.author, 'Sam Author');
      expect(book.text.sentences, [
        'First page opens here.',
        'It has two sentences.',
        'Second page follows.',
        'The end is near.',
      ]);
      expect(book.text.chapterAt(0), 'Page 1');
      expect(book.text.chapterAt(3), 'Page 2');
    });

    test('rejects PDFs without text', () {
      expect(
        () => extractBook(buildPdf(pages: ['']), 'PDF'),
        throwsA(isA<BookImportException>()
            .having((e) => e.message, 'message', contains('Scanned'))),
      );
    });

    test('rejects corrupt PDFs', () {
      expect(
        () => extractBook(Uint8List.fromList(List.filled(64, 7)), 'PDF'),
        throwsA(isA<BookImportException>()),
      );
    });
  });

  test('BookText round-trips through JSON', () {
    const text = BookText(
      sentences: ['A.', 'B.'],
      chapters: [ChapterMark('One', 0), ChapterMark('Two', 1)],
    );
    final copy = BookText.fromJson(text.toJson());
    expect(copy.sentences, text.sentences);
    expect(copy.chapterAt(1), 'Two');
  });
}
