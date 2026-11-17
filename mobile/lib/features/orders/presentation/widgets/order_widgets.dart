import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/models/order.dart';

/// Status pill with a semantic colour.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (status) {
      OrderStatus.delivered => colors.success,
      OrderStatus.cancelled => colors.error,
      OrderStatus.placed || OrderStatus.confirmed => colors.secondary,
      _ => colors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.18 : 0.1),
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(status.label, style: context.textTheme.labelSmall!.copyWith(color: color)),
    );
  }
}

/// Vertical tracker: every step of the happy path, done steps checked with
/// their time, the current step pulsing. Cancelled orders show what happened.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final cancelled = order.status == OrderStatus.cancelled;
    final steps = cancelled
        ? [
            for (final s in OrderStatus.flow)
              if (order.eventFor(s) != null) s,
            OrderStatus.cancelled,
          ]
        : OrderStatus.flow;
    final currentIndex = cancelled ? steps.length - 1 : OrderStatus.flow.indexOf(order.status);

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            status: steps[i],
            event: order.eventFor(steps[i]),
            done: i <= currentIndex,
            current: i == currentIndex,
            isLast: i == steps.length - 1,
            nextDone: i + 1 <= currentIndex,
            eta: steps[i] == OrderStatus.delivered && i > currentIndex ? order.estimatedDelivery : null,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.status,
    required this.event,
    required this.done,
    required this.current,
    required this.isLast,
    required this.nextDone,
    this.eta,
  });

  final OrderStatus status;
  final OrderEvent? event;
  final bool done;
  final bool current;
  final bool isLast;
  final bool nextDone;
  final DateTime? eta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final accent = status == OrderStatus.cancelled ? colors.error : colors.primary;
    final subtitle = event != null
        ? [if (event!.note != null) event!.note!, if (event!.createdAt != null) Formatters.dateTime(event!.createdAt)].join(' · ')
        : (eta != null ? 'Expected by ${Formatters.date(eta)}' : null);

    return Semantics(
      label: '${status.stepTitle}, ${done ? (current ? 'current step' : 'done') : 'pending'}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  _Dot(done: done, current: current, color: accent, cancelled: status == OrderStatus.cancelled),
                  if (!isLast)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: nextDone ? 1 : 0),
                          duration: context.motion(AppDurations.slow),
                          curve: AppCurves.standard,
                          builder: (_, v, _) => Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              Container(width: 2, color: colors.border),
                              FractionallySizedBox(
                                heightFactor: v,
                                child: Container(width: 2, color: accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg, top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.stepTitle,
                      style: t.titleSmall!.copyWith(color: done ? colors.text : colors.muted),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, style: t.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _Dot extends StatefulWidget {
  const _Dot({required this.done, required this.current, required this.color, required this.cancelled});

  final bool done;
  final bool current;
  final Color color;
  final bool cancelled;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final shouldPulse = widget.current && !widget.cancelled && !context.reduceMotion;
    if (shouldPulse && _pulse == null) {
      _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    } else if (!shouldPulse && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dot = AnimatedContainer(
      duration: context.motion(AppDurations.normal),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: widget.done ? widget.color : colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: widget.done ? widget.color : colors.border, width: 2),
      ),
      child: widget.done
          ? Icon(widget.cancelled ? Icons.close_rounded : Icons.check_rounded, size: 14, color: colors.onPrimary)
          : null,
    );
    final pulse = _pulse;
    if (pulse == null) return dot;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (_, _) => Container(
              width: 24 + 12 * pulse.value,
              height: 24 + 12 * pulse.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: widget.color.withValues(alpha: 0.5 * (1 - pulse.value)), width: 2),
              ),
            ),
          ),
          dot,
        ],
      ),
    );
  }
}
