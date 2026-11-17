import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/auth_controller.dart';
import 'widgets/auth_scaffold.dart';

enum _Action { email, demo }

/// Email/password sign-in, demo account shortcut and guest mode.
/// On success the router redirects (to `from` or home) — no manual navigation.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.from});

  /// Location to return to after signing in.
  final String? from;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Action? _busy;
  ApiException? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(_Action action, Future<void> Function() task) async {
    if (_busy != null) return;
    context.unfocus();
    setState(() {
      _busy = action;
      _error = null;
    });
    try {
      await task();
      TextInput.finishAutofillContext();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _submit() {
    if (!validateForm(_formKey)) {
      setState(() => _error = const ApiException(kFixFieldsMessage));
      return;
    }
    _run(
      _Action.email,
      () => ref.read(authControllerProvider.notifier).login(email: _email.text, password: _password.text),
    );
  }

  void _demo() => _run(_Action.demo, () => ref.read(authControllerProvider.notifier).demoLogin());

  Future<void> _guest() async {
    await ref.read(authControllerProvider.notifier).continueAsGuest();
    if (mounted) context.go(Routes.returnTo(widget.from));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy != null;
    final fieldErrors = _error?.fieldErrors ?? const {};
    final canPop = context.canPop();

    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Up late'
        : hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return AuthScaffold(
      eyebrow: greeting,
      title: 'Welcome back',
      subtitle: 'Your cart, saved items and conversations with ${AppConfig.assistantName} are where you left them.',
      onBack: canPop ? () => context.pop() : null,
      footer: AuthFooterLink(
        question: 'New to Zelora?',
        action: 'Create an account',
        onTap: () => context.pushReplacement(Routes.registerFrom(widget.from)),
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DemoButton(loading: _busy == _Action.demo, onPressed: busy ? null : _demo),
              const OrDivider(label: 'or sign in with email'),
              FormErrorBanner(message: fieldErrors.isEmpty ? _error?.message : null),
              AppTextField(
                label: 'Email',
                controller: _email,
                hint: 'you@example.com',
                prefixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                errorText: fieldErrors['email'],
                enabled: !busy,
              ),
              AppSpacing.gapMd,
              AppTextField(
                label: 'Password',
                controller: _password,
                isPassword: true,
                prefixIcon: Icons.lock_outline_rounded,
                autofillHints: const [AutofillHints.password],
                validator: Validators.loginPassword,
                errorText: fieldErrors['password'],
                onSubmitted: (_) => _submit(),
                enabled: !busy,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : () => context.push(Routes.forgotPassword),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.primary,
                    textStyle: context.textTheme.labelLarge!.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ),
              AppSpacing.gapXs,
              AppButton(
                label: 'Sign in',
                onPressed: busy ? null : _submit,
                loading: _busy == _Action.email,
                expand: true,
              ),
              AppSpacing.gapSm,
              AppButton.ghost(
                label: 'Continue as guest',
                onPressed: busy ? null : _guest,
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-tap demo sign-in (for presentations) — the most prominent option on
/// the screen: a light-blue card with a blue outline, the assistant's mascot in a blue
/// circle, a line of context and an arrow that nudges on hover.
class _DemoButton extends StatefulWidget {
  const _DemoButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  State<_DemoButton> createState() => _DemoButtonState();
}

class _DemoButtonState extends State<_DemoButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final enabled = widget.onPressed != null || widget.loading;
    final lifted = _hovered && enabled;

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: 'Continue with demo account',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Pressable(
          enabled: widget.onPressed != null,
          scale: 0.98,
          child: AnimatedContainer(
            duration: context.motion(AppDurations.color),
            decoration: BoxDecoration(
              borderRadius: AppRadii.cardAll,
              boxShadow: lifted ? colors.shadowMd : colors.shadowSm,
            ),
            child: Material(
              color: colors.primarySoft,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.cardAll,
                side: BorderSide(color: colors.primary, width: 1.5),
              ),
              child: InkWell(
                onTap: widget.loading ? null : widget.onPressed,
                onHover: (h) => setState(() => _hovered = h),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 14, AppSpacing.sm, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                        child: widget.loading
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
                              )
                            : AiSparkleIcon(size: 20, color: colors.onPrimary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Continue with demo account',
                              style: t.titleMedium!.copyWith(fontSize: 15.5, fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'One tap, no sign-up. Cart and chats included.',
                              style: t.bodySmall!.copyWith(color: colors.muted),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      AnimatedSlide(
                        offset: Offset(lifted && !context.reduceMotion ? 0.15 : 0, 0),
                        duration: AppDurations.fast,
                        curve: AppCurves.standard,
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle),
                          child: Icon(Icons.arrow_forward_rounded, size: 18, color: colors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
