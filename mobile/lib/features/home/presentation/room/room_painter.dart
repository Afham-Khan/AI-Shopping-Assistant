import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import 'room_layout.dart';

/// Colours for the room, derived from theme tokens only, so the re-theme and
/// dark mode flow through. Furniture is white like the app's cards; the wall
/// is a lavender wash; department hues appear only as small accents.
@immutable
class RoomPalette {
  const RoomPalette({
    required this.wallTop,
    required this.wallBottom,
    required this.floorFar,
    required this.floorNear,
    required this.floorLine,
    required this.furniture,
    required this.furnitureShade,
    required this.edge,
    required this.wood,
    required this.woodDark,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.accentSoft,
    required this.skyDay,
    required this.skyNight,
    required this.warm,
    required this.leaf,
    required this.shadow,
    required this.nightTint,
    required this.fashion,
    required this.beauty,
    required this.home,
    required this.groceries,
    required this.sports,
    required this.automotive,
  });

  factory RoomPalette.of(AppPalette c, {required bool dark}) {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    final opaqueShadow = c.shadow.withValues(alpha: 1);
    return RoomPalette(
      wallTop: mix(c.backgroundTop, c.primarySoft, 0.55),
      wallBottom: mix(c.background, c.primarySoft, 0.25),
      floorFar: mix(c.surfaceRaised, c.border, 0.4),
      floorNear: mix(c.surfaceRaised, c.borderStrong, 0.45),
      floorLine: c.borderStrong.withValues(alpha: dark ? 0.55 : 0.5),
      furniture: c.surface,
      furnitureShade: c.surfaceVariant,
      edge: c.borderStrong,
      wood: mix(c.surface, c.departmentAccent('home-living'), 0.26),
      woodDark: mix(c.surfaceRaised, c.departmentAccent('home-living'), 0.48),
      ink: c.text,
      inkSoft: c.muted,
      accent: c.primary,
      accentSoft: c.primarySoft,
      skyDay: mix(c.secondarySoft, c.surface, 0.15),
      skyNight: mix(opaqueShadow, c.primary, 0.22),
      warm: c.star,
      leaf: mix(c.departmentAccent('groceries'), c.surface, 0.18),
      shadow: c.shadow.withValues(alpha: dark ? 0.45 : 0.16),
      nightTint: opaqueShadow,
      fashion: c.departmentAccent('fashion'),
      beauty: c.departmentAccent('beauty-personal-care'),
      home: c.departmentAccent('home-living'),
      groceries: c.departmentAccent('groceries'),
      sports: c.departmentAccent('sports-outdoors'),
      automotive: c.departmentAccent('automotive'),
    );
  }

  final Color wallTop, wallBottom, floorFar, floorNear, floorLine;
  final Color furniture, furnitureShade, edge, wood, woodDark;
  final Color ink, inkSoft, accent, accentSoft;
  final Color skyDay, skyNight, warm, leaf, shadow, nightTint;
  final Color fashion, beauty, home, groceries, sports, automotive;

  /// Department hue softened toward the furniture colour.
  Color soft(Color hue, [double t = 0.55]) => Color.lerp(hue, furniture, t)!;

  @override
  bool operator ==(Object other) =>
      other is RoomPalette && other.wallTop == wallTop && other.furniture == furniture && other.accent == accent;

  @override
  int get hashCode => Object.hash(wallTop, furniture, accent);
}

/// The room, drawn in code as a calm flat illustration with soft depth.
/// Painted once (and once a minute for the clock / light) behind a
/// RepaintBoundary; the camera only transforms the cached layer.
class RoomPainter extends CustomPainter {
  RoomPainter({required this.palette, required this.night, required this.time});

  final RoomPalette palette;

  /// 0 day … 1 night.
  final double night;
  final DateTime time;

