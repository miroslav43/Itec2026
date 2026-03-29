import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/sticker_model.dart';
import '../services/ai_image_service.dart';
import '../theme/app_theme.dart';

/// Opened from BattleCanvasScreen when the user taps the STICKERS button.
/// Returns a [StickerItem] when the user taps one to place it.
class StickerGeneratorScreen extends StatefulWidget {
  const StickerGeneratorScreen({super.key});

  @override
  State<StickerGeneratorScreen> createState() => _StickerGeneratorScreenState();
}

class _StickerGeneratorScreenState extends State<StickerGeneratorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final TextEditingController _promptCtrl = TextEditingController();
  bool _generating = false;
  bool _loadingLib = false;
  bool _isGifMode = false;
  StickerItem? _generated;
  List<StickerItem> _library = [];
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadLibrary();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    setState(() => _loadingLib = true);
    final list = await AiImageService.fetchStickers();
    if (mounted) setState(() { _library = list; _loadingLib = false; });
  }

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;
    setState(() { _generating = true; _errorMsg = null; _generated = null; });
    final result = _isGifMode
        ? await AiImageService.generateGifSticker(prompt: prompt)
        : await AiImageService.generateSticker(prompt: prompt);
    if (!mounted) return;
    if (result == null) {
      setState(() { _generating = false; _errorMsg = 'Generarea a eșuat. Verifică conexiunea.'; });
    } else {
      setState(() { _generating = false; _generated = result; });
      await _loadLibrary();
    }
  }

  void _pickSticker(StickerItem sticker) {
    Navigator.of(context).pop(sticker);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_buildGenerateTab(), _buildLibraryTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back_ios_new, color: AppTheme.neonCyan, size: 20),
          ),
          const SizedBox(width: 12),
          Icon(Icons.auto_awesome, color: AppTheme.neonPurple, size: 22),
          const SizedBox(width: 8),
          Text('AI STICKERE',
              style: AppTheme.neonTextStyle(color: AppTheme.neonPurple, fontSize: 18)),
          const Spacer(),
          Text('Selectează pentru a plasa',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF0D1117),
      child: TabBar(
        controller: _tabs,
        indicatorColor: AppTheme.neonPurple,
        labelColor: AppTheme.neonPurple,
        unselectedLabelColor: Colors.white38,
        tabs: const [
          Tab(text: 'GENEREAZĂ'),
          Tab(text: 'LIBRĂRIE'),
        ],
      ),
    );
  }

  // ── GENERATE tab ────────────────────────────────────────────────────────────

  Widget _buildGenerateTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text('Descrie sticker-ul tău',
              style: TextStyle(color: Colors.white70, fontSize: 13,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          // GIF / Image toggle
          Row(
            children: [
              _ModeChip(
                label: '🖼 Imagine',
                selected: !_isGifMode,
                onTap: () => setState(() => _isGifMode = false),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                label: '✨ GIF animat',
                selected: _isGifMode,
                onTap: () => setState(() => _isGifMode = true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promptCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'ex: cyberpunk wolf, neon fish, pixel dragon...',
              hintStyle: TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: AppTheme.neonPurple.withOpacity(0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: AppTheme.neonPurple.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: AppTheme.neonPurple, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _generate(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(_generating
                  ? (_isGifMode ? 'Se animă...' : 'Se generează...')
                  : (_isGifMode ? 'GENEREAZĂ GIF' : 'GENEREAZĂ'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonPurple.withOpacity(0.2),
                foregroundColor: AppTheme.neonPurple,
                side: BorderSide(color: AppTheme.neonPurple.withOpacity(0.7)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Text(_errorMsg!,
                style: TextStyle(color: AppTheme.neonRed, fontSize: 13)),
          ],
          if (_generated != null) ...[
            const SizedBox(height: 20),
            Text('Sticker generat:',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 10),
            Center(
              child: _StickerCard(
                sticker: _generated!,
                onTap: () => _pickSticker(_generated!),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Apasă pentru a-l plasa pe canvas',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  // ── LIBRARY tab ─────────────────────────────────────────────────────────────

  Widget _buildLibraryTab() {
    if (_loadingLib) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.neonPurple),
            const SizedBox(height: 12),
            Text('Se încarcă...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (_library.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text('Niciun sticker generat încă.\nFolosește tab-ul GENEREAZĂ!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadLibrary,
              icon: Icon(Icons.refresh, color: AppTheme.neonPurple),
              label: Text('Reîncarcă',
                  style: TextStyle(color: AppTheme.neonPurple)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('${_library.length} stickere disponibile',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: _loadLibrary,
                child: Icon(Icons.refresh, color: Colors.white38, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _library.length,
            itemBuilder: (_, i) => _StickerCard(
              sticker: _library[i],
              onTap: () => _pickSticker(_library[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Mode chip ────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.neonPurple.withOpacity(0.25)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.neonPurple
                : Colors.white24,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppTheme.neonPurple : Colors.white38,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }
}

// ── Sticker card ─────────────────────────────────────────────────────────────

class _StickerCard extends StatelessWidget {
  final StickerItem sticker;
  final VoidCallback onTap;

  const _StickerCard({required this.sticker, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: sticker.isGif
              ? AppTheme.neonCyan.withOpacity(0.07)
              : AppTheme.neonPurple.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sticker.isGif
                  ? AppTheme.neonCyan.withOpacity(0.5)
                  : AppTheme.neonPurple.withOpacity(0.35),
              width: 1),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(11)),
                    child: Image.memory(
                      sticker.imageBytes,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      gaplessPlayback: false,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image, color: Colors.white24),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(
                    sticker.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                ),
              ],
            ),
            if (sticker.isGif)
              Positioned(
                top: 4, right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('GIF',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
