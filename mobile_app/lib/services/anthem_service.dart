import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AnthemService {
  static final AnthemService _instance = AnthemService._internal();
  factory AnthemService() => _instance;

  StreamSubscription? _completeSub;

  AnthemService._internal() {
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (_completeSub == null) return; // disposed
      _isPlaying = false;
      _currentTeamId = null;
    });
  }

  final AudioPlayer _player = AudioPlayer();
  String? _currentTeamId;
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;
  String? get currentTeamId => _currentTeamId;

  /// Upload an MP3 file for the given team.
  static Future<bool> uploadAnthem({
    required String serverUrl,
    required String teamId,
    required String filePath,
  }) async {
    try {
      final uri = Uri.parse('$serverUrl/api/anthem/$teamId');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath(
        'anthem',
        filePath,
        filename: '$teamId.mp3',
      ));
      final response = await request.send().timeout(const Duration(seconds: 30));
      final ok = response.statusCode == 200;
      debugPrint('[Anthem] Upload $teamId: ${response.statusCode}');
      return ok;
    } catch (e) {
      debugPrint('[Anthem] Upload error: $e');
      return false;
    }
  }

  /// Check if a team has an anthem on the server.
  static Future<bool> anthemExists({
    required String serverUrl,
    required String teamId,
  }) async {
    try {
      final resp = await http
          .get(Uri.parse('$serverUrl/api/anthem/$teamId/exists'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        return json['exists'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Download and play the anthem for the given team.
  /// If [teamId] == current team, does nothing (don't play your own anthem).
  Future<void> playAnthem({
    required String serverUrl,
    required String enemyTeamId,
    required String myTeamId,
  }) async {
    if (enemyTeamId == myTeamId) return; // never play your own anthem on yourself
    if (_isPlaying && _currentTeamId == enemyTeamId) return; // already playing

    await stop();

    try {
      // Download to temp file
      final resp = await http
          .get(Uri.parse('$serverUrl/api/anthem/$enemyTeamId'))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/anthem_$enemyTeamId.mp3');
      await file.writeAsBytes(resp.bodyBytes);

      _currentTeamId = enemyTeamId;
      _isPlaying = true;
      await _player.play(DeviceFileSource(file.path));
      debugPrint('[Anthem] Playing anthem for team $enemyTeamId');
    } catch (e) {
      debugPrint('[Anthem] playAnthem error: $e');
      _isPlaying = false;
      _currentTeamId = null;
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    _currentTeamId = null;
  }

  void dispose() {
    _completeSub?.cancel();
    _completeSub = null;
    _player.dispose();
  }
}
