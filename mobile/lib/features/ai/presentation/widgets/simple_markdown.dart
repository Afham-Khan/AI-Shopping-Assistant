import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';

/// A tiny Markdown subset for assistant replies (no package):
/// paragraphs with line breaks, `- ` / `* ` / `• ` bullets, `1.` lists,
/// `#` headings, **bold**, *italic* / _italic_, `code`, and [links](url)
/// (shown as plain text). Unclosed markers stay open to the end, so a
/// partially revealed `**Rs 30,` already renders bold.

enum MdBlockType { paragraph, bullet, numbered, heading }

@immutable
class MdSpan {
  const MdSpan(this.text, {this.bold = false, this.italic = false, this.code = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  bool sameStyle(MdSpan o) => o.bold == bold && o.italic == italic && o.code == code;

  @override
  bool operator ==(Object other) => other is MdSpan && other.text == text && sameStyle(other);

  @override
  int get hashCode => Object.hash(text, bold, italic, code);

  @override
  String toString() => 'MdSpan("$text"${bold ? ' b' : ''}${italic ? ' i' : ''}${code ? ' c' : ''})';
}

@immutable
class MdBlock {
  const MdBlock(this.type, this.spans, {this.number});

  final MdBlockType type;
  final List<MdSpan> spans;

  /// For numbered items.
  final int? number;

  String get plainText => spans.map((s) => s.text).join();

  @override
  String toString() => 'MdBlock($type${number == null ? '' : ' $number'}, $spans)';
}

final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');
final _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');
final _link = RegExp(r'\[([^\]]+)\]\(([^)\s]*)\)');

/// Parses [source] into blocks. Pure; safe on partial text.
List<MdBlock> parseMarkdown(String source) {
  final blocks = <MdBlock>[];
  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(MdBlock(MdBlockType.paragraph, parseInline(paragraph.join('\n'))));
    paragraph.clear();
  }

  for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      flush();
      blocks.add(MdBlock(MdBlockType.heading, parseInline(h.group(1)!)));
      continue;
    }
    final b = _bullet.firstMatch(line);
    if (b != null) {
      flush();
      blocks.add(MdBlock(MdBlockType.bullet, parseInline(b.group(1)!)));
      continue;
    }
    final n = _numbered.firstMatch(line);
    if (n != null) {
      flush();
      blocks.add(MdBlock(MdBlockType.numbered, parseInline(n.group(2)!), number: int.parse(n.group(1)!)));
      continue;
    }
    paragraph.add(line.trimLeft());
  }
  flush();
  return blocks;
}

bool _isSpace(String c) => c.trim().isEmpty;
bool _isWord(String c) => RegExp(r'[A-Za-z0-9]').hasMatch(c);

/// Inline styles: **bold** / __bold__, *italic* / _italic_, `code`.
List<MdSpan> parseInline(String input) {
  final text = input.replaceAllMapped(_link, (m) => m.group(1)!);
  final spans = <MdSpan>[];
  final buf = StringBuffer();
  var bold = false, italic = false, code = false;
  String? italicMarker;

  void emit() {
    if (buf.isEmpty) return;
    final span = MdSpan(buf.toString(), bold: bold, italic: italic, code: code);
    buf.clear();
    if (spans.isNotEmpty && spans.last.sameStyle(span)) {
      spans[spans.length - 1] = MdSpan(spans.last.text + span.text, bold: bold, italic: italic, code: code);
    } else {
      spans.add(span);
    }
  }

  var i = 0;
  while (i < text.length) {
    final c = text[i];
    final next = i + 1 < text.length ? text[i + 1] : '';
    final prev = i > 0 ? text[i - 1] : '';

    if (c == '`') {
      emit();
      code = !code;
      i++;
      continue;
    }
    if (code) {
      buf.write(c);
      i++;
      continue;
    }
    final afterPair = i + 2 < text.length ? text[i + 2] : '';
    if ((c == '*' && next == '*') || (c == '_' && next == '_' && (bold ? !_isWord(afterPair) : !_isWord(prev)))) {
      emit();
      bold = !bold;
      i += 2;
      continue;
    }
    if (c == '*' || c == '_') {
      final after = next;
      final opens = !italic && after.isNotEmpty && !_isSpace(after) && (prev.isEmpty || !_isWord(prev) || c == '*');
      final closes = italic && italicMarker == c && prev.isNotEmpty && !_isSpace(prev) && (c == '*' || !_isWord(after));
      // a lone * between spaces or inside snake_case stays literal
      final hasCloser = opens && text.indexOf(c, i + 1) > i + 1;
      if (closes) {
        emit();
        italic = false;
        italicMarker = null;
        i++;
        continue;
      }
      if (opens && hasCloser) {
        emit();
        italic = true;
        italicMarker = c;
        i++;
        continue;
      }
    }
    buf.write(c);
    i++;
  }
  emit();
  return spans;
}

/// Renders [text] with [parseMarkdown].
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? context.textTheme.bodyMedium!.copyWith(height: 1.5);
    final blocks = parseMarkdown(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _gapBefore(blocks[i], blocks[i - 1])),
            child: _block(context, blocks[i], base),
          ),
      ],
    );
  }

  double _gapBefore(MdBlock b, MdBlock prev) {
    bool listy(MdBlockType t) => t == MdBlockType.bullet || t == MdBlockType.numbered;
    if (listy(b.type) && listy(prev.type)) return 4;
    return AppSpacing.xs;
  }

  Widget _block(BuildContext context, MdBlock b, TextStyle base) {
    final colors = context.colors;
    switch (b.type) {
      case MdBlockType.paragraph:
        return Text.rich(_spans(context, b.spans, base));
      case MdBlockType.heading:
        return Text.rich(_spans(context, b.spans, base.copyWith(fontWeight: FontWeight.w700)));
      case MdBlockType.bullet:
      case MdBlockType.numbered:
        final marker = b.type == MdBlockType.bullet ? '•' : '${b.number}.';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: b.type == MdBlockType.bullet ? 16 : 24,
              child: Text(
                marker,
                style: base.copyWith(color: colors.ai, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: Text.rich(_spans(context, b.spans, base))),
          ],
        );
    }
  }

  TextSpan _spans(BuildContext context, List<MdSpan> spans, TextStyle base) {
    final colors = context.colors;
    return TextSpan(
      style: base,
      children: [
        for (final s in spans)
          TextSpan(
            text: s.text,
            style: TextStyle(
              fontWeight: s.bold ? FontWeight.w700 : null,
              fontStyle: s.italic ? FontStyle.italic : null,
              fontFamily: s.code ? 'monospace' : null,
              backgroundColor: s.code ? colors.surfaceVariant : null,
            ),
          ),
      ],
    );
  }
}
