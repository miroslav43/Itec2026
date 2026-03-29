import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../services/anthem_service.dart';
import '../theme/app_theme.dart';
import 'battle_canvas_screen.dart';
import 'sticker_generator_screen.dart';

// ── Poster metadata ──────────────────────────────────────────────────────────

class _Poster {
  final String id;
  final String label;
  final double physicalWidthM; // physical width in metres (approx)

  const _Poster(this.id, this.label, {this.physicalWidthM = 0.4});
}

const List<_Poster> _kPosters = [
  _Poster('afis1',  'Afis 1',  physicalWidthM: 0.4),
  _Poster('afis2',  'Afis 2',  physicalWidthM: 0.4),
  _Poster('afis3',  'Afis 3',  physicalWidthM: 0.4),
  _Poster('afis4',  'Afis 4',  physicalWidthM: 0.4),
  _Poster('afis5',  'Afis 5',  physicalWidthM: 0.4),
  _Poster('afis6',  'Afis 6',  physicalWidthM: 0.4),
  _Poster('afis7',  'Afis 7',  physicalWidthM: 0.4),
  _Poster('afis8',  'Afis 8',  physicalWidthM: 0.4),
  _Poster('afis9',  'Afis 9',  physicalWidthM: 0.4),
  _Poster('afis10', 'Afis 10', physicalWidthM: 0.4),
];

// ── Channel names (match native side) ────────────────────────────────────────

const _kMethodChannel = 'com.itec.override/ar_method';
const _kEventChannel  = 'com.itec.override/ar_events';
const _kViewType      = 'ar_poster_view';

// ── Screen ───────────────────────────────────────────────────────────────────

class ArScanScreen extends StatefulWidget {
  final String? targetPosterId;
  final String? textureFilePath;  // optional: rendered battle canvas PNG
  const ArScanScreen({super.key, this.targetPosterId, this.textureFilePath});

  @override
  State<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends State<ArScanScreen> {
  final MethodChannel _method = const MethodChannel(_kMethodChannel);
  final EventChannel  _events = const EventChannel(_kEventChannel);

  String?       _detectedId;
  bool          _dialogShown  = false;
  bool          _trackingActive = false;  // true when ARCore is in TRACKING state
  bool          _arSessionReady = false;
  String        _statusText   = 'Inițializare ARCore...';
  // Debug overlay fields
  int           _dbImageCount = -1;   // -1 = unknown
  String        _camState     = '?';
  String        _lastEvent    = '';

  @override
  void initState() {
    super.initState();
    _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  // ── AR event handler ───────────────────────────────────────────────────────

  void _onEvent(dynamic raw) {
    final Map<String, dynamic> ev = raw is String
        ? jsonDecode(raw) as Map<String, dynamic>
        : Map<String, dynamic>.from(raw as Map);

    final type     = ev['type'] as String;
    final posterId = ev['posterId'] as String? ?? '';

    if (type == 'ar_ready') {
      final loaded = ev['imagesLoaded'] as int? ?? 0;
      if (mounted) setState(() {
        _arSessionReady = true;
        _dbImageCount   = loaded;
        _statusText     = loaded > 0
            ? 'Îndreptați camera spre poster... (DB: $loaded imagini)'
            : 'EROARE: 0 imagini în DB — verifici assets!';
        _lastEvent = 'ar_ready loaded=$loaded';
      });
      return;
    }
    if (type == 'camera_state') {
      if (mounted) setState(() {
        _camState  = ev['state'] as String? ?? '?';
        _lastEvent = 'camera_state=$_camState';
      });
      return;
    }
    if (type == 'image_paused') {
      if (mounted) setState(() {
        _lastEvent = 'IMAGE PAUSED: $posterId (seen, moving to 3D)';
        _statusText = 'Poster văzut! Mișcă puțin camera pentru tracking 3D...';
      });
      return;
    }
    if (type == 'ar_error') {
      if (mounted) setState(() {
        _statusText = 'ARCore eroare: ${ev['message'] ?? ''}';
        _lastEvent  = 'ar_error: ${ev['message']}';
      });
      return;
    }
    if (type == 'lost') {
      if (mounted) setState(() { _trackingActive = false; _lastEvent = 'lost: $posterId'; _statusText = 'Îndreptați camera spre poster...'; });
      AnthemService().stop();
      return;
    }

    // detected / updated — GL renders the actual poster overlay natively
    if (type == 'detected' || type == 'updated') {
      if (mounted) setState(() {
        _trackingActive = true;
        _lastEvent      = '$type: $posterId';
        _statusText     = 'Tracking activ — $posterId';
      });
      if (type == 'detected' && !_dialogShown) {
        _dialogShown = true;
        _detectedId  = posterId;
        // Play enemy anthem if this poster is conquered by a rival
        _maybePlayAnthem(posterId);
        if (widget.targetPosterId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDetectionSheet(posterId);
          });
        }
      }
    }
  }

