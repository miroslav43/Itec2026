import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/drawing_provider.dart';
import '../models/stroke_model.dart';
import '../models/poster_model.dart';
import '../services/anthem_service.dart';
import '../services/audio_service.dart';
import '../services/esp32_service.dart';
import '../services/haptic_service.dart';
import '../services/player_stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/drawing_toolbar.dart';
import '../widgets/player_badge.dart';
import '../widgets/user_count_badge.dart';
import 'ar_scan_screen.dart';
import 'sticker_generator_screen.dart';
import '../models/sticker_model.dart';

class BattleCanvasScreen extends StatefulWidget {
  final String posterId;
  final String? posterName;
  final String? posterImageUrl;
  
  const BattleCanvasScreen({
    super.key,
    required this.posterId,
    this.posterName,
    this.posterImageUrl,
  });

  @override
  State<BattleCanvasScreen> createState() => _BattleCanvasScreenState();
}

class _BattleCanvasScreenState extends State<BattleCanvasScreen> {
  bool _isJoined = false;
  bool _showToolbar = true;
  bool _battleEnded = false;
  bool _won = false;
  int _xpGained = 0;
  bool _leveledUp = false;
  bool _exportingAR = false;
  PlacedSticker? _draggingSticker;

  // ── Glitch state ──────────────────────────────────────────────────────────
  final Map<String, DateTime> _recentStrokeTeams = {};
  final ValueNotifier<bool> _glitchNotifier = ValueNotifier<bool>(false);
  Timer? _glitchCheckTimer;

  // ── ESP32 controller state ─────────────────────────────────────────────────
  Offset _esp32Cursor = const Offset(0.5, 0.5); // normalized 0-1
  bool _esp32Spraying = false;
  Timer? _esp32SprayTimer;
  StreamSubscription<Esp32Command>? _esp32Sub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _accX = 0, _accZ = 0;

  // Joystick direction → color + LED
  static const _joyColors = {
    Esp32Command.left:  Color(0xFFFF0040), // red
    Esp32Command.right: Color(0xFF00D4FF), // blue
    Esp32Command.up:    Color(0xFF00FF88), // green
    Esp32Command.down:  Color(0xFFFFE600), // yellow
  };
  
  @override
  void initState() {
    super.initState();
    _joinRoom();
    _connectEsp32();
  }

  void _connectEsp32() {
    _esp32Sub = Esp32Service().commands.listen(_handleEsp32Command);
  }

  @override
  void dispose() {
    _esp32SprayTimer?.cancel();
    _esp32Sub?.cancel();
    _accelSub?.cancel();
    _glitchCheckTimer?.cancel();
    _glitchNotifier.dispose();
    AnthemService().stop();
    super.dispose();
  }

  void _recordTeamActivity(String teamId) {
    if (teamId.isEmpty || _battleEnded) return;
    _recentStrokeTeams[teamId] = DateTime.now();
    _updateGlitchState();
    _glitchCheckTimer?.cancel();
    _glitchCheckTimer = Timer(const Duration(seconds: 3), _updateGlitchState);
  }

