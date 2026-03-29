import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../services/anthem_service.dart';
import '../services/esp32_service.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';

class TeamSelector extends StatefulWidget {
  const TeamSelector({super.key});

  @override
  State<TeamSelector> createState() => _TeamSelectorState();
}

class _TeamSelectorState extends State<TeamSelector> {
  final Map<String, bool> _anthemExists = {};
  final Map<String, bool> _uploading = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAnthems());
  }

  String get _serverUrl => context.read<SocketProvider>().serverUrl;

  Future<void> _checkAnthems() async {
    final appState = context.read<AppStateProvider>();
    for (final team in appState.teams) {
      final exists = await AnthemService.anthemExists(
        serverUrl: _serverUrl,
        teamId: team.id,
      );
      if (mounted) setState(() => _anthemExists[team.id] = exists);
    }
  }

  Future<void> _pickAndUploadAnthem(String teamId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );
    if (result == null || result.files.single.path == null) return;
    final filePath = result.files.single.path!;

    setState(() => _uploading[teamId] = true);
    final ok = await AnthemService.uploadAnthem(
      serverUrl: _serverUrl,
      teamId: teamId,
      filePath: filePath,
    );
    if (mounted) {
      setState(() {
        _uploading[teamId] = false;
        _anthemExists[teamId] = ok;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Imn încărcat pentru echipa $teamId!'
            : 'Eroare la upload. Încearcă din nou.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Color _parseColor(String hexColor) {
    String hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  static Map<String, String> _teamLabel(String id) => switch (id) {
    'red'    => {'name': 'VALAHIA',  'region': 'Muntenia'},
    'blue'   => {'name': 'ARDEAL',   'region': 'Transilvania'},
    'green'  => {'name': 'MOLDOVA',  'region': 'Bucovina'},
    'purple' => {'name': 'ARCANE',   'region': 'Dobrogea'},
    _        => {'name': id.toUpperCase(), 'region': ''},
  };

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: AppTheme.panelDecoration(borderColor: AppTheme.gold),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.gold.withOpacity(0.35), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🛡', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Text('ALEGE-ȚI TABĂRA',
                    style: AppTheme.neonTextStyle(color: AppTheme.gold, fontSize: 15)),
                const SizedBox(width: 10),
                Text('🛡', style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),

          // Teams row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: appState.teams.map((team) {
                final isSelected = appState.teamId == team.id;
                final color = _parseColor(team.color);
                final label = _teamLabel(team.id);
                return GestureDetector(
                  onTap: () {
                    HapticService.mediumImpact();
                    appState.setTeam(team.id);
                    final c = _parseColor(team.color);
                    Esp32Service().sendColor(c.red, c.green, c.blue);
                    Future.delayed(const Duration(milliseconds: 300),
                        () => Navigator.pop(context));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.22) : AppTheme.darkBgSecondary,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? color : color.withOpacity(0.35),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: color.withOpacity(0.45), blurRadius: 14, spreadRadius: 1),
                             BoxShadow(color: AppTheme.gold.withOpacity(0.15), blurRadius: 20)]
                          : null,
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Shield icon coloured
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: color.withOpacity(isSelected ? 0.9 : 0.5),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: AppTheme.gold.withOpacity(0.4)),
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withOpacity(0.55), blurRadius: 8)] : null,
                        ),
                        child: isSelected
                            ? Icon(Icons.shield, color: Colors.white.withOpacity(0.9), size: 20)
                            : Icon(Icons.shield_outlined, color: Colors.white.withOpacity(0.55), size: 20),
                      ),
                      const SizedBox(height: 7),
                      Text(label['name']!,
                          style: AppTheme.cinzel(
                              fontSize: 9,
                              color: isSelected ? color : color.withOpacity(0.65),
                              letterSpacing: 1)),
                      Text(label['region']!,
                          style: AppTheme.cinzel(
                              fontSize: 7, weight: FontWeight.normal,
                              color: AppTheme.parchment.withOpacity(0.45),
                              letterSpacing: 0.5)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Anthem section ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('♪', style: TextStyle(fontSize: 13, color: AppTheme.gold.withOpacity(0.7))),
                  const SizedBox(width: 7),
                  Text('IMN DE LUPTĂ',
                      style: AppTheme.cinzel(
                          fontSize: 9, color: AppTheme.parchment.withOpacity(0.45),
                          letterSpacing: 2)),
                ]),
                const SizedBox(height: 8),
                ...appState.teams.map((team) {
                  final color = _parseColor(team.color);
                  final hasAnthem  = _anthemExists[team.id] ?? false;
                  final isUploading = _uploading[team.id] ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: color, borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(team.id.toUpperCase(),
                          style: AppTheme.cinzel(fontSize: 10, color: color, letterSpacing: 1)),
                      const SizedBox(width: 8),
                      if (hasAnthem)
                        Row(children: [
                          Text('♪', style: TextStyle(fontSize: 12, color: AppTheme.neonGreen)),
                          const SizedBox(width: 4),
                          Text('imn setat',
                              style: AppTheme.cinzel(
                                  fontSize: 9, color: AppTheme.neonGreen,
                                  letterSpacing: 1, weight: FontWeight.normal)),
                        ])
                      else
                        Text('fără imn',
                            style: AppTheme.cinzel(
                                fontSize: 9, color: AppTheme.parchment.withOpacity(0.25),
                                letterSpacing: 1, weight: FontWeight.normal)),
                      const Spacer(),
                      if (isUploading)
                        SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: AppTheme.gold))
                      else
                        Row(children: [
                          GestureDetector(
                            onTap: () => _pickAndUploadAnthem(team.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: color.withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Icon(hasAnthem ? Icons.edit : Icons.upload_file,
                                    color: color, size: 12),
                                const SizedBox(width: 4),
                                Text(hasAnthem ? 'schimbă' : 'import',
                                    style: AppTheme.cinzel(
                                        fontSize: 9, color: color,
                                        letterSpacing: 1, weight: FontWeight.normal)),
                              ]),
                            ),
                          ),
                          if (hasAnthem) ...[const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _deleteAnthemHttp(team.id),
                              child: Icon(Icons.close, color: AppTheme.neonRed.withOpacity(0.7), size: 15),
                            )],
                        ]),
                    ]),
                  );
                }),
              ],
            ),
          ),

          // Username input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              onChanged: (v) => appState.setUsername(v),
              style: AppTheme.cinzel(
                  fontSize: 13, color: AppTheme.parchment, letterSpacing: 1),
              decoration: InputDecoration(
                hintText: 'NUMELE LUPTĂTORULUI',
                hintStyle: AppTheme.cinzel(
                    fontSize: 11, color: AppTheme.parchment.withOpacity(0.25),
                    letterSpacing: 1.5),
                prefixIcon: Icon(Icons.person, color: AppTheme.gold.withOpacity(0.5), size: 18),
                filled: true,
                fillColor: AppTheme.darkBgTertiary,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.25)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.25)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: AppTheme.gold.withOpacity(0.75), width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAnthemHttp(String teamId) async {
    try {
      await http
          .delete(Uri.parse('$_serverUrl/api/anthem/$teamId'))
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _anthemExists[teamId] = false);
    } catch (_) {}
  }
}
