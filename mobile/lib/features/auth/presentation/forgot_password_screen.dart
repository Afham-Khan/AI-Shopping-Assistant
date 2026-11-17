import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/auth_controller.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/otp_input.dart';
import 'widgets/password_strength_meter.dart';

enum _Step { email, code, password }

/// Three-step reset: email → 6-digit code → new password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _resendSeconds = 60;

  final _emailForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  ApiException? _error;
  String? _resetToken;
  Timer? _timer;
  int _cooldown = 0;

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    context.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
        return;
      }
      setState(() => _cooldown--);
    });
  }

  void _sendCode() {
    if (!_emailForm.currentState!.validate()) return;
    _run(() async {
      await _auth.requestPasswordReset(_email.text);
      if (!mounted) return;
      _otp.clear();
      setState(() => _step = _Step.code);
      _startCooldown();
    });
  }

  void _resend() => _run(() async {
    await _auth.requestPasswordReset(_email.text);
    if (!mounted) return;
    _otp.clear();
    _startCooldown();
    AppSnack.success(context, 'A new code is on its way');
  });

  void _verify() {
    if (Validators.otp(_otp.text) != null) {
      setState(() => _error = const ApiException('Enter the 6-digit code from your email.'));
      return;
    }
    _run(() async {
      final token = await _auth.verifyResetCode(email: _email.text, otp: _otp.text);
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _step = _Step.password;
      });
    });
  }

  void _reset() {
    if (!_passwordForm.currentState!.validate()) return;
    _run(() async {
      await _auth.resetPassword(resetToken: _resetToken!, password: _password.text);
      if (!mounted) return;
      AppSnack.success(context, 'Password updated — sign in with your new password');
      context.go(Routes.login);
    });
  }

  // steps back inside the flow (the first step pops the route instead)
  void _back() {
    if (_busy || _step == _Step.email) return;
    setState(() {
      _error = null;
      _step = _step == _Step.password ? _Step.code : _Step.email;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_step) {
      _Step.email => ('Reset your password', "Enter your account email and we'll send a 6-digit code."),
      _Step.code => ('Check your email', 'We sent a code to ${_email.text.trim()}. It expires in 10 minutes.'),
      _Step.password => ('Choose a new password', 'Use at least 8 characters with a letter and a number.'),
    };

    return PopScope(
      canPop: _step == _Step.email,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AuthScaffold(
        title: title,
        subtitle: subtitle,
        step: _step.index + 1,
        steps: _Step.values.length,
        onBack: () => _step == _Step.email ? (context.canPop() ? context.pop() : context.go(Routes.login)) : _back(),
        child: AnimatedSwitcher(
          duration: context.motion(AppDurations.normal),
          switchInCurve: AppCurves.standard,
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: switch (_step) {
              _Step.email => _emailStep(),
              _Step.code => _codeStep(),
              _Step.password => _passwordStep(),
            },
          ),
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Form(
      key: _emailForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormErrorBanner(message: _error?.hasFieldErrors == true ? null : _error?.message),
          AppTextField(
            label: 'Email',
            controller: _email,
            hint: 'you@example.com',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: Validators.email,
            errorText: _error?.fieldError('email'),
            onSubmitted: (_) => _sendCode(),
            enabled: !_busy,
            autofocus: true,
          ),
          AppSpacing.gapXl,
          AppButton(label: 'Send code', onPressed: _sendCode, loading: _busy, expand: true),
        ],
      ),
    );
  }

  Widget _codeStep() {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormErrorBanner(message: _error?.message),
        OtpInput(controller: _otp, hasError: _error != null, enabled: !_busy, onCompleted: (_) => _verify()),
        AppSpacing.gapXl,
        AppButton(label: 'Verify code', onPressed: _verify, loading: _busy, expand: true),
        AppSpacing.gapSm,
        Center(
          child: _cooldown > 0
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    'Resend available in 0:${_cooldown.toString().padLeft(2, '0')}',
                    style: AppType.data(context, color: colors.faint),
                  ),
                )
              : TextButton(onPressed: _busy ? null : _resend, child: const Text("Didn't get it? Resend code")),
        ),
      ],
    );
  }

  Widget _passwordStep() {
    return Form(
      key: _passwordForm,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormErrorBanner(message: _error?.hasFieldErrors == true ? null : _error?.message),
            AppTextField(
              label: 'New password',
              controller: _password,
              isPassword: true,
              prefixIcon: Icons.lock_outline_rounded,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.password,
              errorText: _error?.fieldError('password'),
              enabled: !_busy,
              autofocus: true,
            ),
            AppSpacing.gapXs,
            PasswordStrengthMeter(password: _password.text),
            AppSpacing.gapMd,
            AppTextField(
              label: 'Confirm new password',
              controller: _confirm,
              isPassword: true,
              prefixIcon: Icons.lock_outline_rounded,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.confirmPassword(() => _password.text),
              onSubmitted: (_) => _reset(),
              enabled: !_busy,
            ),
            AppSpacing.gapXl,
            AppButton(label: 'Update password', onPressed: _reset, loading: _busy, expand: true),
          ],
        ),
      ),
    );
  }
}
