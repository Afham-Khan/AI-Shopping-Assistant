import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../../core/models/product.dart';
import '../../data/room_repository.dart';

/// Where a zone lives in the illustrated room. All geometry is in the scene's
/// design space ([RoomLayout.size], 1000 × 880); the stage scales it to fit.
@immutable
class RoomZoneSpec {
  const RoomZoneSpec({
    required this.id,
    required this.number,
    required this.hit,
    required this.hotspot,
    required this.slot,
  });

  final String id;

  /// 1-based number shown on the hotspot.
  final int number;

  /// Tap target and camera focus.
  final Rect hit;

  /// Centre of the pulsing numbered dot.
  final Offset hotspot;

  /// Where product cut-outs stand (bottom edge = the surface they rest on).
  final Rect slot;
}

/// A zone ready for the UI: geometry + what the API says about it.
@immutable
class RoomZone {
  const RoomZone({required this.spec, required this.data});

  final RoomZoneSpec spec;
  final RoomZoneData data;

  String get id => spec.id;
  String get label => data.label;
  String get department => data.department;
  List<ProductSummary> get featured => data.featured;
}

abstract final class RoomLayout {
  static const size = Size(1000, 880);
  static const floorY = 600.0;

  /// Bundle items whose category matches no zone land on the rug.
  static const rugSlot = Rect.fromLTWH(430, 650, 180, 100);

  /// In hit-test priority order (small, specific zones first).
  static const zones = <RoomZoneSpec>[
    RoomZoneSpec(
      id: 'garage',
      number: 3,
      hit: Rect.fromLTWH(318, 48, 264, 240),
      hotspot: Offset(372, 104),
      slot: Rect.fromLTWH(452, 196, 112, 76),
    ),
    RoomZoneSpec(
      id: 'shelf',
      number: 5,
      hit: Rect.fromLTWH(630, 86, 360, 136),
      hotspot: Offset(690, 150),
      slot: Rect.fromLTWH(790, 104, 136, 96),
    ),
    RoomZoneSpec(
      id: 'vanity',
      number: 4,
      hit: Rect.fromLTWH(656, 288, 184, 362),
      hotspot: Offset(712, 330),
      slot: Rect.fromLTWH(688, 420, 124, 85),
    ),
    RoomZoneSpec(
      id: 'kitchen',
      number: 6,
      hit: Rect.fromLTWH(842, 340, 158, 340),
      hotspot: Offset(920, 540),
      slot: Rect.fromLTWH(856, 366, 136, 96),
    ),
    RoomZoneSpec(
      id: 'desk',
      number: 2,
      hit: Rect.fromLTWH(280, 300, 370, 360),
      hotspot: Offset(515, 374),
      slot: Rect.fromLTWH(294, 362, 128, 106),
    ),
    RoomZoneSpec(
      id: 'wardrobe',
      number: 1,
      hit: Rect.fromLTWH(30, 160, 232, 506),
      hotspot: Offset(145, 300),
      slot: Rect.fromLTWH(62, 452, 166, 108),
    ),
    RoomZoneSpec(
      id: 'corner',
      number: 7,
      hit: Rect.fromLTWH(20, 668, 280, 206),
      hotspot: Offset(222, 712),
      slot: Rect.fromLTWH(48, 680, 150, 112),
    ),
  ];

