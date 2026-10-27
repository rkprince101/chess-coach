import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/settings.dart';
import 'speech_text.dart';
import 'tts_worker.dart';
import 'voice_pack_store.dart';
import 'voice_packs.dart';

class _Utterance {
  _Utterance(this.text);

  final String text;
  final Completer<void> done = Completer<void>();
  SynthesizedAudio? audio;
  bool cancelled = false;

  void finish() {
    if (!done.isCompleted) done.complete();
  }
}

/// The coach's voice: on-device neural text-to-speech with sentence-level
/// queuing so speech starts while the explanation is still streaming.
class VoiceService extends ChangeNotifier {
  VoiceService(this.settings, {VoicePackStore? store, TtsWorker? worker})
      : store = store ?? VoicePackStore(),
        _worker = worker ?? TtsWorker() {
    settings.addListener(_onSettingsChanged);
  }

  final SettingsController settings;
  final VoicePackStore store;
  final TtsWorker _worker;
  final AudioPlayer _player = AudioPlayer();

  final List<_Utterance> _queue = [];
  final List<_Utterance> _ready = [];
  bool _synthRunning = false;
  bool _playRunning = false;
  _Utterance? _current;
  Completer<void>? _playbackDone;
  int _fileCounter = 0;
  String? _lastFile;

  VoicePack? _loadedPack;
  bool _loading = false;
  String? lastError;
  bool speaking = false;
  bool _initialised = false;

  /// Voice needs native sherpa-onnx; the web build has none.
  bool get available => !kIsWeb;

  VoicePack? get selectedPack => voicePackById(settings.voicePack);
  VoicePack? get loadedPack => _loadedPack;
  bool get isLoading => _loading;
  int get speakerCount => _worker.numSpeakers;

  bool get selectedPackInstalled =>
      selectedPack != null && store.status(selectedPack!).state == PackState.installed;

  /// True when the user turned the voice on and the selected pack is on disk.
  bool get enabled => available && settings.voiceEnabled && selectedPackInstalled;

