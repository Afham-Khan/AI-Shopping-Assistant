import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';

/// Pakistani provinces / territories for the address form.
const pakistanProvinces = <String>[
  'Punjab',
  'Sindh',
  'Khyber Pakhtunkhwa',
  'Balochistan',
  'Islamabad Capital Territory',
  'Gilgit-Baltistan',
  'Azad Jammu & Kashmir',
];

/// Saved shipping address (`/addresses`); also the order's `shippingAddress` snapshot.
@immutable
class Address {
  const Address({
    this.id = 0,
    this.label,
    required this.fullName,
    required this.phone,
    required this.line1,
    this.line2,
    required this.city,
    required this.province,
    this.postalCode,
    this.country = 'Pakistan',
    this.isDefault = false,
  });

  factory Address.fromJson(Map<String, dynamic> json) => Address(
    id: JsonX.asInt(json['id']),
    label: JsonX.asStringOrNull(json['label']),
    fullName: JsonX.asString(json['fullName']),
    phone: JsonX.asString(json['phone']),
    line1: JsonX.asString(json['line1']),
    line2: JsonX.asStringOrNull(json['line2']),
    city: JsonX.asString(json['city']),
    province: JsonX.asString(json['province']),
    postalCode: JsonX.asStringOrNull(json['postalCode']),
    country: JsonX.asString(json['country'], 'Pakistan'),
    isDefault: JsonX.asBool(json['isDefault']),
  );

  final int id;
  final String? label;
  final String fullName;
  final String phone;
  final String line1;
  final String? line2;
  final String city;
  final String province;
  final String? postalCode;
  final String country;
  final bool isDefault;

  /// Body for POST/PATCH (no id / isDefault).
  Map<String, dynamic> toJson() => {
    'label': label,
    'fullName': fullName,
    'phone': phone,
    'line1': line1,
    'line2': line2,
    'city': city,
    'province': province,
    'postalCode': postalCode,
    'country': country,
  };

  String get streetLine => [line1, if (line2 != null && line2!.isNotEmpty) line2].join(', ');

  String get cityLine =>
      [city, province, if (postalCode != null && postalCode!.isNotEmpty) postalCode].join(', ');

  String get oneLine => '$streetLine, $cityLine';
}
