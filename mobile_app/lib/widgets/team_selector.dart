import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';

class TeamSelector extends StatelessWidget {
  const TeamSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: AppTheme.neonBoxDecoration(
        color: AppTheme.neonPurple,
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
                  color: AppTheme.neonPurple.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield,
                  color: AppTheme.neonPurple,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'CHOOSE YOUR TEAM',
                  style: AppTheme.neonTextStyle(
                    color: AppTheme.neonPurple,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          
          // Teams
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: appState.teams.map((team) {
                final isSelected = appState.teamId == team.id;
                final color = _parseColor(team.color);
                
                return GestureDetector(
                  onTap: () {
                    HapticService.mediumImpact();
                    appState.setTeam(team.id);
                    Future.delayed(const Duration(milliseconds: 300), () {
                      Navigator.pop(context);
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? color.withOpacity(0.3) 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected 
                            ? color 
                            : color.withOpacity(0.3),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Team color indicator
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        
                        // Team name
                        Text(
                          team.id.toUpperCase(),
                          style: TextStyle(
                            color: isSelected ? color : color.withOpacity(0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Username input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              onChanged: (value) => appState.setUsername(value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter username (optional)',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(
                  Icons.person,
                  color: AppTheme.neonPurple.withOpacity(0.5),
                ),
                filled: true,
                fillColor: AppTheme.darkBgTertiary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.neonPurple.withOpacity(0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.neonPurple.withOpacity(0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.neonPurple,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Color _parseColor(String hexColor) {
    String hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
