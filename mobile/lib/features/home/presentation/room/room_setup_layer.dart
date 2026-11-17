import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../providers/room_providers.dart';
import 'room_layout.dart';

/// One piece of a built setup as the room shows it: where it rests (design
/// space), its number (shared by the cut-out badge and its label chip) and
/// its slot on the fly-in timeline (0…1 of the flight controller).
@immutable
class PinnedPiece {
  const PinnedPiece({
    required this.item,
    required this.rect,
    required this.number,
    required this.start,
    required this.end,
  });

  final PlacedItem item;
  final Rect rect;
  final int number;
  final double start;
  final double end;

  double progress(double t) => end <= start ? 1 : ((t - start) / (end - start)).clamp(0.0, 1.0);
}

/// The pinned pieces of [setup] and the flight timeline, computed once per
/// setup (never per frame).
@immutable
class SetupStaging {
  const SetupStaging({required this.pieces, required this.duration, required this.chipTail, required this.holes});

  factory SetupStaging.of(RoomSetup setup) {
    // group by zone; a zone holds three, the rest spill onto the rug, then are listed only
    final groups = <String?, List<PlacedItem>>{};
    for (final item in setup.items) {
      final zone = (groups[item.zoneId]?.length ?? 0) >= 3 ? null : item.zoneId;
      final list = groups[zone] ??= [];
      if (list.length < 3) list.add(item);
    }
    const step = 0.2; // seconds between pieces
    const travel = 0.75; // seconds per flight
    const tail = 0.3; // label chips pop in after landing
    final n = groups.values.fold<int>(0, (s, l) => s + l.length);
    final total = step * math.max(0, n - 1) + travel + tail;
    final pieces = <PinnedPiece>[];
    final holes = <Rect>[];
    var i = 0;
    for (final entry in groups.entries) {
      final rects = RoomLayout.pinRects(entry.key, entry.value.length);
      var area = entry.key == null ? const Rect.fromLTWH(300, 640, 440, 156) : RoomLayout.spec(entry.key!)!.hit;
      for (var j = 0; j < entry.value.length; j++) {
        pieces.add(
          PinnedPiece(
            item: entry.value[j],
            rect: rects[j],
            number: i + 1,
            start: i * step / total,
            end: (i * step + travel) / total,
          ),
        );
        area = area.expandToInclude(rects[j].inflate(10));
        i++;
      }
      holes.add(area.intersect(Offset.zero & RoomLayout.size));
    }
    return SetupStaging(
      pieces: pieces,
      duration: Duration(milliseconds: (total * 1000).round()),
      chipTail: tail / total,
      holes: holes,
    );
  }

  final List<PinnedPiece> pieces;
  final Duration duration;

  /// Share of the timeline a label chip takes to pop in after its piece lands.
  final double chipTail;

  /// Furnished areas (design space) the spotlight leaves bright.
  final List<Rect> holes;

  /// Money "landed" at flight time [t] (fills the budget bar as pieces arrive).
  double spentAt(double t, RoomSetup setup) {
    var sum = 0.0;
    final shown = <int>{};
    for (final p in pieces) {
      shown.add(p.item.product.id);
      sum += p.item.product.price * Curves.easeOut.transform(p.progress(t));
    }
    for (final i in setup.items) {
      if (!shown.contains(i.product.id)) sum += i.product.price * t;
    }
    return sum;
  }
}

/// The setup's pieces standing in the room as larger "pinned" cut-outs with
/// a highlight ring, a number badge and a label chip ("Gaming laptop ·
/// Rs 307,999").
///
/// Performance: every piece and chip is a [RepaintBoundary] child of one
/// [Flow]; [flight] only changes the transforms the delegate paints with, so
/// the fly-in never rebuilds widgets or re-decodes images.
class RoomPinnedLayer extends StatelessWidget {
  const RoomPinnedLayer({
    super.key,
    required this.staging,
    required this.k,
    required this.flight,
    required this.showChips,
  });

  final SetupStaging staging;

  /// Design space → logical pixels.
  final double k;
  final Animation<double> flight;
  final bool showChips;

