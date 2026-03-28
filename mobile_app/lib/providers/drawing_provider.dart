import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/stroke_model.dart';
import '../theme/app_theme.dart';

/// A pixel-art sticker stamped onto the canvas at a given position.
class StickerStamp {
  final Uint8List bytes;    // 32×32 PNG
  final Offset   position;  // top-left in canvas local coordinates

  const StickerStamp({required this.bytes, required this.position});

  StickerStamp copyWith({Uint8List? bytes, Offset? position}) => StickerStamp(
        bytes:    bytes    ?? this.bytes,
        position: position ?? this.position,
      );
}

class DrawingProvider extends ChangeNotifier {
  // Drawing settings
  Color _currentColor = AppTheme.neonCyan;
  double _brushSize = 8.0;
  bool _isEraserMode = false;
  bool _isDrawing = false;
  
  // Current stroke being drawn
  List<StrokePoint> _currentPoints = [];
  
  // All local strokes (for immediate display)
  final List<Stroke> _localStrokes = [];

  // Pixel-art sticker stamps
  final List<StickerStamp> _stamps = [];
  
  // Predefined colors
  final List<Color> availableColors = [
    AppTheme.neonCyan,
    AppTheme.neonPink,
    AppTheme.neonPurple,
    AppTheme.neonGreen,
    AppTheme.neonYellow,
    AppTheme.neonOrange,
    AppTheme.neonRed,
    Colors.white,
  ];
  
  // Brush sizes
  final List<double> brushSizes = [4.0, 8.0, 12.0, 20.0, 32.0];
  
  // Getters
  Color get currentColor => _currentColor;
  double get brushSize => _brushSize;
  bool get isEraserMode => _isEraserMode;
  bool get isDrawing => _isDrawing;
  List<StrokePoint>  get currentPoints => _currentPoints;
  List<Stroke>       get localStrokes  => _localStrokes;
  List<StickerStamp> get stamps        => List.unmodifiable(_stamps);
  
  void setColor(Color color) {
    _currentColor = color;
    _isEraserMode = false;
    notifyListeners();
  }
  
  void setBrushSize(double size) {
    _brushSize = size;
    notifyListeners();
  }
  
  void toggleEraser() {
    _isEraserMode = !_isEraserMode;
    notifyListeners();
  }
  
  void setEraserMode(bool enabled) {
    _isEraserMode = enabled;
    notifyListeners();
  }
  
  void startDrawing(StrokePoint point) {
    _isDrawing = true;
    _currentPoints = [point];
    notifyListeners();
  }
  
  void addPoint(StrokePoint point) {
    if (!_isDrawing) return;
    _currentPoints.add(point);
    notifyListeners();
  }
  
  Stroke? endDrawing(String oderId, String teamId) {
    if (!_isDrawing || _currentPoints.isEmpty) {
      _isDrawing = false;
      _currentPoints = [];
      return null;
    }
    
    final stroke = Stroke(
      id: const Uuid().v4(),
      oderId: oderId,
      teamId: teamId,
      points: List.from(_currentPoints),
      color: _isEraserMode ? Colors.transparent : _currentColor,
      size: _brushSize,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isEraser: _isEraserMode,
    );
    
    _localStrokes.add(stroke);
    _isDrawing = false;
    _currentPoints = [];
    notifyListeners();
    
    return stroke;
  }
  
  void cancelDrawing() {
    _isDrawing = false;
    _currentPoints = [];
    notifyListeners();
  }
  
  void addRemoteStroke(Stroke stroke) {
    // Check if stroke already exists
    if (!_localStrokes.any((s) => s.id == stroke.id)) {
      _localStrokes.add(stroke);
      notifyListeners();
    }
  }
  
  void setStrokes(List<Stroke> strokes) {
    _localStrokes.clear();
    _localStrokes.addAll(strokes);
    notifyListeners();
  }
  
  void clearLocalStrokes() {
    _localStrokes.clear();
    notifyListeners();
  }

  // ── Sticker stamp management ────────────────────────────────────────────────

  /// Adds a new sticker stamp at [position] (canvas-local coordinates).
  void addStamp(Uint8List bytes, Offset position) {
    _stamps.add(StickerStamp(bytes: bytes, position: position));
    notifyListeners();
  }

  /// Moves the stamp at [index] to [newPosition].
  void updateStampPosition(int index, Offset newPosition) {
    if (index < 0 || index >= _stamps.length) return;
    _stamps[index] = _stamps[index].copyWith(position: newPosition);
    notifyListeners();
  }

  /// Removes the most recently added stamp.
  void removeLastStamp() {
    if (_stamps.isNotEmpty) {
      _stamps.removeLast();
      notifyListeners();
    }
  }

  /// Removes all sticker stamps.
  void clearStamps() {
    _stamps.clear();
    notifyListeners();
  }

  void reset() {
    _currentColor = AppTheme.neonCyan;
    _brushSize    = 8.0;
    _isEraserMode = false;
    _isDrawing    = false;
    _currentPoints = [];
    _localStrokes.clear();
    _stamps.clear();
    notifyListeners();
  }
}
