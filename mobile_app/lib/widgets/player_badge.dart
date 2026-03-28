import 'package:flutter/material.dart';
import '../services/player_stats_service.dart';
import '../theme/app_theme.dart';

class PlayerBadge extends StatelessWidget {
  const PlayerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final level = PlayerStatsService.level;
    final wins = PlayerStatsService.wins;
    final losses = PlayerStatsService.losses;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.darkBgSecondary.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.neonYellow.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonYellow.withOpacity(0.12),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: AppTheme.neonYellow, size: 13),
          const SizedBox(width: 2),
          Text(
            '$level',
            style: const TextStyle(
              color: AppTheme.neonYellow,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          const Text('🏆', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 2),
          Text(
            '$wins',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          const Text('💀', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 2),
          Text(
            '$losses',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