  void _updateGlitchState() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 2));
    _recentStrokeTeams.removeWhere((_, t) => t.isBefore(cutoff));
    final should = _recentStrokeTeams.length >= 2;
    if (_glitchNotifier.value != should) _glitchNotifier.value = should;
  }

  void _handleEsp32Command(Esp32Command cmd) {
    if (_battleEnded) return;
    // Joystick direction → pick color + light ESP32 LED
    final color = _joyColors[cmd];
    if (color != null) {
      context.read<DrawingProvider>().setColor(color);
      Esp32Service().sendColor(color.red, color.green, color.blue);
      if (mounted) setState(() {});
      return;
    }
    switch (cmd) {
      case Esp32Command.sprayStart:
        _startEsp32Spray();
      case Esp32Command.sprayStop:
        _stopEsp32Spray();
      default:
        break;
    }
  }

  void _startEsp32Spray() {
    if (_esp32Spraying) return;
    _esp32Spraying = true;
    final dp = context.read<DrawingProvider>();
    dp.startDrawing(StrokePoint(x: _esp32Cursor.dx, y: _esp32Cursor.dy));

    // Accelerometer → cursor velocity (tilt phone to aim)
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 40),
    ).listen((e) {
      _accX = e.x;  // tilt stânga/dreapta  (phone vertical)
      _accZ = e.z;  // tilt sus/jos         (phone vertical, z iese din ecran)
    });

    AudioService.startSpraySound();

    // Every 40 ms: move cursor by accel + scatter spray points
    final rng = math.Random();
    _esp32SprayTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!_esp32Spraying || !mounted) return;
      const speed = 0.007;
      const scatter = 0.022; // spray scatter radius (normalized)
      setState(() {
        _esp32Cursor = Offset(
          (_esp32Cursor.dx + _accX * speed).clamp(0.0, 1.0),
          (_esp32Cursor.dy - _accZ * speed).clamp(0.0, 1.0),
        );
      });
      final dp = context.read<DrawingProvider>();
      // Centre point
      dp.addPoint(StrokePoint(x: _esp32Cursor.dx, y: _esp32Cursor.dy));
      // Scattered satellite points (spray effect)
      for (int i = 0; i < 5; i++) {
        final angle = rng.nextDouble() * 2 * math.pi;
        final dist  = rng.nextDouble() * scatter;
        dp.addPoint(StrokePoint(
          x: (_esp32Cursor.dx + math.cos(angle) * dist).clamp(0.0, 1.0),
          y: (_esp32Cursor.dy + math.sin(angle) * dist).clamp(0.0, 1.0),
        ));
      }
    });
  }

  void _stopEsp32Spray() {
    if (!_esp32Spraying) return;
    _esp32Spraying = false;
    _esp32SprayTimer?.cancel();
    _accelSub?.cancel();
    _accelSub = null;
    _accX = 0;
    _accZ = 0;
    AudioService.stopSpraySound();
    final appState = context.read<AppStateProvider>();
    final dp = context.read<DrawingProvider>();
    final stroke = dp.endDrawing(appState.oderId, appState.teamId);
    if (stroke != null) _handleStrokeComplete(stroke);
  }
  
  void _joinRoom() {
    final appState = context.read<AppStateProvider>();
    final socketProvider = context.read<SocketProvider>();
    final drawingProvider = context.read<DrawingProvider>();
    
    // Setup callbacks
    socketProvider.onStrokeReceived = (stroke) {
      drawingProvider.addRemoteStroke(stroke);
      _recordTeamActivity(stroke.teamId);
      // Haptic + sound when enemy erases in real time
      if (stroke.isEraser && stroke.teamId != appState.teamId) {
        HapticService.enemyEraseVibration();
        AudioService.playEnemyEraseSound();
      }
    };
    
    socketProvider.onTerritoryUpdate = (territory) {
      appState.setTerritory(territory);
      appState.updatePosterTerritory(widget.posterId, territory);
      if (!_battleEnded) _checkWinCondition(territory, appState.teamId);
    };
    
    socketProvider.onUserCountChanged = (count) {
      appState.setUserCount(count);
    };
    
    socketProvider.onRoomJoined = () {
      setState(() => _isJoined = true);
      drawingProvider.setStrokes(socketProvider.strokes);
      if (socketProvider.territory != null) {
        appState.setTerritory(socketProvider.territory!);
      }
      HapticService.successVibration();
    };

    socketProvider.onCanvasCleared = () {
      drawingProvider.clearLocalStrokes();
      appState.setTerritory(Territory(teams: {}));
    };
    
    // Join the room
    socketProvider.joinRoom(
      widget.posterId,
      appState.oderId,
      appState.teamId,
      appState.username,
    );
  }
  
  void _handleStrokeComplete(Stroke stroke) {
    final socketProvider = context.read<SocketProvider>();
    socketProvider.sendStroke(stroke);
    PlayerStatsService.recordStroke();
    if (!stroke.isEraser) AudioService.playDrawStrokeSound();
    _recordTeamActivity(stroke.teamId);
  }

  Future<void> _checkWinCondition(Territory territory, String myTeamId) async {
    for (final entry in territory.teams.entries) {
      if (entry.value.percentage >= 60) {
        // Mark battle ended immediately to stop re-triggers
        setState(() => _battleEnded = true);
        final isWinner = entry.key == myTeamId;

        // recordResult returns null if already counted (cooldown/session guard)
        final result = await PlayerStatsService.recordResult(isWinner, widget.posterId);
        if (!mounted) return;

        setState(() {
          _won = isWinner;
          _xpGained = result?.xpGained ?? 0;
          _leveledUp = result?.leveledUp ?? false;
        });

        if (isWinner) {
          AudioService.playWinSound();
          HapticService.winVibration();
          // Play own team's anthem on conquest
          final serverUrl = context.read<SocketProvider>().serverUrl;
          AnthemService().playCelebrationAnthem(
            serverUrl: serverUrl,
            teamId: myTeamId,
          );
        } else {
          AudioService.playLoseSound();
          HapticService.loseVibration();
        }
        if (result?.leveledUp == true) {
          context.read<DrawingProvider>().syncBrushToLevel();
          await Future.delayed(const Duration(milliseconds: 800));
          AudioService.playLevelUpSound();
          HapticService.levelUpVibration();
        }
        return;
      }
    }

    // Warn player when enemy team is close to winning (≥60%)
    for (final entry in territory.teams.entries) {
      if (entry.key != myTeamId && entry.value.percentage >= 40) {
        HapticService.enemyDominatingVibration();
        break;
      }
    }
  }
  
  Future<void> _leaveRoom() async {
    // Auto-save canvas so AR scan can use it even when accessed from outside battle
    await _exportCanvas();
    if (!mounted) return;
    final socketProvider = context.read<SocketProvider>();
    final drawingProvider = context.read<DrawingProvider>();
    socketProvider.leaveRoom();
    drawingProvider.reset();
    Navigator.of(context).pop();
  }

  /// Composes poster + strokes into a PNG using PictureRecorder (no widget render dependency).
  Future<String?> _exportCanvas() async {
    try {
      const exportW = 1024.0;
      const exportH = 1024.0;
      const exportSize = Size(exportW, exportH);

      // Load poster image bytes
      ui.Image posterImage;
      if (widget.posterImageUrl != null) {
        final resp = await http.get(Uri.parse(widget.posterImageUrl!));
        final codec = await ui.instantiateImageCodec(resp.bodyBytes);
        final frame = await codec.getNextFrame();
        posterImage = frame.image;
      } else {
        final data = await rootBundle.load(
            'assets/posters/${widget.posterId}.png');
        final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        posterImage = frame.image;
      }

      // Compose into a Picture
      final recorder = ui.PictureRecorder();
      final canvas   = Canvas(recorder,
          Rect.fromLTWH(0, 0, exportW, exportH));

      // Draw poster filling full export area — no letterboxing
      canvas.drawImageRect(
        posterImage,
        Rect.fromLTWH(0, 0,
            posterImage.width.toDouble(), posterImage.height.toDouble()),
        Rect.fromLTWH(0, 0, exportW, exportH),
        Paint(),
      );

      // Draw strokes on top (normalized coords map correctly to any size)
      final dp = context.read<DrawingProvider>();
      CanvasPainter(
        strokes:       dp.localStrokes,
        currentPoints: dp.currentPoints,
        currentColor:  dp.currentColor,
        currentSize:   dp.brushSize,
        isEraserMode:  dp.isEraserMode,
        canvasSize:    exportSize,
      ).paint(canvas, exportSize);

      // Draw placed stickers on top
      for (final ps in dp.placedStickers) {
        try {
          final codec = await ui.instantiateImageCodec(ps.imageBytes);
          final frame = await codec.getNextFrame();
          final stickerImg = frame.image;
          final sz = 80.0 * ps.scale * (exportW / 400.0);
          final dx = ps.x * exportW - sz / 2;
          final dy = ps.y * exportH - sz / 2;
          canvas.drawImageRect(
            stickerImg,
            Rect.fromLTWH(0, 0,
                stickerImg.width.toDouble(), stickerImg.height.toDouble()),
            Rect.fromLTWH(dx, dy, sz, sz),
            Paint(),
          );
          stickerImg.dispose();
        } catch (_) {}
      }

      final picture = recorder.endRecording();
      final image   = await picture.toImage(
          exportW.toInt(), exportH.toInt());
      final bytes   = await image.toByteData(
          format: ui.ImageByteFormat.png);
      if (bytes == null) return null;

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/ar_texture_${widget.posterId}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      debugPrint('[BattleCanvas] AR texture saved: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[BattleCanvas] export error: $e');
      return null;
    }
  }

  Future<void> _openStickerScreen() async {
    final result = await Navigator.push<StickerItem>(
      context,
      MaterialPageRoute(builder: (_) => const StickerGeneratorScreen()),
    );
    if (result == null || !mounted) return;
    final dp = context.read<DrawingProvider>();
    final placed = PlacedSticker(
      uid: result.id + '_${DateTime.now().millisecondsSinceEpoch}',
      stickerId: result.id,
      prompt: result.prompt,
      imageBytes: result.imageBytes,
      x: 0.5,
      y: 0.5,
    );
    setState(() => _draggingSticker = placed);
  }

  void _reconquer() {
    final dp = context.read<DrawingProvider>();
    dp.clearLocalStrokes();
    setState(() {
      _battleEnded = false;
      _won = false;
      _xpGained = 0;
      _leveledUp = false;
    });
  }

  void _confirmStickerPlacement() {
    if (_draggingSticker == null) return;
    final dp = context.read<DrawingProvider>();
    dp.addPlacedSticker(_draggingSticker!);
    setState(() => _draggingSticker = null);
  }

  Future<void> _viewAR() async {
    setState(() => _exportingAR = true);
    final texturePath = await _exportCanvas();
    if (!mounted) return;
    setState(() => _exportingAR = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArScanScreen(
          targetPosterId: widget.posterId,
          textureFilePath: texturePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final socketProvider = context.watch<SocketProvider>();
    final poster = appState.posters[widget.posterId];
    final displayName = widget.posterName ?? poster?.name ?? widget.posterId;
    
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // Drawing canvas + glitch wrapper
          Positioned.fill(
            child: _GlitchWrapper(
              glitchNotifier: _glitchNotifier,
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _showToolbar = !_showToolbar),
                    child: DrawingCanvas(
                      posterId: widget.posterId,
                      posterImageUrl: widget.posterImageUrl,
                      onStrokeComplete: _handleStrokeComplete,
                    ),
                  ),
                  if (Esp32Service().isConnected)
                    _SprayCursor(
                      normalizedPos: _esp32Cursor,
                      active: _esp32Spraying,
                      color: context.watch<DrawingProvider>().currentColor,
                    ),
                ],
              ),
            ),
          ),
          
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: AnimatedOpacity(
                opacity: _showToolbar ? 1.0 : 0.3,
                duration: const Duration(milliseconds: 200),
                child: _buildTopBar(displayName, socketProvider.isConnected),
              ),
            ),
          ),
          
          // Live score bar (always visible)
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 12,
            right: 12,
            child: _LiveScoreBar(
              territory: appState.territory,
              myTeamId: appState.teamId,
            ),
          ),

          // User count
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: UserCountBadge(count: appState.userCount),
          ),

          // Player badge (level + trophies)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 80,
            child: PlayerBadge(),
          ),

          // Win / Lose overlay
          if (_battleEnded)
            Positioned.fill(
              child: _BattleResultOverlay(
                won: _won,
                xpGained: _xpGained,
                leveledUp: _leveledUp,
                newLevel: PlayerStatsService.level,
                onClose: _leaveRoom,
                onReconquer: _won ? null : _reconquer,
              ),
            ),
          
          // Loading overlay
          if (!_isJoined)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [AppTheme.darkBgTertiary, AppTheme.darkBg],
                    radius: 1.2,
                  ),
                ),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 44, height: 44,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppTheme.gold)),
                    const SizedBox(height: 22),
                    Text('⚔  INTRARE ÎN LUPTĂ  ⚔',
                        style: AppTheme.neonTextStyle(
                            color: AppTheme.gold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Pregătește-ți armele, luptătorule...',
                        style: AppTheme.cinzel(
                            fontSize: 11,
                            color: AppTheme.parchment.withOpacity(0.5),
                            letterSpacing: 1, weight: FontWeight.normal)),
                  ]),
                ),
              ),
            ),
          
          // Drawing toolbar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: AnimatedSlide(
                offset: _showToolbar ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 200),
                child: const DrawingToolbar(),
              ),
            ),
          ),

          // Draggable sticker overlay
          if (_draggingSticker != null)
            _DraggableStickerOverlay(
              sticker: _draggingSticker!,
              onPositionChanged: (x, y) {
                setState(() {
                  _draggingSticker!.x = x;
                  _draggingSticker!.y = y;
                });
              },
              onConfirm: _confirmStickerPlacement,
              onCancel: () => setState(() => _draggingSticker = null),
            ),
        ],
      ),
    );
  }
  
  Widget _buildTopBar(String posterName, bool isConnected) {
    final accent = isConnected ? AppTheme.neonGreen : AppTheme.neonRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.darkBg, AppTheme.darkBg.withOpacity(0)],
        ),
      ),
      child: Row(children: [
        // ── Back ──
        GestureDetector(
          onTap: () { HapticService.mediumImpact(); _leaveRoom(); },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: AppTheme.neonBoxDecoration(
                color: AppTheme.neonPink, borderRadius: 4, glowIntensity: 0.25),
            child: const Icon(Icons.arrow_back, color: AppTheme.neonPink, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        // ── Poster name ──
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚔  CÂMPUL BĂTĂLIEI',
                style: AppTheme.cinzel(
                    fontSize: 8, color: AppTheme.gold.withOpacity(0.55),
                    letterSpacing: 2)),
            Text(posterName.toUpperCase(),
                style: AppTheme.neonTextStyle(color: AppTheme.gold, fontSize: 14),
                overflow: TextOverflow.ellipsis),
          ],
        )),
        // ── Stickers ──
        GestureDetector(
          onTap: _openStickerScreen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            margin: const EdgeInsets.only(right: 6),
            decoration: AppTheme.neonBoxDecoration(
                color: AppTheme.neonPurple, borderRadius: 4, glowIntensity: 0.2),
            child: Text('🏷 BLAZOANE',
                style: AppTheme.cinzel(
                    fontSize: 9, color: AppTheme.neonPurple, letterSpacing: 1)),
          ),
        ),
        // ── View AR ──
        GestureDetector(
          onTap: _exportingAR ? null : _viewAR,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: AppTheme.neonBoxDecoration(
                color: AppTheme.gold, borderRadius: 4, glowIntensity: 0.35),
            child: _exportingAR
                ? SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold))
                : Text('🗺 HARTA AR',
                    style: AppTheme.cinzel(
                        fontSize: 9, color: AppTheme.gold, letterSpacing: 1)),
          ),
        ),
        const SizedBox(width: 6),
        // ── Connection dot ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accent.withOpacity(0.5), width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: accent,
                    boxShadow: [BoxShadow(color: accent.withOpacity(0.5), blurRadius: 5)])),
            const SizedBox(width: 5),
            Text(isConnected ? 'VIU' : 'MORT',
                style: AppTheme.cinzel(
                    fontSize: 9, color: accent, letterSpacing: 1)),
          ]),
        ),
      ]),
    );
  }
}

