import 'package:flutter/material.dart';

enum EquipType {
  weapon,
  helmet,
  armor,
  shield,
  boots,
  ring,
}

extension EquipTypeX on EquipType {
  String get displayName {
    switch (this) {
      case EquipType.weapon:
        return '무기';
      case EquipType.helmet:
        return '투구';
      case EquipType.armor:
        return '갑옷';
      case EquipType.shield:
        return '방패';
      case EquipType.boots:
        return '신발';
      case EquipType.ring:
        return '반지';
    }
  }
}

enum ItemGrade {
  normal,
  rare,
  unique,
  epic,
  legendary,
  mythic,
}

extension ItemGradeX on ItemGrade {
  String get displayName {
    switch (this) {
      case ItemGrade.normal:
        return '노멀';
      case ItemGrade.rare:
        return '레어';
      case ItemGrade.unique:
        return '유니크';
      case ItemGrade.epic:
        return '에픽';
      case ItemGrade.legendary:
        return '레전더리';
      case ItemGrade.mythic:
        return '신화';
    }
  }
}

Color getGradeColor(ItemGrade grade) {
  switch (grade) {
    case ItemGrade.normal:
      return const Color(0xFF9E9E9E);
    case ItemGrade.rare:
      return const Color(0xFF2ECC71);
    case ItemGrade.unique:
      return const Color(0xFF3498DB);
    case ItemGrade.epic:
      return const Color(0xFF9B59B6);
    case ItemGrade.legendary:
      return const Color(0xFFE67E22);
    case ItemGrade.mythic:
      return const Color(0xFFFF3B3B);
  }
}

class Equipment {
  Equipment({
    required this.id,
    required this.name,
    required this.type,
    required this.grade,
    required this.statMultiplier,
    this.isEquipped = false,
  });

  final String id;
  final String name;
  final EquipType type;
  final ItemGrade grade;
  final double statMultiplier;
  bool isEquipped;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'grade': grade.name,
      'statMultiplier': statMultiplier,
      'isEquipped': isEquipped,
    };
  }

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as String,
      name: json['name'] as String,
      type: EquipType.values.byName(json['type'] as String),
      grade: ItemGrade.values.byName(json['grade'] as String),
      statMultiplier: (json['statMultiplier'] as num).toDouble(),
      isEquipped: json['isEquipped'] as bool,
    );
  }
}
