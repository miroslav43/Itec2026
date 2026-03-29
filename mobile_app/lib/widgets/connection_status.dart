import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/socket_provider.dart';
import '../theme/app_theme.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final isConnected = context.watch<SocketProvider>().isConnected;
    final accent = isConnected ? AppTheme.neonGreen : AppTheme.neonRed;
    final label  = isConnected ? 'CETATEA ACTIVA' : 'DECONECTAT';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.darkBgSecondary.withOpacity(0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withOpacity(0.55), width: 1.2),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1.0),
            duration: const Duration(milliseconds: 900),
            builder: (_, v, __) => Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(isConnected ? v : 1.0),
                boxShadow: isConnected
                    ? [BoxShadow(color: accent.withOpacity(0.5 * v), blurRadius: 5)]
                    : null,
              ),
            ),
            onEnd: () {},
          ),
          const SizedBox(width: 6),
          Text(label,
              style: AppTheme.cinzel(
                  fontSize: 9, color: accent, letterSpacing: 1.2)),
        ],
      ),
    );
  }
}
