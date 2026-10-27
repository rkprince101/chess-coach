import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'search.dart';

/// Runs searches off the UI thread and serialises them so only one runs at
/// a time.
///
/// On native platforms a single long-lived worker isolate is used, which
/// avoids the ~50-100 ms isolate spawn cost of `compute` on every move (this
/// matters on phones). On the web, where isolates are unavailable, the search
/// runs inline via `compute`'s fallback.
class EngineService {
  Future<void> _queue = Future.value();
  final Map<String, SearchResult> _cache = {};

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  StreamSubscription<dynamic>? _subscription;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 0;

  /// Analyses [fen]. Results are cached per FEN + time budget so re-analysing
  /// a position after a take-back is instant.
  Future<SearchResult> analyze(String fen, {required int timeMs, int maxDepth = 6}) {
    final key = '$fen|$timeMs|$maxDepth';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    final completer = Completer<SearchResult>();
    _queue = _queue.then((_) async {
      try {
        final request = {'fen': fen, 'timeMs': timeMs, 'maxDepth': maxDepth};
        final json = kIsWeb ? await compute(runSearch, request) : await _runOnWorker(request);
        final result = SearchResult.fromJson(json);
        _cache[key] = result;
        if (_cache.length > 200) _cache.remove(_cache.keys.first);
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _runOnWorker(Map<String, dynamic> request) async {
    final port = await _ensureWorker();
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    port.send({'id': id, ...request});
    return completer.future;
  }

  Future<SendPort> _ensureWorker() async {
    final existing = _toWorker;
    if (existing != null) return existing;

    final fromWorker = ReceivePort();
    final ready = Completer<SendPort>();
    _fromWorker = fromWorker;
    _subscription = fromWorker.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is Map) {
        final id = message['id'] as int;
        final completer = _pending.remove(id);
        if (completer == null) return;
        if (message['error'] != null) {
          completer.completeError(StateError(message['error'] as String));
        } else {
          completer.complete(Map<String, dynamic>.from(message['result'] as Map));
        }
      }
    });

    final errors = ReceivePort()
      ..listen((_) {
        // The worker died: fail what is pending and respawn lazily.
        for (final c in _pending.values) {
          c.completeError(StateError('Engine worker crashed'));
        }
        _pending.clear();
        _teardown();
      });

    _isolate = await Isolate.spawn(
      _workerMain,
      fromWorker.sendPort,
      onError: errors.sendPort,
      onExit: errors.sendPort,
      debugName: 'chess-engine',
    );
    final port = await ready.future;
    _toWorker = port;
    return port;
  }

  void _teardown() {
    _subscription?.cancel();
    _fromWorker?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _fromWorker = null;
    _subscription = null;
  }

  void dispose() {
    _teardown();
  }
}

void _workerMain(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  inbox.listen((message) {
    final request = Map<String, dynamic>.from(message as Map);
    final id = request.remove('id') as int;
    try {
      toMain.send({'id': id, 'result': runSearch(request)});
    } catch (e) {
      toMain.send({'id': id, 'error': e.toString()});
    }
  });
}
