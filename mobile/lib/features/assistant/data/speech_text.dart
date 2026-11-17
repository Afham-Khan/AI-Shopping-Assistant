/// Plain speakable text from the assistant's small markdown subset: no
/// asterisks, backticks, bullets or link targets, and line breaks become
/// sentence pauses.
String speechTextFromMarkdown(String markdown) {
  var s = markdown;
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1] ?? '');
  s = s.replaceAll(RegExp(r'[*`#>]+'), '');
  s = s.replaceAll(RegExp(r'^\s*(?:[-•]|\d+[.)])\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\s*\n+\s*'), '. ');
  // "near Rs 30,000:. Great" → "near Rs 30,000: Great"
  s = s.replaceAllMapped(RegExp(r'([.:!?])\s*\.'), (m) => m[1] ?? '');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _amount = r'\d+(?:,\d+)*(?:\.\d+)?';
const _scale = r'(?:k|m|lakh|lac|crore)';

// "Rs 30,000", "Rs. 1.5k", "PKR 10,000-20,000", "Rs 5,000 – Rs 10,000"
// (the scale word only eats the space before it when it is really there, so
// "Rs 500 more" keeps its space)
final _rupees = RegExp(
  r'\b(?:Rs|PKR)\.?\s*(' '$_amount' r')(?:\s*(' '$_scale' r')\b)?'
  r'(?:\s*(?:-|–|—|to)\s*(?:(?:Rs|PKR)\.?\s*)?(' '$_amount' r')(?:\s*(' '$_scale' r')\b)?)?',
  caseSensitive: false,
);

String _scaled(String amount, String? scale) {
  switch (scale?.toLowerCase()) {
    case 'k':
      return '$amount thousand';
    case 'm':
      return '$amount million';
    case null:
      return amount;
    default:
      return '$amount ${scale!.toLowerCase()}';
  }
}

/// Text ready for the voice: [speechTextFromMarkdown] plus the things a
/// speech engine stumbles on — "Rs 30,000" is said as "30,000 rupees", ranges
/// as "10,000 to 20,000 rupees", "30k" as "30 thousand", percent signs,
/// "4.6/5", web addresses, emoji, arrows, ampersands and table bars.
///
/// ```dart
/// speakableText('Best pick at **Rs 29,999** (-10%) 🎉')
///   // "Best pick at 29,999 rupees (10 percent off)"
/// ```
String speakableText(String markdown) {
  var s = speechTextFromMarkdown(markdown);

  s = s.replaceAll(RegExp(r'https?://\S+|www\.\S+'), '');
  s = s.replaceAll('→', ' to ').replaceAll('←', ' ');
  // emoji, pictographs, dingbats, arrows, variation selectors
  s = s.replaceAll(
    RegExp('[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{25A0}-\u{25FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true),
    '',
  );

  // "~Rs 30,000" → "about Rs 30,000"
  s = s.replaceAll(RegExp(r'[~≈]\s*(?=\d|Rs|PKR)', caseSensitive: false), 'about ');

  s = s.replaceAllMapped(_rupees, (m) {
    final first = _scaled(m[1]!, m[2]);
    final second = m[3];
    final amount = second == null ? first : '$first to ${_scaled(second, m[4])}';
    final one = second == null && m[1] == '1' && m[2] == null;
    return '$amount ${one ? 'rupee' : 'rupees'}';
  });
  // a bare "Rs" with no figure after it
  s = s.replaceAll(RegExp(r'\b(?:Rs|PKR)\b\.?', caseSensitive: false), 'rupees');

  // "(-10%)" is a discount: "10 percent off"
  s = s.replaceAllMapped(RegExp(r'(?<![\w])-(\d+(?:\.\d+)?)\s*%'), (m) => '${m[1]} percent off');
  s = s.replaceAllMapped(RegExp(r'(\d)\s*%'), (m) => '${m[1]} percent');
  s = s.replaceAll('%', ' percent');
  s = s.replaceAllMapped(RegExp(r'(\d(?:\.\d+)?)\s*/\s*5\b'), (m) => '${m[1]} out of 5');
  s = s.replaceAll('&', ' and ');
  s = s.replaceAll('|', ', ');
  // underscore emphasis (_like this_) but not snake_case
  s = s.replaceAll(RegExp(r'(?<![A-Za-z0-9])_+|_+(?![A-Za-z0-9])'), '');
  // a spaced dash is a pause
  s = s.replaceAll(RegExp(r'\s[–—]\s'), ', ');

  // no space before punctuation, and no doubled punctuation ("rupees, ." → "rupees.")
  s = s.replaceAllMapped(RegExp(r'\s+([.,:;!?])'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'([.,:;!?])(?:\s*[.,:;])+'), (m) => m[1]!);
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Splits [text] into chunks of at most [maxLength] characters, preferably at
/// sentence ends, then clause breaks, then spaces. Chrome cuts a single long
/// utterance off after ~15 s, so long replies are queued piece by piece.
List<String> splitForSpeech(String text, {int maxLength = 180}) {
  final out = <String>[];
  final buffer = StringBuffer();

  void flush() {
    final piece = buffer.toString().trim();
    if (piece.isNotEmpty) out.add(piece);
    buffer.clear();
  }

  // sentences first
  for (final sentence in text.trim().split(RegExp(r'(?<=[.!?])\s+'))) {
    if (sentence.isEmpty) continue;
    if (sentence.length > maxLength) {
      flush();
      out.addAll(_breakLong(sentence, maxLength));
    } else if (buffer.length + sentence.length + 1 > maxLength) {
      flush();
      buffer.write(sentence);
    } else {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }
  }
  flush();
  return out;
}

List<String> _breakLong(String sentence, int maxLength) {
  final pieces = <String>[];
  var rest = sentence.trim();
  while (rest.length > maxLength) {
    final window = rest.substring(0, maxLength);
    var cut = window.lastIndexOf(RegExp(r'[,;:]\s'));
    if (cut < maxLength ~/ 3) cut = window.lastIndexOf(' ');
    if (cut < maxLength ~/ 3) cut = maxLength - 1;
    pieces.add(rest.substring(0, cut + 1).trim());
    rest = rest.substring(cut + 1).trim();
  }
  if (rest.isNotEmpty) pieces.add(rest);
  return pieces;
}
