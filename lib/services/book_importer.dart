import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'book_extractor.dart';

export 'book_extractor.dart' show BookImportException, ExtractedBook;

const maxBookBytes = 100 * 1024 * 1024;

/// A file the user picked, not yet read.
class PickedBook {
  const PickedBook({required this.name, required this.read, this.size});

  final String name;
  final int? size;
  final Future<Uint8List> Function() read;
}

/// Picks PDF/EPUB files and turns them into readable text.
abstract class BookImporter {
  /// Opens the system file picker. Returns null if the user cancels.
  Future<PickedBook?> pick(String format);

  /// Reads and extracts [file]. Throws [BookImportException] with a message
  /// for the user when the file can't be used.
  Future<(String format, ExtractedBook book)> extract(
    PickedBook file, {
    void Function(double progress)? onProgress,
  });
}

/// 'PDF' or 'EPUB' judged by content, falling back to the file name.
String detectFormat(Uint8List bytes, String name) {
  if (bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return 'PDF'; // %PDF
  }
  if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    return 'EPUB'; // PK (zip)
  }
  return name.toLowerCase().endsWith('.pdf') ? 'PDF' : 'EPUB';
}

class DeviceBookImporter implements BookImporter {
  @override
  Future<PickedBook?> pick(String format) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [format.toLowerCase()],
    );
    if (file == null) return null;
    return PickedBook(
      name: file.name,
      size: file.lengthSync(),
      read: file.readAsBytes,
    );
  }

  @override
  Future<(String, ExtractedBook)> extract(
    PickedBook file, {
    void Function(double progress)? onProgress,
  }) async {
    if ((file.size ?? 0) > maxBookBytes) {
      throw const BookImportException(
          'This file is larger than 100 MB. Try a smaller edition.');
    }
    final bytes = await file.read();
    if (bytes.length > maxBookBytes) {
      throw const BookImportException(
          'This file is larger than 100 MB. Try a smaller edition.');
    }
    final format = detectFormat(bytes, file.name);

    // Extraction is CPU-heavy; run it off the UI isolate and stream
    // progress back.
    final progress = ReceivePort();
    progress.listen((p) => onProgress?.call(p as double));
    final send = progress.sendPort;
    try {
      final book = await Isolate.run(
        () => extractBook(bytes, format, onProgress: send.send),
      );
      return (format, book);
    } finally {
      progress.close();
    }
  }
}
