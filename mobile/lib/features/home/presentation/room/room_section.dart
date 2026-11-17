import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/presentation/ai_actions.dart';
import '../../providers/room_providers.dart';
import 'room_layout.dart';
import 'room_painter.dart';
import 'room_tray.dart';
import 'setup_sheet.dart';

/// Home's hero: an illustrated room where every corner is a department.
///
/// Tap a zone (or its numbered hotspot): the camera glides in and a tray of
/// that zone's products slides up. "Build my setup" asks Zel for a bundle
/// and flies each piece into its zone while the budget meter fills.
///
/// Performance: the room is painted once into a RepaintBoundary (again only
/// when the minute or theme changes); the camera is a single [Transform]
/// driven by an AnimatedBuilder, so zooming never repaints the illustration.
class RoomSection extends ConsumerStatefulWidget {
  const RoomSection({super.key});

  @override
  ConsumerState<RoomSection> createState() => _RoomSectionState();
}

class _Flight {
  const _Flight({required this.product, required this.to, required this.start, required this.end});

  final ProductSummary product;
  final Rect to;
  final double start;
  final double end;

  double progress(double t) => ((t - start) / (end - start)).clamp(0.0, 1.0);
}

class _RoomSectionState extends ConsumerState<RoomSection> with TickerProviderStateMixin {
  static const _full = Rect.fromLTWH(0, 0, 1000, 880);
  static const _flyFrom = Offset(500, 1040);

