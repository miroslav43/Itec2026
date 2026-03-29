import 'package:flutter/material.dart';
import '../services/player_stats_service.dart';
import '../theme/app_theme.dart';

class PlayerBadge extends StatelessWidget {
  const PlayerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final level = PlayerStatsService.level;
    final wins  = PlayerStatsService.wins;
    final losses = PlayerStatsService.losses;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.darkBgSecondary.withOpacity(0.92),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.gold.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(color: AppTheme.gold.withOpacity(0.18), blurRadius: 10),
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('⚔', style: TextStyle(fontSize: 11, color: AppTheme.gold)),
          const SizedBox(width: 4),
          Text(
            'LVL $level',
            style: AppTheme.cinzel(fontSize: 11, color: AppTheme.goldBright, letterSpacing: 1),
          ),
          Container(
            width: 1, height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            color: AppTheme.gold.withOpacity(0.4),
          ),
          Text('🏆', style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 3),
          Text(
            '$wins',
            style: AppTheme.cinzel(fontSize: 11, color: AppTheme.parchment, letterSpacing: 1),
          ),
          const SizedBox(width: 6),
          Text('💀', style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 3),
          Text(
            '$losses',
            style: AppTheme.cinzel(fontSize: 11,
                color: AppTheme.parchment.withOpacity(0.65), letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}
