import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/drawing_provider.dart';
import '../providers/socket_provider.dart';
import '../services/haptic_service.dart';
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
          
          // Brush size slider
          _buildBrushSizeSelector(context, drawingProvider),
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
  
  Widget _buildBrushSizeSelector(BuildContext context, DrawingProvider provider) {
    return Row(
      children: [
        Icon(
          Icons.brush,
          color: AppTheme.neonCyan.withOpacity(0.7),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.neonCyan,
              inactiveTrackColor: AppTheme.neonCyan.withOpacity(0.2),
              thumbColor: AppTheme.neonCyan,
              overlayColor: AppTheme.neonCyan.withOpacity(0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: provider.brushSize,
              min: 2,
              max: 40,
              onChanged: (value) {
                provider.setBrushSize(value);
              },
              onChangeEnd: (_) {
                HapticService.selectionClick();
              },
            ),
          ),
        ),
        Container(
          width: 40,
          alignment: Alignment.center,
          child: Text(
            '${provider.brushSize.round()}',
            style: const TextStyle(
              color: AppTheme.neonCyan,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildToolButtons(BuildContext context, DrawingProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Brush sizes
        ...provider.brushSizes.map((size) {
          final isSelected = provider.brushSize == size;
          return GestureDetector(
            onTap: () {
              HapticService.selectionClick();
              provider.setBrushSize(size);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected 
                    ? AppTheme.neonCyan.withOpacity(0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected 
                      ? AppTheme.neonCyan 
                      : AppTheme.neonCyan.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Center(
                child: Container(
                  width: size / 2 + 4,
                  height: size / 2 + 4,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.neonCyan : Colors.white54,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
        
        const SizedBox(width: 8),
        
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