  late final AnimationController _camera = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _tray = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final AnimationController _fly = AnimationController(vsync: this);
  late final CurvedAnimation _trayCurve = CurvedAnimation(
    parent: _tray,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  Rect _viewFrom = _full;
  Rect _viewTo = _full;
  bool _fromZoomed = false;
  bool _toZoomed = false;
  String? _selected;
  String? _trayZone;
  Rect? _dimFocus;

  List<_Flight> _flights = const [];
  bool _flying = false;

  DateTime _now = DateTime.now();
  Timer? _clock;
  bool _pulseStarted = false;

  @override
  void initState() {
    super.initState();
    // drop the tray's content once it has fully slid away
    _tray.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
    // the wall clock and the day/night light follow local time
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pulseStarted && !context.reduceMotion) {
      _pulseStarted = true;
      // a few calm pulses to invite a tap, then the dots rest
      _pulse.repeat(count: 5);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _trayCurve.dispose();
    _camera.dispose();
    _tray.dispose();
    _pulse.dispose();
    _fly.dispose();
    super.dispose();
  }

  double get _cameraT => Curves.easeInOutCubic.transform(_camera.value);

  Rect get _viewport => Rect.lerp(_viewFrom, _viewTo, _cameraT)!;

  double get _dimAmount => _lerp(_fromZoomed ? 1 : 0, _toZoomed ? 1 : 0, _cameraT);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  void _select(String? id) {
    if (id == _selected) return;
    HapticFeedback.selectionClick();
    final spec = id == null ? null : RoomLayout.spec(id);
    setState(() {
      _viewFrom = _viewport;
      _fromZoomed = _selected != null;
      _toZoomed = spec != null;
      _viewTo = spec == null ? _full : RoomLayout.viewportFor(spec.hit);
      if (spec != null) _dimFocus = spec.hit;
      _selected = id;
      if (id != null) _trayZone = id;
    });
    if (id != null) ref.read(roomExploredProvider.notifier).mark(id);
    if (context.reduceMotion) {
      _camera.value = 1;
      _tray.value = id == null ? 0 : 1;
    } else {
      _camera.forward(from: 0);
      id == null ? _tray.reverse() : _tray.forward();
    }
  }

  Future<void> _buildSetup(List<RoomZone> zones) async {
    final result = await showSetupSheet(context);
    if (result == null || !mounted) return;
    _select(null);
    final setup = ref.read(roomSetupProvider.notifier).place(result, zones);
    _launch(setup);
  }

  /// Flies every placed product from below the stage into its zone, one
  /// after another, while the budget meter fills.
  void _launch(RoomSetup setup) {
    final flights = <_Flight>[];
    final groups = <String?, List<PlacedItem>>{};
    for (final item in setup.items) {
      (groups[item.zoneId] ??= []).add(item);
    }
    const step = 0.24;
    const travel = 0.8;
    final n = setup.items.length;
    final total = step * math.max(0, n - 1) + travel;
    var i = 0;
    for (final entry in groups.entries) {
      final slot = entry.key == null ? RoomLayout.rugSlot : RoomLayout.spec(entry.key!)!.slot;
      final count = entry.value.length;
      for (var j = 0; j < count && j < 3; j++) {
        final start = i * step / total;
        flights.add(
          _Flight(
            product: entry.value[j].product,
            to: RoomLayout.placedRect(slot, j, count),
            start: start,
            end: (i * step + travel) / total,
          ),
        );
        i++;
      }
    }
    if (context.reduceMotion || flights.isEmpty) {
      setState(() => _flying = false);
      return;
    }
    _fly.duration = Duration(milliseconds: (total * 1000).round());
    setState(() {
      _flights = flights;
      _flying = true;
    });
    _fly.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _flying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final async = ref.watch(roomZonesProvider);
    final zones = async.value ?? RoomLayout.merge(const []);
    final explored = ref.watch(roomExploredProvider);
    final setup = ref.watch(roomSetupProvider);
    final trayZone = _trayZone == null ? null : zones.firstWhere((z) => z.id == _trayZone, orElse: () => zones.first);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.sheetAll,
        boxShadow: colors.shadowSm,
        border: Border.all(color: context.isDark ? colors.border : colors.border.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
            child: _RoomHeader(explored: explored.where((id) => RoomLayout.spec(id) != null).length, now: _now),
          ),
          ClipRRect(
            borderRadius: AppRadii.cardAll,
            child: _stage(context, zones, explored, setup),
          ),
          if (async.hasError && !async.isLoading)
            _InlineRetry(onRetry: () => ref.invalidate(roomZonesProvider)),
          SizeTransition(
            sizeFactor: _trayCurve,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _trayCurve,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(_trayCurve),
                child: trayZone == null || (_selected == null && _tray.isDismissed)
                    ? const SizedBox.shrink()
                    : RoomTray(
                        zone: trayZone,
                        products: _trayProducts(trayZone, setup),
                        placedIds: {for (final i in setup?.items ?? const <PlacedItem>[]) i.product.id},
                        onClose: () => _select(null),
                        onSeeAll: () => context.push(
                          Routes.productList(
                            department: trayZone.department,
                            title: RoomLayout.departmentName(trayZone.department),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.xs),
            child: setup == null
                ? _BuildPrompt(onBuild: () => _buildSetup(zones))
                : AnimatedBuilder(
                    animation: _fly,
                    builder: (context, _) => _BudgetBar(
                      setup: setup,
                      spent: _flying ? _spent(setup) : setup.total,
                      onAddAll: () => addAllToCart(context, ref, [for (final i in setup.items) i.product], source: 'room'),
                      onRebuild: () => _buildSetup(zones),
                      onClear: () => ref.read(roomSetupProvider.notifier).clear(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  double _spent(RoomSetup setup) {
    var sum = 0.0;
    for (final f in _flights) {
      sum += f.product.price * Curves.easeOut.transform(f.progress(_fly.value));
    }
    // items beyond three per zone don't fly but still count
    final flown = {for (final f in _flights) f.product.id};
    for (final i in setup.items) {
      if (!flown.contains(i.product.id)) sum += i.product.price * _fly.value;
    }
    return sum;
  }

  List<ProductSummary> _trayProducts(RoomZone zone, RoomSetup? setup) {
    final placed = [for (final i in setup?.inZone(zone.id) ?? const <PlacedItem>[]) i.product];
    final ids = {for (final p in placed) p.id};
    return [...placed, for (final p in zone.featured) if (!ids.contains(p.id)) p];
  }

  Widget _stage(BuildContext context, List<RoomZone> zones, Set<String> explored, RoomSetup? setup) {
    final colors = context.colors;
    final palette = RoomPalette.of(colors, dark: context.isDark);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = w * RoomLayout.size.height / RoomLayout.size.width;
        final k = w / RoomLayout.size.width;

        final scene = SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // static layer: the illustration + product cut-outs, cached
              RepaintBoundary(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: Size(w, h),
                      painter: RoomPainter(palette: palette, night: RoomLayout.nightFactor(_now), time: _now),
                    ),
                    ..._sceneProducts(zones, setup, k),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: RoomFocusPainter(
                      focus: _dimFocus,
                      amount: () => _dimAmount,
                      color: colors.shadow.withValues(alpha: context.isDark ? 0.5 : 0.28),
                      repaint: _camera,
                    ),
                  ),
                ),
              ),
              if (_flying)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _fly,
                      builder: (context, _) => Stack(clipBehavior: Clip.none, children: _flightWidgets(k)),
                    ),
                  ),
                ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final id = RoomLayout.zoneAt(d.localPosition / k);
                    if (id != null) _select(id);
                  },
                ),
              ),
              // hotspots fade out while the camera is in
              AnimatedBuilder(
                animation: _camera,
                builder: (context, child) {
                  final o = 1 - _dimAmount;
                  return IgnorePointer(
                    ignoring: _selected != null,
                    child: Opacity(opacity: o.clamp(0.0, 1.0), child: child),
                  );
                },
                child: RepaintBoundary(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final z in zones)
                        Positioned(
                          left: z.spec.hotspot.dx * k - 22,
                          top: z.spec.hotspot.dy * k - 22,
                          width: 44,
                          height: 44,
                          child: _Hotspot(
                            zone: z,
                            explored: explored.contains(z.id),
                            pulse: _pulse,
                            onTap: () => _select(z.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              ClipRect(
                child: AnimatedBuilder(
                  animation: _camera,
                  child: scene,
                  builder: (context, child) {
                    final v = _viewport;
                    final z = RoomLayout.size.width / v.width;
                    // column-major: uniform scale, then translate the viewport's corner to the origin
                    final m = Matrix4(z, 0, 0, 0, 0, z, 0, 0, 0, 0, 1, 0, -v.left * k * z, -v.top * k * z, 0, 1);
                    return Transform(transform: m, child: child);
                  },
                ),
              ),
              // camera controls, outside the transform so they stay crisp
              Positioned(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
                child: _ZoomedOverlay(
                  visible: _selected != null,
                  label: _selected == null
                      ? ''
                      : RoomLayout.departmentName(zones.firstWhere((z) => z.id == _selected).department),
                  hue: _selected == null
                      ? colors.primary
                      : colors.departmentAccent(zones.firstWhere((z) => z.id == _selected).department),
                  onBack: () => _select(null),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Featured cut-outs at each zone's anchor; setup pieces replace them.
  List<Widget> _sceneProducts(List<RoomZone> zones, RoomSetup? setup, double k) {
    final out = <Widget>[];
    for (final z in zones) {
      final placed = (setup != null && !_flying) ? setup.inZone(z.id) : const <PlacedItem>[];
      if (placed.isNotEmpty) {
        for (var i = 0; i < placed.length && i < 3; i++) {
          out.add(_SceneProduct(product: placed[i].product, rect: RoomLayout.placedRect(z.spec.slot, i, placed.length), k: k, placed: true));
        }
      } else if (z.featured.isNotEmpty) {
        final p = z.featured.firstWhere((p) => p.thumbnail != null, orElse: () => z.featured.first);
        out.add(_SceneProduct(product: p, rect: z.spec.slot, k: k));
      }
    }
    if (setup != null && !_flying) {
      final rug = setup.inZone(null);
      for (var i = 0; i < rug.length && i < 3; i++) {
        out.add(_SceneProduct(product: rug[i].product, rect: RoomLayout.placedRect(RoomLayout.rugSlot, i, rug.length), k: k, placed: true));
      }
    }
    return out;
  }

  List<Widget> _flightWidgets(double k) {
    final t = _fly.value;
    final out = <Widget>[];
    for (final f in _flights) {
      final p = f.progress(t);
      if (p <= 0) continue;
      final e = Curves.easeOutCubic.transform(p);
      final to = f.to.center;
      // a gentle arc: up from below the stage, then down into the zone
      final control = Offset((_flyFrom.dx + to.dx) / 2, math.min(_flyFrom.dy, to.dy) - 280);
      final pos = _bezier(_flyFrom, control, to, e);
      final scale = _lerp(1.7, 1, e);
      final size = f.to.size * scale;
      out.add(
        _SceneProduct(
          product: f.product,
          rect: Rect.fromCenter(center: pos, width: size.width, height: size.height),
          k: k,
          placed: p >= 1,
          opacity: (p * 4).clamp(0.0, 1.0),
        ),
      );
    }
    return out;
  }

  static Offset _bezier(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return a * (u * u) + c * (2 * u * t) + b * (t * t);
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.explored, required this.now});

  final int explored;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final total = RoomLayout.zones.length;
    final night = RoomLayout.nightFactor(now) > 0.5;
    final done = explored >= total;
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final status = _status(context, done: done, total: total, night: night);
    final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text('Shop the room', style: t.titleLarge)),
              const SizedBox(height: 2),
              Text(
                'Every corner is a department. Tap one to look closer.',
                style: t.bodySmall!.copyWith(color: colors.muted),
              ),
            ],
          );
    if (big) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [copy, const SizedBox(height: AppSpacing.xs), FittedBox(fit: BoxFit.scaleDown, child: status)],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: copy),
        const SizedBox(width: AppSpacing.xs),
        status,
      ],
    );
  }

  Widget _status(BuildContext context, {required bool done, required int total, required bool night}) {
    final t = context.textTheme;
    final colors = context.colors;
    return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Semantics(
              label: done ? 'All $total corners explored' : '$explored of $total corners explored',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.pillAll),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: done
                          ? Icon(Icons.check_circle_rounded, size: 14, color: colors.primary)
                          : TweenAnimationBuilder<double>(
                              tween: Tween(end: explored / total),
                              duration: context.motion(AppDurations.slow),
                              builder: (_, v, _) => CircularProgressIndicator(
                                value: v,
                                strokeWidth: 2.4,
                                color: colors.primary,
                                backgroundColor: colors.primary.withValues(alpha: 0.18),
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      done ? 'All explored' : '$explored/$total explored',
                      style: t.labelMedium!.copyWith(color: colors.primary, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(night ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 13, color: colors.faint),
                const SizedBox(width: 4),
                Text(
                  Formatters.time(now),
                  style: t.labelSmall!.copyWith(color: colors.faint, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ],
        );
  }
}

/// A product cut-out standing in the scene, decoded at ~2.4× its resting
/// size so it stays sharp when the camera zooms in.
class _SceneProduct extends StatelessWidget {
  const _SceneProduct({required this.product, required this.rect, required this.k, this.placed = false, this.opacity = 1});

  final ProductSummary product;
  final Rect rect;
  final double k;
  final bool placed;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = Rect.fromLTRB(rect.left * k, rect.top * k, rect.right * k, rect.bottom * k);
    Widget image = FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: r.width * 2.4,
        height: r.height * 2.4,
        child: AppNetworkImage(
          product.thumbnail,
          width: r.width * 2.4,
          height: r.height * 2.4,
          fit: BoxFit.contain,
          backgroundColor: Colors.transparent,
          semanticLabel: product.title,
        ),
      ),
    );
    if (opacity < 1) image = Opacity(opacity: opacity, child: image);
    return Positioned.fromRect(
      rect: r,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // soft contact shadow where the product meets its surface
          Positioned(
            left: r.width * 0.12,
            right: r.width * 0.12,
            bottom: -r.height * 0.03,
            height: math.max(3, r.height * 0.07),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.elliptical(100, 20)),
                color: colors.shadow.withValues(alpha: 0.12 * opacity),
              ),
            ),
          ),
          Positioned.fill(child: image),
          if (placed)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: math.max(8, r.width * 0.09),
                height: math.max(8, r.width * 0.09),
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hotspot extends StatelessWidget {
  const _Hotspot({required this.zone, required this.explored, required this.pulse, required this.onTap});

  final RoomZone zone;
  final bool explored;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Semantics(
      button: true,
      label: '${zone.label}, ${RoomLayout.departmentName(zone.department)}${explored ? ', explored' : ''}',
      excludeSemantics: true,
      child: Tooltip(
        message: zone.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: CustomPaint(
              painter: explored ? null : _PulsePainter(pulse, colors.primary),
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: explored ? colors.primary : colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.primary, width: 2),
                  boxShadow: colors.shadowSm,
                ),
                child: explored
                    ? Icon(Icons.check_rounded, size: 14, color: colors.onPrimary)
                    : Text(
                        '${zone.spec.number}',
                        style: t.labelSmall!.copyWith(color: colors.primary, fontWeight: FontWeight.w700, height: 1),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Expanding ring behind an unexplored hotspot (paint-only; no rebuilds).
class _PulsePainter extends CustomPainter {
  _PulsePainter(this.pulse, this.color) : super(repaint: pulse);

  final Animation<double> pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = pulse.value;
    if (v <= 0 || v >= 1) return;
    final r = size.width / 2 * (1 + v * 0.9);
    canvas.drawCircle(size.center(Offset.zero), r, Paint()..color = color.withValues(alpha: 0.35 * (1 - v)));
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.color != color;
}

class _ZoomedOverlay extends StatelessWidget {
  const _ZoomedOverlay({required this.visible, required this.label, required this.hue, required this.onBack});

  final bool visible;
  final String label;
  final Color hue;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: context.motion(AppDurations.normal),
        child: Material(
          color: colors.surface,
          shape: const StadiumBorder(),
          elevation: 0,
          shadowColor: colors.shadow,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 20, color: colors.text),
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: hue, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(label, style: t.labelLarge, semanticsLabel: 'Back to the room, viewing $label'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BuildPrompt extends StatelessWidget {
  const _BuildPrompt({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final hint = Row(
      children: [
        const AiSparkleIcon(size: 18),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Let Zel furnish it to your budget.',
            style: t.bodySmall!.copyWith(color: context.colors.muted),
          ),
        ),
      ],
    );
    final button = AppButton(label: 'Build my setup', size: AppButtonSize.small, onPressed: onBuild);
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hint,
          const SizedBox(height: AppSpacing.xs),
          FittedBox(fit: BoxFit.scaleDown, child: button),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: hint),
        const SizedBox(width: AppSpacing.xs),
        button,
      ],
    );
  }
}

/// "Rs 84,000 of Rs 150,000" with a bar that fills as pieces land.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({
    required this.setup,
    required this.spent,
    required this.onAddAll,
    required this.onRebuild,
    required this.onClear,
  });

  final RoomSetup setup;
  final double spent;
  final VoidCallback onAddAll;
  final VoidCallback onRebuild;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final budget = setup.budget <= 0 ? setup.total : setup.budget;
    final ratio = budget <= 0 ? 0.0 : spent / budget;
    final over = spent > budget + 0.5;
    final barColor = over ? colors.sale : colors.primary;
    const tabular = [FontFeature.tabularFigures()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(setup.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
            ),
            IconButton(
              tooltip: 'Clear setup',
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: colors.muted),
            ),
          ],
        ),
        Semantics(
          label: '${Formatters.price(spent)} of ${Formatters.price(budget)} budget',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: AppSpacing.xs,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: Formatters.price(spent),
                          style: t.titleMedium!.copyWith(color: barColor, fontFeatures: tabular),
                        ),
                        TextSpan(
                          text: ' of ${Formatters.price(budget)}',
                          style: t.bodySmall!.copyWith(color: colors.muted, fontFeatures: tabular),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    over ? 'Over by ${Formatters.price(spent - budget)}' : '${Formatters.price(budget - spent)} left',
                    style: t.labelMedium!.copyWith(color: over ? colors.sale : colors.muted, fontFeatures: tabular),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppRadii.pillAll,
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: colors.surfaceRaised)),
                      FractionallySizedBox(
                        widthFactor: ratio.clamp(0.0, 1.0),
                        child: ColoredBox(color: barColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton(
              label: 'Add all to cart',
              icon: Icons.shopping_bag_outlined,
              size: AppButtonSize.small,
              onPressed: onAddAll,
            ),
            AppButton.secondary(label: 'Rebuild', size: AppButtonSize.small, onPressed: onRebuild),
          ],
        ),
      ],
    );
  }
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: context.colors.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text("Couldn't load the room's products", style: t.bodySmall!.copyWith(color: context.colors.muted)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
