import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import 'book_text.dart';

/// The result of extracting a PDF or EPUB.
class ExtractedBook {
  const ExtractedBook({
    required this.title,
    required this.author,
    required this.text,
  });

  /// Empty when the file carries no title metadata.
  final String title;
  final String author;
  final BookText text;
}

/// A file that can't be turned into readable text. [message] is shown to
/// the user as is.
class BookImportException implements Exception {
  const BookImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _noText = BookImportException(
  'This file has no readable text. Scanned PDFs (pictures of pages) '
  'can\'t be read aloud.',
);

/// Extracts [bytes] as 'PDF' or 'EPUB'. [onProgress] receives 0.0 – 1.0.
///
/// Pure Dart, so it can run in a background isolate.
ExtractedBook extractBook(
  Uint8List bytes,
  String format, {
  void Function(double progress)? onProgress,
}) {
  final book = switch (format) {
    'PDF' => _extractPdf(bytes, onProgress),
    'EPUB' => _extractEpub(bytes, onProgress),
    _ => throw BookImportException('Unsupported file type: $format'),
  };
  if (book.text.sentences.isEmpty) throw _noText;
  return book;
}

// ---- PDF -----------------------------------------------------------------

ExtractedBook _extractPdf(
  Uint8List bytes,
  void Function(double)? onProgress,
) {
  final PdfDocument doc;
  try {
    doc = PdfDocument(inputBytes: bytes);
  } catch (e) {
    final message = e.toString().toLowerCase();
    if (message.contains('password') || message.contains('encrypt')) {
      throw const BookImportException(
          'This PDF is password-protected. Remove the password and try again.');
    }
    throw const BookImportException('This PDF could not be opened.');
  }

  try {
    final extractor = PdfTextExtractor(doc);
    final pageCount = doc.pages.count;
    final sentences = <String>[];
    final pageStarts = <int>[];
    for (var i = 0; i < pageCount; i++) {
      pageStarts.add(sentences.length);
      String pageText;
      try {
        pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
      } catch (_) {
        pageText = '';
      }
      sentences.addAll(splitSentences(_joinPdfLines(pageText)));
      onProgress?.call((i + 1) / pageCount);
    }

    final chapters = _pdfOutline(doc, pageStarts);
    return ExtractedBook(
      title: doc.documentInformation.title.trim(),
      author: doc.documentInformation.author.trim(),
      text: BookText(
        sentences: sentences,
        chapters: chapters.isNotEmpty
            ? chapters
            : [
                for (var i = 0; i < pageStarts.length; i++)
                  ChapterMark('Page ${i + 1}', pageStarts[i]),
              ],
      ),
    );
  } finally {
    doc.dispose();
  }
}

/// Undoes line-end hyphenation and joins wrapped lines.
String _joinPdfLines(String text) => text
    .replaceAll(RegExp(r'(\w)-\r?\n(\w)'), r'$1$2')
    .replaceAll(RegExp(r'\r?\n'), ' ');

/// Top-level PDF bookmarks mapped to sentence indexes.
List<ChapterMark> _pdfOutline(PdfDocument doc, List<int> pageStarts) {
  final marks = <ChapterMark>[];
  try {
    final bookmarks = doc.bookmarks;
    for (var i = 0; i < bookmarks.count; i++) {
      final bookmark = bookmarks[i];
      final page = bookmark.destination?.page ??
          bookmark.namedDestination?.destination?.page;
      if (page == null) continue;
      final index = doc.pages.indexOf(page);
      if (index < 0 || index >= pageStarts.length) continue;
      final title = bookmark.title.trim();
      if (title.isNotEmpty) marks.add(ChapterMark(title, pageStarts[index]));
    }
  } catch (_) {
    return const [];
  }
  marks.sort((a, b) => a.start.compareTo(b.start));
  return marks;
}

// ---- EPUB ----------------------------------------------------------------

ExtractedBook _extractEpub(
  Uint8List bytes,
  void Function(double)? onProgress,
) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const BookImportException('This EPUB could not be opened.');
  }

  String? readText(String path) {
    final file = zip.findFile(path);
    if (file == null) return null;
    return utf8.decode(file.content, allowMalformed: true);
  }

  if (_isDrmProtected(readText('META-INF/encryption.xml'))) {
    throw const BookImportException(
        'This EPUB is copy-protected (DRM) and can\'t be read aloud.');
  }

  final container = readText('META-INF/container.xml');
  if (container == null) {
    throw const BookImportException('This EPUB is missing its contents list.');
  }
  final opfPath = XmlDocument.parse(container)
      .findAllElements('rootfile')
      .firstOrNull
      ?.getAttribute('full-path');
  final opfText = opfPath == null ? null : readText(opfPath);
  if (opfPath == null || opfText == null) {
    throw const BookImportException('This EPUB is missing its contents list.');
  }

  final opf = XmlDocument.parse(opfText);
  final baseDir = p.posix.dirname(opfPath);
  String resolve(String href) => p.posix.normalize(
      p.posix.join(baseDir == '.' ? '' : baseDir, Uri.decodeFull(href)));

  final manifest = <String, ({String path, String type, String props})>{};
  for (final item in opf.findAllElements('item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = (
      path: resolve(href.split('#').first),
      type: item.getAttribute('media-type') ?? '',
      props: item.getAttribute('properties') ?? '',
    );
  }

  final spine = opf.findAllElements('spine').firstOrNull;
  final order = [
    for (final ref in spine?.findElements('itemref') ?? <XmlElement>[])
      if (ref.getAttribute('linear') != 'no') ref.getAttribute('idref'),
  ].whereType<String>().where(manifest.containsKey).toList();

  final tocTitles = _epubTocTitles(
    readText: readText,
    manifest: manifest,
    ncxId: spine?.getAttribute('toc'),
  );

  final sentences = <String>[];
  final chapters = <ChapterMark>[];
  for (var i = 0; i < order.length; i++) {
    final item = manifest[order[i]]!;
    final source = readText(item.path);
    onProgress?.call((i + 1) / order.length);
    if (source == null) continue;
    final doc = html_parser.parse(source);
    final chapterSentences = splitSentences(_htmlText(doc.body));
    if (chapterSentences.isEmpty) continue;
    final title = tocTitles[item.path] ?? _firstHeading(doc);
    if (title != null && title.isNotEmpty) {
      chapters.add(ChapterMark(title, sentences.length));
    }
    sentences.addAll(chapterSentences);
  }

  String meta(String name) =>
      opf
          .findAllElements(name, namespaceUri: '*')
          .firstOrNull
          ?.innerText
          .trim() ??
      '';

  return ExtractedBook(
    title: meta('title'),
    author: meta('creator'),
    text: BookText(sentences: sentences, chapters: chapters),
  );
}

