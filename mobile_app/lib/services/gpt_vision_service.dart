import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  static const _apiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: 'YOUR_OPENAI_API_KEY_HERE',
  );
  static const _openAiUrl = 'https://api.openai.com/v1/chat/completions';

  static const _basePrompt = '''
You are identifying which iTEC poster is shown in the image.
Reply with ONLY the poster ID or "unknown". No other text.

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

  // Fetch custom posters and build dynamic prompt
  static Future<(String prompt, List<String> validIds)> _buildPrompt() async {
    final ids = List<String>.from(_builtinIds);
    String extra = '';
    try {
      final resp = await http
          .get(Uri.parse('$serverUrl/api/custom-posters'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        for (final p in list) {
          final id = p['id'] as String;
          final desc = p['description'] as String? ?? p['name'] as String;
          ids.add(id);
          extra += '$id: $desc\n';
        }
      }
    } catch (_) {}
    final prompt = extra.isEmpty
        ? _basePrompt
        : '$_basePrompt\nCustom posters:\n$extra';
    return (prompt, ids);
  }

  // Crop center square of image and resize to 600×600 PNG
  static Future<Uint8List> cropCenterSquare(Uint8List jpegBytes) async {
    final codec = await ui.instantiateImageCodec(jpegBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;

    final side = min(src.width, src.height);
    final sx = ((src.width - side) / 2).round();
    final sy = ((src.height - side) / 2).round();
    const outSize = 600;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(sx.toDouble(), sy.toDouble(), side.toDouble(), side.toDouble()),
      ui.Rect.fromLTWH(0, 0, outSize.toDouble(), outSize.toDouble()),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(outSize, outSize);
    final pngBd = await img.toByteData(format: ui.ImageByteFormat.png);
    if (pngBd != null) return pngBd.buffer.asUint8List();
    return jpegBytes;
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
        return body['id'] as String?;
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
      final (prompt, validIds) = await _buildPrompt();
      final b64 = base64Encode(cropped ?? jpegBytes);
      debugPrint('GptVision: sending ${((cropped ?? jpegBytes).length / 1024).toStringAsFixed(0)}KB');

      final response = await http.post(
        Uri.parse(_openAiUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,$b64',
                    'detail': 'low',
                  },
                },
              ],
            }
          ],
          'max_tokens': 20,
        }),
      ).timeout(const Duration(seconds: 20));

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

        // Check if GPT thinks it sees a poster-like image
        final looksLike = answer.contains('poster') ||
            answer.contains('sign') ||
            answer.contains('advertisement') ||
            answer.contains('banner') ||
            answer.contains('afis') ||
            answer.contains('unknown');
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
