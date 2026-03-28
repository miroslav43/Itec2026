import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/drawing_provider.dart';
import '../providers/socket_provider.dart';
import '../screens/sticker_generator_screen.dart';
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
            onTap: () {
              HapticService.selectionClick();
              provider.setColor(color);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isSelected ? 40 : 32,
              height: isSelected ? 40 : 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
        // Custom color picker
        GestureDetector(
          onTap: () => _showColorPicker(context, provider),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const SweepGradient(
                colors: [
                  Colors.red,
                  Colors.orange,
                  Colors.yellow,
                  Colors.green,
                  Colors.blue,
                  Colors.purple,
                  Colors.red,
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
            ),
            child: const Icon(
              Icons.colorize,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildLevelIndicator(DrawingProvider provider) {
    final level = PlayerStatsService.level;
    final brushSize = PlayerStatsService.brushSizeForLevel;
    final progress = PlayerStatsService.levelProgress;
    return Row(
      children: [
        Icon(Icons.bolt, color: AppTheme.neonYellow, size: 18),
        const SizedBox(width: 4),
        Text(
          'LVL $level',
          style: const TextStyle(
            color: AppTheme.neonYellow,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppTheme.neonYellow.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.neonYellow),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.brush, color: AppTheme.neonCyan.withOpacity(0.7), size: 16),
        const SizedBox(width: 4),
        Text(
          '${brushSize.round()}px',
          style: TextStyle(
            color: AppTheme.neonCyan.withOpacity(0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  
  Widget _buildToolButtons(BuildContext context, DrawingProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Eraser
        GestureDetector(
          onTap: () {
            HapticService.mediumImpact();
            provider.toggleEraser();
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: provider.isEraserMode 
                  ? AppTheme.neonPink.withOpacity(0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: provider.isEraserMode 
                    ? AppTheme.neonPink 
                    : AppTheme.neonPink.withOpacity(0.5),
                width: provider.isEraserMode ? 2 : 1,
              ),
            ),
            child: Icon(
              Icons.auto_fix_high,
              color: provider.isEraserMode 
                  ? AppTheme.neonPink 
                  : AppTheme.neonPink.withOpacity(0.7),
              size: 22,
            ),
          ),
        ),

        // Pixel-art sticker generator
        GestureDetector(
          onTap: () => _openStickerGenerator(context, provider),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.neonYellow.withOpacity(0.7),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.neonYellow.withOpacity(0.15),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome,
              color: AppTheme.neonYellow.withOpacity(0.85),
              size: 22,
            ),
          ),
        ),
        
        // Clear (local only)
        GestureDetector(
          onTap: () {
            HapticService.heavyImpact();
            _showClearConfirmation(context, provider);
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.neonRed.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.delete_outline,
              color: AppTheme.neonRed.withOpacity(0.7),
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
  
  Future<void> _openStickerGenerator(
      BuildContext context, DrawingProvider provider) async {
    HapticService.mediumImpact();

    final result = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => const StickerGeneratorScreen(),
        fullscreenDialog: true,
      ),
    );

    if (result == null) return; // user dismissed without stamping

    // Place stamp near the centre of the canvas with a slight random offset
    // so multiple stamps don't pile on top of each other.
    final screenSize = MediaQuery.sizeOf(context);
    final cx = screenSize.width  * 0.35;
    final cy = screenSize.height * 0.35;
    provider.addStamp(result, Offset(cx, cy));
    HapticService.heavyImpact();
  }

  void _showColorPicker(BuildContext context, DrawingProvider provider) {
    Color pickerColor = provider.currentColor;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBgSecondary,
        title: Text(
          'SELECT COLOR',
          style: AppTheme.neonTextStyle(
            color: AppTheme.neonCyan,
            fontSize: 16,
          ),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
            pickerAreaHeightPercent: 0.7,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              provider.setColor(pickerColor);
              Navigator.pop(context);
            },
            child: const Text('SELECT'),
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
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.neonRed, width: 1),
        ),
        title: Text(
          'STERGE TOT?',
          style: AppTheme.neonTextStyle(color: AppTheme.neonRed, fontSize: 16),
        ),
        content: const Text(
          'Se sterge desenul pentru TOTI jucatorii din room!',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ANULEAZA', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonRed.withOpacity(0.2),
              foregroundColor: AppTheme.neonRed,
            ),
            onPressed: () {
              socketProvider.clearCanvas();
              provider.clearLocalStrokes();
              Navigator.pop(ctx);
            },
            child: const Text('STERGE TOT'),
          ),
        ],
      ),
    );
  }
}
