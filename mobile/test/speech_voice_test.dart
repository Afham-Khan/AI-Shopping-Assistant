import 'package:cartwise/features/assistant/data/speech_text.dart';
import 'package:cartwise/features/assistant/data/speech_voice.dart';
import 'package:cartwise/features/assistant/presentation/widgets/chat_input_bar.dart';
import 'package:flutter_test/flutter_test.dart';

VoiceInfo v(String name, {String lang = 'en-US', bool isDefault = false}) =>
    VoiceInfo(name: name, lang: lang, isDefault: isDefault);

String? pick(List<VoiceInfo> voices) => pickVoice(voices)?.name;

void main() {
  group('voice selection', () {
    test('prefers Google UK English Female above everything', () {
      final voices = [
        v('Microsoft Aria Online (Natural) - English (United States)'),
        v('Samantha'),
        v('Google UK English Male', lang: 'en-GB'),
        v('Google UK English Female', lang: 'en-GB'),
      ];
      expect(pick(voices), 'Google UK English Female');
    });

    test('follows the preference list: Aria, Jenny, Zira, Samantha', () {
      expect(pick([v('Microsoft Zira - English (United States)'), v('Microsoft Jenny Online (Natural) - English (United States)')]),
          startsWith('Microsoft Jenny'));
      expect(pick([v('Samantha'), v('Microsoft Zira Desktop - English (United States)')]), startsWith('Microsoft Zira'));
      expect(pick([v('Alex'), v('Samantha'), v('Daniel', lang: 'en-GB')]), 'Samantha');
      expect(
        pick([v('Microsoft Jenny Online (Natural) - English (United States)'), v('Microsoft Aria Online (Natural) - English (United States)')]),
        startsWith('Microsoft Aria'),
      );
    });

    test('falls back to any voice called female, then to any non-male English voice', () {
      expect(pick([v('Some Voice'), v('English Female Voice 2')]), 'English Female Voice 2');
      // no female anywhere: the first English voice that is not a known male one
      expect(pick([v('Microsoft David - English (United States)'), v('Google UK English Male', lang: 'en-GB'), v('Tessa')]), 'Tessa');
      expect(pick([v('Voice A'), v('Voice B')]), 'Voice A');
    });

    test('with only male voices it still speaks English rather than nothing', () {
      expect(pick([v('Microsoft David - English (United States)'), v('Microsoft Mark - English (United States)')]),
          'Microsoft David - English (United States)');
    });

    test('ignores voices in other languages, even with a preferred name', () {
      final voices = [v('Amélie', lang: 'fr-FR'), v('Samantha Español', lang: 'es-ES'), v('Kanya', lang: 'th-TH')];
      expect(pickVoiceIndex(voices), -1);
      expect(pickVoice(voices), isNull);
      expect(pickVoiceIndex(const []), -1);
      // an English voice anywhere in the list wins
      expect(pick([...voices, v('Daniel', lang: 'en-GB')]), 'Daniel');
    });

    test('accepts en_GB style tags and voices that report no language', () {
      expect(pick([v('Google UK English Female', lang: 'en_GB')]), 'Google UK English Female');
      expect(pick([v('Microsoft Zira English', lang: ''), v('Kanya', lang: 'th-TH')]), 'Microsoft Zira English');
    });

    test('inside one tier, natural voices win, then the browser default, then the first', () {
      expect(
        pick([v('Microsoft Aria - English (United States)'), v('Microsoft Aria Online (Natural) - English (United States)')]),
        'Microsoft Aria Online (Natural) - English (United States)',
      );
      expect(pick([v('Samantha'), v('Samantha (Enhanced)')]), 'Samantha (Enhanced)');
      expect(pick([v('Voice A'), v('Voice B', isDefault: true)]), 'Voice B');
    });

    test('a name matches at a word start, so "ava" does not match "Java"', () {
      expect(pick([v('Java Speaker'), v('Microsoft Ava Online (Natural)')]), startsWith('Microsoft Ava'));
      expect(pick([v('Java Speaker'), v('Voice B')]), 'Java Speaker'); // plain English fallback, not a preferred hit
    });

    test('the owner\'s five names come first, in order', () {
      expect(preferredVoiceNames.take(5), [
        'google uk english female',
        'microsoft aria',
        'microsoft jenny',
        'microsoft zira',
        'samantha',
      ]);
    });
  });

  group('speakable text', () {
    test('says rupees naturally', () {
      expect(speakableText('It costs Rs 29,999 today'), 'It costs 29,999 rupees today');
      expect(speakableText('Rs. 1,500.'), '1,500 rupees.');
      expect(speakableText('around PKR 45,000, great value'), 'around 45,000 rupees, great value');
      expect(speakableText('Rs 1'), '1 rupee');
      expect(speakableText('under Rs 30k'), 'under 30 thousand rupees');
      expect(speakableText('between Rs 10,000-20,000'), 'between 10,000 to 20,000 rupees');
      expect(speakableText('from Rs 5,000 to Rs 10,000 only'), 'from 5,000 to 10,000 rupees only');
      expect(speakableText('~Rs 2,000'), 'about 2,000 rupees');
      expect(speakableText('prices in Rs are shown'), 'prices in rupees are shown');
    });

    test('keeps the markdown stripping of speechTextFromMarkdown', () {
      expect(speakableText('Here are **2 phones** near `Rs 30,000`:\n- Great battery\n- Big screen'),
          'Here are 2 phones near 30,000 rupees: Great battery. Big screen');
      expect(speakableText('## Title\n1. First\n2. Second'), 'Title. First. Second');
      expect(speakableText('See [the list](https://example.com/x) now'), 'See the list now');
      expect(speakableText('   '), '');
    });

    test('percent, ratings, ampersands, urls, emoji and arrows', () {
      expect(speakableText('Save 15% today'), 'Save 15 percent today');
      expect(speakableText('Best pick (-10%) 🎉'), 'Best pick (10 percent off)');
      expect(speakableText('Rated 4.6/5 by buyers'), 'Rated 4.6 out of 5 by buyers');
      expect(speakableText('Fast & light'), 'Fast and light');
      expect(speakableText('Open https://zelora.app/p/12 for more'), 'Open for more');
      expect(speakableText('Wait ⏳ — almost done ✅'), 'Wait, almost done');
      expect(speakableText('Phone → Laptop'), 'Phone to Laptop');
      expect(speakableText('Name | Price'), 'Name, Price');
    });

    test('underscore emphasis goes, snake_case stays', () {
      expect(speakableText('this is _important_ now'), 'this is important now');
      expect(speakableText('the max_price filter'), 'the max_price filter');
    });
  });

  group('splitting long replies', () {
    test('short text stays one piece', () {
      expect(splitForSpeech('Hello there. How are you?'), ['Hello there. How are you?']);
      expect(splitForSpeech(''), isEmpty);
    });

    test('breaks at sentence ends and keeps every piece under the limit', () {
      final text = List.generate(12, (i) => 'This is sentence number $i of a long reply.').join(' ');
      final pieces = splitForSpeech(text, maxLength: 100);
      expect(pieces.length, greaterThan(3));
      expect(pieces.every((p) => p.length <= 100), isTrue);
      // nothing lost, nothing added
      expect(pieces.join(' '), text);
    });

    test('a very long sentence is cut at commas, then spaces', () {
      final text = '${List.generate(30, (i) => 'word$i').join(', ')}.';
      final pieces = splitForSpeech(text, maxLength: 60);
      expect(pieces.every((p) => p.length <= 60), isTrue);
      expect(pieces.join(' ').replaceAll(RegExp(r'\s+'), ' '), text);
      final noSpaces = splitForSpeech('a' * 130, maxLength: 50);
      expect(noSpaces.every((p) => p.length <= 50), isTrue);
      expect(noSpaces.join(), 'a' * 130);
    });
  });

  group('typing progress for the mascot', () {
    test('null unless focused and non-empty, then eighths of a short message', () {
      expect(ChatInputBar.typingProgress('hello', focused: false), isNull);
      expect(ChatInputBar.typingProgress('', focused: true), isNull);
      expect(ChatInputBar.typingProgress('   ', focused: true), isNull);
      expect(ChatInputBar.typingProgress('hi', focused: true), 0.0); // 2 of ~40 characters rounds to 0 eighths
      expect(ChatInputBar.typingProgress('a' * 20, focused: true), 0.5);
      expect(ChatInputBar.typingProgress('a' * 400, focused: true), 1.0);
    });
  });
}
