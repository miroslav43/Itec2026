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
  /// Compile-time only. Run:
  /// `flutter run --dart-define=OPENAI_API_KEY=sk-...`
  /// Release: `flutter build ipa --dart-define=OPENAI_API_KEY=sk-...`
  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY');
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

  // Prompt cache — refresh every 60 s
  static String? _cachedPrompt;
  static List<String>? _cachedValidIds;
  static DateTime? _lastPromptFetch;
  static final Map<String, String> _posterNames = {}; // id -> display name

  static String? getPosterName(String id) => _posterNames[id];

  // Fetch custom posters and build dynamic prompt
  static Future<(String, List<String>)> _buildPrompt() async {
    // Use cache if fresh (< 60 s)
    final now = DateTime.now();
    if (_cachedPrompt != null &&
        _lastPromptFetch != null &&
        now.difference(_lastPromptFetch!).inSeconds < 60) {
      return (_cachedPrompt!, _cachedValidIds!);
    }

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
          final desc = p['description'] as String? ?? name;
          ids.add(id);
          _posterNames[id] = name;
          extra += '$id: $desc\n';
        }
      }
    } catch (_) {}
    final prompt = extra.isEmpty
        ? _basePrompt
        : '$_basePrompt\nCustom posters:\n$extra';
    _cachedPrompt = prompt;
    _cachedValidIds = ids;
    _lastPromptFetch = now;
    return (prompt, ids);
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
          // Immediately register in local cache so next scan recognises it
          _posterNames[id] = name;
          _cachedValidIds?.add(id);
          // Invalidate prompt cache so it's rebuilt with the new poster
          _cachedPrompt = null;
          _lastPromptFetch = null;
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
      if (_apiKey.isEmpty) {
        debugPrint(
          'GptVision: OPENAI_API_KEY is empty. Pass at build/run time, e.g. '
          'flutter run --dart-define=OPENAI_API_KEY=sk-your-key',
        );
        return const GptResult(posterId: null, looksLikePoster: false);
      }

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
                    'url': 'data:image/jpeg;base64,$b64',
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
