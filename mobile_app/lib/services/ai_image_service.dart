import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img_lib;
import 'package:uuid/uuid.dart';

import '../models/sticker_model.dart';
import 'gpt_vision_service.dart';

class AiImageService {
  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const _dalleUrl = 'https://api.openai.com/v1/images/generations';

  /// Generate a sticker via DALL-E 2, save to backend, return StickerItem.
  static Future<StickerItem?> generateSticker({
    required String prompt,
    String? creatorId,
  }) async {
    try {
      // 1. Call DALL-E 2 (supports 256x256 — fast & cheap)
      final genResp = await http.post(
        Uri.parse(_dalleUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'dall-e-2',
          'prompt': prompt,
          'n': 1,
          'size': '256x256',
          'response_format': 'b64_json',
        }),
      ).timeout(const Duration(seconds: 30));

      if (genResp.statusCode != 200) {
        debugPrint('[AiImage] DALL-E error ${genResp.statusCode}: ${genResp.body}');
        return null;
      }

      final body = jsonDecode(genResp.body) as Map<String, dynamic>;
      final b64 = (body['data'] as List).first['b64_json'] as String;
      final imageBytes = base64Decode(b64);

      // 2. Build StickerItem
      final id = const Uuid().v4();
      final sticker = StickerItem(
        id: id,
        prompt: prompt,
        creatorId: creatorId,
        createdAt: DateTime.now(),
        imageBytes: imageBytes,
      );

      // 3. Persist to backend
      await _saveToBackend(sticker);

      return sticker;
    } catch (e) {
      debugPrint('[AiImage] generateSticker error: $e');
      return null;
    }
  }

  /// Generate an animated GIF sticker via DALL-E 2 + pulse animation.
  static Future<StickerItem?> generateGifSticker({
    required String prompt,
    String? creatorId,
  }) async {
    try {
      final genResp = await http.post(
        Uri.parse(_dalleUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'dall-e-2',
          'prompt': prompt,
          'n': 1,
          'size': '256x256',
          'response_format': 'b64_json',
        }),
      ).timeout(const Duration(seconds: 30));

      if (genResp.statusCode != 200) {
        debugPrint('[AiImage] DALL-E GIF error ${genResp.statusCode}: ${genResp.body}');
        return null;
      }

      final body = jsonDecode(genResp.body) as Map<String, dynamic>;
      final b64 = (body['data'] as List).first['b64_json'] as String;
      final pngBytes = base64Decode(b64);

      final gifBytes = await compute(_buildPulseGif, pngBytes);

      final id = const Uuid().v4();
      final sticker = StickerItem(
        id: id,
        prompt: prompt,
        creatorId: creatorId,
        createdAt: DateTime.now(),
        imageBytes: gifBytes,
        isGif: true,
      );

      await _saveToBackend(sticker);
      return sticker;
    } catch (e) {
      debugPrint('[AiImage] generateGifSticker error: $e');
      return null;
    }
  }

  /// Builds a 6-frame pulse-zoom animated GIF from a PNG image (runs in isolate).
  static Uint8List _buildPulseGif(Uint8List pngBytes) {
    final src = img_lib.decodeImage(pngBytes);
    if (src == null) return pngBytes;
    final base = img_lib.copyResize(src, width: 128, height: 128,
        interpolation: img_lib.Interpolation.linear);

    // 6 frames: zoom pulse 100% → 108% → 100% → 92% → 100% → 108%
    const frameCount = 6;
    const scales = [1.00, 1.08, 1.04, 1.00, 0.94, 0.98];
    img_lib.Image? anim;

    for (int i = 0; i < frameCount; i++) {
      final s = scales[i];
      final fw = (128 * s).round();
      final fh = (128 * s).round();

      var frame = img_lib.copyResize(base, width: fw, height: fh,
          interpolation: img_lib.Interpolation.linear);

      if (fw > 128) {
        // Zoomed in — crop center
        final ox = (fw - 128) ~/ 2;
        final oy = (fh - 128) ~/ 2;
        frame = img_lib.copyCrop(frame, x: ox, y: oy, width: 128, height: 128);
      } else if (fw < 128) {
        // Zoomed out — pad with transparent
        final canvas = img_lib.Image(width: 128, height: 128);
        final ox = (128 - fw) ~/ 2;
        final oy = (128 - fh) ~/ 2;
        img_lib.compositeImage(canvas, frame, dstX: ox, dstY: oy);
        frame = canvas;
      }

      frame.frameDuration = 140;

      if (anim == null) {
        anim = frame;
        anim.loopCount = 0;
      } else {
        anim.addFrame(frame);
      }
    }

    return Uint8List.fromList(img_lib.encodeGif(anim!));
  }

  static Future<void> _saveToBackend(StickerItem sticker) async {
    try {
      final serverUrl = GptVisionService.serverUrl;
      await http.post(
        Uri.parse('$serverUrl/api/stickers'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': sticker.id,
          'prompt': sticker.prompt,
          'creatorId': sticker.creatorId ?? 'anonymous',
          'imageBase64': base64Encode(sticker.imageBytes),
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[AiImage] saveToBackend error: $e');
    }
  }

  /// Fetch all stickers from backend.
  static Future<List<StickerItem>> fetchStickers() async {
    try {
      final serverUrl = GptVisionService.serverUrl;
      final resp = await http
          .get(Uri.parse('$serverUrl/api/stickers'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>;
      final stickers = <StickerItem>[];
      for (final item in list) {
        try {
          final bytes = base64Decode(item['image_base64'] as String);
          stickers.add(StickerItem(
            id: item['id'] as String,
            prompt: item['prompt'] as String,
            creatorId: item['creator_id'] as String?,
            createdAt: DateTime.tryParse(item['created_at'] as String? ?? '') ?? DateTime.now(),
            imageBytes: bytes,
            isGif: StickerItem.detectGif(bytes),
          ));
        } catch (_) {}
      }
      return stickers;
    } catch (e) {
      debugPrint('[AiImage] fetchStickers error: $e');
      return [];
    }
  }
}
