import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/drawing_provider.dart';
import '../models/stroke_model.dart';
import '../models/poster_model.dart';
import '../services/audio_service.dart';
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
  
  @override
  void initState() {
    super.initState();
    _joinRoom();
  }
  
  void _joinRoom() {
    final appState = context.read<AppStateProvider>();
    final socketProvider = context.read<SocketProvider>();
    final drawingProvider = context.read<DrawingProvider>();
    
    // Setup callbacks
    socketProvider.onStrokeReceived = (stroke) {
      drawingProvider.addRemoteStroke(stroke);
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
          // Drawing canvas (full screen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                setState(() => _showToolbar = !_showToolbar);
              },
              child: DrawingCanvas(
                posterId: widget.posterId,
                posterImageUrl: widget.posterImageUrl,
                onStrokeComplete: _handleStrokeComplete,
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
                color: AppTheme.darkBg.withOpacity(0.8),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppTheme.neonCyan,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'JOINING BATTLE...',
                        style: AppTheme.neonTextStyle(
                          color: AppTheme.neonCyan,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.darkBg,
            AppTheme.darkBg.withOpacity(0),
          ],
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              HapticService.mediumImpact();
              _leaveRoom();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: AppTheme.neonBoxDecoration(
                color: AppTheme.neonPink,
                borderRadius: 8,
                glowIntensity: 0.3,
              ),
              child: const Icon(
                Icons.arrow_back,
                color: AppTheme.neonPink,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Poster name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BATTLE ZONE',
                  style: TextStyle(
                    color: AppTheme.neonCyan.withOpacity(0.7),
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  posterName.toUpperCase(),
                  style: AppTheme.neonTextStyle(
                    color: AppTheme.neonCyan,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Stickers button
          GestureDetector(
            onTap: _openStickerScreen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: AppTheme.neonBoxDecoration(
                color: AppTheme.neonPurple,
                borderRadius: 8,
                glowIntensity: 0.3,
              ),
              child: const Text('STICKERE',
                  style: TextStyle(
                      color: AppTheme.neonPurple,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
            ),
          ),

          // View AR button
          GestureDetector(
            onTap: _exportingAR ? null : _viewAR,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: AppTheme.neonBoxDecoration(
                color: AppTheme.neonCyan,
                borderRadius: 8,
                glowIntensity: 0.4,
              ),
              child: _exportingAR
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.neonCyan))
                  : const Text('VIEW AR',
                      style: TextStyle(
                          color: AppTheme.neonCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5)),
            ),
          ),
          const SizedBox(width: 8),

          // Connection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (isConnected ? AppTheme.neonGreen : AppTheme.neonRed).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected ? AppTheme.neonGreen : AppTheme.neonRed,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected ? AppTheme.neonGreen : AppTheme.neonRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isConnected ? AppTheme.neonGreen : AppTheme.neonRed).withOpacity(0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'LIVE' : 'OFFLINE',
                  style: TextStyle(
                    color: isConnected ? AppTheme.neonGreen : AppTheme.neonRed,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final color = widget.won ? AppTheme.neonGreen : AppTheme.neonRed;
    final emoji = widget.won ? '🏆' : '💀';
    final title = widget.won ? 'VICTORIE!' : 'ÎNFRÂNGERE';
    final subtitle = widget.won
        ? 'Ai cucerit 80% din afiș!'
        : 'Inamicul a cucerit 80% din afiș.';

    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black.withOpacity(0.82),
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppTheme.darkBgSecondary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color, width: 2),
                boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 30)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      shadows: [Shadow(color: color, blurRadius: 12)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.neonYellow.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.neonYellow.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: AppTheme.neonYellow, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '+${widget.xpGained} XP',
                          style: const TextStyle(
                            color: AppTheme.neonYellow,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.leveledUp) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.neonCyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.5)),
                      ),
                      child: Text(
                        '⬆ LEVEL UP → LVL ${widget.newLevel}!',
                        style: const TextStyle(
                          color: AppTheme.neonCyan,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (!widget.won && widget.onReconquer != null) ...[  
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text(
                          'LUPTĂ DIN NOU',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonCyan.withOpacity(0.15),
                          foregroundColor: AppTheme.neonCyan,
                          side: const BorderSide(color: AppTheme.neonCyan),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: widget.onReconquer,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color.withOpacity(0.2),
                        foregroundColor: color,
                        side: BorderSide(color: color),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: widget.onClose,
                      child: const Text(
                        'ÎNAPOI',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Text(
            'Incepe sa desenezi pentru a cuceri teritoriu!',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: sorted.map((entry) {
              final isMe = entry.key == myTeamId;
              final color = AppTheme.teamColors[entry.key] ?? AppTheme.neonCyan;
              final pct = entry.value.percentage;
              return Expanded(
                child: Text(
                  isMe ? 'TU $pct%' : '${entry.key.toUpperCase()} $pct%',
                  textAlign: isMe ? TextAlign.start : TextAlign.end,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: color, blurRadius: 8)],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  ...sorted.where((e) => e.value.percentage > 0).map((entry) {
                    return Expanded(
                      flex: entry.value.percentage,
                      child: Container(
                        color: AppTheme.teamColors[entry.key] ?? AppTheme.neonCyan,
                      ),
                    );
                  }),
                  if (unclaimed > 0)
                    Expanded(
                      flex: unclaimed,
                      child: Container(color: Colors.white12),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
