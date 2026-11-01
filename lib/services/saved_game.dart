import 'dart:convert';

import 'package:dartchess/dartchess.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Play & Learn game the user chose to save when leaving mid-game.
class SavedGame {
  const SavedGame({
    required this.startFen,
    required this.playerSide,
    required this.moves,
    this.matchId,
    this.startedAt,
  });

  final String startFen;
  final Side playerSide;

  /// Moves played from [startFen], in UCI notation.
  final List<String> moves;

  /// Match history id and start time, so a resumed game is still recorded
  /// as the same match. Absent in games saved by older versions.
  final String? matchId;
  final DateTime? startedAt;

  Map<String, Object> toJson() => {
        'fen': startFen,
        'side': playerSide.name,
        'moves': moves,
        'matchId': ?matchId,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      };

  static SavedGame? fromJson(Map<String, dynamic> json) {
    final fen = json['fen'];
    final side = Side.values.asNameMap()[json['side']];
    final moves = json['moves'];
    if (fen is! String || side == null || moves is! List) return null;
    return SavedGame(
      startFen: fen,
      playerSide: side,
      moves: moves.whereType<String>().toList(),
      matchId: json['matchId'] as String?,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
    );
  }
}

/// Keeps at most one saved game on the device.
class SavedGameStore {
  static const _key = 'savedGame';

  static Future<SavedGame?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    try {
      return SavedGame.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  static Future<void> save(SavedGame game) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(game.toJson()));

  static Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}
