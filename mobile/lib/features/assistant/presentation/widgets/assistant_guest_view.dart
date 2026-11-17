import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/presentation/widgets/ai_ui.dart';
import '../../../auth/providers/auth_controller.dart';

/// Sign-in prompt shown inside the assistant tab for guests.
class AssistantGuestView extends ConsumerStatefulWidget {
  const AssistantGuestView({super.key, this.returnTo = Routes.assistant});

  final String returnTo;

  @override
  ConsumerState<AssistantGuestView> createState() => _AssistantGuestViewState();
}

class _AssistantGuestViewState extends ConsumerState<AssistantGuestView> {
  bool _demoBusy = false;

  Future<void> _demo() async {
    setState(() => _demoBusy = true);
    try {
      await ref.read(authControllerProvider.notifier).demoLogin();
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    const points = [
      (Icons.chat_outlined, 'Ask in plain English or Roman Urdu', '"sasta mobile chahiye 30k tak" just works.'),
      (Icons.fact_check_outlined, 'Every pick is explained', 'See the match score and the reasons behind it.'),
      (Icons.compare_arrows_rounded, 'Compare and decide faster', 'Specs side by side with a clear verdict.'),
      (Icons.history_rounded, 'Your chats are saved', 'Pick up any conversation on any device.'),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: context.pagePadding, vertical: AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.maxForm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AiAvatar(size: 56)),
              AppSpacing.gapMd,
              Semantics(
                header: true,
                child: Text(
                  'Meet ${AppConfig.assistantName}',
                  textAlign: TextAlign.center,
                  style: t.headlineSmall!.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              AppSpacing.gapXs,
              Text(
                'Sign in to chat with your personal shopping assistant.',
                textAlign: TextAlign.center,
                style: t.bodyMedium!.copyWith(color: colors.muted),
              ),
              AppSpacing.gapXl,
              for (final (icon, title, body) in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: colors.aiSoft, borderRadius: AppRadii.inputAll),
                        child: Icon(icon, size: 18, color: colors.ai),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: t.titleSmall),
                            Text(body, style: t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              AppSpacing.gapMd,
              AppButton(
                label: 'Sign in',
                expand: true,
                onPressed: () => context.push(Routes.loginFrom(widget.returnTo)),
              ),
              AppSpacing.gapSm,
              AppButton.secondary(
                label: 'Create an account',
                expand: true,
                onPressed: () => context.push(Routes.registerFrom(widget.returnTo)),
              ),
              AppSpacing.gapXs,
              AppButton.ghost(label: 'Try the demo account', expand: true, loading: _demoBusy, onPressed: _demo),
            ],
          ),
        ),
      ),
    );
  }
}
