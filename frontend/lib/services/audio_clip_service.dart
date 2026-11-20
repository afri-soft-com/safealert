import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A recorded clip ready to upload: base64 data URL + length.
class AudioClip {
  final String dataUrl;
  final int seconds;
  const AudioClip(this.dataUrl, this.seconds);
}

/// Records short AAC clips (SOS evidence, group voice notes) and plays
/// clips received as data URLs. Low bitrate mono keeps a minute under ~250 KB,
/// below the server's 2 MB body limit once base64-encoded.
class AudioClipService {
  static final AudioClipService _instance = AudioClipService._();
  AudioClipService._();
  factory AudioClipService() => _instance;

  static const _mime = 'audio/mp4';
  static const config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 24000,
    sampleRate: 16000,
    numChannels: 1,
  );

  AudioRecorder? _recorder;
  DateTime? _startedAt;
  final AudioPlayer _player = AudioPlayer();

  bool get isRecording => _startedAt != null;

  /// Asks for the microphone if needed. Call from a user action, never
  /// during an SOS, so no system prompt shows up at the worst moment.
  Future<bool> ensurePermission({bool request = true}) async {
    try {
      final rec = _recorder ??= AudioRecorder();
      return await rec.hasPermission(request: request);
    } catch (e) {
      debugPrint('AudioClipService permission: $e');
      return false;
    }
  }

  Future<bool> start() async {
    if (isRecording) return true;
    if (!await ensurePermission(request: false)) return false;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await (_recorder ??= AudioRecorder()).start(config, path: path);
      _startedAt = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('AudioClipService start: $e');
      _startedAt = null;
      return false;
    }
  }

  /// Stops and returns the clip, or null if nothing usable was recorded.
  Future<AudioClip?> stop() async {
    final started = _startedAt;
    _startedAt = null;
    if (started == null || _recorder == null) return null;
    try {
      final path = await _recorder!.stop();
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      unawaited(file.delete().catchError((_) => file));
      final seconds = DateTime.now().difference(started).inSeconds;
      if (bytes.isEmpty || seconds < 1) return null;
      return AudioClip('data:$_mime;base64,${base64Encode(bytes)}', seconds);
    } catch (e) {
      debugPrint('AudioClipService stop: $e');
      return null;
    }
  }

  Future<void> cancel() async {
    _startedAt = null;
    try {
      await _recorder?.cancel();
    } catch (_) {}
  }

  /// Records [duration] then returns the clip (used during an SOS).
  Future<AudioClip?> recordFor(Duration duration) async {
    if (!await start()) return null;
    await Future<void>.delayed(duration);
    return stop();
  }

  /// Plays a data URL by writing it to a temp file (works on iOS and Android).
  Future<void> playDataUrl(String dataUrl) async {
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return;
    final bytes = base64Decode(dataUrl.substring(comma + 1));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/play_${dataUrl.hashCode}.m4a');
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    await _player.stop();
    await _player.play(DeviceFileSource(file.path, mimeType: _mime));
  }

  Future<void> stopPlayback() => _player.stop();
}
