import 'package:flutter/material.dart';

class BattleScreenPlaceholder extends StatelessWidget {
  final String posterId;
  const BattleScreenPlaceholder({super.key, required this.posterId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'BATTLE — $posterId'.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 2),
                        color: Colors.cyanAccent.withOpacity(0.05),
                      ),
                      child: const Icon(Icons.sports_esports,
                          color: Colors.cyanAccent, size: 64),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'BATTLE SCREEN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Poster: $posterId',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '(placeholder — integrate with BattleCanvasScreen)',
                      style: TextStyle(color: Colors.white30, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
