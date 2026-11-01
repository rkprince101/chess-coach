import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/game_analysis.dart';
import '../models/move_quality.dart';

/// One played Play & Learn game: everything needed to replay, export and
/// analyse it later.
class MatchRecord {
  const MatchRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.startFen,
    required this.playerSide,
    required this.moves,
    required this.result,
    required this.resultText,
    required this.endReason,
    this.opening,
    this.opponentElo,
    this.liveGrades = const {},
    this.analysis,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String startFen;
  final Side playerSide;

  /// Moves played from [startFen], in UCI notation.
  final List<String> moves;

  /// PGN result: "1-0", "0-1", "1/2-1/2", or "*" for an unfinished game.
  final String result;

  /// How the game ended in words, e.g. "Checkmate. White wins.".
  final String resultText;

  /// Short reason, e.g. "Checkmate", "Resignation", "Abandoned".
  final String endReason;
  final String? opening;

  /// The engine opponent's Elo setting when the game was played.
  final int? opponentElo;

  /// The coach's grades of the player's moves during play, by ply index.
  final Map<int, MoveQuality> liveGrades;

  /// Full-game engine analysis, once run.
  final GameAnalysis? analysis;

  bool get finished => result != '*';

  /// Null for a draw or an unfinished game.
  Side? get winner => switch (result) {
        '1-0' => Side.white,
        '0-1' => Side.black,
        _ => null,
      };

  Position get startPosition => Chess.fromSetup(Setup.parseFen(startFen));

  /// The moves as [Move]s, stopping at the first one that does not parse or
  /// is not legal (a corrupted record still replays up to that point).
  List<Move> get parsedMoves {
    final out = <Move>[];
    Position pos = startPosition;
    for (final uci in moves) {
      final m = Move.parse(uci);
      if (m == null || !pos.isLegal(m)) break;
      out.add(m);
      pos = pos.play(m);
    }
    return out;
  }

  MatchRecord copyWith({GameAnalysis? analysis}) => MatchRecord(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        startFen: startFen,
        playerSide: playerSide,
        moves: moves,
        result: result,
        resultText: resultText,
        endReason: endReason,
        opening: opening,
        opponentElo: opponentElo,
        liveGrades: liveGrades,
        analysis: analysis ?? this.analysis,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'fen': startFen,
        'side': playerSide.name,
        'moves': moves,
        'result': result,
        'resultText': resultText,
        'endReason': endReason,
        'opening': opening,
        'elo': opponentElo,
        'grades': {for (final e in liveGrades.entries) '${e.key}': e.value.name},
        'analysis': ?analysis?.toJson(),
      };

