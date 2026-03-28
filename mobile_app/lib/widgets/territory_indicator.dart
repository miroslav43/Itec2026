import 'package:flutter/material.dart';
import '../models/poster_model.dart';
import '../theme/app_theme.dart';

class TerritoryIndicator extends StatelessWidget {
  final Territory? territory;
  final String currentTeamId;
  
  const TerritoryIndicator({
    super.key,
    this.territory,
    required this.currentTeamId,
  });

  @override
  Widget build(BuildContext context) {
    if (territory == null || territory!.teams.isEmpty) {
      return _buildEmptyState();
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.neonBoxDecoration(
        color: AppTheme.neonPurple,
        glowIntensity: 0.2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TERRITORY CONTROL',
                style: TextStyle(
                  color: AppTheme.neonPurple.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              if (territory!.dominantTeam != null)
                _buildDominantBadge(territory!.dominantTeam!),
            ],
          ),
          const SizedBox(height: 8),
          
          // Territory bar
          _buildTerritoryBar(),
          
          const SizedBox(height: 8),
          
          // Team percentages
          _buildTeamStats(),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.neonBoxDecoration(
        color: AppTheme.neonPurple,
        glowIntensity: 0.2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.grid_4x4,
            color: AppTheme.neonPurple.withOpacity(0.5),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'NO TERRITORY CLAIMED',
            style: TextStyle(
              color: AppTheme.neonPurple.withOpacity(0.5),
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDominantBadge(String teamId) {
    final color = _getTeamColor(teamId);
    final isMyTeam = teamId == currentTeamId;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events,
            color: color,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            isMyTeam ? 'YOU LEAD!' : teamId.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTerritoryBar() {
    final teams = territory!.teams;
    if (teams.isEmpty) return const SizedBox.shrink();
    
    // Sort teams by percentage
    final sortedTeams = teams.entries.toList()
      ..sort((a, b) => b.value.percentage.compareTo(a.value.percentage));
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 8,
        child: Row(
          children: sortedTeams.map((entry) {
            final teamId = entry.key;
            final percentage = entry.value.percentage;
            if (percentage == 0) return const SizedBox.shrink();
            
            return Expanded(
              flex: percentage,
              child: Container(
                color: _getTeamColor(teamId),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  Widget _buildTeamStats() {
    final teams = territory!.teams;
    if (teams.isEmpty) return const SizedBox.shrink();
    
    // Sort and show top teams
    final sortedTeams = teams.entries.toList()
      ..sort((a, b) => b.value.percentage.compareTo(a.value.percentage));
    
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: sortedTeams.take(4).map((entry) {
        final teamId = entry.key;
        final percentage = entry.value.percentage;
        final color = _getTeamColor(teamId);
        final isMyTeam = teamId == currentTeamId;
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isMyTeam ? 'YOU' : teamId.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isMyTeam ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$percentage%',
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
  
  Color _getTeamColor(String teamId) {
    return AppTheme.teamColors[teamId] ?? AppTheme.neonCyan;
  }
}
