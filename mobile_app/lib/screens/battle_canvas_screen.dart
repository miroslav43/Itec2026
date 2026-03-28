import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/drawing_provider.dart';
import '../models/stroke_model.dart';
import '../models/poster_model.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/drawing_toolbar.dart';
import '../widgets/user_count_badge.dart';

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
    };
    
    socketProvider.onTerritoryUpdate = (territory) {
      appState.setTerritory(territory);
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
  }
  
  void _leaveRoom() {
    final socketProvider = context.read<SocketProvider>();
    final drawingProvider = context.read<DrawingProvider>();
    
    socketProvider.leaveRoom();
    drawingProvider.reset();
    Navigator.of(context).pop();
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
