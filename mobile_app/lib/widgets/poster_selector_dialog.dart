import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';

class PosterSelectorDialog extends StatelessWidget {
  final Function(String) onPosterSelected;
  
  const PosterSelectorDialog({
    super.key,
    required this.onPosterSelected,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final posters = appState.posters.values.toList();
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: AppTheme.neonBoxDecoration(
          color: AppTheme.neonCyan,
          glowIntensity: 0.4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.neonCyan.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SELECT POSTER',
                    style: AppTheme.neonTextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 18,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close,
                      color: AppTheme.neonCyan.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            
            // Poster grid
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: posters.length,
                itemBuilder: (context, index) {
                  final poster = posters[index];
                  return _buildPosterCard(context, poster);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPosterCard(BuildContext context, dynamic poster) {
    final colors = [
      AppTheme.neonCyan,
      AppTheme.neonPink,
      AppTheme.neonPurple,
      AppTheme.neonGreen,
      AppTheme.neonYellow,
      AppTheme.neonOrange,
    ];
    final color = colors[poster.id.hashCode % colors.length];
    
    return GestureDetector(
      onTap: () {
        HapticService.mediumImpact();
        onPosterSelected(poster.id);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.darkBgTertiary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Poster icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: color.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.image,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            
            // Poster name
            Text(
              poster.name,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            
            // Poster ID
            Text(
              poster.id.toUpperCase(),
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
