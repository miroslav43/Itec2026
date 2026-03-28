import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'camera_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  String _statusText = 'Initializing...';
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLoading());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _setProgress(double p, String text) {
    if (mounted) setState(() { _progress = p; _statusText = text; });
  }

  Future<void> _runLoading() async {
    _setProgress(0.1, 'Inițializare servicii...');
    await HapticService.init();
    await AudioService.init();

    _setProgress(0.5, 'Conectare la server...');
    final socketProvider = context.read<SocketProvider>();
    AuthService.serverUrl = socketProvider.serverUrl;

    _setProgress(0.8, 'Verificare autentificare...');
    final user = await AuthService.checkAuth();

    _setProgress(1.0, 'Gata!');
    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;
    if (user != null) {
      context.read<AppStateProvider>().setUsername(user.username);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).round();

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // ── Logo ──────────────────────────────────────────────────────
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.neonCyan
                          .withOpacity(0.4 + _pulseCtrl.value * 0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonCyan
                            .withOpacity(0.15 + _pulseCtrl.value * 0.25),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                    ],
                    color: AppTheme.darkBgSecondary,
                  ),
                  child: const Icon(Icons.layers,
                      color: AppTheme.neonCyan, size: 44),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('iTEC',
                      style: AppTheme.neonTextStyle(
                          color: AppTheme.neonCyan, fontSize: 32)),
                  const SizedBox(width: 8),
                  Text('OVERRIDE',
                      style: AppTheme.neonTextStyle(
                          color: AppTheme.neonPink, fontSize: 32)),
                ],
              ),

              const Spacer(flex: 2),

              // ── Progress bar ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _statusText,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                  ),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: AppTheme.neonCyan.withOpacity(0.1),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppTheme.neonCyan),
                ),
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
