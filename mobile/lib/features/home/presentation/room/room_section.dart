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
import '../../../ai/data/ai_repository.dart';
import '../../../ai/presentation/ai_actions.dart';
import '../../providers/room_providers.dart';
import 'room_layout.dart';
import 'room_painter.dart';
import 'room_setup_layer.dart';
import 'room_setup_panel.dart';
import '../widgets/scroll_depth.dart';
import 'room_tray.dart';
import 'setup_sheet.dart';

/// Home's hero: an illustrated room where every corner is a department.
///
/// Tap a zone (or its numbered hotspot): the camera glides in and a tray of
/// that zone's products slides up.
///
/// "Build my setup" asks Zel for the best set of products that fits a budget
/// (`POST /ai/bundle`, a knapsack under the budget) and shows the answer in
/// the room itself: the room scrolls into view, the untouched corners dim,
/// each piece flies to where it belongs and stays pinned (larger, ringed,
/// numbered, with a "role · price" chip), the header becomes "Your Gaming
/// setup" with a budget bar, and "How Zel chose these" explains the picks.
///
/// Performance: the room is painted once into a RepaintBoundary (again only
/// when the minute or theme changes); the camera is a single [Transform]
/// driven by an AnimatedBuilder, so zooming never repaints the illustration.
/// The fly-in is one [Flow] whose delegate only changes transforms, and the
/// spotlight is a cached path whose alpha follows a controller. Reduced
/// motion places everything at once.
class RoomSection extends ConsumerStatefulWidget {
  const RoomSection({super.key});

  @override
  ConsumerState<RoomSection> createState() => _RoomSectionState();
}

class _RoomSectionState extends ConsumerState<RoomSection> with TickerProviderStateMixin {
  static const _full = Rect.fromLTWH(0, 0, 1000, 880);

  /// Depth parallax (logical px at the viewport edges): the wall lags behind
  /// the page, the product cut-outs run ahead of it.
  static const _backShift = 18.0;
  static const _cutoutShift = -12.0;

  late final AnimationController _camera = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _tray = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final AnimationController _fly = AnimationController(vsync: this);
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  final _stageKey = GlobalKey();
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

  /// Pinned pieces + timeline for the current setup (computed once per setup).
  SetupStaging? _staging;
  RoomSetup? _stagedFor;
  bool _rebuilding = false;

  DateTime _now = DateTime.now();
  Timer? _clock;
  bool _pulseStarted = false;

