import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/drawing_provider.dart';
import '../providers/socket_provider.dart';
import '../services/haptic_service.dart';
import '../services/player_stats_service.dart';
import '../theme/app_theme.dart';

class DrawingToolbar extends StatelessWidget {
  const DrawingToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final drawingProvider = context.watch<DrawingProvider>();
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.neonBoxDecoration(
        color: AppTheme.neonCyan,
        glowIntensity: 0.3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color palette
          _buildColorPalette(context, drawingProvider),
          const SizedBox(height: 12),

          // Level + brush size indicator (replaces slider)
          _buildLevelIndicator(drawingProvider),
          const SizedBox(height: 12),
          
          // Tool buttons
          _buildToolButtons(context, drawingProvider),
        ],
      ),
    );
  }
  
  Widget _buildColorPalette(BuildContext context, DrawingProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ...provider.availableColors.map((color) {
          final isSelected = provider.currentColor == color && !provider.isEraserMode;
          return GestureDetector(
            onTap: () { HapticService.selectionClick(); provider.setColor(color); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: isSelected ? 36 : 28,
              height: isSelected ? 36 : 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isSelected ? AppTheme.goldBright : AppTheme.gold.withOpacity(0.35),
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: color.withOpacity(0.65), blurRadius: 10, spreadRadius: 1),
                       BoxShadow(color: AppTheme.gold.withOpacity(0.3), blurRadius: 6)]
                    : null,
              ),
            ),
          );
        }),
        GestureDetector(
          onTap: () => _showColorPicker(context, provider),
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: const SweepGradient(colors: [
                Colors.red, Colors.orange, Colors.yellow,
                Colors.green, Colors.blue, Colors.purple, Colors.red,
              ]),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppTheme.gold.withOpacity(0.5), width: 1),
            ),
            child: Icon(Icons.colorize, size: 14, color: Colors.white.withOpacity(0.9)),
          ),
        ),
      ],
    );
  }

  Widget _buildLevelIndicator(DrawingProvider provider) {
    final level    = PlayerStatsService.level;
    final brushSz  = PlayerStatsService.brushSizeForLevel;
    final progress = PlayerStatsService.levelProgress;
    return Row(children: [
      Text('⚔', style: TextStyle(fontSize: 14, color: AppTheme.goldBright)),
      const SizedBox(width: 5),
      Text('LVL $level',
          style: AppTheme.cinzel(fontSize: 12, color: AppTheme.goldBright, letterSpacing: 1.5)),
      const SizedBox(width: 8),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppTheme.gold.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gold),
            minHeight: 5,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('${brushSz.round()}px',
          style: AppTheme.cinzel(
              fontSize: 11, color: AppTheme.parchment.withOpacity(0.7), letterSpacing: 1)),
    ]);
  }

  Widget _buildToolButtons(BuildContext context, DrawingProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _MedievalToolBtn(
          icon: Icons.auto_fix_high,
          label: 'RADIERE',
          active: provider.isEraserMode,
          activeColor: AppTheme.neonPink,
          onTap: () { HapticService.mediumImpact(); provider.toggleEraser(); },
        ),
        _MedievalToolBtn(
          icon: Icons.delete_forever,
          label: 'CURĂȚĂ',
          active: false,
          activeColor: AppTheme.neonRed,
          onTap: () { HapticService.heavyImpact(); _showClearConfirmation(context, provider); },
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context, DrawingProvider provider) {
    Color pickerColor = provider.currentColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: AppTheme.gold.withOpacity(0.7), width: 1.5),
        ),
        title: Text('ALEGE CULOAREA',
            style: AppTheme.neonTextStyle(color: AppTheme.gold, fontSize: 14)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            pickerAreaHeightPercent: 0.7,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ÎNAPOI',
                style: AppTheme.cinzel(fontSize: 12, color: AppTheme.parchment.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () { provider.setColor(pickerColor); Navigator.pop(context); },
            child: Text('SELECTEAZĂ',
                style: AppTheme.cinzel(fontSize: 12, color: AppTheme.goldBright)),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmation(BuildContext context, DrawingProvider provider) {
    final socketProvider = context.read<SocketProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkBgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: AppTheme.neonRed.withOpacity(0.8), width: 1.5),
        ),
        title: Row(children: [
          const Text('🔥', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text('ARDERE TOTALĂ',
              style: AppTheme.neonTextStyle(color: AppTheme.neonRed, fontSize: 14)),
        ]),
        content: Text(
          'Teritoriul va fi curățat pentru TOȚI luptătorii din cetate!',
          style: AppTheme.cinzel(fontSize: 12, color: AppTheme.parchment.withOpacity(0.8),
              letterSpacing: 0.8, weight: FontWeight.normal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('RETRAGE-TE',
                style: AppTheme.cinzel(fontSize: 11, color: AppTheme.parchment.withOpacity(0.4))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonRed.withOpacity(0.25),
              foregroundColor: AppTheme.neonRed,
              side: BorderSide(color: AppTheme.neonRed.withOpacity(0.7)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () {
              socketProvider.clearCanvas();
              provider.clearLocalStrokes();
              Navigator.pop(ctx);
            },
            child: Text('ARD TOTUL',
                style: AppTheme.cinzel(fontSize: 12, color: AppTheme.neonRed)),
          ),
        ],
      ),
    );
  }
}

class _MedievalToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _MedievalToolBtn({required this.icon, required this.label,
      required this.active, required this.activeColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = active ? activeColor : AppTheme.gold.withOpacity(0.6);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c, width: active ? 2 : 1),
          boxShadow: active ? [BoxShadow(color: activeColor.withOpacity(0.3), blurRadius: 8)] : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(height: 3),
          Text(label, style: AppTheme.cinzel(fontSize: 9, color: c, letterSpacing: 1)),
        ]),
      ),
    );
  }
}
