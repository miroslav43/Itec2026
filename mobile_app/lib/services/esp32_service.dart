import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Commands received from ESP32
enum Esp32Command { up, down, left, right, select, sprayStart, sprayStop, unknown }

Esp32Command _parseCmd(String raw) {
  switch (raw.trim()) {
    case 'up': return Esp32Command.up;
    case 'down': return Esp32Command.down;
    case 'left': return Esp32Command.left;
    case 'right': return Esp32Command.right;
    case 'select': return Esp32Command.select;
    case 'sprayStart': return Esp32Command.sprayStart;
    case 'sprayStop': return Esp32Command.sprayStop;
    default: return Esp32Command.unknown;
  }
}

class Esp32Service {
  static const String defaultIp = '10.27.252.186';

  static final Esp32Service _instance = Esp32Service._internal();
  factory Esp32Service() => _instance;
  Esp32Service._internal();

  WebSocket? _socket;
  bool _connected = false;
  String? _ip;

  final StreamController<Esp32Command> _cmdCtrl =
      StreamController<Esp32Command>.broadcast();

  Stream<Esp32Command> get commands => _cmdCtrl.stream;
  bool get isConnected => _connected;
  String? get ip => _ip;

  Future<bool> connect(String ip) async {
    await disconnect();
    try {
      _socket = await WebSocket.connect('ws://$ip:81')
          .timeout(const Duration(seconds: 5));
      _ip = ip;
      _connected = true;
      debugPrint('[ESP32] Connected to ws://$ip:81');
      _socket!.listen(
        (data) {
          final cmd = _parseCmd(data.toString());
          if (cmd != Esp32Command.unknown) _cmdCtrl.add(cmd);
          debugPrint('[ESP32] ← $data');
        },
        onDone: () {
          debugPrint('[ESP32] Disconnected');
          _connected = false;
          _socket = null;
        },
        onError: (e) {
          debugPrint('[ESP32] Error: $e');
          _connected = false;
          _socket = null;
        },
        cancelOnError: false,
      );
      return true;
    } catch (e) {
      debugPrint('[ESP32] Connect failed: $e');
      _connected = false;
      _socket = null;
      return false;
    }
  }

  Future<void> disconnect() async {
    try { await _socket?.close(); } catch (_) {}
    _socket = null;
    _connected = false;
  }

  /// Send RGB color to ESP32 LED (format: C:r,g,b)
  void sendColor(int r, int g, int b) {
    if (!_connected || _socket == null) return;
    final msg = 'C:$r,$g,$b';
    _socket!.add(msg);
    debugPrint('[ESP32] → $msg');
  }

  void dispose() {
    _socket?.close();
    _cmdCtrl.close();
  }
}
