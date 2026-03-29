import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../theme/app_theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// ── Data model ────────────────────────────────────────────────────────────────

class PosterPin {
  final double x, y, z, nx, ny, nz;

  const PosterPin({
    required this.x, required this.y, required this.z,
    this.nx = 0, this.ny = 1, this.nz = 0,
  });

  Map<String, double> toJson() =>
      {'x': x, 'y': y, 'z': z, 'nx': nx, 'ny': ny, 'nz': nz};

  factory PosterPin.fromJson(Map<String, dynamic> j) => PosterPin(
        x: (j['x'] as num).toDouble(), y: (j['y'] as num).toDouble(),
        z: (j['z'] as num).toDouble(), nx: (j['nx'] as num).toDouble(),
        ny: (j['ny'] as num).toDouble(), nz: (j['nz'] as num).toDouble(),
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

class _MapScreenState extends State<MapScreen> {
  WebViewController? _webCtrl;
  bool  _modelReady = false;
  bool  _pinMode    = false;
  int   _activeIdx  = 0;

  Map<String, PosterPin> _pins = {};   // posterId → PosterPin
  PosterPin? _pendingPin;              // waiting for poster selection
  final Set<String> _visiblePins = {}; // pins currently shown (conquered)
  Timer? _pollTimer;

  // 10 distinct neon colours for poster pins
  static const _pinHex = [
    '#FF0040','#00D4FF','#00FF88','#9D00FF','#FF6B00',
    '#FFE000','#FF69B4','#00BFFF','#FF4500','#39FF14',
  ];

  // ── JS injected into model-viewer page ─────────────────────────────────────
  static const _kJs = r"""
(function(){
  function init(mv){
    mv.addEventListener('load', function(){
      try{ FlutterReady.postMessage('ready'); }catch(e){}
    });

    // Query 3D position at given screen coordinates
    window.queryCenter = function(cx, cy){
      var x=0,y=0,z=0,nx=0,ny=1,nz=0,hit=false;
      try{
        var r = mv.positionAndNormalFromPoint(cx, cy);
        if(r){ x=r.position.x;y=r.position.y;z=r.position.z;
               nx=r.normal.x;ny=r.normal.y;nz=r.normal.z;hit=true; }
      }catch(err){}
      try{
        FlutterChannel.postMessage(JSON.stringify(
          {t: hit?'pin':'miss', x:x,y:y,z:z, nx:nx,ny:ny,nz:nz}));
      }catch(e){}
    };

    window.addPin = function(id,x,y,z,nx,ny,nz,label,color){
      var old = mv.querySelector('[slot="hotspot-'+id+'"]');
      if(old) old.remove();
      var btn = document.createElement('button');
      btn.slot = 'hotspot-'+id;
      btn.dataset.position = x+' '+y+' '+z;
      btn.dataset.normal   = nx+' '+ny+' '+nz;
      btn.dataset.visibilityAttribute = 'visible';
      btn.dataset.conquered = '0';
      btn.style.cssText = 'background:'+color+
        ';border:2.5px solid #fff;border-radius:50%;width:22px;height:22px;'+
        'cursor:pointer;padding:0;position:relative;'+
        'box-shadow:0 0 10px '+color+';display:none;';
      var lbl = document.createElement('div');
      lbl.textContent = label;
      lbl.style.cssText = 'position:absolute;background:rgba(0,0,0,.88);'+
        'color:#fff;padding:3px 8px;border-radius:6px;font-size:11px;'+
        'font-family:monospace;white-space:nowrap;bottom:26px;left:50%;'+
        'transform:translateX(-50%);border:1px solid '+color+
        ';letter-spacing:1px;pointer-events:none;';
      btn.appendChild(lbl);
      mv.appendChild(btn);
    };

    window.showPin = function(id, color){
      var btn = mv.querySelector('[slot="hotspot-'+id+'"]');
      if(!btn) return;
      btn.dataset.conquered = '1';
      btn.style.display = 'block';
      if(color){
        btn.style.background = color;
        btn.style.boxShadow = '0 0 18px '+color+', 0 0 6px #fff';
        btn.style.borderColor = '#fff';
        var lbl = btn.querySelector('div');
        if(lbl) lbl.style.borderColor = color;
      }
    };

    window.hidePin = function(id){
      var btn = mv.querySelector('[slot="hotspot-'+id+'"]');
      if(btn){ btn.style.display='none'; btn.dataset.conquered='0'; }
    };

    window.removePin = function(id){
      var old = mv.querySelector('[slot="hotspot-'+id+'"]');
      if(old) old.remove();
    };

    window.jumpTo = function(x,y,z){
      mv.cameraTarget = x+'m '+y+'m '+z+'m';
      mv.cameraOrbit  = 'auto 75deg 2m';
    };

    window.resetCam = function(){
      mv.cameraTarget = 'auto auto auto';
      mv.cameraOrbit  = 'auto auto auto';
    };
  }

  var mv = document.querySelector('model-viewer');
  if(mv){ init(mv); }
  else{
    var obs = new MutationObserver(function(){
      mv = document.querySelector('model-viewer');
      if(mv){ obs.disconnect(); init(mv); }
    });
    obs.observe(document.body,{childList:true,subtree:true});
  }
})();
""";

  static const _kCss = r"""
button[slot^="hotspot-"] { display:none; }
button[slot^="hotspot-"][data-conquered="1"] { display:block !important; }
""";

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  String get _serverUrl => context.read<SocketProvider>().serverUrl;

  @override
  void initState() {
    super.initState();
    _loadPins();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTerritories();
      context.read<AppStateProvider>().addListener(_onTerritoryChanged);
      // poll territory from backend every 30s
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pollTerritoryFromBackend(),
      );
      _pollTerritoryFromBackend();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // safe remove — might already be disposed
    try { context.read<AppStateProvider>().removeListener(_onTerritoryChanged); } catch (_) {}
    super.dispose();
  }

  void _onTerritoryChanged() {
    if (!mounted) return;
    _syncPinVisibility();
  }

  Future<void> _loadPins() async {
    // 1. Load from SharedPreferences immediately (fast)
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('poster_pins_v1');
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) setState(() {
          _pins = map.map((k, v) =>
              MapEntry(k, PosterPin.fromJson(v as Map<String, dynamic>)));
        });
      } catch (_) {}
    }
    // 2. Fetch from backend (authoritative)
    try {
      final resp = await http
          .get(Uri.parse('$_serverUrl/api/map-pins'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        final fetched = <String, PosterPin>{};
        for (final item in list) {
          fetched[item['poster_id'] as String] = PosterPin(
            x:  (item['x']  as num).toDouble(),
            y:  (item['y']  as num).toDouble(),
            z:  (item['z']  as num).toDouble(),
            nx: (item['nx'] as num).toDouble(),
            ny: (item['ny'] as num).toDouble(),
            nz: (item['nz'] as num).toDouble(),
          );
        }
        if (mounted) setState(() => _pins = fetched);
        // update local cache
        prefs.setString('poster_pins_v1',
            jsonEncode(fetched.map((k, v) => MapEntry(k, v.toJson()))));
      }
    } catch (_) { /* offline - use cached */ }
  }

  Future<void> _savePins() async {
    // local cache
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('poster_pins_v1',
        jsonEncode(_pins.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> _savePinToBackend(String posterId, PosterPin pin) async {
    try {
      await http
          .post(
            Uri.parse('$_serverUrl/api/map-pins/$posterId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(pin.toJson()),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> _deletePinFromBackend(String posterId) async {
    try {
      await http
          .delete(Uri.parse('$_serverUrl/api/map-pins/$posterId'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  void _fetchTerritories() {
    final socket   = context.read<SocketProvider>();
    final appState = context.read<AppStateProvider>();
    for (final id in appState.posters.keys) {
      socket.getPosterState(id);
    }
  }

  Future<void> _pollTerritoryFromBackend() async {
    try {
      final resp = await http
          .get(Uri.parse('$_serverUrl/api/territory'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200 || !mounted) return;
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final appState = context.read<AppStateProvider>();
      for (final entry in map.entries) {
        // Build a minimal territory object from the backend response
        final rawTerritory = entry.value as Map<String, dynamic>;
        // We only need to know if there's a dominant team
        final dominant = rawTerritory['dominant'] as String?;
        if (dominant != null && _pins.containsKey(entry.key)) {
          _revealPin(entry.key, dominant, appState);
        }
      }
    } catch (_) {}
  }

  void _syncPinVisibility() {
    if (!mounted || !_modelReady) return;
    final appState = context.read<AppStateProvider>();
    for (final posterId in _pins.keys) {
      final territory = appState.posterTerritories[posterId];
      final dominant  = territory?.dominantTeam;
      if (dominant != null) {
        _revealPin(posterId, dominant, appState);
      }
    }
  }

  void _revealPin(String posterId, String dominantTeam, AppStateProvider appState) {
    if (_visiblePins.contains(posterId)) return; // already shown
    final teamColor = appState.teams
        .where((t) => t.id == dominantTeam)
        .map((t) => t.color)
        .firstOrNull ?? '#FFFFFF';
    _visiblePins.add(posterId);
    _webCtrl?.runJavaScript("showPin('$posterId','$teamColor')");
  }

  // ── JS callbacks ────────────────────────────────────────────────────────────

  void _onModelReady(JavaScriptMessage _) {
    setState(() => _modelReady = true);
    for (final e in _pins.entries) {
      _sendPinToViewer(e.key, e.value);
    }
    // Reveal any already-conquered pins right after loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPinVisibility();
      _pollTerritoryFromBackend();
    });
  }

  void _onJsMessage(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    final type = data['t'] as String;

    if (type == 'miss') {
      setState(() => _pinMode = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Apasă pe suprafața modelului 3D'),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    if (type == 'pin') {
      setState(() => _pinMode = false);
      _pendingPin = PosterPin(
        x: (data['x'] as num).toDouble(), y: (data['y'] as num).toDouble(),
        z: (data['z'] as num).toDouble(), nx: (data['nx'] as num).toDouble(),
        ny: (data['ny'] as num).toDouble(), nz: (data['nz'] as num).toDouble(),
      );
      _showPosterSelector();
    }
  }

  // ── Feature 1 – pin placement ───────────────────────────────────────────────

  void _confirmPlacePin() {
    if (!_modelReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Modelul 3D se încarcă, încearcă din nou'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: AppTheme.neonGreen.withOpacity(0.6), width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.push_pin, color: AppTheme.neonGreen, size: 22),
            const SizedBox(width: 10),
            Text('Plasează pin',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Ești sigur că vrei să pui pin-ul în centrul țintei?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Anulează',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _placePinAtCenter();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonGreen.withOpacity(0.15),
              foregroundColor: AppTheme.neonGreen,
              side: BorderSide(
                  color: AppTheme.neonGreen.withOpacity(0.7)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('DA, pune pin-ul!',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _placePinAtCenter() {
    final size = MediaQuery.of(context).size;
    final cx   = size.width  / 2;
    final cy   = size.height / 2;
    _webCtrl?.runJavaScript('queryCenter($cx, $cy)');
  }

  void _showPosterSelector() {
    final appState = context.read<AppStateProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PosterPickerSheet(
        posters: appState.posters,
        alreadyPinned: _pins.keys.toSet(),
        onPicked: (posterId) {
          final pin = _pendingPin;
          _pendingPin = null;
          if (pin != null) _commitPin(posterId, pin);
        },
        onCancel: () { _pendingPin = null; },
      ),
    );
  }

  void _commitPin(String posterId, PosterPin pin) {
    setState(() => _pins[posterId] = pin);
    _savePins();
    _savePinToBackend(posterId, pin);
    _sendPinToViewer(posterId, pin);
  }

  void _removePin(String posterId) {
    setState(() {
      _pins.remove(posterId);
      _visiblePins.remove(posterId);
    });
    _savePins();
    _deletePinFromBackend(posterId);
    _webCtrl?.runJavaScript("removePin('$posterId')");
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppTheme.neonRed.withOpacity(0.6), width: 1.5),
        ),
        title: Row(children: [
          Icon(Icons.delete_forever, color: AppTheme.neonRed, size: 22),
          const SizedBox(width: 10),
          Text('Șterge toți pin-ii',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Text('Toți pin-ii vor fi șterși din DB și cache. Nu se poate anula.',
            style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Anulează', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _clearAllPins(); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonRed.withOpacity(0.15),
              foregroundColor: AppTheme.neonRed,
              side: BorderSide(color: AppTheme.neonRed.withOpacity(0.7)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ȘTERGE TOT', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllPins() async {
    // 1. Remove from 3D viewer
    for (final id in _pins.keys) {
      _webCtrl?.runJavaScript("removePin('$id')");
    }
    // 2. Clear state
    setState(() { _pins.clear(); _visiblePins.clear(); });
    // 3. Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('poster_pins_v1');
    // 4. Clear backend DB
    try {
      await http
          .delete(Uri.parse('$_serverUrl/api/map-pins'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Toți pin-ii au fost șterși'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  void _sendPinToViewer(String posterId, PosterPin pin) {
    final appState = context.read<AppStateProvider>();
    final poster   = appState.posters[posterId];
    final label    = (poster?.name ?? posterId).replaceAll("'", "\\'");
    final idx      = appState.posters.keys.toList().indexOf(posterId);
    final color    = _pinHex[idx.clamp(0, _pinHex.length - 1)];
    _webCtrl?.runJavaScript(
      "addPin('$posterId',${pin.x},${pin.y},${pin.z},"
      "${pin.nx},${pin.ny},${pin.nz},'$label','$color')",
    );
  }

  // ── Feature 2 – camera cycling ──────────────────────────────────────────────

  List<String> get _pinnedIds {
    final order = context.read<AppStateProvider>().posters.keys.toList();
    return order.where(_pins.containsKey).toList();
  }

  void _jumpPrev() {
    final ids = _pinnedIds;
    if (ids.isEmpty) return;
    setState(() => _activeIdx = (_activeIdx - 1 + ids.length) % ids.length);
    _jumpToActive(ids);
  }

  void _jumpNext() {
    final ids = _pinnedIds;
    if (ids.isEmpty) return;
    setState(() => _activeIdx = (_activeIdx + 1) % ids.length);
    _jumpToActive(ids);
  }

  void _jumpToActive(List<String> ids) {
    if (_activeIdx >= ids.length) _activeIdx = 0;
    final pin = _pins[ids[_activeIdx]]!;
    _webCtrl?.runJavaScript('jumpTo(${pin.x},${pin.y},${pin.z})');
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pinnedIds    = _pinnedIds;
    final hasPins      = pinnedIds.isNotEmpty;
    final safeIdx      = hasPins ? _activeIdx.clamp(0, pinnedIds.length - 1) : 0;
    final activePoster = hasPins
        ? context.read<AppStateProvider>().posters[pinnedIds[safeIdx]]
        : null;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // ── 3D model ──────────────────────────────────────────────
          Positioned.fill(
            child: ModelViewer(
              src: 'assets/map/venue_map.glb',
              alt: 'Harta 3D',
              cameraControls: true,
              autoRotate: false,
              backgroundColor: AppTheme.darkBg,
              relatedCss: _kCss,
              relatedJs: _kJs,
              javascriptChannels: {
                JavascriptChannel('FlutterReady',
                    onMessageReceived: _onModelReady),
                JavascriptChannel('FlutterChannel',
                    onMessageReceived: _onJsMessage),
              },
              onWebViewCreated: (ctrl) => setState(() => _webCtrl = ctrl),
            ),
          ),

          // ── Permanent crosshair (target) ───────────────────────
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: _Crosshair(),
              ),
            ),
          ),

          // ── Top bar ───────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(child: _buildTopBar()),
          ),

          // ── Feature 2: bottom nav arrows ─────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: _buildBottomNav(hasPins, pinnedIds, safeIdx, activePoster),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkBg.withOpacity(0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.35), width: 1),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back_ios_new,
                color: AppTheme.neonCyan, size: 20),
          ),
          const SizedBox(width: 10),
          Text('HARTA 3D',
              style: AppTheme.neonTextStyle(
                  color: AppTheme.neonCyan, fontSize: 16)),
          const SizedBox(width: 4),
          Text('— TERITORII',
              style: AppTheme.neonTextStyle(
                  color: AppTheme.neonPink, fontSize: 16)),
          const Spacer(),
          // ADD PIN button
          GestureDetector(
            onTap: _confirmPlacePin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.neonGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.neonGreen.withOpacity(0.5), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_location_alt,
                      color: AppTheme.neonGreen, size: 16),
                  const SizedBox(width: 4),
                  Text('PIN',
                      style: TextStyle(
                        color: AppTheme.neonGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Clear all pins
          GestureDetector(
            onTap: _pins.isEmpty ? null : _confirmClearAll,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _pins.isEmpty
                    ? Colors.transparent
                    : AppTheme.neonRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _pins.isEmpty
                        ? Colors.white12
                        : AppTheme.neonRed.withOpacity(0.5),
                    width: 1),
              ),
              child: Icon(Icons.delete_sweep,
                  color: _pins.isEmpty ? Colors.white24 : AppTheme.neonRed,
                  size: 16),
            ),
          ),
          const SizedBox(width: 8),
          // Reset camera
          GestureDetector(
            onTap: () => _webCtrl?.runJavaScript('resetCam()'),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.neonCyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.neonCyan.withOpacity(0.4), width: 1),
              ),
              child: Icon(Icons.center_focus_strong,
                  color: AppTheme.neonCyan, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom navigation (Feature 2) ────────────────────────────────────────────

  Widget _buildBottomNav(bool hasPins, List<String> pinnedIds, int safeIdx,
      dynamic activePoster) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkBg.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppTheme.neonPink.withOpacity(0.30), width: 1),
        boxShadow: [
          BoxShadow(
              color: AppTheme.neonPink.withOpacity(0.08),
              blurRadius: 16, spreadRadius: 2),
        ],
      ),
      child: hasPins
          ? Row(
              children: [
                // ◀ Previous
                _NavArrow(
                  icon: Icons.chevron_left,
                  onTap: _jumpPrev,
                ),
                // Centre: poster info
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${safeIdx + 1} / ${pinnedIds.length}',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 10,
                            letterSpacing: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activePoster?.name ?? pinnedIds[safeIdx],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pinnedIds[safeIdx].toUpperCase(),
                        style: TextStyle(
                            color: AppTheme.neonCyan.withOpacity(0.7),
                            fontSize: 10,
                            letterSpacing: 2),
                      ),
                      // pin delete
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _removePin(pinnedIds[safeIdx]),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline,
                                color: Colors.white24, size: 12),
                            const SizedBox(width: 4),
                            Text('Șterge pin',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // ▶ Next
                _NavArrow(
                  icon: Icons.chevron_right,
                  onTap: _jumpNext,
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_location_alt,
                    color: Colors.white24, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Adaugă pin-uri cu butonul PIN din dreapta sus',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
    );
  }
}

// ── Navigation arrow button ────────────────────────────────────────────────────

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: AppTheme.neonPink.withOpacity(0.10),
          shape: BoxShape.circle,
          border: Border.all(
              color: AppTheme.neonPink.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: AppTheme.neonPink.withOpacity(0.15),
                blurRadius: 12),
          ],
        ),
        child: Icon(icon, color: AppTheme.neonPink, size: 30),
      ),
    );
  }
}

// ── Poster picker bottom sheet ────────────────────────────────────────────────

class _PosterPickerSheet extends StatelessWidget {
  final Map<String, dynamic> posters;
  final Set<String> alreadyPinned;
  final ValueChanged<String> onPicked;
  final VoidCallback onCancel;

  const _PosterPickerSheet({
    required this.posters,
    required this.alreadyPinned,
    required this.onPicked,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final available = posters.entries
        .where((e) => !alreadyPinned.contains(e.key))
        .toList();

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.neonGreen.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin, color: AppTheme.neonGreen, size: 20),
              const SizedBox(width: 8),
              Text('Selectează afișul pentru pin',
                  style: TextStyle(
                      color: AppTheme.neonGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1)),
              const Spacer(),
              GestureDetector(
                onTap: () { onCancel(); Navigator.pop(context); },
                child: Icon(Icons.close, color: Colors.white38, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (available.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Toate afișele au deja un pin.',
                  style: TextStyle(color: Colors.white54)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: available.length,
                itemBuilder: (_, i) {
                  final entry = available[i];
                  final poster = entry.value;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onPicked(entry.key);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.neonGreen.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.neonGreen.withOpacity(0.25),
                            width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on,
                              color: AppTheme.neonGreen, size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(poster.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(entry.key.toUpperCase(),
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 10,
                                      letterSpacing: 1)),
                            ],
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right,
                              color: Colors.white24, size: 18),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Crosshair / target overlay ────────────────────────────────────────────────

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: CustomPaint(painter: _CrosshairPainter()),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;

    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = const Color(0xFF00FF88).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(Offset(cx, cy), 22, glowPaint);
    canvas.drawCircle(Offset(cx, cy), 22, ringPaint);
    canvas.drawCircle(Offset(cx, cy), 2.5,
        Paint()..color = Colors.white.withOpacity(0.9));

    const gap = 6.0;
    const len = 14.0;
    canvas.drawLine(Offset(cx, cy - gap), Offset(cx, cy - gap - len), linePaint);
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, cy + gap + len), linePaint);
    canvas.drawLine(Offset(cx - gap, cy), Offset(cx - gap - len, cy), linePaint);
    canvas.drawLine(Offset(cx + gap, cy), Offset(cx + gap + len, cy), linePaint);
  }

  @override
  bool shouldRepaint(_CrosshairPainter _) => false;
}
