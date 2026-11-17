import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/presentation/widgets/ai_ui.dart';

/// Composer: multiline field (Enter sends, Shift+Enter = new line on
/// keyboards), voice input with live transcript, Snap & Find button and a
/// send button that's disabled while a reply is on its way.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key, required this.onSend, required this.sending, this.onImage, this.controller});

  final ValueChanged<String> onSend;
  final bool sending;
  final VoidCallback? onImage;
  final TextEditingController? controller;

  static const maxLength = 500;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _text = widget.controller ?? TextEditingController();
  final _focus = FocusNode();

  // one recognizer per app; initialize lazily on the first mic tap
  static final SpeechToText _speech = SpeechToText();
  static bool? _speechReady;

  /// This browser or device has no speech recognition (permanent, unlike a
  /// denied permission): the mic says so instead of failing on every tap.
  static bool _speechUnsupported = false;

  // the recognizer is initialised once with these callbacks, so they forward
  // to whichever composer is currently on screen
  static _ChatInputBarState? _current;
  static void _forwardStatus(String status) => _current?._onSpeechStatus(status);
  static void _forwardError(SpeechRecognitionError error) => _current?._onSpeechError(error);

  static const _unsupportedMessage = "Voice input isn't supported in this browser. Try Chrome or Edge, or type your message.";

  bool _listening = false;
  double _level = 0;
  String _prefix = '';

  @override
  void initState() {
    super.initState();
    _current = this;
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    if (_listening) _speech.cancel();
    if (identical(_current, this)) _current = null;
    if (widget.controller == null) _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  bool get _canSend => _text.text.trim().isNotEmpty && !widget.sending;

  void _send() {
    if (!_canSend) return;
    if (_listening) _stopListening();
    final value = _text.text.trim();
    widget.onSend(value);
    _text.clear();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stopListening();
      return;
    }
    HapticFeedback.selectionClick();
    if (_speechUnsupported) {
      AppSnack.info(context, _unsupportedMessage);
      return;
    }
    try {
      _speechReady ??= await _speech.initialize(onError: _forwardError, onStatus: _forwardStatus);
    } catch (_) {
      _speechReady = false;
    }
    if (!mounted) return;
    if (_speechReady != true) {
      _speechReady = null; // let the user try again after granting permission
      if (_speechUnsupported) {
        setState(() {});
        AppSnack.info(context, _unsupportedMessage);
      } else {
        AppSnack.error(context, "Voice input isn't available. Allow microphone access and try again.");
      }
      return;
    }
    _prefix = _text.text.trim().isEmpty ? '' : '${_text.text.trim()} ';
    setState(() => _listening = true);
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: (level) {
          if (mounted) setState(() => _level = ((level + 2) / 12).clamp(0.0, 1.0));
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        AppSnack.error(context, "Couldn't start listening. Please try again.");
      }
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final words = result.recognizedWords;
    final value = '$_prefix$words';
    _text.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    if (result.finalResult) setState(() => _listening = false);
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      setState(() => _listening = false);
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    final msg = error.errorMsg;
    // browsers without the Web Speech API (Firefox, some in-app browsers)
    if (msg.contains('not supported') || msg.contains('not_supported')) {
      _speechUnsupported = true;
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = false);
    if (msg.contains('permission') || msg.contains('not-allowed')) {
      AppSnack.error(context, 'Microphone permission was denied. Enable it in settings to use voice input.');
    } else if (msg != 'error_no_match' && msg != 'error_speech_timeout' && msg != 'no-speech') {
      AppSnack.error(context, "Didn't catch that. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.6))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.xs, context.pagePadding, AppSpacing.sm),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: context.motion(AppDurations.fast),
                    child: _listening
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                _ListeningWave(level: _level),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: AiText('Listening… speak naturally, even in Roman Urdu', style: t.labelMedium, maxLines: 1),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: _listening ? colors.ai : colors.border, width: _listening ? 1.5 : 1),
                    ),
                    padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.onImage != null)
                          IconButton(
                            tooltip: 'Snap & Find: search with a photo',
                            onPressed: widget.onImage,
                            icon: Icon(Icons.photo_camera_outlined, color: colors.muted),
                            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                          ),
                        Expanded(
                          child: Focus(
                            onKeyEvent: _onKey,
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: ChatInputBar.maxLength,
                              maxLengthEnforcement: MaxLengthEnforcement.enforced,
                              textInputAction: TextInputAction.newline,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              style: t.bodyLarge,
                              decoration: InputDecoration(
                                hintText: 'Ask ${AppConfig.assistantName} anything…',
                                counterText: '',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        _MicButton(listening: _listening, level: _level, unsupported: _speechUnsupported, onTap: _toggleVoice),
                        const SizedBox(width: 4),
                        _SendButton(enabled: _canSend, busy: widget.sending, onTap: _send),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.level, required this.onTap, this.unsupported = false});

  final bool listening;
  final double level;
  final VoidCallback onTap;

  /// No speech recognition here: the icon is struck through and says why.
  final bool unsupported;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ring = context.reduceMotion ? 0.0 : level;
    return Semantics(
      toggled: listening,
      child: SizedBox.square(
        dimension: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (listening)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 34 + 10 * ring,
                height: 34 + 10 * ring,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.ai.withValues(alpha: 0.18)),
              ),
            IconButton(
              tooltip: listening
                  ? 'Stop listening'
                  : (unsupported ? "Voice input isn't supported in this browser" : 'Voice input'),
              onPressed: onTap,
              icon: Icon(
                listening ? Icons.stop_rounded : (unsupported ? Icons.mic_off_outlined : Icons.mic_none_rounded),
                color: listening ? colors.ai : (unsupported ? colors.faint : colors.muted),
              ),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListeningWave extends StatelessWidget {
  const _ListeningWave({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.ai;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3,
            height: 6 + 14 * (context.reduceMotion ? 0.3 : (level * (1 - (i - 2).abs() * 0.25))).clamp(0.1, 1.0),
            decoration: BoxDecoration(color: color, borderRadius: AppRadii.pillAll),
          ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.busy, required this.onTap});

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: busy ? 'Waiting for reply' : 'Send message',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Send',
        child: AnimatedContainer(
          duration: context.motion(AppDurations.fast),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? colors.primary : colors.surfaceVariant,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: Center(
                child: busy
                    ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colors.muted))
                    : Icon(Icons.arrow_upward_rounded, color: enabled ? colors.onPrimary : colors.muted, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
