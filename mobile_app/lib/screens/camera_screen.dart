import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../services/esp32_service.dart';
import '../services/gpt_vision_service.dart';
import '../services/haptic_service.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../widgets/player_badge.dart';
import '../widgets/poster_selector_dialog.dart';
import '../widgets/team_selector.dart';
import '../widgets/connection_status.dart';
import 'battle_canvas_screen.dart';
import 'ar_scan_screen.dart';
import 'map_screen.dart';
import 'sticker_generator_screen.dart';

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
    // Auto-connect ESP32 with default IP (background, no error if fails)
    unawaited(Esp32Service().connect(Esp32Service.defaultIp));
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
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted && _detectedPosterId != null) {
          final pid = _detectedPosterId!;
          final imageUrl = pid.startsWith('custom_')
              ? '${GptVisionService.serverUrl}/custom-posters/$pid.jpg'
              : null;
          final customName = pid.startsWith('custom_')
              ? GptVisionService.getPosterName(pid)
              : null;
          _showPosterOptions(pid, posterName: customName, posterImageUrl: imageUrl);
        }
      } else if (result.looksLikePoster && result.posterId == null && mounted) {
        _showAddPosterDialog(result.croppedBytes);
      } else if (!result.looksLikePoster && result.posterId == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nu este un poster recunoscut'),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
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
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: AppTheme.gold.withOpacity(0.7), width: 1.5),
            ),
            title: Text('🏰 CETATE NOUĂ DESCOPERITĂ',
                style: AppTheme.neonTextStyle(color: AppTheme.gold, fontSize: 14)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (croppedBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(croppedBytes,
                        width: 200, height: 200, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  style: AppTheme.cinzel(fontSize: 13, color: AppTheme.parchment, letterSpacing: 1),
                  decoration: InputDecoration(
                    labelText: 'Numele cetății',
                    labelStyle: AppTheme.cinzel(fontSize: 11,
                        color: AppTheme.parchment.withOpacity(0.4), letterSpacing: 1),
                    filled: true, fillColor: AppTheme.darkBgTertiary,
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  style: AppTheme.cinzel(fontSize: 12, color: AppTheme.parchment, letterSpacing: 0.8),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Cronica (opțional)',
                    labelStyle: AppTheme.cinzel(fontSize: 11,
                        color: AppTheme.parchment.withOpacity(0.4), letterSpacing: 1),
                    filled: true, fillColor: AppTheme.darkBgTertiary,
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold, width: 1.5)),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('RETRAGE-TE',
                    style: AppTheme.cinzel(fontSize: 11,
                        color: AppTheme.parchment.withOpacity(0.35))),
              ),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  setDialogState(() => saving = true);
                  final id = await GptVisionService.saveCustomPoster(
                    name: name,
                    description: descCtrl.text.trim().isEmpty ? name : descCtrl.text.trim(),
                    imageBytes: croppedBytes ?? Uint8List(0),
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (id != null && mounted) {
                    final imageUrl = '${GptVisionService.serverUrl}/custom-posters/$id.jpg';
                    _openBattleCanvas(id, posterName: name, posterImageUrl: imageUrl);
                  }
                },
                child: saving
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold))
                    : Text('ADAUGĂ În CRONICI',
                        style: AppTheme.cinzel(fontSize: 12, color: AppTheme.goldBright)),
              ),
            ],
          );
        },
      ),
    );
  }
  
  void _showPosterOptions(String posterId, {String? posterName, String? posterImageUrl}) {
    setState(() => _detectedPosterId = null);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => _PosterOptionsSheet(
        posterId: posterId,
        posterName: posterName ?? posterId,
        onEnterBattle: () {
          Navigator.pop(context);
          _openBattleCanvas(posterId, posterName: posterName, posterImageUrl: posterImageUrl);
        },
        onViewAR: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ArScanScreen(targetPosterId: posterId),
            ),
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

  String get _serverUrl => context.read<SocketProvider>().serverUrl;

  Future<void> _deleteAll(String path, String label) async {
    try {
      await http.delete(Uri.parse('$_serverUrl$path'))
          .timeout(const Duration(seconds: 8));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label — șters!'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _confirmAction(String title, String body, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkBgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: AppTheme.neonRed.withOpacity(0.7), width: 1.5),
        ),
        title: Text(title,
            style: AppTheme.neonTextStyle(color: AppTheme.neonRed, fontSize: 14)),
        content: Text(body,
            style: AppTheme.cinzel(fontSize: 11, color: AppTheme.parchment.withOpacity(0.7),
                letterSpacing: 0.8, weight: FontWeight.normal)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('RETRAGE-TE',
                  style: AppTheme.cinzel(fontSize: 11,
                      color: AppTheme.parchment.withOpacity(0.35)))),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); onConfirm(); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonRed.withOpacity(0.2),
              foregroundColor: AppTheme.neonRed,
              side: BorderSide(color: AppTheme.neonRed.withOpacity(0.6)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Text('CONFIRMĂ',
                style: AppTheme.cinzel(fontSize: 12, color: AppTheme.neonRed)),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    final socketProvider = context.read<SocketProvider>();
    final urlCtrl = TextEditingController(text: socketProvider.serverUrl);
    final esp32Ctrl = TextEditingController(text: Esp32Service().ip ?? Esp32Service.defaultIp);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: AppTheme.panelDecoration(borderColor: AppTheme.neonPink),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('📜', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Text('PERGAMENTUL SETARILOR',
                    style: AppTheme.neonTextStyle(color: AppTheme.neonPink, fontSize: 15)),
              ]),
              const SizedBox(height: 18),

              Text('ADRESA FORTĂREȚEI',
                  style: AppTheme.cinzel(fontSize: 9,
                      color: AppTheme.parchment.withOpacity(0.4), letterSpacing: 2)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: urlCtrl,
                    style: AppTheme.cinzel(fontSize: 12, color: AppTheme.parchment, letterSpacing: 1),
                    decoration: InputDecoration(
                      hintText: 'http://IP:3000',
                      hintStyle: AppTheme.cinzel(fontSize: 11,
                          color: AppTheme.parchment.withOpacity(0.2), letterSpacing: 1),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: AppTheme.darkBgTertiary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.25)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final url = urlCtrl.text.trim();
                    if (url.isNotEmpty) {
                      socketProvider.setServerUrl(url);
                      socketProvider.disconnect();
                      socketProvider.connect();
                    }
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.crimson.withOpacity(0.3),
                    foregroundColor: AppTheme.goldBright,
                    side: BorderSide(color: AppTheme.gold.withOpacity(0.6)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: Text('OK', style: AppTheme.cinzel(fontSize: 12, color: AppTheme.goldBright)),
                ),
              ]),

              const SizedBox(height: 18),
              Text('DISPOZITIV ESP32',
                  style: AppTheme.cinzel(fontSize: 9,
                      color: AppTheme.parchment.withOpacity(0.4), letterSpacing: 2)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: esp32Ctrl,
                    style: AppTheme.cinzel(fontSize: 12, color: AppTheme.parchment, letterSpacing: 1),
                    decoration: InputDecoration(
                      hintText: '192.168.x.x',
                      hintStyle: AppTheme.cinzel(fontSize: 11,
                          color: AppTheme.parchment.withOpacity(0.2), letterSpacing: 1),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: AppTheme.darkBgTertiary,
                      prefixIcon: Icon(
                        Esp32Service().isConnected ? Icons.gamepad : Icons.gamepad_outlined,
                        color: Esp32Service().isConnected
                            ? AppTheme.neonGreen : AppTheme.parchment.withOpacity(0.3),
                        size: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.25)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: Esp32Service().isConnected
                              ? AppTheme.neonGreen.withOpacity(0.6)
                              : AppTheme.gold.withOpacity(0.25),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: AppTheme.gold, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final ip = esp32Ctrl.text.trim();
                    if (ip.isEmpty) return;
                    final ok = await Esp32Service().connect(ip);
                    setSt(() {});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? '⚔ ESP32 conectat! Lupta poate începe!'
                            : '💀 Eroare conectare ESP32'),
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.crimson.withOpacity(0.3),
                    foregroundColor: AppTheme.goldBright,
                    side: BorderSide(color: AppTheme.gold.withOpacity(0.6)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: Text(Esp32Service().isConnected ? '✓' : 'OK',
                      style: AppTheme.cinzel(fontSize: 12, color: AppTheme.goldBright)),
                ),
              ]),

              const SizedBox(height: 22),
              Divider(color: AppTheme.gold.withOpacity(0.2)),
              const SizedBox(height: 14),
              Text('⚔ ADMINISTRAREA REGATULUI',
                  style: AppTheme.cinzel(fontSize: 9,
                      color: AppTheme.parchment.withOpacity(0.35), letterSpacing: 2)),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: Icons.auto_awesome,
                color: AppTheme.neonPurple,
                label: 'Distruge blazoanele AI',
                subtitle: 'Elimină toate blazoanele generate din arhive',
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAction(
                    '🔥 Distruge blazoanele?',
                    'Toate blazoanele generate vor fi incinerate permanent.',
                    () => _deleteAll('/api/stickers', 'Blazoane'),
                  );
                },
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                icon: Icons.account_balance,
                color: AppTheme.gold,
                label: 'Distruge cetățile custom',
                subtitle: 'Elimină toate teritoriile adăugate manual',
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAction(
                    '🏰 Distruge cetățile?',
                    'Toate cetățile custom vor fi șterse din cronici.',
                    () => _deleteAll('/api/custom-posters', 'Cetăți custom'),
                  );
                },
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                icon: Icons.restart_alt,
                color: AppTheme.neonRed,
                label: 'Resetează toate bătăliile',
                subtitle: 'Șterge teritoriile cucerite — lupta rencepe de la zero',
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAction(
                    '🔥 Resetare totală?',
                    'Toate teritoriile cucerite vor fi eliberate. Totul rencepe!',
                    () => _deleteAll('/api/territory/reset', 'Bătălii resetate'),
                  );
                },
              ),
            ],
          ),
        ),
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
            child: PlayerBadge(),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [AppTheme.darkBg, AppTheme.darkBg.withOpacity(0)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('iTEC',
                style: AppTheme.cinzel(
                    fontSize: 22, color: AppTheme.goldBright, letterSpacing: 4,
                    shadows: [Shadow(color: AppTheme.gold, blurRadius: 14)])),
            Text('OVERRIDE',
                style: AppTheme.cinzel(
                    fontSize: 10, color: AppTheme.neonPink, letterSpacing: 6,
                    weight: FontWeight.normal,
                    shadows: [Shadow(color: AppTheme.neonPink, blurRadius: 8)])),
          ]),
          const ConnectionStatus(),
        ],
      ),
    );
  }
  
  Widget _buildDetectionIndicator() {
    final appState = context.read<AppStateProvider>();
    final posterName = appState.posters[_detectedPosterId]?.name ?? _detectedPosterId;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.panelDecoration(borderColor: AppTheme.neonGreen),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('🏰', style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 10),
        Text('TERITORIU DESCOPERIT',
            style: AppTheme.neonTextStyle(color: AppTheme.neonGreen, fontSize: 15)),
        const SizedBox(height: 6),
        Text(AppTheme.divider,
            style: TextStyle(color: AppTheme.gold.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 6),
        Text((posterName ?? '').toUpperCase(),
            style: AppTheme.cinzel(
                fontSize: 14, color: AppTheme.parchment, letterSpacing: 2)),
        const SizedBox(height: 14),
        Text('Pregătește-te de luptă, viteaz...',
            style: AppTheme.cinzel(
                fontSize: 11, color: AppTheme.parchment.withOpacity(0.55),
                letterSpacing: 1, weight: FontWeight.normal)),
      ]),
    );
  }
  
  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panelDecoration(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('📗', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Text('RECUNOAȘTE BLAZONUL',
              style: AppTheme.neonTextStyle(color: AppTheme.gold, fontSize: 14)),
        ]),
        const SizedBox(height: 6),
        Text(
          _isGptProcessing
              ? 'Vrăjitorul AI analizează imaginea...'
              : 'Îndreaptă pergamentul spre blazon ~2s\nsau selectează manual cetatea de mai jos',
          textAlign: TextAlign.center,
          style: AppTheme.cinzel(
              fontSize: 11, color: AppTheme.parchment.withOpacity(0.65),
              letterSpacing: 0.8, weight: FontWeight.normal),
        ),
      ]),
    );
  }
  
  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [AppTheme.darkBg, AppTheme.darkBg.withOpacity(0)],
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── MAIN SCAN BUTTON ──────────────────────────────────────────
        GestureDetector(
          onTap: _isGptProcessing ? null : () {
            HapticService.mediumImpact();
            _runGptDetection();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 58,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isGptProcessing
                    ? [AppTheme.crimson.withOpacity(0.2), AppTheme.darkBgTertiary]
                    : [AppTheme.crimson.withOpacity(0.55), AppTheme.crimson.withOpacity(0.3)],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isGptProcessing
                    ? AppTheme.gold.withOpacity(0.35)
                    : AppTheme.gold,
                width: 1.5,
              ),
              boxShadow: _isGptProcessing ? null : [
                BoxShadow(color: AppTheme.gold.withOpacity(0.3), blurRadius: 18, spreadRadius: 1),
                BoxShadow(color: AppTheme.crimson.withOpacity(0.4), blurRadius: 10),
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_isGptProcessing)
                SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold))
              else
                Text('🔮', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Text(
                _isGptProcessing ? 'VRĂJITORUL SCANEAZĂ...' : '⚔  SCANEAZĂ BLAZONUL  ⚔',
                style: AppTheme.cinzel(
                    fontSize: 14, letterSpacing: 2,
                    color: _isGptProcessing
                        ? AppTheme.gold.withOpacity(0.55)
                        : AppTheme.goldBright,
                    shadows: _isGptProcessing ? null :
                        [Shadow(color: AppTheme.gold, blurRadius: 10)]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        // ── ACTION BUTTONS ────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _buildControlButton(
              icon: Icons.shield, label: 'TABĂRĂ',
              color: AppTheme.neonPurple, onTap: _showTeamSelector),
          _buildControlButton(
              icon: Icons.account_balance, label: 'CETĂȚI',
              color: AppTheme.gold, onTap: _showPosterSelector),
          _buildControlButton(
              icon: Icons.map, label: 'HARTĂ',
              color: AppTheme.neonGreen,
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const MapScreen()))),
          _buildControlButton(
              icon: Icons.auto_awesome, label: 'BLASFEMII',
              color: AppTheme.neonOrange,
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const StickerGeneratorScreen()))),
          _buildControlButton(
              icon: Icons.settings, label: 'PERGAMENT',
              color: AppTheme.neonPink, onTap: _showSettings),
        ]),
      ]),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () { HapticService.mediumImpact(); onTap(); },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.6), width: 1.2),
            boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8)],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: AppTheme.cinzel(
                fontSize: 8, color: color, letterSpacing: 1)),
      ]),
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
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: AppTheme.panelDecoration(borderColor: AppTheme.gold),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 13, height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: AppTheme.gold)),
          const SizedBox(width: 8),
          Text('🔮 vrăjitorul scanează...',
              style: AppTheme.cinzel(
                  fontSize: 10, color: AppTheme.gold, letterSpacing: 1)),
        ]),
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
      ..color = isDetected ? AppTheme.neonGreen : AppTheme.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(centerRect, const Radius.circular(8)),
      framePaint,
    );
    
    // Draw corner accents
    const cornerLength = 30.0;
    final cornerPaint = Paint()
      ..color = isDetected ? AppTheme.neonGreen : AppTheme.goldBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.35), width: 1),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTheme.cinzel(
                      fontSize: 11, color: color, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppTheme.cinzel(
                      fontSize: 9, color: AppTheme.parchment.withOpacity(0.35),
                      letterSpacing: 0.5, weight: FontWeight.normal)),
            ],
          )),
          Icon(Icons.chevron_right, color: color.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}

