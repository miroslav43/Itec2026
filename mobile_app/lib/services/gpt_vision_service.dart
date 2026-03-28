import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img_lib;

class GptResult {
  final String? posterId;
  final bool looksLikePoster;
  final Uint8List? croppedBytes;

  const GptResult({
    this.posterId,
    this.looksLikePoster = false,
    this.croppedBytes,
  });
}

class GptVisionService {
  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const _openAiUrl = 'https://api.openai.com/v1/chat/completions';

  static const _basePrompt = '''
You are identifying printed flat materials in images.
Reply with ONLY one of these — no other text:
- The exact poster ID if you recognise it (e.g. "afis1", "custom_1")
- "unknown" if the image shows ANY flat printed material (poster, flyer, advertisement, badge, ID card, sticker, leaflet, sign, card, label, paper with print) but you do not recognise which one
- "not_a_poster" ONLY if the image clearly shows something that is NOT printed/flat material at all (e.g. a person's face/body, floor, ceiling, food, hand, generic wall without print, outdoor scenery, object)

Known posters:
afis1: blue background, "BOOST YOUR SOCIAL PRESENCE", social media icons (Facebook, Instagram)
afis2: white and red background, "Digital Marketing Agency", phone number 123-456-7891
afis3: purple background, "DIGITAL MARKETING AGENCY", "JOIN US" red button
afis4: red background, red can, "Creaza fara limite" or "fara limite"
afis5: dark background with burger photo, "Best Burger in Town"
afis6: gray/white background with building photo, "FORM FOLLOWS FUNCTION", "BEAUTY FOLLOWS PASSION"
afis7: dark blue background, travel landscape photos, "EXPLORE THE WORLD"
afis8: hot pink/magenta background, fashion model, "Fashion" and "BusinessS"
afis9: blue background, blue sneaker/shoe, "EXCLUSIVE EDITION", "50% DISCOUNT"
afis10: bright yellow background, large "<itec>" logo only
''';

  static const List<String> _builtinIds = [
    'afis1', 'afis2', 'afis3', 'afis4', 'afis5',
    'afis6', 'afis7', 'afis8', 'afis9', 'afis10',
  ];

  // Server URL — should match SocketProvider's server URL
  static String serverUrl = 'http://10.27.252.100:3000';

  // Prompt cache — refresh every 60 s
  static String? _cachedPrompt;
  static List<String>? _cachedValidIds;
  static DateTime? _lastPromptFetch;
  static final Map<String, String> _posterNames = {}; // id -> display name
  static final Map<String, String> _cachedPosterImages = {}; // id -> base64 jpeg

  static String? getPosterName(String id) => _posterNames[id];

  // Fetch custom posters list + images, returns (promptText, validIds, customImages)
  static Future<(String, List<String>, List<Map<String, String>>)> _buildData() async {
    final now = DateTime.now();
    final cacheStale = _cachedPrompt == null ||
        _lastPromptFetch == null ||
        now.difference(_lastPromptFetch!).inSeconds >= 60;

    if (cacheStale) {
      final ids = List<String>.from(_builtinIds);
      String extra = '';
      try {
        final resp = await http
            .get(Uri.parse('$serverUrl/api/custom-posters'))
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final list = jsonDecode(resp.body) as List<dynamic>;
          for (final p in list) {
            final id = p['id'] as String;
            final name = p['name'] as String? ?? id;
            ids.add(id);
            _posterNames[id] = name;
            extra += '$id: $name\n';
          }
        }
      } catch (_) {}
      _cachedPrompt = extra.isEmpty
          ? _basePrompt
          : '$_basePrompt\nCustom posters:\n$extra';
      _cachedValidIds = ids;
      _lastPromptFetch = now;
    }

    // Fetch images for custom poster IDs not yet cached
    final customIds = _cachedValidIds!.where((id) => id.startsWith('custom_')).toList();
    for (final id in customIds) {
      if (!_cachedPosterImages.containsKey(id)) {
        try {
          final imgResp = await http
              .get(Uri.parse('$serverUrl/custom-posters/$id.jpg'))
              .timeout(const Duration(seconds: 4));
          if (imgResp.statusCode == 200) {
            _cachedPosterImages[id] = base64Encode(imgResp.bodyBytes);
          }
        } catch (_) {}
      }
    }