  static RoomZoneSpec? spec(String id) {
    for (final z in zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  /// The zone under [point] (design space), or null for empty floor/wall.
  static String? zoneAt(Offset point) {
    for (final z in zones) {
      if (z.hit.contains(point)) return z.id;
    }
    return null;
  }

  /// Merges API zones into the fixed geometry, in hotspot-number order.
  /// Missing zones get their default label/department and no products.
  static List<RoomZone> merge(List<RoomZoneData> data) {
    final byId = {for (final d in data) d.id: d};
    final out = <RoomZone>[];
    for (final spec in [...zones]..sort((a, b) => a.number.compareTo(b.number))) {
      final fallback = roomZoneDefaults[spec.id]!;
      final d = byId[spec.id];
      out.add(
        RoomZone(
          spec: spec,
          data: RoomZoneData(
            id: spec.id,
            label: (d?.label.isNotEmpty ?? false) ? d!.label : fallback.$1,
            department: (d?.department.isNotEmpty ?? false) ? d!.department : fallback.$2,
            categories: d?.categories ?? const [],
            featured: d?.featured ?? const [],
            tagline: d?.tagline,
          ),
        ),
      );
    }
    return out;
  }

  /// Camera viewport (design space) that frames [focus]: padded, stretched to
  /// the scene's aspect ratio, zoom capped at [maxZoom] and kept inside the scene.
  static Rect viewportFor(Rect focus, {Size scene = size, double pad = 1.18, double maxZoom = 2.6}) {
    final aspect = scene.width / scene.height;
    var w = focus.width * pad;
    var h = focus.height * pad;
    if (w / h < aspect) {
      w = h * aspect;
    } else {
      h = w / aspect;
    }
    final minW = scene.width / maxZoom;
    if (w < minW) {
      w = minW;
      h = w / aspect;
    }
    if (w > scene.width) {
      w = scene.width;
      h = scene.height;
    }
    final left = (focus.center.dx - w / 2).clamp(0.0, scene.width - w);
    final top = (focus.center.dy - h / 2).clamp(0.0, scene.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Rect for item [index] of [count] products sharing one [slot]
  /// (side by side, bottom-aligned, at most three).
  static Rect placedRect(Rect slot, int index, int count) {
    final n = count.clamp(1, 3);
    final i = index.clamp(0, n - 1);
    if (n == 1) return slot;
    final w = slot.width / n * 1.08;
    final step = (slot.width - w) / (n - 1);
    final h = slot.height * (n == 2 ? 0.86 : 0.74);
    return Rect.fromLTWH(slot.left + step * i, slot.bottom - h, w, h);
  }

  /// Horizontal centre for pinned setup pieces where it differs from the
  /// slot's (the desk's slot sits left of the monitor; pinned pieces stand
  /// across the desk top).
  static const _pinCentreX = {'desk': 452.0};

  /// Where a setup's pieces land in [zoneId] (null = the rug): larger than
  /// the featured cut-outs so the change reads on a small phone. Up to three
  /// side by side on the zone's surface, kept inside the scene.
  static List<Rect> pinRects(String? zoneId, int count) {
    final slot = zoneId == null ? rugSlot : (spec(zoneId)?.slot ?? rugSlot);
    final n = count.clamp(1, 3);
    final s = switch (n) {
      1 => 1.35,
      2 => 1.18,
      _ => 1.0,
    };
    final w = slot.width * s;
    final h = slot.height * s;
    final gap = w * 0.86; // neighbours overlap a little, like objects on a shelf
    final span = gap * (n - 1) + w;
    final cx = _pinCentreX[zoneId] ?? slot.center.dx;
    final left = (cx - span / 2).clamp(8.0, size.width - 8 - span);
    final top = math.max(8.0, slot.bottom - h);
    return [for (var i = 0; i < n; i++) Rect.fromLTWH(left + gap * i, top, w, slot.bottom - top)];
  }

  static final _floorPiece = RegExp(r'\b(chair|sofa|couch|table|stool|bean ?bag|ottoman)\b');
  static final _shelfPiece = RegExp(r'\b(speakers?|homepod|soundbar|decor|plant|vase)\b');
  static final _deskPiece = RegExp(
    r'\b(lamp|headphones?|earphones?|earbuds?|headset|keyboard|mouse|monitor|webcam)\b',
  );

  /// Which zone a bundle piece belongs to: the role and title first (a
  /// speaker goes on the shelf, a chair or table on the floor, headphones and
  /// lamps on the desk), then the category ([zoneForProduct]). Null = the rug.
  static String? zoneForItem(ProductSummary p, String role, List<RoomZone> zones) {
    final text = '$role ${p.title}'.toLowerCase();
    bool has(String id) => zones.any((z) => z.id == id);
    if (_floorPiece.hasMatch(text)) return null;
    if (_shelfPiece.hasMatch(text) && has('shelf')) return 'shelf';
    if (_deskPiece.hasMatch(text) && has('desk')) return 'desk';
    return zoneForProduct(p, zones);
  }

  /// Which zone a product belongs to (category slug match), or null.
  static String? zoneForProduct(ProductSummary p, List<RoomZone> zones) {
    final slugs = {?p.category?.slug, ...p.tags};
    for (final z in zones) {
      if (z.data.categories.any(slugs.contains)) return z.id;
    }
    return null;
  }

  /// Display name for a department slug (`home-living` → `Home & Living`).
  static String departmentName(String slug) {
    const names = {
      'beauty-personal-care': 'Beauty & Personal Care',
      'home-living': 'Home & Living',
      'sports-outdoors': 'Sports & Outdoors',
    };
    final known = names[slug];
    if (known != null) return known;
    return slug
        .split('-')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// 0 by day, 1 at night, easing through dusk (17–19 h) and dawn (5–7 h).
  static double nightFactor(DateTime t) {
    final h = t.hour + t.minute / 60;
    double ease(double x) => 0.5 - math.cos(x.clamp(0.0, 1.0) * math.pi) / 2;
    if (h >= 7 && h < 17) return 0;
    if (h >= 17 && h < 19) return ease((h - 17) / 2);
    if (h >= 5 && h < 7) return 1 - ease((h - 5) / 2);
    return 1;
  }
}
