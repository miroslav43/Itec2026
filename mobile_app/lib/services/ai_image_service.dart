import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
