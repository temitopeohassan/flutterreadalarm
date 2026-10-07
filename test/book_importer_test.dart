import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/services/book_importer.dart';

import 'support/sample_files.dart';

/// Exercises [DeviceBookImporter] itself (not the fake), including the
/// background isolate it extracts in.
void main() {
  // Stands in for the import sheet's State, which the progress callback
  // references and which can't be sent to another isolate.
  late ReceivePort uiState;
  setUp(() => uiState = ReceivePort());
  tearDown(() => uiState.close());

  test('extracts a PDF in the background and reports progress', () async {
    final progress = <double>[];
    final (format, book) = await DeviceBookImporter().extract(
      PickedBook(name: 'guide.pdf', read: () async => buildPdf()),
      onProgress: (p) {
        uiState.hashCode;
        progress.add(p);
      },
    );
    expect(format, 'PDF');
    expect(book.title, 'Pocket Guide');
    expect(book.text.sentences, hasLength(4));
    await pumpEventQueue();
    expect(progress, isNotEmpty);
  });

  test('extracts an EPUB in the background', () async {
    final (format, book) = await DeviceBookImporter().extract(
      PickedBook(name: 'book.epub', read: () async => buildEpub()),
      onProgress: (_) => uiState.hashCode,
    );
    expect(format, 'EPUB');
    expect(book.title, 'The Quiet Morning');
  });

  test('detects the format from the content, not the file name', () async {
    final (format, _) = await DeviceBookImporter().extract(
      PickedBook(name: 'download', read: () async => buildPdf()),
    );
    expect(format, 'PDF');
  });

  test('passes the reason a file is unreadable back from the isolate',
      () async {
    expect(
      DeviceBookImporter().extract(
        PickedBook(name: 'scan.pdf', read: () async => buildPdf(pages: [''])),
        onProgress: (_) => uiState.hashCode,
      ),
      throwsA(isA<BookImportException>()
          .having((e) => e.message, 'message', contains('Scanned'))),
    );
  });

  test('rejects files over 100 MB before reading them', () async {
    var read = false;
    expect(
      DeviceBookImporter().extract(PickedBook(
        name: 'huge.pdf',
        size: maxBookBytes + 1,
        read: () async {
          read = true;
          return buildPdf();
        },
      )),
      throwsA(isA<BookImportException>()),
    );
    expect(read, isFalse);
  });
}
