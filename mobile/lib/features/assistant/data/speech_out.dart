/// Reads assistant replies aloud with the browser's built-in speech synthesis
/// (web only, no plugin). Elsewhere [SpeechOut.isSupported] is false and the
/// "read replies aloud" switch is simply not shown.
library;

export 'speech_out_stub.dart' if (dart.library.js_interop) 'speech_out_web.dart';
