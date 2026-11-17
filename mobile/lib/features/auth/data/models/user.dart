import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';

/// Shopping preferences captured on the interests screen.
@immutable
class UserPreferences {
  const UserPreferences({this.interests = const [], this.budgetMin, this.budgetMax, this.gender});

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    final budget = JsonX.asMap(json['budget']);
    return UserPreferences(
      interests: JsonX.asStringList(json['interests']),
      budgetMin: JsonX.asDoubleOrNull(budget['min']),
      budgetMax: JsonX.asDoubleOrNull(budget['max']),
      gender: JsonX.asStringOrNull(json['gender']),
    );
  }

  /// Category slugs.
  final List<String> interests;
  final double? budgetMin;
  final double? budgetMax;

  /// `men` | `women` | `any`.
  final String? gender;

  bool get isEmpty => interests.isEmpty && budgetMax == null && gender == null;

  Map<String, dynamic> toJson() => {
    'interests': interests,
    if (budgetMin != null || budgetMax != null) 'budget': {'min': budgetMin ?? 0, 'max': budgetMax},
    if (gender != null) 'gender': gender,
  };
}

/// The signed-in user (`GET /auth/me`).
@immutable
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.role = 'customer',
    this.preferences = const UserPreferences(),
    this.isOnboarded = false,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: JsonX.asInt(json['id']),
    name: JsonX.asString(json['name']),
    email: JsonX.asString(json['email']),
    phone: JsonX.asStringOrNull(json['phone']),
    avatarUrl: JsonX.asStringOrNull(json['avatarUrl']),
    role: JsonX.asString(json['role'], 'customer'),
    preferences: UserPreferences.fromJson(JsonX.asMap(json['preferences'])),
    isOnboarded: JsonX.asBool(json['isOnboarded']),
    createdAt: JsonX.asDate(json['createdAt']),
  );

  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final UserPreferences preferences;

  /// False until the user saves (or explicitly sets) preferences.
  final bool isOnboarded;
  final DateTime? createdAt;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  User copyWith({
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    UserPreferences? preferences,
    bool? isOnboarded,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role,
      preferences: preferences ?? this.preferences,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'avatarUrl': avatarUrl,
    'role': role,
    'preferences': preferences.toJson(),
    'isOnboarded': isOnboarded,
    'createdAt': createdAt?.toIso8601String(),
  };
}