class _PosterOptionsSheet extends StatelessWidget {
  final String posterId;
  final String posterName;
  final VoidCallback onEnterBattle;
  final VoidCallback onViewAR;

  const _PosterOptionsSheet({
    required this.posterId,
    required this.posterName,
    required this.onEnterBattle,
    required this.onViewAR,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: AppTheme.panelDecoration(borderColor: AppTheme.gold),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 3,
          decoration: BoxDecoration(
            color: AppTheme.gold.withOpacity(0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.neonGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.neonGreen.withOpacity(0.45)),
            ),
            child: Text('🏰', style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⚔  CETATE DESCOPERITĂ',
                  style: AppTheme.cinzel(
                      fontSize: 9, color: AppTheme.neonGreen, letterSpacing: 2)),
              const SizedBox(height: 5),
              Text(posterName.toUpperCase(),
                  style: AppTheme.cinzel(
                      fontSize: 16, color: AppTheme.parchment, letterSpacing: 2,
                      shadows: [Shadow(color: AppTheme.gold.withOpacity(0.5), blurRadius: 8)])),
            ],
          )),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _OptionButton(
            label: 'INTRĂ În LUPTĂ',
            icon: Icons.shield,
            color: AppTheme.crimson,
            onTap: onEnterBattle,
          )),
          const SizedBox(width: 10),
          Expanded(child: _OptionButton(
            label: 'HARTĂ AR',
            icon: Icons.map,
            color: AppTheme.gold,
            onTap: onViewAR,
          )),
        ]),
        const SizedBox(height: 6),
      ]),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _OptionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.6), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 10)],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(label,
              style: AppTheme.cinzel(
                  fontSize: 10, color: color, letterSpacing: 1.5)),
        ]),
      ),
    );
  }
}
