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
