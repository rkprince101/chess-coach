import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'tts_worker.dart';
import 'voice_packs.dart';

enum PackState { notInstalled, downloading, extracting, installed, failed }

class PackStatus {
  const PackStatus(this.state, {this.progress = 0, this.error});

  final PackState state;

  /// 0..1 while downloading.
  final double progress;
  final String? error;
}

/// Downloads voice packs into app storage and resolves their model files.
class VoicePackStore {
  Directory? _root;
  final Map<String, PackStatus> _status = {};
  final Map<String, http.Client> _downloads = {};

  Future<Directory> _rootDir() async {
    final cached = _root;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}voices');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _root = dir;
    return dir;
  }

  Future<Directory> packDir(VoicePack pack) async =>
      Directory('${(await _rootDir()).path}${Platform.pathSeparator}${pack.id}');

  PackStatus status(VoicePack pack) => _status[pack.id] ?? const PackStatus(PackState.notInstalled);

  /// Checks disk for already-installed packs; call once at startup.
  Future<void> refresh() async {
    for (final pack in voicePacks) {
      if (_status[pack.id]?.state == PackState.downloading ||
          _status[pack.id]?.state == PackState.extracting) {
        continue;
      }
      final files = await resolve(pack);
      _status[pack.id] = PackStatus(files == null ? PackState.notInstalled : PackState.installed);
    }
  }

  /// Finds the model files inside an installed pack, or null if incomplete.
  Future<VoiceModelFiles?> resolve(VoicePack pack) async {
    final dir = await packDir(pack);
    if (!dir.existsSync()) return null;
    File? model;
    File? tokens;
    File? voices;
    Directory? data;
    for (final entity in dir.listSync(recursive: true)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entity is File) {
        if (name.endsWith('.onnx')) {
          if (model == null || entity.lengthSync() > model.lengthSync()) model = entity;
        } else if (name == 'tokens.txt') {
          tokens = entity;
        } else if (name == 'voices.bin') {
          voices = entity;
        }
      } else if (entity is Directory && name == 'espeak-ng-data') {
        data = entity;
      }
    }
    if (model == null || tokens == null || data == null) return null;
    if (pack.engine != VoiceEngine.vits && voices == null) return null;
    return VoiceModelFiles(
      engine: pack.engine,
      model: model.path,
      tokens: tokens.path,
      dataDir: data.path,
      voices: voices?.path ?? '',
    );
  }

  /// Downloads and unpacks [pack], reporting progress through [onStatus].
  Future<VoiceModelFiles> install(VoicePack pack, void Function(PackStatus status) onStatus) async {
    void update(PackStatus s) {
      _status[pack.id] = s;
      onStatus(s);
    }

    final root = await _rootDir();
    final archive = File('${root.path}${Platform.pathSeparator}${pack.archiveName}');
    final dest = await packDir(pack);
    final client = http.Client();
    _downloads[pack.id] = client;
    try {
      update(const PackStatus(PackState.downloading));
      final response = await client.send(http.Request('GET', Uri.parse(pack.url)));
      if (response.statusCode != 200) {
        throw HttpException('Download failed with HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? (pack.downloadMb * 1000000);
      var received = 0;
      var lastReport = 0;
      final sink = archive.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (received - lastReport > 512 * 1024) {
            lastReport = received;
            update(PackStatus(PackState.downloading, progress: (received / total).clamp(0, 1)));
          }
        }
      } finally {
        await sink.close();
      }

      update(const PackStatus(PackState.extracting));
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      dest.createSync(recursive: true);
      // bzip2 in pure Dart is slow (tens of seconds for Kokoro); keep it off
      // the UI isolate.
      await Isolate.run(() => extractFileToDisk(archive.path, dest.path));
      final files = await resolve(pack);
      if (files == null) throw const FileSystemException('Pack unpacked but model files were not found');
      update(const PackStatus(PackState.installed));
      return files;
    } catch (e) {
      final cancelled = _downloads[pack.id] == null;
      update(PackStatus(cancelled ? PackState.notInstalled : PackState.failed,
          error: cancelled ? null : e.toString()));
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      rethrow;
    } finally {
      _downloads.remove(pack.id)?.close();
      if (archive.existsSync()) archive.deleteSync();
    }
  }

  void cancel(VoicePack pack) {
    _downloads.remove(pack.id)?.close();
  }

  Future<void> delete(VoicePack pack) async {
    final dir = await packDir(pack);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _status[pack.id] = const PackStatus(PackState.notInstalled);
  }
}
