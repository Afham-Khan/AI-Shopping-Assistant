import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/models/product.dart';
import '../../../core/network/api_client.dart';
import '../../catalog/data/models/catalog_models.dart';

/// One zone of the Home room as the API describes it
/// (`GET /catalog/room` → `[{ id, label, department, categories, featured }]`).
@immutable
class RoomZoneData {
  const RoomZoneData({
    required this.id,
    required this.label,
    required this.department,
    this.categories = const [],
    this.featured = const [],
    this.tagline,
  });

  factory RoomZoneData.fromJson(Map<String, dynamic> json) {
    final dept = json['department'];
    return RoomZoneData(
      id: JsonX.asString(json['id']),
      label: JsonX.asString(json['label']),
      // the department may arrive as a slug or as `{ id, name, slug }`
      department: dept is Map ? JsonX.asString(dept['slug']) : JsonX.asString(dept),
      categories: [
        for (final c in (json['categories'] is List ? json['categories'] as List : const []))
          if (c is Map) JsonX.asString(c['slug']) else JsonX.asString(c),
      ].where((s) => s.isNotEmpty).toList(),
      featured: JsonX.asList(json['featured'] ?? json['products'], ProductSummary.fromJson),
      tagline: JsonX.asStringOrNull(json['tagline']),
    );
  }

  final String id;
  final String label;

  /// Department slug (`electronics`, `fashion`…).
  final String department;

  /// Category slugs that belong to this zone (used to place bundle items).
  final List<String> categories;
  final List<ProductSummary> featured;

  /// Short line under the zone name in the tray ("Everything for your setup").
  final String? tagline;

  RoomZoneData copyWith({String? label, String? department, List<String>? categories, List<ProductSummary>? featured}) =>
      RoomZoneData(
        id: id,
        label: label ?? this.label,
        department: department ?? this.department,
        categories: categories ?? this.categories,
        featured: featured ?? this.featured,
        tagline: tagline,
      );
}

/// Zone id → default label and department, used before `/catalog/room`
/// lands on the server (and to fill gaps in its answer).
const roomZoneDefaults = <String, (String label, String department)>{
  'desk': ('The desk', 'electronics'),
  'wardrobe': ('The wardrobe', 'fashion'),
  'vanity': ('The vanity', 'beauty-personal-care'),
  'kitchen': ('The kitchen', 'groceries'),
  'shelf': ('The shelf', 'home-living'),
  'corner': ('The gym corner', 'sports-outdoors'),
  'garage': ('The driveway', 'automotive'),
};

class RoomRepository {
  RoomRepository(this._api);

  final ApiClient _api;

  /// The room's zones with featured products. Falls back to
  /// `/catalog/departments` + `/products?department=` while the dedicated
  /// endpoint is missing (404).
  Future<List<RoomZoneData>> room() async {
    List<RoomZoneData> zones = const [];
    try {
      zones = await _api.get(
        '/catalog/room',
        decode: (d) => JsonX.asList(d is Map ? d['zones'] : d, RoomZoneData.fromJson),
      );
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    if (zones.isEmpty) return _fallback();
    return _complete(zones);
  }

  /// Adds categories from the department tree when the API sent none.
  Future<List<RoomZoneData>> _complete(List<RoomZoneData> zones) async {
    if (zones.every((z) => z.categories.isNotEmpty)) return zones;
    final departments = await _departments();
    return [
      for (final z in zones)
        z.categories.isNotEmpty ? z : z.copyWith(categories: _categoriesOf(departments, z.department)),
    ];
  }

  Future<List<RoomZoneData>> _fallback() async {
    final departments = await _departments();
    final entries = roomZoneDefaults.entries.toList();
    final featured = await Future.wait([
      for (final e in entries) _featured(e.value.$2),
    ]);
    return [
      for (var i = 0; i < entries.length; i++)
        RoomZoneData(
          id: entries[i].key,
          label: entries[i].value.$1,
          department: entries[i].value.$2,
          categories: _categoriesOf(departments, entries[i].value.$2),
          featured: featured[i],
        ),
    ];
  }

  Future<List<Department>> _departments() async {
    try {
      return await _api.get('/catalog/departments', decode: (d) => JsonX.asList(d, Department.fromJson));
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow;
      return const [];
    }
  }

  Future<List<ProductSummary>> _featured(String department) async {
    try {
      final page = await _api.getPage(
        '/products',
        query: {'department': department, 'sort': 'popular', 'limit': 8},
        item: ProductSummary.fromJson,
      );
      return page.items;
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow;
      return const [];
    }
  }

  static List<String> _categoriesOf(List<Department> departments, String slug) {
    for (final d in departments) {
      if (d.slug == slug) return [for (final c in d.categories) c.slug];
    }
    return const [];
  }
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) => RoomRepository(ref.watch(apiClientProvider)));