  /// Scans installed packs and warms up the selected one if voice is on.
  Future<void> init() async {
    if (!available || _initialised) return;
    _initialised = true;
    try {
      await store.refresh();
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
    if (enabled) unawaited(ensureLoaded());
  }

  Future<bool> ensureLoaded() async {
    final pack = selectedPack;
    if (!available || pack == null) return false;
    if (_loadedPack?.id == pack.id && _worker.isLoaded) return true;
    if (_loading) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _loadedPack?.id == pack.id;
    }
    final files = await store.resolve(pack);
    if (files == null) return false;
    _loading = true;
    notifyListeners();
    try {
      await _worker.load(files);
      _loadedPack = pack;
      lastError = null;
      return true;
    } catch (e) {
      lastError = 'Could not load voice: $e';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Speaking

  /// Queues [text] and completes when it has been spoken (or skipped).
  /// [interrupt] drops everything queued so far first.
  Future<void> say(String text, {bool interrupt = false}) async {
    if (!enabled) return;
    final spoken = normalizeForSpeech(text);
    if (spoken.isEmpty) return;
    if (interrupt) stop();
    if (!await ensureLoaded()) return;
    final u = _Utterance(spoken);
    _queue.add(u);
    _pumpSynth();
    return u.done.future;
  }

  /// Speaks a short sample so the user can judge the voice.
  Future<void> preview() => say(
        'Your knight jumps from f3 to e5 and attacks the queen. Nice idea, but check what the bishop on c4 is doing first.',
        interrupt: true,
      );

  void stop() {
    for (final u in [..._queue, ..._ready]) {
      u.cancelled = true;
      u.finish();
    }
    _queue.clear();
    _ready.clear();
    final cur = _current;
    if (cur != null) {
      cur.cancelled = true;
      unawaited(_player.stop());
      final done = _playbackDone;
      if (done != null && !done.isCompleted) done.complete();
    }
  }

  void _pumpSynth() {
    if (_synthRunning) return;
    _synthRunning = true;
    () async {
      try {
        while (_queue.isNotEmpty) {
          final u = _queue.removeAt(0);
          if (u.cancelled) continue;
          try {
            u.audio = await _worker.synthesize(
              u.text,
              speaker: settings.voiceSpeaker.clamp(0, (_worker.numSpeakers - 1).clamp(0, 1 << 20)),
              speed: settings.voiceSpeed,
            );
          } catch (e) {
            lastError = 'Speech failed: $e';
            u.finish();
            notifyListeners();
            continue;
          }
          if (u.cancelled) {
            u.finish();
            continue;
          }
          _ready.add(u);
          _pumpPlay();
        }
      } finally {
        _synthRunning = false;
      }
    }();
  }

  void _pumpPlay() {
    if (_playRunning) return;
    _playRunning = true;
    () async {
      try {
        while (_ready.isNotEmpty) {
          final u = _ready.removeAt(0);
          if (u.cancelled) {
            u.finish();
            continue;
          }
          _current = u;
          speaking = true;
          notifyListeners();
          try {
            await _play(u.audio!);
          } catch (e) {
            lastError = 'Playback failed: $e';
          }
          _current = null;
          u.finish();
        }
      } finally {
        speaking = false;
        _playRunning = false;
        notifyListeners();
      }
    }();
  }

  Future<void> _play(SynthesizedAudio audio) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}coach_${_fileCounter++ % 4}.wav';
    await File(path).writeAsBytes(_wavBytes(audio), flush: true);
    final done = Completer<void>();
    _playbackDone = done;
    final sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await _player.play(DeviceFileSource(path));
      // Safety net in case the completion event is missed.
      await done.future.timeout(audio.duration + const Duration(seconds: 3), onTimeout: () {});
    } finally {
      await sub.cancel();
      _playbackDone = null;
      final previous = _lastFile;
      _lastFile = path;
      if (previous != null && previous != path) {
        try {
          File(previous).deleteSync();
        } catch (_) {}
      }
    }
  }

  /// 16-bit PCM mono WAV.
  static Uint8List _wavBytes(SynthesizedAudio audio) {
    final n = audio.samples.length;
    final data = ByteData(44 + n * 2);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, audio.sampleRate, Endian.little);
    data.setUint32(28, audio.sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, n * 2, Endian.little);
    var offset = 44;
    for (final s in audio.samples) {
      final v = (s.clamp(-1.0, 1.0) * 32767).round();
      data.setInt16(offset, v, Endian.little);
      offset += 2;
    }
    return data.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // Packs

  PackStatus statusOf(VoicePack pack) => store.status(pack);

  Future<void> installPack(VoicePack pack) async {
    try {
      await store.install(pack, (_) => notifyListeners());
      if (settings.voicePack != pack.id) await settings.setVoicePack(pack.id);
      if (!settings.voiceEnabled) await settings.setVoiceEnabled(true);
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
  }

  void cancelInstall(VoicePack pack) {
    store.cancel(pack);
    notifyListeners();
  }

  Future<void> deletePack(VoicePack pack) async {
    stop();
    if (_loadedPack?.id == pack.id) {
      await _worker.unload();
      _loadedPack = null;
    }
    await store.delete(pack);
    notifyListeners();
  }

  Future<void> selectPack(VoicePack pack) async {
    stop();
    await settings.setVoicePack(pack.id);
    if (settings.voiceSpeaker >= pack.speakerNames.length) {
      await settings.setVoiceSpeaker(pack.defaultSpeaker);
    }
    if (enabled) await ensureLoaded();
  }

  void _onSettingsChanged() {
    if (!settings.voiceEnabled) stop();
    if (_loadedPack != null && _loadedPack!.id != settings.voicePack) {
      stop();
      unawaited(_worker.unload().then((_) {
        _loadedPack = null;
        if (enabled) unawaited(ensureLoaded());
      }));
    }
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    stop();
    _worker.dispose();
    _player.dispose();
    super.dispose();
  }
}
