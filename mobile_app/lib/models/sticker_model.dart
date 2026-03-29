import 'dart:typed_data';

class StickerItem {
  final String id;
  final String prompt;
  final String? creatorId;
  final DateTime createdAt;
  final Uint8List imageBytes;
  final bool isGif;

  const StickerItem({
    required this.id,
    required this.prompt,
    this.creatorId,
    required this.createdAt,
    required this.imageBytes,
    this.isGif = false,
  });

  /// Auto-detect GIF by magic bytes (GIF87a / GIF89a)
  static bool detectGif(Uint8List bytes) =>
      bytes.length > 3 &&
      bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
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