  @override
  void initState() {
    super.initState();
    // a setup built earlier this session is shown placed, without replaying the flight
    if (ref.read(roomSetupProvider) != null) {
      _fly.value = 1;
      _reveal.value = 1;
    }
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
    _reveal.dispose();
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

  SetupStaging _stagingFor(RoomSetup setup) {
    if (!identical(setup, _stagedFor) || _staging == null) {
      _staging = SetupStaging.of(setup);
      _stagedFor = setup;
    }
    return _staging!;
  }

  Future<void> _buildSetup(List<RoomZone> zones) async {
    final result = await showSetupSheet(context);
    if (result == null || !mounted) return;
    _select(null);
    final setup = ref.read(roomSetupProvider.notifier).place(result, zones);
    await _present(setup);
  }

  /// Re-runs the same goal at the budget the notice suggests.
  Future<void> _useSuggested(RoomSetup setup, double budget, List<RoomZone> zones) async {
    setState(() => _rebuilding = true);
    try {
      final result = await ref.read(aiRepositoryProvider).bundle(goal: setup.title, budget: budget);
      if (!mounted) return;
      setState(() => _rebuilding = false);
      if (result.items.isEmpty) return;
      final next = ref.read(roomSetupProvider.notifier).place(result, zones);
      await _present(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rebuilding = false);
      AppSnack.error(context, e);
    }
  }

  /// Shows a freshly built setup in the room: scroll the stage into view, dim
  /// the untouched corners, then fly each piece to its zone, one after another.
  Future<void> _present(RoomSetup setup) async {
    final staging = _stagingFor(setup);
    final reduce = context.reduceMotion;
    _fly.stop();
    _fly.value = 0;
    setState(() {});
    final stage = _stageKey.currentContext;
    if (stage != null) {
      await Scrollable.ensureVisible(
        stage,
        alignment: 0.5,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted) return;
    if (reduce || staging.pieces.isEmpty) {
      _reveal.value = 1;
      _fly.value = 1;
      return;
    }
    _fly.duration = staging.duration;
    _reveal.forward();
    _fly.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted && _fly.isCompleted) HapticFeedback.lightImpact();
    });
  }

  /// Back to the normal room: chips shrink, pieces fly out, the dim lifts.
  Future<void> _clearRoom() async {
    if (!context.reduceMotion && _fly.value > 0) {
      _reveal.reverse();
      await _fly.animateBack(0, duration: const Duration(milliseconds: 420), curve: Curves.easeInCubic);
      if (!mounted) return;
    }
    _reveal.value = 0;
    ref.read(roomSetupProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final async = ref.watch(roomZonesProvider);
    final zones = async.value ?? RoomLayout.merge(const []);
    final explored = ref.watch(roomExploredProvider);
    final setup = ref.watch(roomSetupProvider);
    final staging = setup == null ? null : _stagingFor(setup);
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
          AnimatedSwitcher(
            duration: context.motion(AppDurations.slow),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: setup != null && staging != null
                ? Padding(
                    key: ValueKey(setup),
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: SetupHeaderBar(setup: setup, staging: staging, flight: _fly),
                  )
                : Padding(
                    key: const ValueKey('room-header'),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
                    child: _RoomHeader(explored: explored.where((id) => RoomLayout.spec(id) != null).length, now: _now),
                  ),
          ),
          ClipRRect(
            key: _stageKey,
            borderRadius: AppRadii.cardAll,
            child: _stage(context, zones, explored, setup, staging),
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
            child: setup == null || staging == null
                ? _BuildPrompt(onBuild: () => _buildSetup(zones))
                : SetupResultPanel(
                    setup: setup,
                    staging: staging,
                    zones: zones,
                    busy: _rebuilding,
                    onAddAll: () => addAllToCart(context, ref, [for (final i in setup.items) i.product], source: 'room'),
                    onRebuild: () => _buildSetup(zones),
                    onClear: _clearRoom,
                    onUseSuggested: (v) => _useSuggested(setup, v, zones),
                  ),
          ),
        ],
      ),
    );
  }

  List<ProductSummary> _trayProducts(RoomZone zone, RoomSetup? setup) {
    final placed = [for (final i in setup?.inZone(zone.id) ?? const <PlacedItem>[]) i.product];
    final ids = {for (final p in placed) p.id};
    return [...placed, for (final p in zone.featured) if (!ids.contains(p.id)) p];
  }

  Widget _stage(
    BuildContext context,
    List<RoomZone> zones,
    Set<String> explored,
    RoomSetup? setup,
    SetupStaging? staging,
  ) {
    final colors = context.colors;
    final palette = RoomPalette.of(colors, dark: context.isDark);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = w * RoomLayout.size.height / RoomLayout.size.width;
        final k = w / RoomLayout.size.width;

        final night = RoomLayout.nightFactor(_now);
        final scene = SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // depth parallax while the page scrolls, three cached layers moved by
              // one scroll position: the far wall lags (slowest), the furniture
              // scrolls with the page, the product cut-outs lead (fastest)
              Positioned.fill(
                key: const ValueKey('room-depth-back'),
                child: ScrollDepth(
                  shift: _backShift,
                  child: CustomPaint(
                    painter: RoomPainter(palette: palette, night: night, time: _now, depth: RoomDepth.back),
                  ),
                ),
              ),
              RepaintBoundary(
                key: const ValueKey('room-depth-front'),
                child: CustomPaint(
                  size: Size(w, h),
                  painter: RoomPainter(palette: palette, night: night, time: _now, depth: RoomDepth.front),
                ),
              ),
              Positioned.fill(
                key: const ValueKey('room-depth-cutouts'),
                child: ScrollDepth(
                  shift: _cutoutShift,
                  child: Stack(clipBehavior: Clip.none, children: _sceneProducts(zones, setup, k)),
                ),
              ),
              // a built setup: untouched corners fade back, furnished ones stay lit and ringed
              if (staging != null) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: RoomSpotlightPainter(
                          holes: staging.holes,
                          amount: () => _reveal.value * (1 - _dimAmount),
                          shade: colors.shadow.withValues(alpha: context.isDark ? 0.55 : 0.34),
                          ring: colors.primary.withValues(alpha: 0.85),
                          repaint: Listenable.merge([_reveal, _camera]),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ScrollDepth(
                      shift: _cutoutShift,
                      child: RoomPinnedLayer(staging: staging, k: k, flight: _fly, showChips: _selected == null),
                    ),
                  ),
                ),
              ],
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

  /// Featured cut-outs at each zone's anchor. Zones a setup furnished leave
  /// theirs out: the pinned pieces ([RoomPinnedLayer]) stand there instead.
  List<Widget> _sceneProducts(List<RoomZone> zones, RoomSetup? setup, double k) {
    final furnished = {for (final i in setup?.items ?? const <PlacedItem>[]) i.zoneId};
    final out = <Widget>[];
    for (final z in zones) {
      if (furnished.contains(z.id) || z.featured.isEmpty) continue;
      final p = z.featured.firstWhere((p) => p.thumbnail != null, orElse: () => z.featured.first);
      out.add(_SceneProduct(product: p, rect: z.spec.slot, k: k));
    }
    return out;
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
  const _SceneProduct({required this.product, required this.rect, required this.k});

  final ProductSummary product;
  final Rect rect;
  final double k;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = Rect.fromLTRB(rect.left * k, rect.top * k, rect.right * k, rect.bottom * k);
    final image = FittedBox(
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
                color: colors.shadow.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned.fill(child: image),
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
    final colors = context.colors;
    final hint = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: AiSparkleIcon(size: 18)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Let Zel furnish this room for your budget', style: t.labelLarge),
              const SizedBox(height: 2),
              Text(
                'AI picks the best set that fits and places it here.',
                style: t.bodySmall!.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ],
    );
    final button = AppButton(
      label: 'Build my setup',
      icon: Icons.chair_outlined,
      size: AppButtonSize.small,
      semanticLabel: 'Build my setup: let Zel furnish this room for your budget',
      onPressed: onBuild,
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3 || MediaQuery.sizeOf(context).width < 380) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hint,
          const SizedBox(height: AppSpacing.xs),
          Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: button)),
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
