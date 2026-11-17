import 'package:cartwise/features/ai/presentation/smart_search_screen.dart';
import 'package:cartwise/features/ai/presentation/widgets/entity_chips.dart';
import 'package:cartwise/features/ai/presentation/widgets/simple_markdown.dart';
import 'package:cartwise/features/assistant/presentation/widgets/reveal_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseInline', () {
    test('bold, italic and code spans', () {
      expect(parseInline('Here are **4 laptops** under *budget* with `RTX`'), const [
        MdSpan('Here are '),
        MdSpan('4 laptops', bold: true),
        MdSpan(' under '),
        MdSpan('budget', italic: true),
        MdSpan(' with '),
        MdSpan('RTX', code: true),
      ]);
    });

    test('unclosed bold stays open (partial reveal)', () {
      expect(parseInline('Under **Rs 30,'), const [MdSpan('Under '), MdSpan('Rs 30,', bold: true)]);
    });

    test('snake_case, lone asterisks and links stay literal', () {
      expect(parseInline('intent product_search scored 5 * 3'), const [MdSpan('intent product_search scored 5 * 3')]);
      expect(parseInline('see [the deal](https://x.y) now'), const [MdSpan('see the deal now')]);
    });

    test('__bold__ works and merges adjacent plain text', () {
      expect(parseInline('__Top__ pick'), const [MdSpan('Top', bold: true), MdSpan(' pick')]);
    });
  });

  group('parseMarkdown', () {
    test('paragraphs keep line breaks, blank lines split them', () {
      final blocks = parseMarkdown('Line one\nline two\n\nSecond para');
      expect(blocks, hasLength(2));
      expect(blocks[0].type, MdBlockType.paragraph);
      expect(blocks[0].plainText, 'Line one\nline two');
      expect(blocks[1].plainText, 'Second para');
    });

    test('bullets, numbered items and headings', () {
      final blocks = parseMarkdown('## Picks\n- **Realme C35** · Rs 41,999\n* Infinix\n• Tecno\n1. First\n2) Second');
      expect(blocks.map((b) => b.type), [
        MdBlockType.heading,
        MdBlockType.bullet,
        MdBlockType.bullet,
        MdBlockType.bullet,
        MdBlockType.numbered,
        MdBlockType.numbered,
      ]);
      expect(blocks[1].spans.first, const MdSpan('Realme C35', bold: true));
      expect(blocks[5].number, 2);
    });

    test('a line starting with **bold** is not a bullet', () {
      final blocks = parseMarkdown('**Best value:** Realme');
      expect(blocks.single.type, MdBlockType.paragraph);
      expect(blocks.single.spans.first.bold, isTrue);
    });

    test('empty input → no blocks', () {
      expect(parseMarkdown(''), isEmpty);
      expect(parseMarkdown('\n\n  \n'), isEmpty);
    });
  });

  test('visiblePrefix cuts at a word end', () {
    const text = 'Here are four great phones';
    expect(RevealMarkdown.visiblePrefix(text, 0), '');
    expect(RevealMarkdown.visiblePrefix(text, 1), text);
    final half = RevealMarkdown.visiblePrefix(text, 0.3);
    expect(text.startsWith(half), isTrue);
    expect(half.endsWith(' ') || half.length == text.length || text[half.length] == ' ', isTrue);
  });

  group('entityChips', () {
    test('formats budget, brands, exclusions and skips nulls', () {
      final chips = entityChips({
        'department': 'electronics',
        'category': 'smartphones',
        'categories': ['smartphones'],
        'brands': ['samsung'],
        'budget': {'min': null, 'max': 30000},
        'excludeBrands': ['apple'],
        'color': null,
        'features': <String>[],
        'ordinals': null,
        'minRating': 4,
      });
      final labels = chips.map((c) => c.label).toList();
      expect(labels, containsAll(['Electronics', 'Smartphones', 'Samsung', 'Under Rs 30K', 'No Apple']));
      expect(labels.where((l) => l == 'Smartphones'), hasLength(1));
      expect(chips.firstWhere((c) => c.type == 'rating').label, contains('4'));
    });

    test('budgetLabel ranges', () {
      expect(budgetLabel({'min': 10000, 'max': 30000}), 'Rs 10K – Rs 30K');
      expect(budgetLabel({'min': 5000}), 'Over Rs 5K');
      expect(budgetLabel({'min': null, 'max': null}), isNull);
    });
  });

  group('removeFromQuery', () {
    test('drops budget phrases', () {
      expect(removeFromQuery('red running shoes for women under 15k', type: 'budget', label: 'Under Rs 15K'), 'red running shoes for women');
      expect(removeFromQuery('sasta mobile 30k tak', type: 'budget', label: 'Under Rs 30K'), 'sasta mobile');
    });

    test('drops a word chip', () {
      expect(removeFromQuery('red running shoes for women', type: 'color', label: 'Red'), 'running shoes for women');
      expect(removeFromQuery('red running shoes for women', type: 'gender', label: 'Women'), 'red running shoes');
    });
  });
}
