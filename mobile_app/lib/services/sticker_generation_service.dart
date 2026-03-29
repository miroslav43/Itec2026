import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// On-device sticker generator backed by stable-diffusion.cpp (via JNI).
///
/// Pipeline:
///   prompt → native txt2img (64×64, LCM, 6 steps) → PNG bytes
///          → Dart post-process: nearest-neighbour ↓ 32×32 + 16-colour palette
///          → final 32×32 pixel-art PNG returned
///
/// Falls back to a procedural neon placeholder when the native library is
/// unavailable (e.g. on emulators or during UI-only development).
class StickerGenerationService {
  StickerGenerationService._();

  static const MethodChannel _channel =
      MethodChannel('com.itec.override/stable_diffusion');

  // ── Generation constants ────────────────────────────────────────────────────

  /// Internal SD generation size. 64 is the absolute minimum (8×8 latent).
  /// Increase to 128 if quality at 64 is unacceptable.
  static const int kGenerationSize = 64;

  /// Final pixel-art output size.
  static const int kOutputSize = 32;

  static const int    kSteps        = 6;
  static const double kCfg          = 2.0;
  static const int    kPaletteColors = 16;

  // ── Model download ──────────────────────────────────────────────────────────

  static const String _modelFileName = 'sd-lcm-v1-5.q2_k.gguf';

  /// Direct-download URL for the quantised LCM-distilled SD 1.5 GGUF model.
  ///
  /// If this URL is unavailable, replace it with any q2_k GGUF of an LCM-
  /// compatible SD 1.5 model from HuggingFace or stable-diffusion.cpp examples.
  static const String _modelUrl =
      'https://huggingface.co/Comfy-Org/stable-diffusion-v1-5-archive/resolve/main/'
      'v1-5-pruned-emaonly.safetensors';

  // Whether the native library responded at all (false on emulators / iOS).
  static bool _nativeAvailable = true;

  // ── Model lifecycle ─────────────────────────────────────────────────────────

  /// Returns the local path for the model file.
  static Future<String> modelFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_modelFileName';
  }

  /// Returns true if the model file already exists on disk.
  static Future<bool> isModelDownloaded() async =>
      File(await modelFilePath()).existsSync();

  /// Returns true if the native context currently has a model loaded.
  static Future<bool> isModelLoaded() async {
    try {
      return await _channel.invokeMethod<bool>('isModelLoaded') ?? false;
    } on MissingPluginException {
      _nativeAvailable = false;
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Downloads the model file from [_modelUrl] into the app documents dir.
  ///
  /// [onProgress] receives values in [0.0, 1.0].
  static Future<void> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    final path = await modelFilePath();
    final file = File(path);
    if (file.existsSync()) return; // already present

    final client = http.Client();
    try {
      final request  = http.Request('GET', Uri.parse(_modelUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed — HTTP ${response.statusCode}');
      }

      final total    = response.contentLength ?? 0;
      int received   = 0;
      final sink     = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Loads the model file into the native SD context (blocking on native side).
  static Future<void> loadModel() async {
    final path = await modelFilePath();
    await _channel.invokeMethod<void>('loadModel', {'modelPath': path});
  }

  /// One-shot convenience: downloads (if needed) then loads the model.
  ///
  /// [onProgress] is called with [0.0, 1.0] during download.
  static Future<void> ensureReady({
    void Function(double progress)? onProgress,
  }) async {
    if (!await isModelDownloaded()) {
      await downloadModel(onProgress: onProgress);
    }
    if (!await isModelLoaded()) {
      await loadModel();
    }
  }

  // ── Generation ──────────────────────────────────────────────────────────────

  /// Generates a 32×32 pixel-art sticker from a text [prompt].
  ///
  /// Throws [Exception] when the native library is available but generation
  /// fails. Returns a procedural placeholder when the library is absent.
  static Future<Uint8List> generateSticker(String prompt) async {
    if (!_nativeAvailable) return _proceduralPlaceholder();

    final fullPrompt =
        '$prompt, pixel art, flat colors, simple shape, white background, sticker';
    const negPrompt =
        'photo, realistic, blurry, gradient, smooth shading, anti-aliasing, '
        'detailed background, 3d render, shadow';

    final seed = Random().nextInt(1 << 30);

    try {
      final rawPng = await _channel.invokeMethod<Uint8List>('generateImage', {
        'prompt':         fullPrompt,
        'negativePrompt': negPrompt,
        'width':          kGenerationSize,
        'height':         kGenerationSize,
        'steps':          kSteps,
        'cfg':            kCfg,
        'seed':           seed,
      });

      if (rawPng == null) throw Exception('Native returned null');
      return _postProcess(rawPng);
    } on MissingPluginException {
      _nativeAvailable = false;
      return _proceduralPlaceholder();
    } on PlatformException catch (e) {
      throw Exception('Generation error: ${e.message}');
    }
  }

  // ── Post-processing ─────────────────────────────────────────────────────────

  /// Downscales to [kOutputSize]×[kOutputSize] (nearest-neighbour) and
  /// reduces to [kPaletteColors] colours for an authentic pixel-art look.
  static Uint8List _postProcess(Uint8List pngBytes) {
    final source = img.decodePng(pngBytes);
    if (source == null) throw Exception('Failed to decode generated PNG');

    final small = img.copyResize(
      source,
      width:         kOutputSize,
      height:        kOutputSize,
      interpolation: img.Interpolation.nearest,
    );

    final pixelArt = img.quantize(small, numberOfColors: kPaletteColors);

    return Uint8List.fromList(img.encodePng(pixelArt));
  }

  // ── Procedural fallback ─────────────────────────────────────────────────────

  /// Generates a simple neon noise square — used when the native library
  /// is not available (emulator, iOS, first-run before model loads, etc.).
  static Uint8List _proceduralPlaceholder() {
    const size = kOutputSize;
    final image = img.Image(width: size, height: size);
    final rand  = Random();

    // Dark background
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        image.setPixelRgb(x, y, 10, 10, 15);
      }
    }

    // Neon pixel scatter
    const neonPalette = [
      [0,   212, 255],  // cyan
      [255, 0,   128],  // pink
      [157, 0,   255],  // purple
      [0,   255, 136],  // green
      [255, 229, 0  ],  // yellow
    ];

    for (int y = 2; y < size - 2; y++) {
      for (int x = 2; x < size - 2; x++) {
        if (rand.nextDouble() > 0.65) {
          final c = neonPalette[rand.nextInt(neonPalette.length)];
          image.setPixelRgb(x, y, c[0], c[1], c[2]);
        }
      }
    }

    // Neon border
    for (int i = 0; i < size; i++) {
      image.setPixelRgb(i, 0,        0, 212, 255);
      image.setPixelRgb(i, size - 1, 0, 212, 255);
      image.setPixelRgb(0,        i, 0, 212, 255);
      image.setPixelRgb(size - 1, i, 0, 212, 255);
    }

    return Uint8List.fromList(img.encodePng(image));
  }
}
