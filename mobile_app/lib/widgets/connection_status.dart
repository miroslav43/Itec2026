import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/socket_provider.dart';
import '../theme/app_theme.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final socketProvider = context.watch<SocketProvider>();
    final isConnected = socketProvider.isConnected;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isConnected ? AppTheme.neonGreen : AppTheme.neonRed).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isConnected ? AppTheme.neonGreen : AppTheme.neonRed).withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPulsingDot(isConnected),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(
              color: isConnected ? AppTheme.neonGreen : AppTheme.neonRed,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPulsingDot(bool isConnected) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isConnected 
                ? AppTheme.neonGreen.withOpacity(value) 
                : AppTheme.neonRed,
            shape: BoxShape.circle,
            boxShadow: isConnected
                ? [
                    BoxShadow(
                      color: AppTheme.neonGreen.withOpacity(0.5 * value),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
      onEnd: () {},
    );
  }
}
