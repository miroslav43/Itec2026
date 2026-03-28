import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img_pkg;

import 'battle_screen_placeholder.dart';

// ── Image resize for ARCore (top-level for compute isolate) ──────────────────

Uint8List _resizeForAR(Uint8List raw) {
  final decoded = img_pkg.decodeImage(raw);
  if (decoded == null) return raw;
  // 600px gives ARCore more feature points than 300px; PNG preserves edges
  final targetW = decoded.width > 600 ? 600 : decoded.width;
  final resized  = img_pkg.copyResize(decoded, width: targetW);
  return Uint8List.fromList(img_pkg.encodePng(resized));
}

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

// ── Overlay data ─────────────────────────────────────────────────────────────

class _OverlayData {
  final String posterId;
  final double cx, cy, widthPx, heightPx, angleDeg;

  const _OverlayData({
    required this.posterId,
    required this.cx,
    required this.cy,
    required this.widthPx,
    required this.heightPx,
    required this.angleDeg,
  });
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ArScanScreen extends StatefulWidget {
  final String? targetPosterId;
  const ArScanScreen({super.key, this.targetPosterId});

  @override
  State<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends State<ArScanScreen> {
  final MethodChannel _method = const MethodChannel(_kMethodChannel);
  final EventChannel  _events = const EventChannel(_kEventChannel);

  _OverlayData? _overlay;
  String?       _detectedId;
  bool          _dialogShown  = false;
  bool          _showOverlay  = false;
  bool          _arSessionReady = false; // true once ARCore session is live
  String        _statusText   = 'Inițializare ARCore...';

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
      if (mounted) setState(() {
        _arSessionReady = true;
        _statusText = 'Îndreptați camera spre poster...';
      });
      return;
    }
    if (type == 'ar_error') {
      if (mounted) setState(() {
        _statusText = 'ARCore indisponibil: ${ev['message'] ?? ''}';
      });
      return;
    }
    if (type == 'lost') {
      if (mounted) setState(() { _overlay = null; _showOverlay = false; });
      return;
    }

    final cx       = (ev['cx']       as num).toDouble();
    final cy       = (ev['cy']       as num).toDouble();
    final widthPx  = (ev['widthPx']  as num).toDouble();
    final heightPx = (ev['heightPx'] as num).toDouble();
    final angle    = (ev['angle']    as num).toDouble();

    final data = _OverlayData(
      posterId: posterId, cx: cx, cy: cy,
      widthPx: widthPx, heightPx: heightPx, angleDeg: angle,
    );

    // Always update overlay position data
    if (mounted) setState(() => _overlay = data);

    if (type == 'detected' || type == 'updated') {
      if (!_dialogShown) {
        _dialogShown = true;
        _detectedId  = posterId;
        if (widget.targetPosterId != null) {
          // Launched from camera scan — auto-show overlay
          if (mounted) setState(() { _showOverlay = true; _statusText = 'Tracking activ'; });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDetectionSheet(posterId, data);
          });
        }
      } else if (_showOverlay) {
        // Already showing — just update position (handled by setState above)
      }
    }
  }

  // ── Detection bottom-sheet ─────────────────────────────────────────────────

  void _showDetectionSheet(String posterId, _OverlayData data) {
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
            MaterialPageRoute(builder: (_) => BattleScreenPlaceholder(posterId: posterId)),
          );
        },
        onViewAR: () {
          Navigator.pop(context);
          if (mounted) {
            setState(() {
              _showOverlay = true;
              _overlay = data;
            });
          }
        },
      ),
    ).whenComplete(() => _dialogShown = false);
  }

  // ── Initialise AR with poster images ───────────────────────────────────────

  bool _arInitDone = false;

  Future<void> _initAR() async {
    if (_arInitDone) return;
    _arInitDone = true;

    final Map<String, Uint8List> images = {};
    final Map<String, double>    widths = {};

    // If launched with a specific poster, only load that one for faster DB compile
    final target = widget.targetPosterId;
    final postersToLoad = target != null
        ? _kPosters.where((p) => p.id == target).toList()
        : _kPosters;

    for (final p in postersToLoad) {
      try {
        final raw = (await rootBundle.load('assets/posters/${p.id}.png'))
            .buffer
            .asUint8List();
        final resized = await compute(_resizeForAR, raw);
        images[p.id] = resized;
        widths[p.id] = p.physicalWidthM;
      } catch (_) {}
    }

    try {
      await _method.invokeMethod<void>('initialize', {
        'images': images,
        'widths': widths,
      });
      // invokeMethod returns once native session is started — update status here
      // instead of waiting for EventChannel (which has an async onListen race)
      if (mounted) {
        setState(() {
          _arSessionReady = true;
          _statusText = 'Îndreptați camera spre poster...';
        });
      }
    } on PlatformException catch (e) {
      debugPrint('AR init error: $e');
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

          // ── AR-tracked poster overlay (only when ARCore fires position data) ────
          if (_showOverlay && _overlay != null)
            _PosterOverlay(data: _overlay!),

          // ── Top bar ────────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'AR POSTER SCAN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    if (_showOverlay)
                      TextButton(
                        onPressed: () => setState(() {
                          _showOverlay = false;
                          _overlay = null;
                        }),
                        child: const Text('HIDE AR', style: TextStyle(color: Colors.cyanAccent)),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Scan hint / status ──────────────────────────────────────────────
          if (!_showOverlay || _overlay == null)
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

// ── Poster overlay widget ─────────────────────────────────────────────────────

class _PosterOverlay extends StatelessWidget {
  final _OverlayData data;
  const _PosterOverlay({required this.data});

  @override
  Widget build(BuildContext context) {
    final left = data.cx - data.widthPx / 2;
    final top  = data.cy - data.heightPx / 2;

    return Positioned(
      left: left,
      top:  top,
      width:  data.widthPx,
      height: data.heightPx,
      child: Transform.rotate(
        angle: data.angleDeg * pi / 180,
        child: Opacity(
          opacity: 0.88,
          child: Image.asset(
            'assets/posters/${data.posterId}.png',
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.cyanAccent, width: 2),
                color: Colors.black45,
              ),
              child: Center(
                child: Text(data.posterId,
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Detection bottom-sheet widget ─────────────────────────────────────────────

class _DetectionSheet extends StatelessWidget {
  final _Poster poster;
  final VoidCallback onEnterBattle;
  final VoidCallback onViewAR;

  const _DetectionSheet({
    required this.poster,
    required this.onEnterBattle,
    required this.onViewAR,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.cyanAccent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'POSTER DETECTAT',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      poster.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  label: 'ENTER BATTLE',
                  icon: Icons.sports_esports,
                  color: Colors.redAccent,
                  onTap: onEnterBattle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetButton(
                  label: 'VIEW AR',
                  icon: Icons.view_in_ar,
                  color: Colors.cyanAccent,
                  onTap: onViewAR,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Centered poster overlay (shown immediately, before ARCore tracks) ─────────

class _CenteredPosterOverlay extends StatelessWidget {
  final String posterId;
  const _CenteredPosterOverlay({required this.posterId});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width * 0.75;
    final h = w * 1.4;
    return Positioned(
      left: (size.width - w) / 2,
      top: (size.height - h) / 2,
      width: w,
      height: h,
      child: Opacity(
        opacity: 0.85,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/posters/$posterId.png',
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.cyanAccent, width: 2),
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(posterId,
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scanning)
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
              ),
            )
          else
            const Icon(Icons.crop_free, color: Colors.cyanAccent, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}
