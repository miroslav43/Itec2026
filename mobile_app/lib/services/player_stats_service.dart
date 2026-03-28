import 'package:shared_preferences/shared_preferences.dart';

class PlayerStatsService {
  static const _keyXp = 'player_xp';
  static const _keyWins = 'player_wins';
  static const _keyLosses = 'player_losses';
  static const _keyStrokes = 'player_strokes';
  static const _keyLastBattle = 'player_last_battle_';

  // ── XP values ──────────────────────────────────────────────
  static const int xpPerWin = 100;
  static const int xpPerLoss = 25;
  static const int xpPerLevel = 200;
  // Stroke XP: +1 XP every 10 strokes (throttled)
  static const int strokesPerXp = 10;
  // Minimum minutes between recording a result for the same poster
  static const int battleCooldownMinutes = 5;

  // ── Cached values ──────────────────────────────────────────
  static int _xp = 0;
  static int _wins = 0;
  static int _losses = 0;
  static int _strokes = 0;
  static bool _loaded = false;

  // Session-based set: poster IDs whose result was already recorded this session
  static final Set<String> _settledThisSession = {};
  // Stroke counter per session (not persisted — resets on restart)
  static int _strokesSinceLastXp = 0;

  // ── Getters ────────────────────────────────────────────────
  static int get xp => _xp;
  static int get wins => _wins;
  static int get losses => _losses;
  static int get strokes => _strokes;

  static int get level => 1 + (_xp ~/ xpPerLevel);
  static int get xpInCurrentLevel => _xp % xpPerLevel;
  static double get levelProgress => xpInCurrentLevel / xpPerLevel;

  /// Brush size driven by level (no manual selection)
  static double get brushSizeForLevel {
    final lvl = level;
    if (lvl <= 1) return 4.0;
    if (lvl == 2) return 6.0;
    if (lvl == 3) return 9.0;
    if (lvl == 4) return 12.0;
    if (lvl == 5) return 16.0;
    if (lvl == 6) return 20.0;
    if (lvl == 7) return 25.0;
    if (lvl == 8) return 30.0;
    if (lvl == 9) return 35.0;
    return 40.0; // level 10+
  }

  // ── Lifecycle ──────────────────────────────────────────────
  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _xp = prefs.getInt(_keyXp) ?? 0;
    _wins = prefs.getInt(_keyWins) ?? 0;
    _losses = prefs.getInt(_keyLosses) ?? 0;
    _strokes = prefs.getInt(_keyStrokes) ?? 0;
    _loaded = true;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyXp, _xp);
    await prefs.setInt(_keyWins, _wins);
    await prefs.setInt(_keyLosses, _losses);
    await prefs.setInt(_keyStrokes, _strokes);
  }

  // ── Update methods ─────────────────────────────────────────

  /// Returns true if this poster battle can be recorded (not already settled this session
  /// AND the cooldown since last battle on this poster has passed).
  static Future<bool> canRecordResult(String posterId) async {
    // Already settled in this app session — reject
    if (_settledThisSession.contains(posterId)) return false;
    // Check persisted cooldown
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt('$_keyLastBattle$posterId') ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
    return elapsed >= battleCooldownMinutes * 60 * 1000;
  }

  /// Call when player wins or loses a battle.
  /// Returns null if the result was NOT recorded (cooldown / already counted).
  static Future<({int xpGained, bool leveledUp})?> recordResult(
      bool won, String posterId) async {
    if (!await canRecordResult(posterId)) return null;

    final levelBefore = level;
    final xpGained = won ? xpPerWin : xpPerLoss;
    _xp += xpGained;
    if (won) {
      _wins++;
    } else {
      _losses++;
    }
    _settledThisSession.add(posterId);
    final leveledUp = level > levelBefore;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        '$_keyLastBattle$posterId', DateTime.now().millisecondsSinceEpoch);
    await _save();
    return (xpGained: xpGained, leveledUp: leveledUp);
  }

  /// Call every time a stroke is completed.
  /// XP is only awarded every [strokesPerXp] strokes (throttled).
  /// Returns true if XP was actually awarded this call.
  static Future<bool> recordStroke() async {
    _strokes++;
    _strokesSinceLastXp++;
    if (_strokesSinceLastXp >= strokesPerXp) {
      _strokesSinceLastXp = 0;
      _xp += 1;
      await _save();
      return true;
    }
    return false;
  }
}
