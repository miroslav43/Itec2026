import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../services/gpt_vision_service.dart';
import '../services/haptic_service.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../widgets/player_badge.dart';
import '../widgets/poster_selector_dialog.dart';
import '../widgets/team_selector.dart';
import '../widgets/connection_status.dart';
import 'battle_canvas_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isGptProcessing = false;
  String? _detectedPosterId;
  Timer? _gptTimer;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _initCamera();
  }
  
  Future<void> _initServices() async {
    await HapticService.init();
    await AudioService.init();
    if (mounted) {
      context.read<SocketProvider>().connect();
    }
  }
  
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('No cameras available');
        return;
      }
      
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      
      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
        _startGptTimer();
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }
  
  void _startGptTimer() {
    _gptTimer?.cancel();
    // No auto-scan — user triggers manually via SCAN button
  }

  Future<void> _runGptDetection() async {
    if (_isGptProcessing || _detectedPosterId != null) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _isGptProcessing = true;
    if (mounted) setState(() {});

    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      // Sync server URL to GptVisionService
      if (mounted) {
        GptVisionService.serverUrl =
            context.read<SocketProvider>().serverUrl;
      }

      final result = await GptVisionService.identifyPoster(bytes);

      if (result.posterId != null && mounted && _detectedPosterId == null) {
        setState(() => _detectedPosterId = result.posterId);
        HapticService.successVibration();
        AudioService.playPosterDetectedSound();
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && _detectedPosterId != null) {
          final pid = _detectedPosterId!;
          final imageUrl = pid.startsWith('custom_')
              ? '${GptVisionService.serverUrl}/custom-posters/$pid.jpg'
              : null;
          final customName = pid.startsWith('custom_')
              ? GptVisionService.getPosterName(pid)
              : null;
          _openBattleCanvas(pid, posterName: customName, posterImageUrl: imageUrl);
        }
      } else if (result.looksLikePoster && result.posterId == null && mounted) {
        _showAddPosterDialog(result.croppedBytes);
      }
    } catch (e) {
      debugPrint('GPT detection error: $e');
    }

    _isGptProcessing = false;
    if (mounted) setState(() {});
  }

  void _showAddPosterDialog(Uint8List? croppedBytes) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool saving = false; // outside builder so it persists across rebuilds
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.darkBgSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.neonCyan, width: 1),
            ),
            title: Text(
              'POSTER NOU DETECTAT',
              style: AppTheme.neonTextStyle(color: AppTheme.neonCyan, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (croppedBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        croppedBytes,
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nume afiș',
                      labelStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.neonCyan.withOpacity(0.4)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.neonCyan),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Descriere (optional)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.neonCyan.withOpacity(0.4)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.neonCyan),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ANULEAZĂ', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonCyan.withOpacity(0.2),
                  foregroundColor: AppTheme.neonCyan,
                ),
                onPressed: saving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        setDialogState(() => saving = true);
                        final id = await GptVisionService.saveCustomPoster(
                          name: name,
                          description: descCtrl.text.trim().isEmpty
                              ? name
                              : descCtrl.text.trim(),
                          imageBytes: croppedBytes ?? Uint8List(0),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (id != null && mounted) {
                          final imageUrl =
                              '${GptVisionService.serverUrl}/custom-posters/$id.jpg';
                          _openBattleCanvas(id,
                              posterName: name, posterImageUrl: imageUrl);
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.neonCyan,
                        ),
                      )
                    : const Text('ADAUGĂ ÎN BAZA DE DATE'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  void _openBattleCanvas(String posterId, {String? posterName, String? posterImageUrl}) {
    final appState = context.read<AppStateProvider>();
    appState.setCurrentPoster(posterId);
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BattleCanvasScreen(
          posterId: posterId,
          posterName: posterName,
          posterImageUrl: posterImageUrl,
        ),
      ),
    ).then((_) {
      setState(() => _detectedPosterId = null);
      appState.reset();
    });
  }
  
  void _showPosterSelector() {
    showDialog(
      context: context,
      builder: (context) => PosterSelectorDialog(
        onPosterSelected: (posterId) {
          Navigator.pop(context);
          _openBattleCanvas(posterId);
        },
      ),
    );
  }
  
  void _showTeamSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const TeamSelector(),
    );
  }

  void _showServerSettings() {
    final socketProvider = context.read<SocketProvider>();
    final controller = TextEditingController(text: 'http://10.27.252.100:3000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkBgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.neonPink, width: 1),
        ),
        title: Text('SERVER URL', style: AppTheme.neonTextStyle(color: AppTheme.neonPink, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'http://IP:3000',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.neonPink.withOpacity(0.5)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.neonPink),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Schimba IP-ul daca esti pe alta retea', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ANULEAZA', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonPink.withOpacity(0.2)),
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                socketProvider.setServerUrl(url);
                socketProvider.disconnect();
                socketProvider.connect();
              }
              Navigator.pop(ctx);
            },
            child: Text('CONECTEAZA', style: TextStyle(color: AppTheme.neonPink)),
          ),
        ],
      ),
    );
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _gptTimer?.cancel();
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }
  
  @override
  void dispose() {
    _gptTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // Camera preview
          if (_isInitialized && _cameraController != null)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(
              child: CircularProgressIndicator(
                color: AppTheme.neonCyan,
              ),
            ),
          
          // Scan overlay
          Positioned.fill(
            child: CustomPaint(
              painter: ScanOverlayPainter(
                isDetected: _detectedPosterId != null,
              ),
            ),
          ),
          
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildTopBar(),
            ),
          ),

          // Player badge — level + trophies
          Positioned(
            top: MediaQuery.of(context).padding.top + 52,
            left: 16,
            child: const PlayerBadge(),
          ),
          
          // Detection indicator
          if (_detectedPosterId != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.3,
              left: 0,
              right: 0,
              child: _buildDetectionIndicator(),
            ),
          
          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildBottomControls(),
            ),
          ),
          
          // AI scanning indicator
          if (_isGptProcessing)
            const Positioned(
              top: 80,
              right: 16,
              child: _GptScanningBadge(),
            ),

          // Instructions
          if (_detectedPosterId == null)
            Positioned(
              bottom: 180,
              left: 20,
              right: 20,
              child: _buildInstructions(),
            ),
        ],
      ),
    );
  }
  
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          Text(
            'iTEC',
            style: AppTheme.neonTextStyle(
              color: AppTheme.neonCyan,
              fontSize: 24,
            ),
          ),
          Text(
            'OVERRIDE',
            style: AppTheme.neonTextStyle(
              color: AppTheme.neonPink,
              fontSize: 24,
            ),
          ),
          // Connection status
          const ConnectionStatus(),
        ],
      ),
    );
  }
  
  Widget _buildDetectionIndicator() {
    final appState = context.read<AppStateProvider>();
    final posterName = appState.posters[_detectedPosterId]?.name ?? _detectedPosterId;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.neonBoxDecoration(
        color: AppTheme.neonGreen,
        glowIntensity: 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.neonGreen,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'POSTER DETECTED',
            style: AppTheme.neonTextStyle(
              color: AppTheme.neonGreen,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            posterName ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Entering battle...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkBgSecondary.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.neonCyan.withOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt,
                color: AppTheme.neonCyan.withOpacity(0.8),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'SCANEAZA POSTER',
                style: AppTheme.neonTextStyle(
                  color: AppTheme.neonCyan,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isGptProcessing
                ? 'AI analizeaza imaginea...'
                : 'Tine camera spre poster ~ 2s\nsau selecteaza manual mai jos',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Big SCAN button
          GestureDetector(
            onTap: _isGptProcessing ? null : () {
              HapticService.mediumImpact();
              _runGptDetection();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: _isGptProcessing
                    ? AppTheme.neonCyan.withOpacity(0.1)
                    : AppTheme.neonCyan.withOpacity(0.2),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _isGptProcessing
                      ? AppTheme.neonCyan.withOpacity(0.4)
                      : AppTheme.neonCyan,
                  width: 2,
                ),
                boxShadow: _isGptProcessing
                    ? null
                    : [
                        BoxShadow(
                          color: AppTheme.neonCyan.withOpacity(0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        )
                      ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isGptProcessing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.neonCyan,
                      ),
                    )
                  else
                    const Icon(Icons.document_scanner, color: AppTheme.neonCyan, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    _isGptProcessing ? 'AI SCANEAZA...' : 'SCANEAZA CU AI',
                    style: TextStyle(
                      color: _isGptProcessing
                          ? AppTheme.neonCyan.withOpacity(0.6)
                          : AppTheme.neonCyan,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Small buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: Icons.group,
                label: 'TEAM',
                color: AppTheme.neonPurple,
                onTap: _showTeamSelector,
              ),
              _buildControlButton(
                icon: Icons.grid_view,
                label: 'POSTERS',
                color: AppTheme.neonCyan,
                onTap: _showPosterSelector,
              ),
              _buildControlButton(
                icon: Icons.wifi,
                label: 'SERVER',
                color: AppTheme.neonPink,
                onTap: _showServerSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isLarge = false,
  }) {
    final size = isLarge ? 70.0 : 56.0;
    
    return GestureDetector(
      onTap: () {
        HapticService.mediumImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: AppTheme.neonBoxDecoration(
              color: color,
              borderRadius: size / 2,
              glowIntensity: 0.4,
            ),
            child: Icon(
              icon,
              color: color,
              size: isLarge ? 32 : 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GptScanningBadge extends StatefulWidget {
  const _GptScanningBadge();

  @override
  State<_GptScanningBadge> createState() => _GptScanningBadgeState();
}

class _GptScanningBadgeState extends State<_GptScanningBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_ctrl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.neonCyan, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.neonCyan,
              ),
            ),
            const SizedBox(width: 8),
            Text('AI scanning...', style: TextStyle(color: AppTheme.neonCyan, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class ScanOverlayPainter extends CustomPainter {
  final bool isDetected;
  
  ScanOverlayPainter({this.isDetected = false});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    
    // Draw dark overlay with transparent center
    final centerRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.7,
      height: size.height * 0.4,
    );
    
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(centerRect, const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
    
    // Draw scan frame
    final framePaint = Paint()
      ..color = isDetected ? AppTheme.neonGreen : AppTheme.neonCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(centerRect, const Radius.circular(20)),
      framePaint,
    );
    
    // Draw corner accents
    final cornerLength = 30.0;
    final cornerPaint = Paint()
      ..color = isDetected ? AppTheme.neonGreen : AppTheme.neonCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    
    // Top left
    canvas.drawLine(
      Offset(centerRect.left + 10, centerRect.top),
      Offset(centerRect.left + 10 + cornerLength, centerRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.left, centerRect.top + 10),
      Offset(centerRect.left, centerRect.top + 10 + cornerLength),
      cornerPaint,
    );
    
    // Top right
    canvas.drawLine(
      Offset(centerRect.right - 10, centerRect.top),
      Offset(centerRect.right - 10 - cornerLength, centerRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.right, centerRect.top + 10),
      Offset(centerRect.right, centerRect.top + 10 + cornerLength),
      cornerPaint,
    );
    
    // Bottom left
    canvas.drawLine(
      Offset(centerRect.left + 10, centerRect.bottom),
      Offset(centerRect.left + 10 + cornerLength, centerRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.left, centerRect.bottom - 10),
      Offset(centerRect.left, centerRect.bottom - 10 - cornerLength),
      cornerPaint,
    );
    
    // Bottom right
    canvas.drawLine(
      Offset(centerRect.right - 10, centerRect.bottom),
      Offset(centerRect.right - 10 - cornerLength, centerRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.right, centerRect.bottom - 10),
      Offset(centerRect.right, centerRect.bottom - 10 - cornerLength),
      cornerPaint,
    );
  }
  
  @override
  bool shouldRepaint(ScanOverlayPainter oldDelegate) {
    return oldDelegate.isDetected != isDetected;
  }
}
