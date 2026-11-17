/// No speech synthesis on this platform.
abstract final class SpeechOut {
  static bool get isSupported => false;

  static void warmUp() {}

  static void speak(String text) {}

  static void stop() {}
}
