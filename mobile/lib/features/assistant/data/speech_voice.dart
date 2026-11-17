/// Picking the voice that reads Zel's replies aloud. Pure Dart so the
/// preference logic is unit-testable; `speech_out_web.dart` feeds it the
/// browser's `speechSynthesis.getVoices()`.
library;

/// What the picker needs to know about one browser voice.
class VoiceInfo {
  const VoiceInfo({required this.name, this.lang = '', this.isDefault = false, this.localService = true});

  final String name;

  /// BCP-47 tag as the browser reports it (`en-GB`; some Android builds say `en_GB`).
  final String lang;
  final bool isDefault;
  final bool localService;

  @override
  String toString() => 'VoiceInfo($name, $lang)';
}

/// Voices we like, best first: a sweet, natural female English voice. The
/// first five are the owner's list; the rest are well-known pleasant female
/// voices on the same platforms (Windows, Edge, macOS, Chrome, Android).
const preferredVoiceNames = <String>[
  'google uk english female',
  'microsoft aria',
  'microsoft jenny',
  'microsoft zira',
  'samantha',
  'microsoft sonia',
  'microsoft libby',
  'google us english',
  'ava',
  'allison',
  'susan',
  'karen',
  'moira',
  'tessa',
  'serena',
  'victoria',
  'hazel',
  'female',
];

// a name matches an entry at a word start, so "ava" finds "Microsoft Ava" but not "Java"
final _preferredPatterns = [for (final n in preferredVoiceNames) RegExp('(?:^|[^a-z])${RegExp.escape(n)}(?![a-z])')];

// first names of common male English voices, for the last-resort fallback
final _maleVoice = RegExp(
  r'\b(?:male|david|mark|guy|ryan|daniel|alex|fred|george|james|thomas|oliver|rishi|ravi|liam|brian|eric|'
  r'christopher|roger|steffan|connor|jorge|diego|aaron|arthur|gordon|lee|nathan|rocko|reed|eddy|grandpa|ralph|bruce)\b',
);

bool _isEnglish(VoiceInfo v) {
  final lang = v.lang.toLowerCase().replaceAll('_', '-');
  if (lang.isNotEmpty) return lang == 'en' || lang.startsWith('en-');
  // no language reported: trust the name
  return v.name.toLowerCase().contains('english');
}

bool _isNatural(VoiceInfo v) {
  final n = v.name.toLowerCase();
  return n.contains('natural') || n.contains('neural') || n.contains('online') || n.contains('enhanced') || n.contains('premium');
}

/// Index into [voices] of the best voice for reading replies aloud, or -1
/// when nothing speaks English (the browser's default is then used).
///
/// Preference, best first: [preferredVoiceNames] in order (a name matches when
/// it *contains* the entry, case-insensitive; "Microsoft Aria Online (Natural)"
/// matches "microsoft aria"), then any voice not known to be male, then any
/// English voice at all. Within a tier, natural / neural / online voices win,
/// then the browser's default voice, then the first in the list. Only English
/// voices are considered.
int pickVoiceIndex(List<VoiceInfo> voices) {
  var best = -1;
  var bestScore = 1 << 30;

  for (var i = 0; i < voices.length; i++) {
    final v = voices[i];
    if (!_isEnglish(v)) continue;
    final name = v.name.toLowerCase();

    var tier = _preferredPatterns.indexWhere((p) => p.hasMatch(name));
    if (tier < 0) {
      tier = _maleVoice.hasMatch(name) && !name.contains('female') ? preferredVoiceNames.length + 1 : preferredVoiceNames.length;
    }
    // tiers dominate; natural and default voices break ties inside one
    final score = tier * 10 + (_isNatural(v) ? 0 : 2) + (v.isDefault ? 0 : 1);
    if (score < bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}

/// The best voice itself, or null.
VoiceInfo? pickVoice(List<VoiceInfo> voices) {
  final i = pickVoiceIndex(voices);
  return i < 0 ? null : voices[i];
}
