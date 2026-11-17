import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage.dart';

/// Whether the first-launch intro has been seen (persisted).
final onboardingDoneProvider = NotifierProvider<OnboardingController, bool>(OnboardingController.new);

class OnboardingController extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(StorageKeys.onboardingDone) ?? false;

  Future<void> complete() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(StorageKeys.onboardingDone, true);
  }
}
