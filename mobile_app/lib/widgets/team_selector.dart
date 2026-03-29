import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../services/anthem_service.dart';
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
                Icon(Icons.shield, color: AppTheme.neonPurple, size: 20),
                const SizedBox(width: 8),
                Text(
                  'CHOOSE YOUR TEAM',
                  style: AppTheme.neonTextStyle(
                      color: AppTheme.neonPurple, fontSize: 16),
                ),
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
                return GestureDetector(
                  onTap: () {
                    HapticService.mediumImpact();
                    appState.setTeam(team.id);
                    Future.delayed(const Duration(milliseconds: 300),
                        () => Navigator.pop(context));
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
                          ? [BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: color.withOpacity(0.5),
                                  blurRadius: 8),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          team.id.toUpperCase(),
                          style: TextStyle(
                            color: isSelected
                                ? color
                                : color.withOpacity(0.7),
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

          // ── Anthem section ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.music_note,
                      color: AppTheme.neonCyan.withOpacity(0.7), size: 14),
                  const SizedBox(width: 6),
                  Text('IMN ECHIPĂ',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          letterSpacing: 1.5)),
                ]),
                const SizedBox(height: 8),
                ...appState.teams.map((team) {
                  final color = _parseColor(team.color);
                  final hasAnthem = _anthemExists[team.id] ?? false;
                  final isUploading = _uploading[team.id] ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          team.id.toUpperCase(),
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        if (hasAnthem)
                          Row(children: [
                            Icon(Icons.music_note,
                                color: AppTheme.neonGreen, size: 14),
                            const SizedBox(width: 4),
                            Text('imn setat',
                                style: TextStyle(
                                    color: AppTheme.neonGreen, fontSize: 10)),
                          ])
                        else
                          Text('fără imn',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 10)),
                        const Spacer(),
                        if (isUploading)
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.neonCyan))
                        else
                          Row(children: [
                            GestureDetector(
                              onTap: () => _pickAndUploadAnthem(team.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: color.withOpacity(0.4)),
                                ),
                                child: Row(children: [
                                  Icon(
                                    hasAnthem
                                        ? Icons.edit
                                        : Icons.upload_file,
                                    color: color,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    hasAnthem ? 'schimbă' : 'import MP3',
                                    style: TextStyle(
                                        color: color, fontSize: 10),
                                  ),
                                ]),
                              ),
                            ),
                            if (hasAnthem) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () async {
                                  await _deleteAnthemHttp(team.id);
                                },
                                child: Icon(Icons.delete_outline,
                                    color: AppTheme.neonRed.withOpacity(0.7),
                                    size: 16),
                              ),
                            ],
                          ]),
                      ],
                    ),
                  );
                }),
              ],
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
                hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.3)),
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
                  borderSide:
                      const BorderSide(color: AppTheme.neonPurple),
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
