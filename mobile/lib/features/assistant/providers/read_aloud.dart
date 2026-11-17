import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage.dart';
import '../data/speech_out.dart';

/// "Read replies aloud" switch, persisted. Always false where the platform
/// has no speech synthesis (everything but web), so callers need no checks.
final readAloudProvider = NotifierProvider<ReadAloudController, bool>(ReadAloudController.new);

class ReadAloudController extends Notifier<bool> {
  @override
  bool build() => SpeechOut.isSupported && (ref.read(sharedPreferencesProvider).getBool(StorageKeys.aiReadAloud) ?? false);

  Future<void> toggle() async {
    if (!SpeechOut.isSupported) return;
    state = !state;
    if (!state) SpeechOut.stop();
    await ref.read(sharedPreferencesProvider).setBool(StorageKeys.aiReadAloud, state);
  }
}
