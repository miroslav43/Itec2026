import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/drawing_provider.dart';
import '../models/stroke_model.dart';
import '../models/sticker_model.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';

class DrawingCanvas extends StatefulWidget {
  final String posterId;
  final String? posterImageUrl;
  final Function(Stroke)? onStrokeComplete;
  final GlobalKey? repaintKey;

  const DrawingCanvas({
    super.key,
    required this.posterId,
    this.posterImageUrl,
    this.onStrokeComplete,
    this.repaintKey,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Size _canvasSize = Size.zero;
  int _hapticCounter = 0;
  final Map<String, ui.Image> _stickerImageCache = {};
  final Set<String> _loadingStarted = {};

  @override
  void dispose() {
    for (final img in _stickerImageCache.values) img.dispose();
    super.dispose();
  }

  Future<ui.Image?> _loadStickerImage(String uid, Uint8List bytes) async {
    if (_stickerImageCache.containsKey(uid)) return _stickerImageCache[uid];
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      _stickerImageCache[uid] = img;
      return img;
    } catch (_) { return null; }
  }
  
  @override
  Widget build(BuildContext context) {
    final drawingProvider = context.watch<DrawingProvider>();
    final appState = context.watch<AppStateProvider>();
    
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        
        final renderStack = Stack(
          fit: StackFit.expand,
          children: [
            // Dark background behind poster
            Container(color: AppTheme.darkBg),
            // Poster image — network for custom, asset for built-in
            if (widget.posterImageUrl != null)
              Image.network(
                widget.posterImageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            else
              Image.asset(
                'assets/posters/${widget.posterId}.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            // Subtle grid overlay
            CustomPaint(
              painter: GridPainter(canvasSize: _canvasSize, gridSize: 20),
            ),
            // Drawing strokes
            CustomPaint(
              painter: CanvasPainter(
                strokes: drawingProvider.localStrokes,
                currentPoints: drawingProvider.currentPoints,
                currentColor: drawingProvider.currentColor,
                currentSize: drawingProvider.brushSize,
                isEraserMode: drawingProvider.isEraserMode,
                canvasSize: _canvasSize,
              ),
            ),
            // Placed stickers (non-interactive display layer)
            ...drawingProvider.placedStickers.map((ps) {
              if (!_stickerImageCache.containsKey(ps.uid) &&
                  !_loadingStarted.contains(ps.uid)) {
                _loadingStarted.add(ps.uid);
                _loadStickerImage(ps.uid, ps.imageBytes).then((_) {
                  if (mounted) setState(() {});
                });
              }
              final cachedImg = _stickerImageCache[ps.uid];
              if (cachedImg == null) return const SizedBox.shrink();
              final stickerSize = 80.0 * ps.scale;
              return Positioned(
                left: ps.x * _canvasSize.width - stickerSize / 2,
                top:  ps.y * _canvasSize.height - stickerSize / 2,
                child: IgnorePointer(
                  child: SizedBox(
                    width: stickerSize, height: stickerSize,
                    child: RawImage(image: cachedImg, fit: BoxFit.contain),
                  ),
                ),
              );
            }),
          ],
        );

        return GestureDetector(
          onPanStart: (details) => _onPanStart(details, drawingProvider),
          onPanUpdate: (details) => _onPanUpdate(details, drawingProvider),
          onPanEnd: (details) => _onPanEnd(details, drawingProvider, appState),
          child: SizedBox(
            width: _canvasSize.width,
            height: _canvasSize.height,
            child: widget.repaintKey != null
                ? RepaintBoundary(key: widget.repaintKey, child: renderStack)
                : renderStack,
          ),
        );
      },
    );
  }
  
  void _onPanStart(DragStartDetails details, DrawingProvider provider) {
    final point = StrokePoint.fromOffset(
      details.localPosition,
      _canvasSize,
    );
    provider.startDrawing(point);
    HapticService.lightImpact();
  }
  
  void _onPanUpdate(DragUpdateDetails details, DrawingProvider provider) {
    final point = StrokePoint.fromOffset(
      details.localPosition,
      _canvasSize,
    );
    provider.addPoint(point);
    
    // Haptic feedback every few points
    _hapticCounter++;
    if (_hapticCounter >= 10) {
      HapticService.selectionClick();
      _hapticCounter = 0;
    }
  }
  
  void _onPanEnd(DragEndDetails details, DrawingProvider drawingProvider, AppStateProvider appState) {
    final stroke = drawingProvider.endDrawing(appState.oderId, appState.teamId);
    if (stroke != null) {
      widget.onStrokeComplete?.call(stroke);
      HapticService.mediumImpact();
    }
  }
}

class GridPainter extends CustomPainter {
  final Size canvasSize;
  final int gridSize;

  GridPainter({required this.canvasSize, required this.gridSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 0.5;
    final cellW = size.width / gridSize;
    final cellH = size.height / gridSize;
    for (int i = 0; i <= gridSize; i++) {
      canvas.drawLine(Offset(i * cellW, 0), Offset(i * cellW, size.height), paint);
      canvas.drawLine(Offset(0, i * cellH), Offset(size.width, i * cellH), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) => false;
}

class CanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<StrokePoint> currentPoints;
  final Color currentColor;
  final double currentSize;
  final bool isEraserMode;
  final Size canvasSize;

  CanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentSize,
    required this.isEraserMode,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // saveLayer required for BlendMode.clear (eraser) to work
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, size);
    }
    if (currentPoints.isNotEmpty) {
      _drawCurrentStroke(canvas, size);
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, Stroke stroke, Size size) {
    if (stroke.points.isEmpty) return;

    if (stroke.isEraser) {
      final p = Paint()
        ..blendMode = BlendMode.clear
        ..strokeWidth = stroke.size * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _drawPoints(canvas, stroke.points, p, size);
      return;
    }

    // Glow
    final glow = Paint()
      ..color = stroke.color.withOpacity(0.35)
      ..strokeWidth = stroke.size + 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    _drawPoints(canvas, stroke.points, glow, size);

    final line = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    _drawPoints(canvas, stroke.points, line, size);
  }

  void _drawCurrentStroke(Canvas canvas, Size size) {
    if (isEraserMode) {
      final p = Paint()
        ..blendMode = BlendMode.clear
        ..strokeWidth = currentSize * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _drawPoints(canvas, currentPoints, p, size);
      return;
    }

    final glow = Paint()
      ..color = currentColor.withOpacity(0.35)
      ..strokeWidth = currentSize + 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    _drawPoints(canvas, currentPoints, glow, size);

    final line = Paint()
      ..color = currentColor
      ..strokeWidth = currentSize
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    _drawPoints(canvas, currentPoints, line, size);
  }
  
  void _drawPoints(Canvas canvas, List<StrokePoint> points, Paint paint, Size size) {
    if (points.length == 1) {
      final offset = points[0].toOffset(size);
      canvas.drawCircle(offset, paint.strokeWidth / 2, paint);
      return;
    }

    final path = Path();
    final firstOffset = points[0].toOffset(size);
    path.moveTo(firstOffset.dx, firstOffset.dy);

    for (int i = 1; i < points.length; i++) {
      final offset = points[i].toOffset(size);
      if (i < points.length - 1) {
        final nextOffset = points[i + 1].toOffset(size);
        path.quadraticBezierTo(
          offset.dx, offset.dy,
          (offset.dx + nextOffset.dx) / 2, (offset.dy + nextOffset.dy) / 2,
        );
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CanvasPainter old) => true;
}
