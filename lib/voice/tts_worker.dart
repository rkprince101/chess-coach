import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice_packs.dart';

/// Paths of an installed voice pack, resolved by [VoicePackStore].
class VoiceModelFiles {
  const VoiceModelFiles({
    required this.engine,
    required this.model,
    required this.tokens,
    required this.dataDir,
    this.voices = '',
  });

  final VoiceEngine engine;
  final String model;
  final String tokens;
  final String dataDir;
  final String voices;

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        'model': model,
        'tokens': tokens,
        'dataDir': dataDir,
        'voices': voices,
      };

  factory VoiceModelFiles.fromJson(Map<String, dynamic> j) => VoiceModelFiles(
        engine: VoiceEngine.values.byName(j['engine'] as String),
        model: j['model'] as String,
        tokens: j['tokens'] as String,
        dataDir: j['dataDir'] as String,
        voices: j['voices'] as String? ?? '',
      );
}

class SynthesizedAudio {
  const SynthesizedAudio(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;

  Duration get duration => Duration(milliseconds: samples.length * 1000 ~/ sampleRate);
}

/// Hosts the sherpa-onnx synthesizer in its own isolate so generation never
/// blocks the UI. One model is loaded at a time.
class TtsWorker {
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _inbox;
  StreamSubscription<dynamic>? _sub;
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 0;

  int numSpeakers = 0;
  int sampleRate = 0;
  VoiceModelFiles? loaded;

  bool get isLoaded => loaded != null;

  Future<void> load(VoiceModelFiles files) async {
    final port = await _ensureIsolate();
    final reply = await _request(port, {'cmd': 'load', 'files': files.toJson()}) as Map;
    if (reply['error'] != null) throw StateError(reply['error'] as String);
    numSpeakers = reply['numSpeakers'] as int;
    sampleRate = reply['sampleRate'] as int;
    loaded = files;
  }

  Future<SynthesizedAudio> synthesize(String text, {int speaker = 0, double speed = 1.0}) async {
    final port = _port;
    if (port == null || loaded == null) throw StateError('No voice loaded');
    final reply = await _request(port, {
      'cmd': 'generate',
      'text': text,
      'sid': speaker,
      'speed': speed,
    }) as Map;
    if (reply['error'] != null) throw StateError(reply['error'] as String);
    return SynthesizedAudio(reply['samples'] as Float32List, reply['sampleRate'] as int);
  }

  Future<void> unload() async {
    final port = _port;
    if (port != null && loaded != null) {
      await _request(port, {'cmd': 'unload'});
    }
    loaded = null;
    numSpeakers = 0;
  }

  void dispose() {
    _sub?.cancel();
    _inbox?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
    _inbox = null;
    _sub = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('TTS worker disposed'));
    }
    _pending.clear();
  }

  Future<dynamic> _request(SendPort port, Map<String, dynamic> message) {
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    port.send({'id': id, ...message});
    return completer.future;
  }

  Future<SendPort> _ensureIsolate() async {
    final existing = _port;
    if (existing != null) return existing;
    final inbox = ReceivePort();
    final ready = Completer<SendPort>();
    _inbox = inbox;
    _sub = inbox.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is Map) {
        final c = _pending.remove(message['id'] as int);
        c?.complete(message);
      }
    });
    _isolate = await Isolate.spawn(_workerMain, inbox.sendPort, debugName: 'chess-tts');
    _port = await ready.future;
    return _port!;
  }
}

void _workerMain(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  sherpa.OfflineTts? tts;
  var bindingsReady = false;

  inbox.listen((message) {
    final msg = message as Map;
    final id = msg['id'] as int;
    try {
      switch (msg['cmd']) {
        case 'load':
          if (!bindingsReady) {
            sherpa.initBindings();
            bindingsReady = true;
          }
          tts?.free();
          final files = VoiceModelFiles.fromJson(Map<String, dynamic>.from(msg['files'] as Map));
          tts = sherpa.OfflineTts(_configFor(files));
          toMain.send({'id': id, 'numSpeakers': tts!.numSpeakers, 'sampleRate': tts!.sampleRate});
        case 'generate':
          final engine = tts;
          if (engine == null) {
            toMain.send({'id': id, 'error': 'No voice loaded'});
            return;
          }
          final audio = engine.generate(
            text: msg['text'] as String,
            sid: msg['sid'] as int,
            speed: (msg['speed'] as num).toDouble(),
          );
          toMain.send({'id': id, 'samples': audio.samples, 'sampleRate': audio.sampleRate});
        case 'unload':
          tts?.free();
          tts = null;
          toMain.send({'id': id, 'ok': true});
      }
    } catch (e) {
      toMain.send({'id': id, 'error': e.toString()});
    }
  });
}

sherpa.OfflineTtsConfig _configFor(VoiceModelFiles f) {
  final model = switch (f.engine) {
    VoiceEngine.kokoro => sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: f.model,
          voices: f.voices,
          tokens: f.tokens,
          dataDir: f.dataDir,
        ),
        numThreads: 2,
        debug: false,
      ),
    VoiceEngine.kitten => sherpa.OfflineTtsModelConfig(
        kitten: sherpa.OfflineTtsKittenModelConfig(
          model: f.model,
          voices: f.voices,
          tokens: f.tokens,
          dataDir: f.dataDir,
        ),
        numThreads: 2,
        debug: false,
      ),
    VoiceEngine.vits => sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: f.model,
          tokens: f.tokens,
          dataDir: f.dataDir,
        ),
        numThreads: 2,
        debug: false,
      ),
  };
  return sherpa.OfflineTtsConfig(model: model, maxNumSenetences: 2);
}
