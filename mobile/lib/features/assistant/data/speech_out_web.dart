import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Browser speech synthesis (`window.speechSynthesis`).
abstract final class SpeechOut {
  static bool get isSupported =>
      web.window.hasProperty('speechSynthesis'.toJS).toDart && web.window.hasProperty('SpeechSynthesisUtterance'.toJS).toDart;

  /// Speaks [text], replacing anything already being read.
  static void speak(String text) {
    if (!isSupported || text.trim().isEmpty) return;
    final synth = web.window.speechSynthesis;
    synth.cancel();
    synth.speak(web.SpeechSynthesisUtterance(text));
  }

  static void stop() {
    if (isSupported) web.window.speechSynthesis.cancel();
  }
}
