import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/extensions.dart';

/// Six digit boxes backed by one hidden text field, so paste, SMS autofill
/// and backspace all behave natively.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autofocus;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onChanged() {
    setState(() {});
    final value = widget.controller.text;
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;

    return Semantics(
      label: 'Verification code, ${widget.length} digits',
      value: value,
      textField: true,
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        child: Stack(
          children: [
            // invisible field that owns the keyboard/autofill
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: widget.length,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(counterText: '', border: InputBorder.none, filled: false),
                ),
              ),
            ),
            IgnorePointer(
              child: Row(
                children: [
                  for (var i = 0; i < widget.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _Box(
                        digit: i < value.length ? value[i] : '',
                        active: _focus.hasFocus && (i == value.length || (i == widget.length - 1 && value.length == widget.length)),
                        hasError: widget.hasError,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.digit, required this.active, required this.hasError});

  final String digit;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final filled = digit.isNotEmpty;
    final borderColor = hasError ? palette.error : (active ? palette.primary : (filled ? palette.borderStrong : palette.border));
    return AnimatedContainer(
      duration: context.motion(AppDurations.fast),
      height: 56,
      constraints: const BoxConstraints(maxWidth: 56),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadii.inputAll,
        border: Border.all(color: borderColor, width: active || hasError ? 1.5 : 1),
      ),
      // the active box shows a caret bar, like a real field
      child: digit.isEmpty && active
          ? Container(width: 1.5, height: 22, color: palette.primary)
          : Text(digit, style: AppType.mono(TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: palette.text))),
    );
  }
}
