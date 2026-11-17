import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/extensions.dart';

/// Labelled text field with inline error, optional prefix icon and a
/// show/hide toggle for passwords. Works inside a [Form] (uses [validator]).
///
/// ```dart
/// AppTextField(
///   label: 'Email',
///   controller: _email,
///   prefixIcon: Icons.mail_outline,
///   keyboardType: TextInputType.emailAddress,
///   validator: Validators.email,
///   errorText: apiError?.fieldError('email'),   // server-side error
/// )
/// AppTextField(label: 'Password', isPassword: true, onSubmitted: (_) => submit())
/// ```
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.autofillHints,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onTap,
    this.initialValue,
    this.required = false,
  });

  final TextEditingController? controller;

  /// Shown above the field.
  final String? label;
  final String? hint;
  final String? helperText;

  /// Error to show regardless of [validator] (e.g. from the API's `errors[]`).
  final String? errorText;
  final IconData? prefixIcon;
  final Widget? suffix;

  /// Obscures input and adds a visibility toggle.
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;

  /// Keyboard "done/go" — wire this to submit on the last field.
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final FocusNode? focusNode;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final VoidCallback? onTap;
  final String? initialValue;

  /// Marks the label with a red asterisk.
  final bool required;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;
  bool _capsLock = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.isPassword) HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    if (widget.isPassword) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // password fields warn about Caps Lock while focused (hardware keyboards)
  bool _onKey(KeyEvent event) {
    final on = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (on != _capsLock && mounted) setState(() => _capsLock = on);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget? suffix = widget.suffix;
    if (widget.isPassword) {
      suffix = IconButton(
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
        tooltip: _obscured ? 'Show password' : 'Hide password',
      );
    }

    final capsWarning = widget.isPassword && _capsLock && _focused && widget.errorText == null;

    final Widget field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: TextFormField(
      controller: widget.controller,
      initialValue: widget.controller == null ? widget.initialValue : null,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      obscureText: widget.isPassword && _obscured,
      enableSuggestions: !widget.isPassword,
      autocorrect: !widget.isPassword,
      keyboardType: widget.isPassword ? TextInputType.visiblePassword : widget.keyboardType,
      textInputAction: widget.textInputAction ?? (widget.onSubmitted != null ? TextInputAction.done : TextInputAction.next),
      textCapitalization: widget.textCapitalization,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      validator: widget.validator,
      // errors appear only once a field has been touched (left), then live
      autovalidateMode: AutovalidateMode.onUnfocus,
      autofillHints: widget.enabled ? widget.autofillHints : null,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      style: context.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: widget.hint,
        helperText: capsWarning ? 'Caps Lock is on' : widget.helperText,
        helperStyle: capsWarning
            ? context.textTheme.bodySmall!.copyWith(color: colors.warning, fontWeight: FontWeight.w600)
            : null,
        errorText: widget.errorText,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: 20),
        suffixIcon: suffix,
        counterText: widget.maxLength == null ? null : '',
      ),
      ),
    );

    if (widget.label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: widget.label),
              if (widget.required) TextSpan(text: ' *', style: TextStyle(color: colors.error)),
            ],
          ),
          semanticsLabel: widget.required ? '${widget.label}, required' : widget.label,
          style: context.textTheme.labelLarge!.copyWith(
            fontSize: 13,
            color: widget.enabled ? colors.text : colors.faint,
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }
}
