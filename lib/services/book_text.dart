/// The readable content of an imported book: its sentences in reading order
/// and the chapter each one belongs to.
class BookText {
  const BookText({required this.sentences, this.chapters = const []});

  final List<String> sentences;

  /// Chapter starts, sorted by [ChapterMark.start].
  final List<ChapterMark> chapters;

  /// Title of the chapter containing sentence [index], or '' if none.
  String chapterAt(int index) {
    var title = '';
    for (final c in chapters) {
      if (c.start > index) break;
      title = c.title;
    }
    return title;
  }

  Map<String, Object?> toJson() => {
        'sentences': sentences,
        'chapters': [
          for (final c in chapters) {'title': c.title, 'start': c.start},
        ],
      };

  factory BookText.fromJson(Map<String, Object?> json) => BookText(
        sentences: [for (final s in json['sentences'] as List) s as String],
        chapters: [
          for (final c in json['chapters'] as List? ?? const [])
            ChapterMark(
              (c as Map)['title'] as String,
              c['start'] as int,
            ),
        ],
      );
}

class ChapterMark {
  const ChapterMark(this.title, this.start);

  final String title;

  /// Index of the chapter's first sentence.
  final int start;
}

/// Sentences longer than this are split further, so each speech request
/// stays short and pausing or skipping feels responsive.
const maxSentenceLength = 280;

final _whitespace = RegExp(r'\s+');
final _sentenceEnd =
    RegExp(r'''(?<=[.!?…]["'”’)\]]*)\s+(?=["“‘'(\[]*[A-Z0-9À-ÖØ-Þ])''');

/// Splits prose into sentences for text-to-speech.
List<String> splitSentences(String text) {
  final normalized = text.replaceAll(_whitespace, ' ').trim();
  if (normalized.isEmpty) return const [];
  return [
    for (final sentence in normalized.split(_sentenceEnd))
      ..._chunk(sentence.trim()),
  ].where((s) => s.isNotEmpty).toList();
}

Iterable<String> _chunk(String sentence) sync* {
  var rest = sentence;
  while (rest.length > maxSentenceLength) {
    // Prefer breaking after punctuation, then at a space.
    var cut = -1;
    for (final mark in const [';', ':', ',', ' ']) {
      cut = rest.lastIndexOf(mark, maxSentenceLength);
      if (cut > maxSentenceLength ~/ 3) break;
    }
    if (cut <= 0) cut = maxSentenceLength;
    yield rest.substring(0, cut + 1).trim();
    rest = rest.substring(cut + 1).trim();
  }
  if (rest.isNotEmpty) yield rest;
}
