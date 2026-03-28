import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;
  static bool _soundEnabled = true;
  
  static Future<void> init() async {
    if (_initialized) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    _initialized = true;
  }
  
  static void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
  }
  
  static bool get soundEnabled => _soundEnabled;
  
  // Play sound when entering enemy territory
  static Future<void> playEnemyTerritorySound() async {
    if (!_soundEnabled) return;
    try {
      // Using a built-in beep sound as fallback
      await _player.play(AssetSource('sounds/enemy_territory.mp3'));
    } catch (e) {
      debugPrint('Error playing enemy territory sound: $e');
      // Fallback: system beep would go here
    }
  }
  
  // Play sound when poster is detected
  static Future<void> playPosterDetectedSound() async {
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('sounds/poster_detected.mp3'));
    } catch (e) {
      debugPrint('Error playing poster detected sound: $e');
    }
  }
  
  // Play sound when joining room
  static Future<void> playJoinRoomSound() async {
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('sounds/join_room.mp3'));
    } catch (e) {
      debugPrint('Error playing join room sound: $e');
    }
  }
  
  // Play sound when territory is captured
  static Future<void> playTerritoryCapturedSound() async {
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('sounds/territory_captured.mp3'));
    } catch (e) {
      debugPrint('Error playing territory captured sound: $e');
    }
  }
  
  static void dispose() {
    _player.dispose();
  }
}
