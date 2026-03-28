import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class HapticService {
  static bool _hasVibrator = false;
  static bool _initialized = false;
  
  static Future<void> init() async {
    if (_initialized) return;
    _hasVibrator = await Vibration.hasVibrator() ?? false;
    _initialized = true;
  }
  
  // Light feedback for drawing
  static Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }
  
  // Medium feedback for button taps
  static Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }
  
  // Heavy feedback for important actions
  static Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }
  
  // Selection feedback
  static Future<void> selectionClick() async {
    await HapticFeedback.selectionClick();
  }
  
  // Vibration for entering enemy territory
  static Future<void> enemyTerritoryVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 100, 50, 100, 50, 200],
        intensities: [0, 128, 0, 128, 0, 255],
      );
    } else {
      await HapticFeedback.heavyImpact();
    }
  }
  
  // Success vibration
  static Future<void> successVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(duration: 100);
    } else {
      await HapticFeedback.mediumImpact();
    }
  }
  
  // Warning vibration
  static Future<void> warningVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(pattern: [0, 50, 50, 50]);
    } else {
      await HapticFeedback.heavyImpact();
    }
  }
  
  // Drawing feedback - very light
  static Future<void> drawingFeedback() async {
    await HapticFeedback.selectionClick();
  }

  // Win vibration — long triumphant pulse
  static Future<void> winVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 200, 100, 200, 100, 500],
        intensities: [0, 200, 0, 200, 0, 255],
      );
    } else {
      await HapticFeedback.heavyImpact();
    }
  }

  // Lose vibration — short sad pattern
  static Future<void> loseVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 400, 100, 200],
        intensities: [0, 255, 0, 128],
      );
    } else {
      await HapticFeedback.heavyImpact();
    }
  }

  // Enemy dominating (≥60%) — intermittent warning
  static Future<void> enemyDominatingVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 80, 80, 80, 80, 80],
        intensities: [0, 200, 0, 200, 0, 200],
      );
    } else {
      await HapticFeedback.mediumImpact();
    }
  }

  // Enemy erasing your drawing — aggressive intermittent
  static Future<void> enemyEraseVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 50, 30, 50, 30, 50],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    } else {
      await HapticFeedback.heavyImpact();
    }
  }

  // Level up — celebratory pattern
  static Future<void> levelUpVibration() async {
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 100, 50, 100, 50, 100, 50, 300],
        intensities: [0, 128, 0, 180, 0, 220, 0, 255],
      );
    } else {
      await HapticFeedback.mediumImpact();
    }
  }
}
