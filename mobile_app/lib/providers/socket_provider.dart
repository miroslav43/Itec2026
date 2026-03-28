import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/stroke_model.dart';
import '../models/poster_model.dart';

class SocketProvider extends ChangeNotifier {
  io.Socket? _socket;
  bool _isConnected = false;
  String? _currentRoom;
  List<Stroke> _strokes = [];
  Territory? _territory;
  int _userCount = 0;
  
  // Callbacks
  Function(Stroke)? onStrokeReceived;
  Function(Territory)? onTerritoryUpdate;
  Function(int)? onUserCountChanged;
  Function(String)? onError;
  Function()? onRoomJoined;
  Function()? onCanvasCleared;
  
  // Getters
  bool get isConnected => _isConnected;
  String? get currentRoom => _currentRoom;
  List<Stroke> get strokes => _strokes;
  Territory? get territory => _territory;
  int get userCount => _userCount;
  
  // Server URL - configured for real device
  static const String _defaultServerUrl = 'http://10.27.252.100:3000';
  
  String _serverUrl = _defaultServerUrl;
  
  String get serverUrl => _serverUrl;

  void setServerUrl(String url) {
    _serverUrl = url;
  }
  
  void connect() {
    if (_socket != null && _isConnected) return;
    
    try {
      _socket = io.io(_serverUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
      });
      
      _socket!.onConnect((_) {
        debugPrint('Socket connected');
        _isConnected = true;
        notifyListeners();
      });
      
      _socket!.onDisconnect((_) {
        debugPrint('Socket disconnected');
        _isConnected = false;
        _currentRoom = null;
        notifyListeners();
      });
      
      _socket!.onConnectError((error) {
        debugPrint('Connection error: $error');
        _isConnected = false;
        onError?.call('Connection error: $error');
        notifyListeners();
      });
      
      _socket!.on('error', (data) {
        debugPrint('Socket error: $data');
        onError?.call(data['message'] ?? 'Unknown error');
      });
      
      _socket!.on('room_joined', (data) {
        debugPrint('Room joined: $data');
        _currentRoom = data['posterId'];
        _strokes = (data['strokes'] as List<dynamic>?)
            ?.map((s) => Stroke.fromJson(s as Map<String, dynamic>))
            .toList() ?? [];
        if (data['territory'] != null) {
          _territory = Territory.fromJson(data['territory'] as Map<String, dynamic>);
          onTerritoryUpdate?.call(_territory!);
        }
        _userCount = data['userCount'] ?? 1;
        onUserCountChanged?.call(_userCount);
        onRoomJoined?.call();
        notifyListeners();
      });
      
      _socket!.on('receive_stroke', (data) {
        final stroke = Stroke.fromJson(data as Map<String, dynamic>);
        _strokes.add(stroke);
        onStrokeReceived?.call(stroke);
        notifyListeners();
      });
      
      _socket!.on('territory_update', (data) {
        _territory = Territory.fromJson(data as Map<String, dynamic>);
        onTerritoryUpdate?.call(_territory!);
        notifyListeners();
      });
      
      _socket!.on('user_joined', (data) {
        _userCount = data['userCount'] ?? _userCount;
        onUserCountChanged?.call(_userCount);
        notifyListeners();
      });
      
      _socket!.on('user_left', (data) {
        _userCount = data['userCount'] ?? _userCount;
        onUserCountChanged?.call(_userCount);
        notifyListeners();
      });
      
      _socket!.on('poster_state', (data) {
        _strokes = (data['strokes'] as List<dynamic>?)
            ?.map((s) => Stroke.fromJson(s as Map<String, dynamic>))
            .toList() ?? [];
        if (data['territory'] != null) {
          _territory = Territory.fromJson(data['territory'] as Map<String, dynamic>);
          onTerritoryUpdate?.call(_territory!);
        }
        notifyListeners();
      });

      _socket!.on('canvas_cleared', (_) {
        _strokes = [];
        _territory = null;
        onCanvasCleared?.call();
        notifyListeners();
      });
      
      _socket!.connect();
    } catch (e) {
      debugPrint('Failed to connect: $e');
      onError?.call('Failed to connect: $e');
    }
  }
  
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _currentRoom = null;
    _strokes = [];
    _territory = null;
    notifyListeners();
  }
  
  void joinRoom(String posterId, String oderId, String teamId, String username) {
    if (_socket == null || !_isConnected) {
      connect();
      // Wait for connection then join
      Future.delayed(const Duration(milliseconds: 500), () {
        _emitJoinRoom(posterId, oderId, teamId, username);
      });
    } else {
      _emitJoinRoom(posterId, oderId, teamId, username);
    }
  }
  
  void _emitJoinRoom(String posterId, String oderId, String teamId, String username) {
    _socket?.emit('join_poster_room', {
      'posterId': posterId,
      'userId': oderId,
      'teamId': teamId,
      'username': username,
    });
  }
  
  void leaveRoom() {
    _socket?.emit('leave_room');
    _currentRoom = null;
    _strokes = [];
    _territory = null;
    notifyListeners();
  }
  
  void sendStroke(Stroke stroke) {
    if (_socket == null || !_isConnected || _currentRoom == null) return;
    
    _socket!.emit('send_stroke', stroke.toJson());
  }
  
  void sendDrawingPoint(double x, double y, String color, double size) {
    if (_socket == null || !_isConnected || _currentRoom == null) return;
    
    _socket!.emit('drawing_point', {
      'point': {'x': x, 'y': y},
      'color': color,
      'size': size,
    });
  }
  
  void getPosterState(String posterId) {
    _socket?.emit('get_poster_state', {'posterId': posterId});
  }
  
  void clearCanvas() {
    if (_socket == null || !_isConnected || _currentRoom == null) return;
    _socket!.emit('clear_canvas');
  }

  void clearStrokes() {
    _strokes = [];
    notifyListeners();
  }
  
  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
