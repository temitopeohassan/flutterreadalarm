import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'book_text.dart';

/// Persists app state and the extracted text of each book.
abstract class AppStorage {
  Future<Map<String, Object?>?> loadState();
  Future<void> saveState(Map<String, Object?> state);
  Future<BookText?> loadBookText(String bookId);
  Future<void> saveBookText(String bookId, BookText text);
  Future<void> deleteBook(String bookId);
}

/// JSON files in the app's private support directory.
class FileAppStorage implements AppStorage {
  FileAppStorage._(this._dir);

  static Future<FileAppStorage> open() async =>
      FileAppStorage._(await getApplicationSupportDirectory());

  final Directory _dir;
  Future<void> _writes = Future.value();

  File get _stateFile => File('${_dir.path}/state.json');
  File _bookFile(String id) => File('${_dir.path}/books/$id.json');

  @override
  Future<Map<String, Object?>?> loadState() async {
    try {
      if (!_stateFile.existsSync()) return null;
      return jsonDecode(await _stateFile.readAsString())
          as Map<String, Object?>;
    } catch (_) {
      return null; // Corrupt state: start fresh rather than crash.
    }
  }

  @override
  Future<void> saveState(Map<String, Object?> state) =>
      _write(_stateFile, jsonEncode(state));

  @override
  Future<BookText?> loadBookText(String bookId) async {
    final file = _bookFile(bookId);
    if (!file.existsSync()) return null;
    return BookText.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>);
  }

  @override
  Future<void> saveBookText(String bookId, BookText text) =>
      _write(_bookFile(bookId), jsonEncode(text.toJson()));

  @override
  Future<void> deleteBook(String bookId) async {
    final file = _bookFile(bookId);
    if (file.existsSync()) await file.delete();
  }

  /// Writes are serialised and atomic (temp file + rename), so a crash
  /// mid-write never leaves a truncated file behind.
  Future<void> _write(File file, String contents) {
    return _writes = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(contents, flush: true);
      await tmp.rename(file.path);
    });
  }
}

/// In-memory storage for tests and previews.
class MemoryAppStorage implements AppStorage {
  Map<String, Object?>? state;
  final texts = <String, BookText>{};

  @override
  Future<Map<String, Object?>?> loadState() async => state == null
      ? null
      : jsonDecode(jsonEncode(state)) as Map<String, Object?>;

  @override
  Future<void> saveState(Map<String, Object?> state) async =>
      this.state = jsonDecode(jsonEncode(state)) as Map<String, Object?>;

  @override
  Future<BookText?> loadBookText(String bookId) async => texts[bookId];

  @override
  Future<void> saveBookText(String bookId, BookText text) async =>
      texts[bookId] = text;

  @override
  Future<void> deleteBook(String bookId) async => texts.remove(bookId);
}
