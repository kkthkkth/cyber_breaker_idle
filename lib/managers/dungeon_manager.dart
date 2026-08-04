import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DungeonType { goldDungeon, equipmentDungeon, towerOfInfinity }

class DungeonManager extends ChangeNotifier {
  DungeonManager._internal();

  static final DungeonManager instance = DungeonManager._internal();

  static const int maxDailyTickets = 3;

  int goldDungeonTickets = maxDailyTickets;
  int equipmentDungeonTickets = maxDailyTickets;

  /// Tower of Infinity has no ticket limit — you simply can't skip floors,
  /// so progress itself is the gate.
  int currentFloor = 1;

  DateTime? _lastResetDate;

  bool consumeTicket(DungeonType type) {
    _resetTicketsIfNewDay();

    switch (type) {
      case DungeonType.goldDungeon:
        if (goldDungeonTickets <= 0) {
          return false;
        }
        goldDungeonTickets--;
      case DungeonType.equipmentDungeon:
        if (equipmentDungeonTickets <= 0) {
          return false;
        }
        equipmentDungeonTickets--;
      case DungeonType.towerOfInfinity:
        break;
    }

    notifyListeners();
    return true;
  }

  void _resetTicketsIfNewDay() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    if (_lastResetDate == null || _lastResetDate!.isBefore(today)) {
      goldDungeonTickets = maxDailyTickets;
      equipmentDungeonTickets = maxDailyTickets;
      _lastResetDate = today;
      notifyListeners();
    }
  }

  void advanceFloor() {
    currentFloor++;
    notifyListeners();
    saveDungeonData();
  }

  static const String _saveKey = 'dungeon_manager_save';

  Future<void> saveDungeonData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final Map<String, dynamic> data = {
      'goldDungeonTickets': goldDungeonTickets,
      'equipmentDungeonTickets': equipmentDungeonTickets,
      'currentFloor': currentFloor,
      'lastResetDate': _lastResetDate?.millisecondsSinceEpoch,
    };

    await prefs.setString(_saveKey, jsonEncode(data));
  }

  Future<void> loadDungeonData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;

    goldDungeonTickets =
        data['goldDungeonTickets'] as int? ?? goldDungeonTickets;
    equipmentDungeonTickets =
        data['equipmentDungeonTickets'] as int? ?? equipmentDungeonTickets;
    currentFloor = data['currentFloor'] as int? ?? currentFloor;

    final int? lastResetMillis = data['lastResetDate'] as int?;
    _lastResetDate = lastResetMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastResetMillis)
        : null;

    _resetTicketsIfNewDay();
    notifyListeners();
  }
}
