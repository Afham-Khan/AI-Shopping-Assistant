import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../ai/presentation/widgets/ai_ui.dart';

/// Assistant "typing": avatar, three bouncing dots and a cycling
/// status line that tells the user what the AI is doing.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  static const statuses = [
    'Understanding your request',
    'Searching the catalog',
    'Ranking the best matches',
    'Writing a reply',
  ];

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  Timer? _timer;
  int _status = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted && _status < TypingIndicator.statuses.length - 1) setState(() => _status++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = TypingIndicator.statuses[_status];
    return Semantics(
      liveRegion: true,
      label: '${AppConfig.appName} AI is thinking: $status',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AiAvatar(size: 30),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Color.alphaBlend(colors.aiSoft.withValues(alpha: 0.7), colors.surface),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (var i = 0; i < 3; i++) _dot(i)],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: context.motion(AppDurations.normal),
                      child: AiText(
                        '$status…',
                        key: ValueKey(status),
                        maxLines: 1,
                        style: context.textTheme.labelMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(int i) {
    final phase = (_c.value - i * 0.18) % 1.0;
    final lift = math.sin(phase * math.pi).clamp(0.0, 1.0);
    final color = context.colors.ai;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Transform.translate(
        offset: Offset(0, -4 * lift),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4 + 0.6 * lift),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