bool _isDrmProtected(String? encryptionXml) {
  if (encryptionXml == null) return false;
  // Font obfuscation also lives in encryption.xml and is harmless.
  final methods = XmlDocument.parse(encryptionXml)
      .findAllElements('EncryptionMethod', namespaceUri: '*')
      .map((e) => e.getAttribute('Algorithm') ?? '');
  return methods.any((a) => !a.contains('obfuscation'));
}

/// Chapter titles keyed by content file path, from the EPUB 3 nav document
/// or the EPUB 2 NCX.
Map<String, String> _epubTocTitles({
  required String? Function(String) readText,
  required Map<String, ({String path, String type, String props})> manifest,
  required String? ncxId,
}) {
  final titles = <String, String>{};
  void add(String fromPath, String? href, String title) {
    if (href == null || title.trim().isEmpty) return;
    final path = p.posix.normalize(p.posix.join(
        p.posix.dirname(fromPath), Uri.decodeFull(href.split('#').first)));
    titles.putIfAbsent(path, () => title.trim().replaceAll(_spaces, ' '));
  }

  try {
    final nav =
        manifest.values.where((m) => m.props.contains('nav')).firstOrNull;
    final navText = nav == null ? null : readText(nav.path);
    if (nav != null && navText != null) {
      final doc = html_parser.parse(navText);
      final toc = doc.querySelectorAll('nav').firstWhere(
            (n) => (n.attributes['epub:type'] ?? n.attributes['type'] ?? '')
                .contains('toc'),
            orElse: () => doc.querySelector('nav') ?? html.Element.tag('nav'),
          );
      for (final a in toc.querySelectorAll('a')) {
        add(nav.path, a.attributes['href'], a.text);
      }
    }

    final ncx = manifest[ncxId] ??
        manifest.values
            .where((m) => m.type == 'application/x-dtbncx+xml')
            .firstOrNull;
    final ncxText = ncx == null ? null : readText(ncx.path);
    if (ncx != null && ncxText != null) {
      for (final point in XmlDocument.parse(ncxText)
          .findAllElements('navPoint', namespaceUri: '*')) {
        final label = point
                .findElements('navLabel', namespaceUri: '*')
                .firstOrNull
                ?.innerText ??
            '';
        final src = point
            .findElements('content', namespaceUri: '*')
            .firstOrNull
            ?.getAttribute('src');
        add(ncx.path, src, label);
      }
    }
  } catch (_) {
    // A broken table of contents only costs us chapter names.
  }
  return titles;
}

final _spaces = RegExp(r'\s+');

String? _firstHeading(html.Document doc) {
  for (final tag in const ['h1', 'h2', 'h3', 'title']) {
    final text = doc.querySelector(tag)?.text.trim().replaceAll(_spaces, ' ');
    if (text != null && text.isNotEmpty && text.length < 120) return text;
  }
  return null;
}

const _blockTags = {
  'address',
  'article',
  'aside',
  'blockquote',
  'br',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'td',
  'th',
  'tr',
  'ul',
};

const _skipTags = {'script', 'style', 'head', 'svg', 'math', 'rt', 'rp'};

/// Visible text of [root], with block elements ending in sentence breaks so
/// headings and paragraphs don't run together.
String _htmlText(html.Element? root) {
  if (root == null) return '';
  final out = StringBuffer();
  void walk(html.Node node) {
    if (node is html.Text) {
      out.write(node.text);
    } else if (node is html.Element) {
      final tag = node.localName ?? '';
      if (_skipTags.contains(tag)) return;
      final block = _blockTags.contains(tag);
      if (block) out.write('\n');
      node.nodes.forEach(walk);
      if (block) _endBlock(out);
    }
  }

  walk(root);
  return out.toString();
}

/// Ends a block with a full stop (unless it already ends in punctuation) so
/// the sentence splitter treats it as a sentence of its own.
void _endBlock(StringBuffer out) {
  final text = out.toString().trimRight();
  if (text.isEmpty) return;
  final last = text[text.length - 1];
  if (!'.!?…:;"”’)'.contains(last)) out.write('.');
  out.write('\n');
}
