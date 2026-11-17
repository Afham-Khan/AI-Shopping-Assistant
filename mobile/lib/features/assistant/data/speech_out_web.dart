import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'speech_text.dart';
import 'speech_voice.dart';

/// Browser speech synthesis (`window.speechSynthesis`), tuned to sound warm:
/// a natural female English voice (see [pickVoice]), pitch 1.1, rate 0.95.
abstract final class SpeechOut {
  static bool get isSupported =>
      web.window.hasProperty('speechSynthesis'.toJS).toDart && web.window.hasProperty('SpeechSynthesisUtterance'.toJS).toDart;

  /// A little above neutral and a little slower: friendly, not rushed.
  static const double pitch = 1.1;
  static const double rate = 0.95;

  static web.SpeechSynthesisVoice? _voice;
  static bool _watching = false;

  /// Loads the voice list ahead of the first reply. Chrome fills
  /// `getVoices()` asynchronously and announces it with `voiceschanged`, so
  /// the first call is often empty; this listens for the event and re-picks.
  static void warmUp() {
    if (!isSupported) return;
    _pickVoice();
    if (_watching) return;
    _watching = true;
    web.window.speechSynthesis.onvoiceschanged = ((web.Event _) => _pickVoice()).toJS;
  }

  static void _pickVoice() {
    final voices = web.window.speechSynthesis.getVoices().toDart;
    if (voices.isEmpty) return;
    final index = pickVoiceIndex([
      for (final v in voices) VoiceInfo(name: v.name, lang: v.lang, isDefault: v.default_, localService: v.localService),
    ]);
    _voice = index < 0 ? null : voices[index];
  }

  /// Speaks [text] (already speakable, see `speakableText`), replacing
  /// anything already being read. Long text is queued in sentence-sized
  /// pieces because Chrome stops a single long utterance after ~15 s.
  static void speak(String text) {
    if (!isSupported || text.trim().isEmpty) return;
    warmUp();
    final synth = web.window.speechSynthesis;
    synth.cancel();
    for (final piece in splitForSpeech(text)) {
      final utterance = web.SpeechSynthesisUtterance(piece)
        ..pitch = pitch
        ..rate = rate
        ..volume = 1;
      final voice = _voice;
      if (voice != null) {
        utterance
          ..voice = voice
          ..lang = voice.lang;
      }
      synth.speak(utterance);
    }
  }

  static void stop() {
    if (isSupported) web.window.speechSynthesis.cancel();
  }
}