// ── Draggable Sticker Overlay ─────────────────────────────────────────────────

class _DraggableStickerOverlay extends StatefulWidget {
  final PlacedSticker sticker;
  final void Function(double x, double y) onPositionChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _DraggableStickerOverlay({
    required this.sticker,
    required this.onPositionChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_DraggableStickerOverlay> createState() =>
      _DraggableStickerOverlayState();
}

class _DraggableStickerOverlayState extends State<_DraggableStickerOverlay> {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const stickerSize = 80.0;
    final left = widget.sticker.x * size.width - stickerSize / 2;
    final top  = widget.sticker.y * size.height - stickerSize / 2;

    return Positioned.fill(
      child: Stack(
        children: [
          // Semi-transparent instruction banner
          Positioned(
            top: 80,
            left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.neonPurple.withOpacity(0.5)),
                ),
                child: Text('Drag sticker-ul, apoi apasă ✓',
                    style: TextStyle(
                        color: AppTheme.neonPurple, fontSize: 13)),
              ),
            ),
          ),

          // Sticker — draggable via GestureDetector
          Positioned(
            left: left,
            top: top,
            child: GestureDetector(
              onPanUpdate: (d) {
                final nx = ((widget.sticker.x * size.width + d.delta.dx) /
                        size.width)
                    .clamp(0.05, 0.95);
                final ny = ((widget.sticker.y * size.height + d.delta.dy) /
                        size.height)
                    .clamp(0.05, 0.95);
                widget.onPositionChanged(nx, ny);
              },
              child: Container(
                width: stickerSize,
                height: stickerSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.neonPurple, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.neonPurple.withOpacity(0.5),
                        blurRadius: 12),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(widget.sticker.imageBytes,
                      fit: BoxFit.cover),
                ),
              ),
            ),
          ),

          // Confirm (✓) button — top-right of sticker
          Positioned(
            left: left + stickerSize - 4,
            top:  top - 4,
            child: GestureDetector(
              onTap: widget.onConfirm,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.neonGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.neonGreen.withOpacity(0.6),
                        blurRadius: 8),
                  ],
                ),
                child: const Icon(Icons.check,
                    color: Colors.black, size: 20),
              ),
            ),
          ),

          // Cancel (✕) button — top-left of sticker
          Positioned(
            left: left - 16,
            top:  top - 4,
            child: GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.neonRed.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Win/Lose Overlay ─────────────────────────────────────────────────────────

class _BattleResultOverlay extends StatefulWidget {
  final bool won;
  final int xpGained;
  final bool leveledUp;
  final int newLevel;
  final VoidCallback onClose;
  final VoidCallback? onReconquer;

  const _BattleResultOverlay({
    required this.won,
    required this.xpGained,
    required this.leveledUp,
    required this.newLevel,
    required this.onClose,
    this.onReconquer,
  });

  @override
  State<_BattleResultOverlay> createState() => _BattleResultOverlayState();
}

class _BattleResultOverlayState extends State<_BattleResultOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color   = widget.won ? AppTheme.neonGreen : AppTheme.neonRed;
    final emoji   = widget.won ? '🏆' : '💀';
    final title   = widget.won ? 'GLORIA VICTORIEI' : 'ONOAREA CĂZUTĂ';
    final subtitle = widget.won
        ? 'Ai cucerit 80% din afiș! Stema ta domină cetatea!'
        : 'Inamicul a cucerit 80% din afiș. Recucerește ce ți-a fost luat!';

    return FadeTransition(
      opacity: _fade,
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.4,
            colors: [
              color.withOpacity(0.08),
              Colors.black.withOpacity(0.88),
            ],
          ),
        ),
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(28),
              decoration: AppTheme.panelDecoration(borderColor: color),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Decorative top
                Text('✦  ${widget.won ? "⚔" : "💀"}  ✦',
                    style: TextStyle(fontSize: 28, color: color,
                        shadows: [Shadow(color: color, blurRadius: 14)])),
                const SizedBox(height: 10),
                Text(title,
                    textAlign: TextAlign.center,
                    style: AppTheme.cinzel(
                        fontSize: 22, color: color, letterSpacing: 3,
                        shadows: [Shadow(color: color, blurRadius: 14),
                                  Shadow(color: color.withOpacity(0.4), blurRadius: 28)])),
                const SizedBox(height: 10),
                Text(AppTheme.divider,
                    style: TextStyle(color: AppTheme.gold.withOpacity(0.5), fontSize: 14)),
                const SizedBox(height: 8),
                Text(subtitle,
                    style: AppTheme.cinzel(fontSize: 11,
                        color: AppTheme.parchment.withOpacity(0.75),
                        letterSpacing: 0.8, weight: FontWeight.normal),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                // XP badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: AppTheme.panelDecoration(borderColor: AppTheme.gold),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('⚔', style: TextStyle(fontSize: 16, color: AppTheme.goldBright)),
                    const SizedBox(width: 8),
                    Text('+${widget.xpGained} XP',
                        style: AppTheme.cinzel(
                            fontSize: 18, color: AppTheme.goldBright, letterSpacing: 2,
                            shadows: [Shadow(color: AppTheme.gold, blurRadius: 10)])),
                  ]),
                ),
                if (widget.leveledUp) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: AppTheme.panelDecoration(borderColor: AppTheme.neonGreen),
                    child: Text('⬆ RANG NOU — NVL ${widget.newLevel}!',
                        style: AppTheme.cinzel(
                            fontSize: 12, color: AppTheme.neonGreen, letterSpacing: 1.5,
                            shadows: [Shadow(color: AppTheme.neonGreen, blurRadius: 8)])),
                  ),
                ],
                const SizedBox(height: 24),
                if (!widget.won && widget.onReconquer != null) ...[
                  SizedBox(width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.crimson.withOpacity(0.35),
                        foregroundColor: AppTheme.goldBright,
                        side: BorderSide(color: AppTheme.gold.withOpacity(0.7), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      onPressed: widget.onReconquer,
                      child: Text('⚔  RECUCEREȘTE',
                          style: AppTheme.cinzel(fontSize: 13, color: AppTheme.goldBright, letterSpacing: 2)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color.withOpacity(0.15),
                      foregroundColor: color,
                      side: BorderSide(color: color.withOpacity(0.6), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: widget.onClose,
                    child: Text('RETRAGE-TE',
                        style: AppTheme.cinzel(fontSize: 13, color: color, letterSpacing: 2)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── ESP32 Spray Cursor ────────────────────────────────────────────────────────

class _SprayCursor extends StatefulWidget {
  final Offset normalizedPos;
  final bool active;
  final Color color;

  const _SprayCursor({
    required this.normalizedPos,
    required this.active,
    required this.color,
  });

  @override
  State<_SprayCursor> createState() => _SprayCursorState();
}

class _SprayCursorState extends State<_SprayCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (ctx, box) {
          final cx = widget.normalizedPos.dx * box.maxWidth;
          final cy = widget.normalizedPos.dy * box.maxHeight;
          const size = 72.0;
          return AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Stack(children: [
              Positioned(
                left: cx - size / 2,
                top: cy - size / 2,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: _SprayCursorPainter(
                    active: widget.active,
                    color: widget.color,
                    pulse: _anim.value,
                  ),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

class _SprayCursorPainter extends CustomPainter {
  final bool active;
  final Color color;
  final double pulse; // 0.0 – 1.0

  _SprayCursorPainter({
    required this.active,
    required this.color,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rng = math.Random(7); // fixed seed → stable dot positions

    // ── Outer ring (pulsing when active) ──────────────────────────────────────
    final outerR = active ? 26.0 + pulse * 8.0 : 20.0;
    final ringPaint = Paint()
      ..color = color.withOpacity(active ? 0.55 + pulse * 0.25 : 0.35)
      ..strokeWidth = active ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    if (active) {
      // Dashed ring
      const segments = 12;
      const step = 2 * math.pi / segments;
      for (int i = 0; i < segments; i++) {
        if (i.isEven) continue;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: outerR),
          i * step, step, false, ringPaint,
        );
      }
    } else {
      canvas.drawCircle(Offset(cx, cy), outerR, ringPaint);
    }

    // ── Inner solid dot ───────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy),
      active ? 4.0 + pulse * 1.5 : 3.5,
      Paint()..color = Colors.white,
    );

    // ── Crosshair ─────────────────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx - 5, cy), linePaint);
    canvas.drawLine(Offset(cx + 5,  cy), Offset(cx + 12, cy), linePaint);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy - 5), linePaint);
    canvas.drawLine(Offset(cx, cy + 5),  Offset(cx, cy + 12), linePaint);

    // ── Spray particles (only when active) ────────────────────────────────────
    if (active) {
      final dotPaint = Paint()..style = PaintingStyle.fill;
      for (int i = 0; i < 22; i++) {
        final angle = rng.nextDouble() * 2 * math.pi;
        final dist  = (outerR * 0.4) + rng.nextDouble() * (outerR * 0.6);
        final opacity = ((1.0 - dist / outerR) * pulse * 0.85).clamp(0.0, 1.0);
        final dotR  = 0.9 + rng.nextDouble() * 2.2;
        dotPaint.color = color.withOpacity(opacity);
        canvas.drawCircle(
          Offset(cx + math.cos(angle) * dist, cy + math.sin(angle) * dist),
          dotR, dotPaint,
        );
      }

      // Glow behind centre
      canvas.drawCircle(
        Offset(cx, cy),
        8.0 + pulse * 6.0,
        Paint()
          ..color = color.withOpacity(0.18 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_SprayCursorPainter old) =>
      old.active != active || old.pulse != pulse || old.color != color;
}

// ── Live Score Bar ────────────────────────────────────────────────────────────

class _LiveScoreBar extends StatelessWidget {
  final Territory? territory;
  final String myTeamId;

  const _LiveScoreBar({required this.territory, required this.myTeamId});

  @override
  Widget build(BuildContext context) {
    final teams = territory?.teams ?? {};

    if (teams.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: AppTheme.panelDecoration(),
        child: Center(
          child: Text('Înfige-ți sabia în pământ și cucerește teritoriul!',
              style: AppTheme.cinzel(
                  fontSize: 10, color: AppTheme.parchment.withOpacity(0.35),
                  letterSpacing: 0.8, weight: FontWeight.normal)),
        ),
      );
    }

    final sorted = teams.entries.toList()
      ..sort((a, b) {
        if (a.key == myTeamId) return -1;
        if (b.key == myTeamId) return 1;
        return b.value.percentage.compareTo(a.value.percentage);
      });

    final totalClaimed = sorted.fold<int>(0, (s, e) => s + e.value.percentage);
    final unclaimed = (100 - totalClaimed).clamp(0, 100);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: AppTheme.panelDecoration(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(
          children: sorted.map((entry) {
            final isMe  = entry.key == myTeamId;
            final color = AppTheme.teamColors[entry.key] ?? AppTheme.gold;
            final pct   = entry.value.percentage;
            return Expanded(
              child: Text(
                isMe ? '⚔ TU $pct%' : '${entry.key.toUpperCase()} $pct%',
                textAlign: isMe ? TextAlign.start : TextAlign.end,
                style: AppTheme.cinzel(
                    fontSize: 11, color: color, letterSpacing: 1,
                    shadows: [Shadow(color: color, blurRadius: 6)]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 7,
            child: Row(children: [
              ...sorted.where((e) => e.value.percentage > 0).map((entry) =>
                Expanded(
                  flex: entry.value.percentage,
                  child: Container(
                    color: AppTheme.teamColors[entry.key] ?? AppTheme.gold,
                  ),
                )),
              if (unclaimed > 0)
                Expanded(flex: unclaimed,
                    child: Container(color: AppTheme.gold.withOpacity(0.08))),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Glitch Wrapper ────────────────────────────────────────────────────────────

class _GlitchWrapper extends StatefulWidget {
  final Widget child;
  final ValueNotifier<bool> glitchNotifier;

  const _GlitchWrapper({required this.child, required this.glitchNotifier});

  @override
  State<_GlitchWrapper> createState() => _GlitchWrapperState();
}

class _GlitchWrapperState extends State<_GlitchWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _rng = math.Random();
  Offset _shake = Offset.zero;
  double _tick = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..addListener(_onTick);
    widget.glitchNotifier.addListener(_onGlitchChanged);
  }

  @override
  void dispose() {
    widget.glitchNotifier.removeListener(_onGlitchChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onGlitchChanged() {
    if (widget.glitchNotifier.value) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
      if (mounted) setState(() { _shake = Offset.zero; _tick = 0; });
    }
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {
      _tick = _ctrl.value;
      _shake = Offset(
        (_rng.nextDouble() - 0.5) * 10,
        (_rng.nextDouble() - 0.5) * 5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final glitching = widget.glitchNotifier.value;
    return Stack(
      children: [
        Transform.translate(
          offset: _shake,
          child: widget.child,
        ),
        if (glitching)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlitchPainter(_rng, _tick),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Glitch Painter ────────────────────────────────────────────────────────────

class _GlitchPainter extends CustomPainter {
  final math.Random _rng;
  final double _tick;

  _GlitchPainter(this._rng, this._tick);

  @override
  void paint(Canvas canvas, Size size) {
    // Horizontal tear strips
    final tearPaint = Paint();
    for (int i = 0; i < 5; i++) {
      final y = _rng.nextDouble() * size.height;
      final h = 2.0 + _rng.nextDouble() * 10;
      final shift = (_rng.nextDouble() - 0.5) * 24;
      tearPaint.color = (i.isEven
              ? const Color(0x99FF0040)
              : const Color(0x990040FF))
          .withOpacity(0.3 + _rng.nextDouble() * 0.4);
      canvas.drawRect(Rect.fromLTWH(shift, y, size.width, h), tearPaint);
    }

    // Vertical RGB fringe lines
    final rx = _rng.nextDouble() * size.width;
    canvas.drawRect(
      Rect.fromLTWH(rx - 2, 0, 2, size.height),
      Paint()..color = const Color(0x44FF0000),
    );
    canvas.drawRect(
      Rect.fromLTWH(rx + 1, 0, 2, size.height),
      Paint()..color = const Color(0x440000FF),
    );

    // Scan-line vignette
    final scanPaint = Paint()..color = Colors.black.withOpacity(0.12);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanPaint);
    }

    // Full-screen flicker pulse (rare)
    if (_tick > 0.85) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withOpacity(0.04),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchPainter old) => true;
}