  // ── Anthem trigger ─────────────────────────────────────────────────────────

  void _maybePlayAnthem(String posterId) {
    if (!mounted) return;
    final myTeamId = context.read<AppStateProvider>().teamId;
    final serverUrl = context.read<SocketProvider>().serverUrl;
    // Fetch territory fresh from backend — don't rely on in-memory cache
    _fetchAndPlayAnthem(serverUrl: serverUrl, posterId: posterId, myTeamId: myTeamId);
  }

  Future<void> _fetchAndPlayAnthem({
    required String serverUrl,
    required String posterId,
    required String myTeamId,
  }) async {
    debugPrint('[Anthem] Checking territory for $posterId (myTeam=$myTeamId, server=$serverUrl)');
    try {
      final resp = await http.get(Uri.parse('$serverUrl/api/territory'))
          .timeout(const Duration(seconds: 5));
      debugPrint('[Anthem] Territory status: ${resp.statusCode}');
      if (resp.statusCode != 200) return;
      final Map<String, dynamic> all =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final posterData = all[posterId] as Map<String, dynamic>?;
      final dominant = posterData?['dominant'] as String?;
      debugPrint('[Anthem] Dominant for $posterId = $dominant');
      if (dominant == null) {
        debugPrint('[Anthem] No dominant team — poster not conquered yet');
        return;
      }
      if (dominant == myTeamId) {
        debugPrint('[Anthem] Poster is YOUR territory — no anthem');
        return;
      }
      debugPrint('[Anthem] Enemy territory ($dominant) — fetching anthem...');
      final existed = await AnthemService.anthemExists(
        serverUrl: serverUrl,
        teamId: dominant,
      );
      if (!existed) {
        debugPrint('[Anthem] No anthem set for team $dominant');
        return;
      }
      await AnthemService().playAnthem(
        serverUrl: serverUrl,
        enemyTeamId: dominant,
        myTeamId: myTeamId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.music_note, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('Teritoriu inamic ($dominant) — imn activ!'),
          ]),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      debugPrint('[Anthem] _fetchAndPlayAnthem error: $e');
    }
  }

  // ── Detection bottom-sheet ─────────────────────────────────────────────────

  void _showDetectionSheet(String posterId) {
    final poster = _kPosters.firstWhere(
      (p) => p.id == posterId,
      orElse: () => _Poster(posterId, posterId),
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetectionSheet(
        poster: poster,
        onEnterBattle: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BattleCanvasScreen(posterId: posterId)),
          );
        },
        onViewAR: () {
          Navigator.pop(context);
          if (mounted) setState(() => _statusText = 'Tracking activ — $posterId');
        },
        onStickers: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StickerGeneratorScreen()),
          );
        },
      ),
    ).whenComplete(() => _dialogShown = false);
  }

  // ── Initialise AR with poster images ───────────────────────────────────────

  bool _arInitDone = false;

  Future<void> _initAR() async {
    if (_arInitDone) return;
    _arInitDone = true;

    // Only load the target poster or all 10 — images are loaded natively from assets
    final target = widget.targetPosterId;
    final postersToLoad = target != null
        ? _kPosters.where((p) => p.id == target).toList()
        : _kPosters;

    final ids    = postersToLoad.map((p) => p.id).toList();
    final widths = { for (final p in postersToLoad) p.id: p.physicalWidthM };

    // Build per-poster texture map: check cache for every poster
    final cacheDir = await getTemporaryDirectory();
    final texturePaths = <String, String>{};
    for (final p in postersToLoad) {
      // Prefer explicitly passed path (from VIEW AR button)
      if (widget.textureFilePath != null && p.id == widget.targetPosterId) {
        texturePaths[p.id] = widget.textureFilePath!;
        debugPrint('[AR] texture for ${p.id}: explicit path');
        continue;
      }
      final cached = File('${cacheDir.path}/ar_texture_${p.id}.png');
      if (await cached.exists()) {
        texturePaths[p.id] = cached.path;
        debugPrint('[AR] texture for ${p.id}: cached at ${cached.path}');
      }
    }
    debugPrint('[AR] _initAR: ${ids.length} poster(s), ${texturePaths.length} custom texture(s)');

    try {
      await _method.invokeMethod<void>('initialize', {
        'posterIds': ids,
        'widths': widths,
        if (texturePaths.isNotEmpty) 'texturePaths': texturePaths,
      });
      debugPrint('[AR] invokeMethod returned — session thread spawned');
      if (mounted) {
        setState(() {
          _arSessionReady = true;
          _statusText = 'Îndreptați camera spre poster...';
        });
      }
    } on PlatformException catch (e) {
      debugPrint('[AR] init error: $e');
      if (mounted) setState(() => _statusText = 'Eroare AR: ${e.message}');
    }
  }

  @override
  void dispose() {
    _method.invokeMethod<void>('dispose').ignore();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Native AR camera view ──────────────────────────────────────────
          Positioned.fill(
            child: _buildPlatformView(),
          ),

          // GL renders the poster overlay natively — no Flutter widget needed here

          // ── Top bar ────────────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                  ),
                ),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: AppTheme.neonBoxDecoration(
                          color: AppTheme.neonPink, borderRadius: 4, glowIntensity: 0.2),
                      child: const Icon(Icons.arrow_back, color: AppTheme.neonPink, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('🗺  HARTA REALITĂȚII',
                        style: AppTheme.cinzel(
                            fontSize: 8, color: AppTheme.gold.withOpacity(0.55), letterSpacing: 2)),
                    Text('AR POSTER SCAN',
                        style: AppTheme.neonTextStyle(color: AppTheme.gold, fontSize: 14)),
                  ]),
                  const Spacer(),
                  if (_trackingActive)
                    GestureDetector(
                      onTap: () => setState(() => _trackingActive = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: AppTheme.panelDecoration(borderColor: AppTheme.neonGreen),
                        child: Text('ASCUNDE AR',
                            style: AppTheme.cinzel(
                                fontSize: 9, color: AppTheme.neonGreen, letterSpacing: 1)),
                      ),
                    ),
                ]),
              ),
            ),
          ),

          // ── Scan hint / status ──────────────────────────────────────────────
          if (!_trackingActive)
            Positioned(
              bottom: 40,
              left: 0, right: 0,
              child: Center(
                child: _ScanHint(
                  text: _statusText,
                  scanning: !_arSessionReady,
                ),
              ),
            ),

          // ── Debug overlay (visible while tracking not active) ─────────────
          if (!_trackingActive)
            Positioned(
              bottom: 100,
              left: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: AppTheme.panelDecoration(),
                child: Text(
                  '⚔ DB: ${_dbImageCount < 0 ? '?' : _dbImageCount} blazoane  |  '
                  'Cam: $_camState\n'
                  'Ultim semnal: $_lastEvent',
                  style: AppTheme.cinzel(
                      fontSize: 9, color: AppTheme.neonGreen,
                      letterSpacing: 0.5, weight: FontWeight.normal),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlatformView() {
    if (Platform.isAndroid) {
      return AndroidView(
        viewType: _kViewType,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => _initAR(),
      );
    } else if (Platform.isIOS) {
      return UiKitView(
        viewType: _kViewType,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => _initAR(),
      );
    }
    return const Center(
      child: Text('AR not supported on this platform',
          style: TextStyle(color: Colors.white)),
    );
  }
}

// ── Detection bottom-sheet widget ─────────────────────────────────────────────

class _DetectionSheet extends StatelessWidget {
  final _Poster poster;
  final VoidCallback onEnterBattle;
  final VoidCallback onViewAR;
  final VoidCallback onStickers;

  const _DetectionSheet({
    required this.poster,
    required this.onEnterBattle,
    required this.onViewAR,
    required this.onStickers,
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
              Text(poster.label.toUpperCase(),
                  style: AppTheme.cinzel(
                      fontSize: 16, color: AppTheme.parchment, letterSpacing: 2,
                      shadows: [Shadow(color: AppTheme.gold.withOpacity(0.5), blurRadius: 8)])),
            ],
          )),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _SheetButton(
            label: 'INTRĂ În LUPTĂ',
            icon: Icons.shield,
            color: AppTheme.crimson,
            onTap: onEnterBattle,
          )),
          const SizedBox(width: 10),
          Expanded(child: _SheetButton(
            label: 'HARTA AR',
            icon: Icons.map,
            color: AppTheme.gold,
            onTap: onViewAR,
          )),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity,
          child: _SheetButton(
            label: 'BLAZOANE AI',
            icon: Icons.auto_awesome,
            color: AppTheme.neonPurple,
            onTap: onStickers,
          ),
        ),
        const SizedBox(height: 6),
      ]),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SheetButton({
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
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.6), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 10)],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: AppTheme.cinzel(
                  fontSize: 10, color: color, letterSpacing: 1.5)),
        ]),
      ),
    );
  }
}

// ── Scan hint ─────────────────────────────────────────────────────────────────

class _ScanHint extends StatelessWidget {
  final String text;
  final bool   scanning;
  const _ScanHint({
    this.text     = 'Îndreptați camera spre un poster',
    this.scanning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: AppTheme.panelDecoration(),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (scanning)
          SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.8, color: AppTheme.gold))
        else
          Text('🗑', style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Text(text,
            style: AppTheme.cinzel(
                fontSize: 11, color: AppTheme.parchment.withOpacity(0.75),
                letterSpacing: 1, weight: FontWeight.normal)),
      ]),
    );
  }
}