    final customImages = <Map<String, String>>[];
    for (final id in customIds) {
      final b64 = _cachedPosterImages[id];
      if (b64 != null) {
        customImages.add({'id': id, 'name': _posterNames[id] ?? id, 'b64': b64});
      }
    }

    return (_cachedPrompt!, _cachedValidIds!, customImages);
  }

  // Fast crop + resize using image package (JPEG output, much smaller/faster than PNG)
  static Future<Uint8List> cropCenterSquare(Uint8List jpegBytes) async {
    return compute(_cropResizeIsolate, jpegBytes);
  }

  static Uint8List _cropResizeIsolate(Uint8List bytes) {
    final src = img_lib.decodeImage(bytes);
    if (src == null) return bytes;
    final side = min(src.width, src.height);
    final x = (src.width - side) ~/ 2;
    final y = (src.height - side) ~/ 2;
    final cropped = img_lib.copyCrop(src, x: x, y: y, width: side, height: side);
    final resized = img_lib.copyResize(cropped, width: 400, height: 400,
        interpolation: img_lib.Interpolation.linear);
    return img_lib.encodeJpg(resized, quality: 82);
  }

  // Save custom poster to backend, returns poster ID
  static Future<String?> saveCustomPoster({
    required String name,
    required String description,
    required Uint8List imageBytes,
  }) async {
    try {
      final b64 = base64Encode(imageBytes);
      final resp = await http
          .post(
            Uri.parse('$serverUrl/api/custom-posters'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'description': description,
              'imageBase64': b64,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final id = body['id'] as String?;
        if (id != null) {
          _posterNames[id] = name;
          _cachedValidIds?.add(id);
          _cachedPrompt = null;
          _lastPromptFetch = null;
          _cachedPosterImages.remove(id); // will be fetched fresh on next scan
        }
        return id;
      }
      debugPrint('SaveCustomPoster HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      debugPrint('SaveCustomPoster error: $e');
    }
    return null;
  }

  static Future<GptResult> identifyPoster(Uint8List jpegBytes) async {
    Uint8List? cropped;
    try {
      cropped = await cropCenterSquare(jpegBytes);
    } catch (_) {
      cropped = jpegBytes;
    }

    try {
      final (prompt, validIds, customImages) = await _buildData();
      final b64 = base64Encode(cropped ?? jpegBytes);
      debugPrint('GptVision: sending ${((cropped ?? jpegBytes).length / 1024).toStringAsFixed(0)}KB, customPosters=${customImages.length}');

      // Single multi-modal message: text prompt + custom poster reference images + scanned image
      final content = <Map<String, dynamic>>[
        {'type': 'text', 'text': prompt},
      ];
      for (final p in customImages) {
        content.add({'type': 'text', 'text': 'Reference image for ${p['id']} (${p['name']}):'}); 
        content.add({'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,${p['b64']}', 'detail': 'low'}});
      }
      content.add({'type': 'text', 'text': 'Identify the scanned poster below. Reply with ONLY the poster ID or "unknown":'}); 
      content.add({'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64', 'detail': 'low'}});

      http.Response? response;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          response = await http.post(
            Uri.parse(_openAiUrl),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'messages': [
                {'role': 'user', 'content': content}
              ],
              'max_tokens': 20,
            }),
          ).timeout(const Duration(seconds: 20));
          break;
        } catch (e) {
          debugPrint('GptVision attempt ${attempt + 1} failed: $e');
          if (attempt < 2) await Future.delayed(const Duration(seconds: 1));
        }
      }
      if (response == null) {
        return const GptResult(posterId: null, looksLikePoster: false);
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final answer = (body['choices'][0]['message']['content'] as String)
            .trim()
            .toLowerCase();
        debugPrint('GptVision: answer="$answer"');

        for (final id in validIds) {
          if (answer.contains(id)) {
            return GptResult(posterId: id, looksLikePoster: true, croppedBytes: cropped);
          }
        }

        // 'unknown' = looks like a poster but not recognised → offer to add it
        // 'not_a_poster' (or anything else) = not a poster → show snackbar
        final looksLike = answer.contains('unknown');
        debugPrint('GptVision: unknown, looksLikePoster=$looksLike');
        return GptResult(posterId: null, looksLikePoster: looksLike, croppedBytes: cropped);
      } else {
        debugPrint('GptVision HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('GptVision error: $e');
    }
    return const GptResult(posterId: null, looksLikePoster: false);
  }
}