  static MatchRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final started = DateTime.tryParse(json['startedAt'] as String? ?? '');
    final ended = DateTime.tryParse(json['endedAt'] as String? ?? '');
    final fen = json['fen'];
    final side = Side.values.asNameMap()[json['side']];
    final moves = json['moves'];
    if (id is! String || started == null || ended == null || fen is! String || side == null || moves is! List) {
      return null;
    }
    final grades = <int, MoveQuality>{};
    if (json['grades'] case final Map g) {
      for (final MapEntry(:key, :value) in g.entries) {
        final ply = int.tryParse('$key');
        final q = MoveQuality.values.asNameMap()[value];
        if (ply != null && q != null) grades[ply] = q;
      }
    }
    return MatchRecord(
      id: id,
      startedAt: started,
      endedAt: ended,
      startFen: fen,
      playerSide: side,
      moves: moves.whereType<String>().toList(),
      result: json['result'] as String? ?? '*',
      resultText: json['resultText'] as String? ?? '',
      endReason: json['endReason'] as String? ?? '',
      opening: json['opening'] as String?,
      opponentElo: json['elo'] as int?,
      liveGrades: grades,
      analysis: GameAnalysis.fromJson(json['analysis']),
    );
  }

  /// The game as PGN, with the analysis grades as move suffixes and the
  /// engine evaluations as `[%eval]` comments when it has been analysed.
  String toPgn() {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = startedAt;
    final computer = 'Computer${opponentElo == null ? '' : ' ($opponentElo)'}';
    final start = startPosition;
    final standardStart = startFen == Chess.initial.fen;
    final headers = <String, String>{
      'Event': 'Chess Coach game',
      'Site': 'Chess Coach',
      'Date': '${d.year}.${two(d.month)}.${two(d.day)}',
      'Round': '-',
      'White': playerSide == Side.white ? 'You' : computer,
      'Black': playerSide == Side.black ? 'You' : computer,
      'Result': result,
      if (!standardStart) 'SetUp': '1',
      if (!standardStart) 'FEN': startFen,
      'Opening': ?opening,
      'Termination': endReason,
    };
    final buffer = StringBuffer();
    headers.forEach((k, v) => buffer.writeln('[$k "${v.replaceAll('"', "'")}"]'));
    buffer.writeln();

    final tokens = <String>[];
    Position pos = start;
    final a = analysis;
    for (final (i, move) in parsedMoves.indexed) {
      final (after, san) = pos.makeSan(move);
      if (pos.turn == Side.white) {
        tokens.add('${pos.fullmoves}.');
      } else if (i == 0) {
        tokens.add('${pos.fullmoves}...');
      }
      final grade = a != null && i < a.plies.length ? a.plies[i].quality : null;
      tokens.add('$san${grade?.annotation ?? ''}');
      // Final positions carry the result instead of an evaluation.
      if (a != null && i + 1 < a.evalCp.length && !const {'1-0', '0-1', '½-½'}.contains(a.evalText[i + 1])) {
        final text = a.evalText[i + 1];
        final eval = text.startsWith('#') ? text : (a.evalCp[i + 1] / 100).toStringAsFixed(2);
        tokens.add('{ [%eval $eval] }');
      }
      pos = after;
    }
    tokens.add(result);

    // Wrap movetext at 80 columns, as PGN export format asks.
    var line = StringBuffer();
    for (final t in tokens) {
      if (line.isNotEmpty && line.length + 1 + t.length > 80) {
        buffer.writeln(line);
        line = StringBuffer();
      }
      if (line.isNotEmpty) line.write(' ');
      line.write(t);
    }
    if (line.isNotEmpty) buffer.writeln(line);
    return buffer.toString();
  }
}

/// Where the history JSON lives: a file in the app's support directory on
/// native platforms, shared preferences on the web, memory in tests.
abstract class MatchStorage {
  Future<String?> read();
  Future<void> write(String data);

  static MatchStorage platform() => kIsWeb ? PrefsMatchStorage() : FileMatchStorage();
}

class FileMatchStorage implements MatchStorage {
  Future<io.File> _file() async => io.File('${(await getApplicationSupportDirectory()).path}/match_history.json');

  @override
  Future<String?> read() async {
    final file = await _file();
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Write then rename, so a crash mid-write never truncates the history.
    final tmp = io.File('${file.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(file.path);
  }
}

class PrefsMatchStorage implements MatchStorage {
  static const _key = 'matchHistory';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String data) async => (await SharedPreferences.getInstance()).setString(_key, data);
}

class MemoryMatchStorage implements MatchStorage {
  MemoryMatchStorage([this.data]);

  String? data;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String data) async => this.data = data;
}

/// Every saved game, newest first. Loads lazily on first use; storage errors
/// are logged and the history keeps working in memory.
class MatchHistory extends ChangeNotifier {
  MatchHistory({MatchStorage? storage}) : _storage = storage ?? MatchStorage.platform();

  final MatchStorage _storage;
  final List<MatchRecord> _records = [];
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<MatchRecord> get records => List.unmodifiable(_records);

  MatchRecord? byId(String id) => _records.where((r) => r.id == id).firstOrNull;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _storage.read();
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) {
          final byId = {for (final r in _records) r.id};
          _records.addAll(list.map(MatchRecord.fromJson).nonNulls.where((r) => !byId.contains(r.id)));
        }
      }
    } catch (e) {
      debugPrint('Match history could not be read: $e');
    }
    _sort();
    _loaded = true;
    notifyListeners();
  }

  /// Adds [record], or replaces the one with the same id.
  Future<void> upsert(MatchRecord record) async {
    await load();
    _records.removeWhere((r) => r.id == record.id);
    _records.add(record);
    _sort();
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    await load();
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    await load();
    _records.clear();
    notifyListeners();
    await _persist();
  }

  void _sort() => _records.sort((a, b) => b.endedAt.compareTo(a.endedAt));

  /// Writes are chained so an older snapshot never lands after a newer one.
  Future<void> _persist() {
    final data = jsonEncode([for (final r in _records) r.toJson()]);
    return _writes = _writes.then((_) async {
      try {
        await _storage.write(data);
      } catch (e) {
        debugPrint('Match history could not be saved: $e');
      }
    });
  }
}