  @override
  Widget build(BuildContext context) {
    final pieces = staging.pieces;
    return Flow(
      key: const ValueKey('room-pinned-layer'),
      clipBehavior: Clip.none,
      delegate: _PinnedFlowDelegate(
        rects: [for (final p in pieces) _scale(p.rect)],
        pieces: pieces,
        flight: flight,
        chipTail: staging.chipTail,
        chips: showChips,
      ),
      children: [
        for (final p in pieces) RepaintBoundary(child: _PinnedCutout(piece: p, size: _scale(p.rect).size)),
        if (showChips)
          for (final p in pieces) RepaintBoundary(child: _PinChip(piece: p)),
      ],
    );
  }

  Rect _scale(Rect r) => Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k);
}

class _PinnedFlowDelegate extends FlowDelegate {
  _PinnedFlowDelegate({
    required this.rects,
    required this.pieces,
    required this.flight,
    required this.chipTail,
    required this.chips,
  }) : super(repaint: flight);

  final List<Rect> rects;
  final List<PinnedPiece> pieces;
  final Animation<double> flight;
  final double chipTail;
  final bool chips;

  /// Chip positions only depend on sizes, so they are solved once.
  List<Rect>? _chipRects;
  Size? _chipsFor;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    if (i < rects.length) return BoxConstraints.tight(rects[i].size);
    return const BoxConstraints(maxWidth: 124);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final t = flight.value;
    final box = context.size;
    final n = rects.length;
    for (var i = 0; i < n; i++) {
      final p = pieces[i].progress(t);
      if (p <= 0) continue;
      final to = rects[i];
      if (p >= 1) {
        context.paintChild(i, transform: Matrix4.translationValues(to.left, to.top, 0));
        continue;
      }
      final e = Curves.easeOutCubic.transform(p);
      // an arc up from below the stage and down onto the surface
      final from = Offset(box.width * (0.35 + 0.3 * (i % 2)), box.height + to.height * 0.8);
      final control = Offset((from.dx + to.center.dx) / 2, math.min(from.dy, to.center.dy) - box.height * 0.35);
      final u = 1 - e;
      final pos = from * (u * u) + control * (2 * u * e) + to.center * (e * e);
      final scale = 1.7 - 0.7 * e;
      final rotation = (i.isEven ? -0.5 : 0.5) * u;
      context.paintChild(i, transform: _around(pos, to.size, scale, rotation));
    }
    if (!chips) return;
    if (_chipRects == null || _chipsFor != box) {
      _chipRects = _solveChips(context, box);
      _chipsFor = box;
    }
    for (var i = 0; i < n; i++) {
      final c = ((t - pieces[i].end) / chipTail).clamp(0.0, 1.0);
      if (c <= 0) continue;
      final r = _chipRects![i];
      final s = c >= 1 ? 1.0 : Curves.easeOutBack.transform(c);
      context.paintChild(n + i, transform: _around(r.center, r.size, s, 0));
    }
  }

  /// Below each piece if there is room, else above; nudged sideways or down
  /// so no two chips overlap.
  List<Rect> _solveChips(FlowPaintingContext context, Size box) {
    const gap = 3.0;
    final out = <Rect>[];
    final bounds = (Offset.zero & box).deflate(4);
    bool fits(Rect r) =>
        r.left >= bounds.left - 0.5 &&
        r.right <= bounds.right + 0.5 &&
        r.top >= bounds.top - 0.5 &&
        r.bottom <= bounds.bottom + 0.5 &&
        out.every((o) => !o.inflate(gap / 2).overlaps(r));
    Rect clampX(Rect r) => r.shift(Offset((bounds.left - r.left).clamp(0.0, double.infinity), 0)).shift(
      Offset(-(r.right - bounds.right).clamp(0.0, double.infinity), 0),
    );
    for (var i = 0; i < rects.length; i++) {
      final size = context.getChildSize(rects.length + i) ?? const Size(90, 30);
      final item = rects[i];
      final below = clampX(Rect.fromLTWH(item.center.dx - size.width / 2, item.bottom + gap, size.width, size.height));
      final above = clampX(Rect.fromLTWH(below.left, item.top - gap - size.height, size.width, size.height));
      final candidates = [
        below,
        above,
        clampX(below.shift(Offset(size.width * 0.6, 0))),
        clampX(below.shift(Offset(-size.width * 0.6, 0))),
        clampX(above.shift(Offset(size.width * 0.6, 0))),
        clampX(above.shift(Offset(-size.width * 0.6, 0))),
      ];
      var chosen = candidates.firstWhere(fits, orElse: () => Rect.zero);
      if (chosen == Rect.zero) {
        // push down past whatever is in the way, staying on the stage
        chosen = below;
        for (var guard = 0; guard < 8 && !fits(chosen); guard++) {
          final blocker = out.firstWhere((o) => o.inflate(gap / 2).overlaps(chosen), orElse: () => Rect.zero);
          final next = blocker == Rect.zero
              ? chosen.shift(Offset(0, bounds.bottom - chosen.bottom))
              : chosen.shift(Offset(0, blocker.bottom + gap - chosen.top));
          if (next.bottom > bounds.bottom) break;
          chosen = next;
        }
        if (chosen.bottom > bounds.bottom) chosen = chosen.shift(Offset(0, bounds.bottom - chosen.bottom));
      }
      out.add(chosen);
    }
    return out;
  }

  static Matrix4 _around(Offset centre, Size size, double scale, double rotation) {
    final cos = math.cos(rotation) * scale;
    final sin = math.sin(rotation) * scale;
    final hx = size.width / 2;
    final hy = size.height / 2;
    return Matrix4(
      cos, sin, 0, 0, //
      -sin, cos, 0, 0, //
      0, 0, 1, 0, //
      centre.dx - (cos * hx - sin * hy), centre.dy - (sin * hx + cos * hy), 0, 1,
    );
  }

  @override
  bool shouldRepaint(_PinnedFlowDelegate old) =>
      old.flight != flight || old.chips != chips || old.pieces != pieces || !_sameRects(old.rects, rects);

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A pinned cut-out: a soft highlight ring behind it, the product (decoded
/// at a capped size), and its number.
class _PinnedCutout extends StatelessWidget {
  const _PinnedCutout({required this.piece, required this.size});

  final PinnedPiece piece;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ring = math.min(size.width, size.height) * 0.98;
    // decode a little above resting size so a camera zoom stays acceptable, capped for old phones
    final decode = math.min(size.width * 1.8, 220.0);
    final badge = math.max(15.0, size.width * 0.16).clamp(15.0, 22.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: (size.width - ring) / 2,
          top: size.height - ring,
          width: ring,
          height: ring,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.10),
              border: Border.all(color: colors.primary.withValues(alpha: 0.65), width: 1.6),
            ),
          ),
        ),
        // contact shadow
        Positioned(
          left: size.width * 0.16,
          right: size.width * 0.16,
          bottom: -2,
          height: math.max(3, size.height * 0.06),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.elliptical(100, 20)),
              color: colors.shadow.withValues(alpha: 0.16),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(size.width * 0.06),
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              child: AppNetworkImage(
                piece.item.product.thumbnail,
                width: decode,
                height: decode * size.height / size.width,
                fit: BoxFit.contain,
                backgroundColor: Colors.transparent,
                semanticLabel: piece.item.product.title,
              ),
            ),
          ),
        ),
        Positioned(
          right: -2,
          top: size.height - ring - 2,
          child: _NumberBadge(number: piece.number, size: badge),
        ),
      ],
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number, required this.size});

  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 1.5),
      ),
      child: Text(
        '$number',
        textScaler: TextScaler.noScaling,
        style: TextStyle(color: colors.onPrimary, fontSize: size * 0.55, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}

/// "② Gaming laptop / Rs 307,999" under (or over) a pinned piece.
class _PinChip extends StatelessWidget {
  const _PinChip({required this.piece});

  final PinnedPiece piece;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final role = piece.item.role.isEmpty ? piece.item.product.title : piece.item.role;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25);
    return Semantics(
      label: '$role, ${Formatters.price(piece.item.product.price)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 7, 3),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.inputAll,
          border: Border.all(color: colors.primary.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NumberBadge(number: piece.number, size: 15),
            const SizedBox(width: 4),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: scaler,
                    style: t.labelSmall!.copyWith(fontWeight: FontWeight.w700, height: 1.15, color: colors.text),
                  ),
                  Text(
                    Formatters.price(piece.item.product.price),
                    maxLines: 1,
                    textScaler: scaler,
                    style: t.labelSmall!.copyWith(
                      color: colors.primary,
                      height: 1.15,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
