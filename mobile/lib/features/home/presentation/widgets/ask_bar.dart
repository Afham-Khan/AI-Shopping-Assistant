import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// The hero "Ask Zelora" prompt: a real input with a rotating example as its
/// hint. Submitting (or tapping the arrow with an empty field) opens the
/// Assistant tab with the text prefilled.
class AskBar extends StatefulWidget {
  const AskBar({super.key});

  static const examples = [
    'a gaming laptop under 2 lakh…',
    'a gift for my mom under Rs 10,000…',
    'running shoes for flat feet…',
    'a phone with the best camera under 100k…',
    'a skincare routine for oily skin…',
    'a smartwatch that tracks sleep…',
  ];

  @override
  State<AskBar> createState() => _AskBarState();
}

class _AskBarState extends State<AskBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      // pause while the user is typing
      if (!mounted || _focus.hasFocus || _controller.text.isNotEmpty) return;
      setState(() => _index = (_index + 1) % AskBar.examples.length);
    });
    _controller.addListener(_onChanged);
    _focus.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = _controller.text.trim();
    // an empty submit asks the example currently shown
    final prompt = typed.isNotEmpty ? typed : 'Find me ${AskBar.examples[_index].replaceAll('…', '')}';
    _focus.unfocus();
    _controller.clear();
    context.go(Routes.assistantWith(prompt: prompt));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final showHint = _controller.text.isEmpty;

    return Semantics(
      textField: true,
      label: 'Ask ${AppConfig.appName}',
      child: AnimatedContainer(
        duration: context.motion(AppDurations.normal),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xxs, AppSpacing.xxs, AppSpacing.xxs),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.sheetAll,
          border: Border.all(color: _focus.hasFocus ? colors.text : colors.border, width: _focus.hasFocus ? 1.5 : 1),
        ),
        child: Row(
          children: [
            const AiSparkleIcon(size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  if (showHint)
                    IgnorePointer(
                      child: Row(
                        children: [
                          Text('Ask for ', style: t.bodyLarge!.copyWith(color: colors.muted)),
                          Expanded(
                            child: ClipRect(
                              child: AnimatedSwitcher(
                                duration: context.motion(AppDurations.slow),
                                switchInCurve: AppCurves.standard,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, anim) => FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(anim),
                                    child: child,
                                  ),
                                ),
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: AlignmentDirectional.centerStart,
                                  children: [...previous, ?current],
                                ),
                                child: Text(
                                  AskBar.examples[_index],
                                  key: ValueKey(_index),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodyLarge!.copyWith(color: colors.text.withValues(alpha: 0.75)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _controller,
                    focusNode: _focus,
                    style: t.bodyLarge,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    maxLines: 1,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton.filled(
              tooltip: 'Ask ${AppConfig.appName}',
              onPressed: _submit,
              style: IconButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size(44, 44),
              ),
              icon: const Icon(Icons.arrow_upward_rounded, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
