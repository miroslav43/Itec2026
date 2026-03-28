import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/sticker_generation_service.dart';
import '../theme/app_theme.dart';

/// Screen that lets the user generate a 32×32 pixel-art sticker on-device
/// using stable-diffusion.cpp (LCM sampler, 64×64 internal, q2_k weights).
///
/// Returns the generated [Uint8List] PNG bytes via [Navigator.pop] when the
/// user taps "STAMP ON CANVAS". Returns null when dismissed without stamping.
class StickerGeneratorScreen extends StatefulWidget {
  const StickerGeneratorScreen({super.key});

  @override
  State<StickerGeneratorScreen> createState() => _StickerGeneratorScreenState();
}

enum _Phase { checking, downloading, loading, ready, generating, done, error }

class _StickerGeneratorScreenState extends State<StickerGeneratorScreen>
    with SingleTickerProviderStateMixin {
  _Phase        _phase           = _Phase.checking;
  double        _downloadProgress = 0;
  Uint8List?    _stickerBytes;
  String        _errorMessage    = '';
  final _promptController        = TextEditingController();
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _initialise();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _promptController.dispose();
    super.dispose();
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> _initialise() async {
    setState(() => _phase = _Phase.checking);

    final loaded = await StickerGenerationService.isModelLoaded();
    if (loaded) {
      setState(() => _phase = _Phase.ready);
      return;
    }

    final downloaded = await StickerGenerationService.isModelDownloaded();
    if (!downloaded) {
      setState(() => _phase = _Phase.downloading);
      try {
        await StickerGenerationService.downloadModel(
          onProgress: (p) => setState(() => _downloadProgress = p),
        );
      } catch (e) {
        _setError('Download failed: $e');
        return;
      }
    }

    setState(() => _phase = _Phase.loading);
    try {
      await StickerGenerationService.loadModel();
    } catch (e) {
      _setError('Model load failed: $e');
      return;
    }
    setState(() => _phase = _Phase.ready);
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _phase        = _Phase.generating;
      _stickerBytes = null;
    });

    try {
      final bytes = await StickerGenerationService.generateSticker(prompt);
      setState(() {
        _stickerBytes = bytes;
        _phase        = _Phase.done;
      });
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _setError(String msg) => setState(() {
        _phase        = _Phase.error;
        _errorMessage = msg;
      });

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.neonCyan),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'PIXEL STICKER',
          style: AppTheme.neonTextStyle(color: AppTheme.neonCyan, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_phase) {
      _Phase.checking    => _buildSpinner('INITIALIZING…'),
      _Phase.downloading => _buildDownloadProgress(),
      _Phase.loading     => _buildSpinner('LOADING MODEL…'),
      _Phase.ready       => _buildInputUI(),
      _Phase.generating  => _buildGenerating(),
      _Phase.done        => _buildResult(),
      _Phase.error       => _buildError(),
    };
  }

  // ── Phase widgets ─────────────────────────────────────────────────────────────

  Widget _buildSpinner(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _neonGlowBox(
            child: const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: AppTheme.neonCyan,
                strokeWidth: 2,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(label,
              style: AppTheme.neonTextStyle(
                  color: AppTheme.neonCyan, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress() {
    final pct = (_downloadProgress * 100).toStringAsFixed(0);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _neonGlowBox(
            color: AppTheme.neonPurple,
            child: const Icon(Icons.download_rounded,
                color: AppTheme.neonPurple, size: 40),
          ),
          const SizedBox(height: 24),
          Text('DOWNLOADING MODEL',
              style: AppTheme.neonTextStyle(
                  color: AppTheme.neonPurple, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '~1 GB — one-time download',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.neonPurple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              widthFactor: _downloadProgress,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.neonPurple,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.neonPurple.withOpacity(0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$pct%',
            style: AppTheme.neonTextStyle(
                color: AppTheme.neonPurple, fontSize: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildInputUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'DESCRIBE YOUR STICKER',
          style: AppTheme.neonTextStyle(color: AppTheme.neonCyan, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Container(
          decoration: AppTheme.neonBoxDecoration(
              color: AppTheme.neonCyan, glowIntensity: 0.2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _promptController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'e.g. red tractor, cyberpunk skull, tiny dragon…',
              hintStyle: TextStyle(
                  color: AppTheme.neonCyan.withOpacity(0.35), fontSize: 14),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _generate(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '32×32 pixel art • LCM sampler • on-device',
          style:
              TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 0.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        _neonButton(
          label: 'GENERATE',
          icon: Icons.auto_awesome,
          color: AppTheme.neonCyan,
          onTap: _generate,
        ),
        const Spacer(),
        _buildExamples(),
      ],
    );
  }

  Widget _buildGenerating() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Opacity(opacity: _pulse.value, child: child),
            child: _neonGlowBox(
              color: AppTheme.neonPink,
              size: 80,
              child: const Icon(Icons.auto_awesome,
                  color: AppTheme.neonPink, size: 38),
            ),
          ),
          const SizedBox(height: 24),
          Text('GENERATING STICKER',
              style: AppTheme.neonTextStyle(
                  color: AppTheme.neonPink, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '~1–3 seconds on device…',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              backgroundColor: AppTheme.neonPink.withOpacity(0.15),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.neonPink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'PIXEL STICKER READY',
          style:
              AppTheme.neonTextStyle(color: AppTheme.neonGreen, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Center(
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.neonGreen, width: 2),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: AppTheme.neonGreen.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2),
              ],
              color: AppTheme.darkBgSecondary,
            ),
            child: _stickerBytes != null
                ? Image.memory(
                    _stickerBytes!,
                    // Nearest-neighbour scaling — preserves pixel crispness
                    filterQuality: FilterQuality.none,
                    fit: BoxFit.contain,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '32×32 pixel art',
          style: TextStyle(color: Colors.white24, fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        _neonButton(
          label: 'STAMP ON CANVAS',
          icon: Icons.add_circle_outline,
          color: AppTheme.neonGreen,
          onTap: () => Navigator.pop(context, _stickerBytes),
        ),
        const SizedBox(height: 12),
        _neonButton(
          label: 'REGENERATE',
          icon: Icons.refresh,
          color: AppTheme.neonCyan,
          onTap: _generate,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            setState(() => _phase = _Phase.ready);
          },
          child: Text(
            'CHANGE PROMPT',
            style: TextStyle(
                color: Colors.white38, fontSize: 13, letterSpacing: 1),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _neonGlowBox(
            color: AppTheme.neonRed,
            child:
                const Icon(Icons.error_outline, color: AppTheme.neonRed, size: 36),
          ),
          const SizedBox(height: 20),
          Text('ERROR',
              style:
                  AppTheme.neonTextStyle(color: AppTheme.neonRed, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _neonButton(
            label: 'RETRY',
            icon: Icons.refresh,
            color: AppTheme.neonRed,
            onTap: _initialise,
          ),
        ],
      ),
    );
  }

  // ── Helper widgets ──────────────────────────────────────────────────────────

  Widget _buildExamples() {
    const examples = [
      'red tractor',
      'cyberpunk skull',
      'tiny dragon',
      'glowing sword',
      'pixel cat',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('EXAMPLES',
            style: TextStyle(
                color: Colors.white24, fontSize: 10, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: examples
              .map((e) => GestureDetector(
                    onTap: () {
                      _promptController.text = e;
                      _promptController.selection = TextSelection.fromPosition(
                        TextPosition(offset: e.length),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppTheme.neonCyan.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(20),
                        color: AppTheme.neonCyan.withOpacity(0.05),
                      ),
                      child: Text(
                        e,
                        style: TextStyle(
                            color: AppTheme.neonCyan.withOpacity(0.7),
                            fontSize: 12),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _neonGlowBox({
    required Widget child,
    Color color = AppTheme.neonCyan,
    double size = 72,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.7), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.3), blurRadius: 20),
        ],
        color: color.withOpacity(0.08),
      ),
      child: Center(child: child),
    );
  }

  Widget _neonButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.8), width: 1),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.25), blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppTheme.neonTextStyle(color: color, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
