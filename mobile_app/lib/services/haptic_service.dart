import 'package:flutter/services.dart';

class HapticService {
  static bool _initialized = false;
  
  static Future<void> init() async {
    if (_initialized) return;
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
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.heavyImpact();
  }
  
  // Success vibration
  static Future<void> successVibration() async {
    await HapticFeedback.mediumImpact();
  }
  
  // Warning vibration
  static Future<void> warningVibration() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.heavyImpact();
  }
  
  // Drawing feedback - very light
  static Future<void> drawingFeedback() async {
    await HapticFeedback.selectionClick();
  }

  // Win vibration — long triumphant pulse
  static Future<void> winVibration() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
  }

  // Lose vibration — short sad pattern
  static Future<void> loseVibration() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await HapticFeedback.mediumImpact();
  }

  // Enemy dominating (≥60%) — intermittent warning
  static Future<void> enemyDominatingVibration() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }

  // Enemy erasing your drawing — aggressive intermittent
  static Future<void> enemyEraseVibration() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.heavyImpact();
  }

  // Level up — celebratory pattern
  static Future<void> levelUpVibration() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.heavyImpact();
  }
}
