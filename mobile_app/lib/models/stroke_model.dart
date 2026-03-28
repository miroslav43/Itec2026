import 'dart:ui';

class StrokePoint {
  final double x;
  final double y;
  
  StrokePoint({required this.x, required this.y});
  
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  
  factory StrokePoint.fromJson(Map<String, dynamic> json) {
    return StrokePoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
  
  Offset toOffset(Size canvasSize) {
    return Offset(x * canvasSize.width, y * canvasSize.height);
  }
  
  static StrokePoint fromOffset(Offset offset, Size canvasSize) {
    return StrokePoint(
      x: offset.dx / canvasSize.width,
      y: offset.dy / canvasSize.height,
    );
  }
}

class Stroke {
  final String id;
  final String oderId;
  final String teamId;
  final List<StrokePoint> points;
  final Color color;
  final double size;
  final int timestamp;
  final bool isEraser;
  
  Stroke({
    required this.id,
    required this.oderId,
    required this.teamId,
    required this.points,
    required this.color,
    required this.size,
    required this.timestamp,
    this.isEraser = false,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': oderId,
      'teamId': teamId,
      'points': points.map((p) => p.toJson()).toList(),
      'color': '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      'size': size,
      'timestamp': timestamp,
      'isEraser': isEraser,
    };
  }
  
  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      id: json['id'] ?? '',
      oderId: json['userId'] ?? json['oderId'] ?? '',
      teamId: json['teamId'] ?? '',
      points: (json['points'] as List<dynamic>?)
          ?.map((p) => StrokePoint.fromJson(p as Map<String, dynamic>))
          .toList() ?? [],
      color: _parseColor(json['color']),
      size: (json['size'] as num?)?.toDouble() ?? 5.0,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      isEraser: json['isEraser'] ?? false,
    );
  }
  
  static Color _parseColor(dynamic colorValue) {
    if (colorValue == null) return const Color(0xFFFFFFFF);
    if (colorValue is String) {
      String hex = colorValue.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFFFFFFFF);
  }
}
