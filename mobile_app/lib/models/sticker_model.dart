import 'dart:typed_data';

class StickerItem {
  final String id;
  final String prompt;
  final String? creatorId;
  final DateTime createdAt;
  final Uint8List imageBytes;

  const StickerItem({
    required this.id,
    required this.prompt,
    this.creatorId,
    required this.createdAt,
    required this.imageBytes,
  });
}

class PlacedSticker {
  final String uid;
  final String stickerId;
  final String prompt;
  Uint8List imageBytes;
  double x; // normalized 0-1
  double y; // normalized 0-1
  double scale;

  PlacedSticker({
    required this.uid,
    required this.stickerId,
    required this.prompt,
    required this.imageBytes,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'stickerId': stickerId,
        'prompt': prompt,
        'x': x,
        'y': y,
        'scale': scale,
      };
}