  RoomPalette get p => palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / RoomLayout.size.width, size.height / RoomLayout.size.height);
    _wall(canvas);
    _window(canvas);
    _clock(canvas);
    _shelf(canvas);
    _floor(canvas);
    _sunPatch(canvas);
    _rug(canvas);
    _wardrobe(canvas);
    _desk(canvas);
    _vanity(canvas);
    _kitchen(canvas);
    _corner(canvas);
    _nightOverlay(canvas);
    _lamplight(canvas);
    canvas.restore();
  }

  // ---------- helpers ----------

  Paint _fill(Color c) => Paint()..color = c;

  void _rr(Canvas canvas, Rect r, double radius, Color color) =>
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), _fill(color));

  void _stroke(Canvas canvas, RRect r, Color color, [double width = 2]) => canvas.drawRRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color,
  );

  /// Soft contact shadow on the floor under a piece of furniture.
  void _floorShadow(Canvas canvas, Rect r) => canvas.drawOval(
    r,
    Paint()
      ..color = p.shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
  );

  /// Furniture body: white face, a shaded side strip and a hairline edge.
  void _body(Canvas canvas, Rect r, {double radius = 12, double side = 10}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    canvas.drawRRect(rr.shift(const Offset(0, 6)), _fill(p.shadow.withValues(alpha: p.shadow.a * 0.6)));
    canvas.drawRRect(rr, _fill(p.furniture));
    if (side > 0) {
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(Rect.fromLTWH(r.right - side, r.top, side, r.height), _fill(p.furnitureShade));
      canvas.restore();
    }
    _stroke(canvas, rr, p.edge.withValues(alpha: 0.6), 1.6);
  }

  // ---------- scene ----------

  void _wall(Canvas canvas) {
    const wall = Rect.fromLTWH(0, 0, 1000, RoomLayout.floorY);
    canvas.drawRect(
      wall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.wallTop, p.wallBottom],
        ).createShader(wall),
    );
    // a quiet picture rail
    canvas.drawRect(const Rect.fromLTWH(0, 40, 1000, 3), _fill(p.furniture.withValues(alpha: 0.7)));
  }

  void _window(Canvas canvas) {
    const frame = Rect.fromLTWH(330, 58, 240, 212);
    _body(canvas, frame, radius: 14, side: 0);
    final glass = frame.deflate(12);
    final glassRR = RRect.fromRectAndRadius(glass, const Radius.circular(8));
    final sky = Color.lerp(p.skyDay, p.skyNight, night)!;
    canvas.save();
    canvas.clipRRect(glassRR);
    canvas.drawRect(
      glass,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sky, Color.lerp(sky, p.furniture, 0.35 * (1 - night) + 0.08)!],
        ).createShader(glass),
    );
    // sun by day, moon and a few stars by night
    final orb = Offset(glass.left + 46, glass.top + 42);
    if (night < 0.5) {
      canvas.drawCircle(orb, 18, _fill(p.warm.withValues(alpha: 0.85 * (1 - night * 2))));
    } else {
      canvas.drawCircle(orb, 15, _fill(p.furniture.withValues(alpha: (night - 0.5) * 2)));
      canvas.drawCircle(orb + const Offset(6, -4), 13, _fill(sky));
      final star = _fill(p.furniture.withValues(alpha: 0.8 * night));
      for (final s in const [Offset(120, 30), Offset(170, 62), Offset(96, 86), Offset(190, 24)]) {
        canvas.drawCircle(glass.topLeft + s, 1.8, star);
      }
    }
    // the driveway and the car outside (automotive)
    final ground = Rect.fromLTWH(glass.left, glass.bottom - 34, glass.width, 34);
    canvas.drawRect(ground, _fill(Color.lerp(p.leaf, p.nightTint, night * 0.5)!.withValues(alpha: 0.55)));
    final car = Color.lerp(p.soft(p.automotive, 0.25), p.nightTint, night * 0.35)!;
    final carBase = Offset(glass.left + 64, glass.bottom - 26);
    _rr(canvas, Rect.fromLTWH(carBase.dx, carBase.dy - 22, 120, 24), 10, car);
    final cabin = Path()
      ..moveTo(carBase.dx + 26, carBase.dy - 22)
      ..lineTo(carBase.dx + 40, carBase.dy - 40)
      ..lineTo(carBase.dx + 82, carBase.dy - 40)
      ..lineTo(carBase.dx + 98, carBase.dy - 22)
      ..close();
    canvas.drawPath(cabin, _fill(car));
    final glassTone = Color.lerp(sky, p.furniture, 0.4)!;
    canvas.drawPath(
      Path()
        ..moveTo(carBase.dx + 34, carBase.dy - 23)
        ..lineTo(carBase.dx + 44, carBase.dy - 36)
        ..lineTo(carBase.dx + 60, carBase.dy - 36)
        ..lineTo(carBase.dx + 60, carBase.dy - 23)
        ..close(),
      _fill(glassTone),
    );
    canvas.drawPath(
      Path()
        ..moveTo(carBase.dx + 64, carBase.dy - 23)
        ..lineTo(carBase.dx + 64, carBase.dy - 36)
        ..lineTo(carBase.dx + 80, carBase.dy - 36)
        ..lineTo(carBase.dx + 90, carBase.dy - 23)
        ..close(),
      _fill(glassTone),
    );
    for (final x in const [24.0, 96.0]) {
      canvas.drawCircle(carBase + Offset(x, 2), 10, _fill(p.ink.withValues(alpha: 0.85)));
      canvas.drawCircle(carBase + Offset(x, 2), 4, _fill(p.furnitureShade));
    }
    canvas.restore();
    // mullions + sill
    final mullion = _fill(p.furniture);
    canvas.drawRect(Rect.fromLTWH(glass.center.dx - 3, glass.top, 6, glass.height), mullion);
    canvas.drawRect(Rect.fromLTWH(glass.left, glass.top + 92, glass.width, 6), mullion);
    _body(canvas, const Rect.fromLTWH(316, 266, 268, 14), radius: 5, side: 0);
  }

  void _clock(Canvas canvas) {
    const c = Offset(145, 100);
    canvas.drawCircle(c + const Offset(0, 4), 40, _fill(p.shadow.withValues(alpha: p.shadow.a * 0.6)));
    canvas.drawCircle(c, 40, _fill(p.furniture));
    canvas.drawCircle(
      c,
      40,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = p.ink.withValues(alpha: 0.85),
    );
    final tick = Paint()
      ..color = p.inkSoft
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(c + dir * 30, c + dir * (i % 3 == 0 ? 24 : 27), tick);
    }
    final minutes = time.minute + time.second / 60;
    final hours = (time.hour % 12) + minutes / 60;
    void hand(double turns, double length, Color color, double width) {
      final a = turns * 2 * math.pi;
      canvas.drawLine(
        c,
        c + Offset(math.sin(a), -math.cos(a)) * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    hand(hours / 12, 17, p.ink, 5);
    hand(minutes / 60, 26, p.accent, 3.5);
    canvas.drawCircle(c, 4, _fill(p.ink));
  }

  void _shelf(Canvas canvas) {
    // brackets + board
    for (final x in const [668.0, 950.0]) {
      _rr(canvas, Rect.fromLTWH(x, 210, 10, 22), 3, p.woodDark);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(640, 206, 340, 12), const Radius.circular(4)).shift(const Offset(0, 5)),
      _fill(p.shadow.withValues(alpha: p.shadow.a * 0.7)),
    );
    _rr(canvas, const Rect.fromLTWH(640, 200, 340, 12), 4, p.wood);
    // books
    final books = [
      (660.0, 58.0, p.soft(p.home, 0.25)),
      (678.0, 66.0, p.accent.withValues(alpha: 0.75)),
      (696.0, 52.0, p.inkSoft.withValues(alpha: 0.7)),
    ];
    for (final (x, h, color) in books) {
      _rr(canvas, Rect.fromLTWH(x, 200 - h, 16, h), 3, color);
    }
    canvas.save();
    canvas.translate(724, 200);
    canvas.rotate(-0.22);
    _rr(canvas, const Rect.fromLTWH(-2, -54, 15, 54), 3, p.soft(p.beauty, 0.35));
    canvas.restore();
    // a small plant
    _rr(canvas, const Rect.fromLTWH(746, 168, 30, 32), 8, p.furniture);
    _stroke(canvas, RRect.fromRectAndRadius(const Rect.fromLTWH(746, 168, 30, 32), const Radius.circular(8)), p.edge, 1.4);
    final leaf = _fill(p.leaf);
    for (final (dx, dy, rot) in const [(-12.0, -14.0, -0.6), (0.0, -20.0, 0.0), (12.0, -14.0, 0.6)]) {
      canvas.save();
      canvas.translate(761 + dx, 170 + dy);
      canvas.rotate(rot);
      canvas.drawOval(const Rect.fromLTWH(-6, -14, 12, 28), leaf);
      canvas.restore();
    }
    // a vase at the far end
    canvas.drawOval(const Rect.fromLTWH(940, 158, 28, 42), _fill(p.soft(p.home, 0.4)));
    _rr(canvas, const Rect.fromLTWH(948, 150, 12, 14), 3, p.soft(p.home, 0.4));
  }

  void _floor(Canvas canvas) {
    const floor = Rect.fromLTWH(0, RoomLayout.floorY, 1000, 280);
    canvas.drawRect(
      floor,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.floorFar, p.floorNear],
        ).createShader(floor),
    );
    // boards converge toward a vanishing point behind the desk
    final line = Paint()
      ..color = p.floorLine
      ..strokeWidth = 1.4;
    const vp = Offset(500, 300);
    for (var i = -6; i <= 6; i++) {
      final top = Offset(500 + i * 92.0, RoomLayout.floorY);
      final t = (880 - vp.dy) / (top.dy - vp.dy);
      canvas.drawLine(top, Offset(vp.dx + (top.dx - vp.dx) * t, 880), line);
    }
    for (var i = 1; i <= 5; i++) {
      final y = RoomLayout.floorY + 280 * math.pow(i / 5.6, 1.5);
      canvas.drawLine(Offset(0, y), Offset(1000, y), line..color = p.floorLine.withValues(alpha: p.floorLine.a * 0.6));
    }
    // skirting board
    canvas.drawRect(const Rect.fromLTWH(0, RoomLayout.floorY - 12, 1000, 12), _fill(p.furniture));
    canvas.drawRect(const Rect.fromLTWH(0, RoomLayout.floorY - 1, 1000, 1.5), _fill(p.edge.withValues(alpha: 0.6)));
  }

  /// Daylight from the window falling on the floor.
  void _sunPatch(Canvas canvas) {
    final strength = (1 - night) * 0.32;
    if (strength <= 0.01) return;
    final path = Path()
      ..moveTo(352, RoomLayout.floorY + 2)
      ..lineTo(548, RoomLayout.floorY + 2)
      ..lineTo(700, 820)
      ..lineTo(392, 820)
      ..close();
    canvas.drawPath(path, _fill(p.furniture.withValues(alpha: strength)));
  }

  void _rug(Canvas canvas) {
    const rug = Rect.fromLTWH(300, 668, 440, 128);
    canvas.drawOval(rug.shift(const Offset(0, 4)), _fill(p.shadow.withValues(alpha: p.shadow.a * 0.5)));
    canvas.drawOval(rug, _fill(p.accentSoft));
    canvas.drawOval(
      rug.deflate(16),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = p.accent.withValues(alpha: 0.22),
    );
  }

  void _wardrobe(Canvas canvas) {
    _floorShadow(canvas, const Rect.fromLTWH(40, 646, 220, 26));
    const body = Rect.fromLTWH(40, 168, 210, 486);
    _body(canvas, body, radius: 14);
    // cornice
    _rr(canvas, const Rect.fromLTWH(32, 160, 226, 16), 6, p.furniture);
    _stroke(canvas, RRect.fromRectAndRadius(const Rect.fromLTWH(32, 160, 226, 16), const Radius.circular(6)), p.edge.withValues(alpha: 0.6), 1.4);
    // open interior
    const inner = Rect.fromLTWH(58, 190, 172, 262);
    _rr(canvas, inner, 8, p.furnitureShade);
    canvas.drawRect(const Rect.fromLTWH(64, 212, 160, 4), _fill(p.inkSoft.withValues(alpha: 0.7)));
    final garments = [
      (78.0, p.soft(p.fashion, 0.45), 150.0),
      (122.0, p.soft(p.accent, 0.5), 176.0),
      (166.0, p.soft(p.fashion, 0.7), 138.0),
    ];
    final hook = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = p.inkSoft;
    for (final (x, color, length) in garments) {
      canvas.drawArc(Rect.fromLTWH(x + 14, 206, 12, 12), math.pi, math.pi, false, hook);
      final g = Path()
        ..moveTo(x, 236)
        ..lineTo(x + 20, 224)
        ..lineTo(x + 40, 236)
        ..lineTo(x + 36, 224 + length)
        ..lineTo(x + 4, 224 + length)
        ..close();
      canvas.drawPath(g, _fill(color));
    }
    // shelf the products stand on + two drawers
    _rr(canvas, const Rect.fromLTWH(58, 556, 172, 8), 3, p.edge.withValues(alpha: 0.5));
    for (final y in const [572.0, 612.0]) {
      final drawer = Rect.fromLTWH(58, y, 172, 34);
      _rr(canvas, drawer, 6, p.furniture);
      _stroke(canvas, RRect.fromRectAndRadius(drawer, const Radius.circular(6)), p.edge.withValues(alpha: 0.6), 1.4);
      _rr(canvas, Rect.fromLTWH(128, y + 14, 32, 6), 3, p.inkSoft.withValues(alpha: 0.6));
    }
  }

  void _desk(Canvas canvas) {
    _floorShadow(canvas, const Rect.fromLTWH(290, 646, 370, 24));
    final leg = p.woodDark;
    _rr(canvas, const Rect.fromLTWH(304, 480, 12, 180), 4, leg);
    _rr(canvas, const Rect.fromLTWH(622, 480, 12, 180), 4, leg);
    _rr(canvas, const Rect.fromLTWH(310, 590, 318, 8), 4, leg.withValues(alpha: 0.7));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(284, 468, 372, 16), const Radius.circular(6)).shift(const Offset(0, 5)),
      _fill(p.shadow.withValues(alpha: p.shadow.a * 0.7)),
    );
    _rr(canvas, const Rect.fromLTWH(284, 468, 372, 16), 6, p.wood);
    // monitor
    const screen = Rect.fromLTWH(432, 318, 166, 112);
    _rr(canvas, const Rect.fromLTWH(506, 428, 18, 30), 4, p.edge);
    canvas.drawOval(const Rect.fromLTWH(478, 456, 74, 13), _fill(p.edge));
    _rr(canvas, screen, 10, p.ink);
    final inner = screen.deflate(7);
    final glow = Color.lerp(p.accentSoft, p.accent, 0.25 + 0.25 * night)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(5)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [glow, Color.lerp(glow, p.furniture, 0.55)!],
        ).createShader(inner),
    );
    // a few interface lines on the screen
    final ui = _fill(p.furniture.withValues(alpha: 0.75));
    _rr(canvas, Rect.fromLTWH(inner.left + 12, inner.top + 14, 60, 8), 4, ui.color);
    _rr(canvas, Rect.fromLTWH(inner.left + 12, inner.top + 30, 96, 6), 3, ui.color.withValues(alpha: 0.5));
    _rr(canvas, Rect.fromLTWH(inner.left + 12, inner.top + 62, 40, 24), 6, ui.color);
    _rr(canvas, Rect.fromLTWH(inner.left + 58, inner.top + 62, 40, 24), 6, ui.color.withValues(alpha: 0.6));
    // keyboard
    _rr(canvas, const Rect.fromLTWH(452, 460, 120, 8), 3, p.furnitureShade);
    // desk lamp (warm at night)
    final lampInk = p.ink.withValues(alpha: 0.85);
    _rr(canvas, const Rect.fromLTWH(596, 458, 44, 10), 5, lampInk);
    final arm = Paint()
      ..color = lampInk
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(618, 460), const Offset(632, 404), arm);
    canvas.drawLine(const Offset(632, 404), const Offset(604, 372), arm);
    final shade = Path()
      ..moveTo(590, 360)
      ..lineTo(616, 366)
      ..lineTo(606, 394)
      ..lineTo(574, 386)
      ..close();
    canvas.drawPath(shade, _fill(p.accent));
    // chair in front of the desk
    final chair = Color.lerp(p.accent, p.furniture, 0.62)!;
    _rr(canvas, const Rect.fromLTWH(446, 500, 118, 66), 18, chair);
    _rr(canvas, const Rect.fromLTWH(430, 562, 150, 16), 8, Color.lerp(chair, p.ink, 0.25)!);
    _rr(canvas, const Rect.fromLTWH(500, 578, 10, 56), 3, p.inkSoft);
    _rr(canvas, const Rect.fromLTWH(456, 632, 98, 8), 4, p.inkSoft);
    for (final x in const [460.0, 550.0]) {
      canvas.drawCircle(Offset(x, 644), 6, _fill(p.ink.withValues(alpha: 0.8)));
    }
  }

  void _vanity(Canvas canvas) {
    _floorShadow(canvas, const Rect.fromLTWH(664, 646, 176, 22));
    // round mirror
    const c = Offset(750, 360);
    canvas.drawCircle(c + const Offset(0, 5), 64, _fill(p.shadow.withValues(alpha: p.shadow.a * 0.6)));
    canvas.drawCircle(c, 64, _fill(p.wood));
    final glass = Rect.fromCircle(center: c, radius: 54);
    canvas.drawCircle(
      c,
      54,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(p.skyDay, p.skyNight, night * 0.6)!, p.furniture],
        ).createShader(glass),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(glass));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 40, c.dy + 10)
        ..lineTo(c.dx + 6, c.dy - 60)
        ..lineTo(c.dx + 26, c.dy - 60)
        ..lineTo(c.dx - 20, c.dy + 10)
        ..close(),
      _fill(p.furniture.withValues(alpha: 0.55)),
    );
    canvas.restore();
    // table
    for (final x in const [676.0, 812.0]) {
      _rr(canvas, Rect.fromLTWH(x, 516, 10, 140), 4, p.woodDark);
    }
    _body(canvas, const Rect.fromLTWH(664, 504, 172, 56), radius: 8, side: 8);
    _rr(canvas, const Rect.fromLTWH(734, 528, 32, 6), 3, p.inkSoft.withValues(alpha: 0.6));
    // ottoman
    final pouf = Rect.fromLTWH(712, 600, 76, 40);
    _floorShadow(canvas, Rect.fromLTWH(pouf.left, pouf.bottom - 8, pouf.width, 16));
    _rr(canvas, pouf, 18, p.soft(p.beauty, 0.5));
    _rr(canvas, Rect.fromLTWH(pouf.left, pouf.top, pouf.width, 14), 10, p.soft(p.beauty, 0.35));
  }

  void _kitchen(Canvas canvas) {
    _floorShadow(canvas, const Rect.fromLTWH(846, 648, 154, 22));
    const base = Rect.fromLTWH(850, 470, 150, 190);
    _body(canvas, base, radius: 8, side: 0);
    for (final x in const [858.0, 928.0]) {
      final door = Rect.fromLTWH(x, 486, 64, 160);
      _stroke(canvas, RRect.fromRectAndRadius(door, const Radius.circular(6)), p.edge.withValues(alpha: 0.6), 1.4);
    }
    _rr(canvas, const Rect.fromLTWH(908, 520, 6, 30), 3, p.inkSoft.withValues(alpha: 0.6));
    _rr(canvas, const Rect.fromLTWH(936, 520, 6, 30), 3, p.inkSoft.withValues(alpha: 0.6));
    // countertop
    _rr(canvas, const Rect.fromLTWH(842, 460, 158, 14), 4, Color.lerp(p.inkSoft, p.furniture, 0.45)!);
    // a produce crate on the floor beside it
    const crate = Rect.fromLTWH(888, 690, 96, 52);
    _floorShadow(canvas, Rect.fromLTWH(crate.left, crate.bottom - 8, crate.width, 16));
    final fruit = [
      (Offset(906, 688), p.soft(p.groceries, 0.15)),
      (Offset(930, 682), p.soft(p.sports, 0.2)),
      (Offset(956, 688), p.soft(p.groceries, 0.35)),
      (Offset(972, 684), p.warm),
    ];
    for (final (o, color) in fruit) {
      canvas.drawCircle(o, 13, _fill(color));
    }
    _rr(canvas, crate, 6, p.wood);
    final slat = _fill(p.woodDark.withValues(alpha: 0.6));
    canvas.drawRect(Rect.fromLTWH(crate.left, crate.top + 16, crate.width, 4), slat);
    canvas.drawRect(Rect.fromLTWH(crate.left, crate.top + 32, crate.width, 4), slat);
  }

  void _corner(Canvas canvas) {
    // a rolled yoga mat and a dumbbell (sports)
    final mat = p.soft(p.sports, 0.35);
    _floorShadow(canvas, const Rect.fromLTWH(40, 800, 210, 26));
    _rr(canvas, const Rect.fromLTWH(46, 786, 168, 34), 17, mat);
    canvas.drawCircle(const Offset(214, 803), 17, _fill(Color.lerp(mat, p.ink, 0.12)!));
    canvas.drawCircle(
      const Offset(214, 803),
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = p.furniture.withValues(alpha: 0.7),
    );
    _rr(canvas, const Rect.fromLTWH(232, 830, 56, 8), 4, p.inkSoft);
    for (final x in const [226.0, 282.0]) {
      _rr(canvas, Rect.fromLTWH(x, 818, 12, 32), 4, p.ink.withValues(alpha: 0.8));
    }
  }

  void _nightOverlay(Canvas canvas) {
    if (night <= 0.01) return;
    canvas.drawRect(Offset.zero & RoomLayout.size, _fill(p.nightTint.withValues(alpha: 0.2 * night)));
  }

  /// The desk lamp's pool of light, drawn after the night tint so it reads.
  void _lamplight(Canvas canvas) {
    if (night <= 0.01) return;
    final cone = Path()
      ..moveTo(578, 388)
      ..lineTo(606, 394)
      ..lineTo(650, 470)
      ..lineTo(500, 470)
      ..close();
    canvas.drawPath(cone, _fill(p.warm.withValues(alpha: 0.16 * night)));
    canvas.drawOval(
      const Rect.fromLTWH(480, 456, 190, 26),
      Paint()
        ..color = p.warm.withValues(alpha: 0.22 * night)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  @override
  bool shouldRepaint(RoomPainter old) =>
      old.palette != palette || (old.night - night).abs() > 0.001 || old.time.minute != time.minute || old.time.hour != time.hour;
}

/// Dims everything but the focused zone while the camera is in. Repaints
/// on its own (camera ticks) without touching the cached room layer.
class RoomFocusPainter extends CustomPainter {
  RoomFocusPainter({required this.focus, required this.amount, required this.color, required Listenable repaint})
    : super(repaint: repaint);

  final Rect? focus;

  /// 0 (no dim) … 1 (full dim), read every frame.
  final ValueGetter<double> amount;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = amount();
    if (focus == null || t <= 0.01) return;
    final k = size.width / RoomLayout.size.width;
    final hole = RRect.fromRectAndRadius(
      Rect.fromLTRB(focus!.left * k, focus!.top * k, focus!.right * k, focus!.bottom * k).inflate(4),
      const Radius.circular(14),
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: color.a * t));
  }

  @override
  bool shouldRepaint(RoomFocusPainter old) => old.focus != focus || old.color != color;
}
