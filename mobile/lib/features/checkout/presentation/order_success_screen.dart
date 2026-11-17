import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../orders/providers/orders_providers.dart';

/// "Order placed" confirmation with an animated check, order number and ETA.
class OrderSuccessScreen extends ConsumerWidget {
  const OrderSuccessScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderDetailProvider(orderId)).value;
    final t = context.textTheme;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(tooltip: 'Close', onPressed: () => context.go(Routes.home), icon: const Icon(Icons.close_rounded)),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.maxForm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: _AnimatedCheck()),
                const SizedBox(height: AppSpacing.xl),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text('Order placed', style: t.headlineMedium, textAlign: TextAlign.center),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Thank you! We\'ve sent the details to your notifications.',
                  style: t.bodyMedium!.copyWith(color: colors.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadii.cardAll,
                    border: Border.all(color: colors.border),
                  ),
                  child: order == null
                      ? const SkeletonText(lines: 3)
                      : Column(
                          children: [
                            _Row(label: 'Order number', value: order.orderNumber),
                            _Row(label: 'Total', value: Formatters.price(order.total)),
                            _Row(label: 'Payment', value: order.paymentLabel),
                            if (order.estimatedDelivery != null)
                              _Row(
                                label: 'Estimated delivery',
                                value: Formatters.date(order.estimatedDelivery),
                                highlight: true,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Track order',
                  icon: Icons.local_shipping_outlined,
                  expand: true,
                  onPressed: () => context.go(Routes.orderDetailOf(orderId)),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton.secondary(
                  label: 'Continue shopping',
                  expand: true,
                  onPressed: () => context.go(Routes.home),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyMedium!.copyWith(color: colors.muted))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: t.titleSmall!.copyWith(color: highlight ? colors.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle fills, then the tick draws itself.
class _AnimatedCheck extends StatefulWidget {
  const _AnimatedCheck();

  @override
  State<_AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<_AnimatedCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final circle = CurvedAnimation(parent: _c, curve: const Interval(0, 0.5, curve: Curves.easeOutBack));
    final tick = CurvedAnimation(parent: _c, curve: const Interval(0.45, 1, curve: Curves.easeOutCubic));
    return Semantics(
      label: 'Success',
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Transform.scale(
          scale: circle.value,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
            child: CustomPaint(painter: _TickPainter(progress: tick.value, color: colors.onPrimary)),
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.37);
    final metric = path.computeMetrics().first;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(4, size.width * 0.07)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.progress != progress || old.color != color;
}
