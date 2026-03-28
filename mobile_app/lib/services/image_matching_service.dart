import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageMatchingService {
  static const int _hashSize = 16;
  static const double _matchThreshold = 0.72;

  static final Map<String, List<bool>> _referenceHashes = {};
  static bool _initialized = false;

  static const List<String> posterIds = [
    'afis1', 'afis2', 'afis3', 'afis4', 'afis5',
    'afis6', 'afis7', 'afis8', 'afis9', 'afis10',
  ];

  static Future<void> initialize() async {
    if (_initialized) return;
    for (final id in posterIds) {
      try {
        final bytes = await rootBundle.load('assets/posters/$id.png');
        final image = img.decodeImage(bytes.buffer.asUint8List());
        if (image != null) {
          _referenceHashes[id] = _pHash(image);
          debugPrint('ImageMatching: loaded $id');
        }
      } catch (e) {
        debugPrint('ImageMatching: skipped $id ($e)');
      }
    }
    _initialized = true;
    debugPrint('ImageMatching: initialized with ${_referenceHashes.length} posters');
  }

  // Perceptual hash - resize to _hashSize x _hashSize, compare each pixel to average
  static List<bool> _pHash(img.Image image) {
    final small = img.copyResize(image, width: _hashSize, height: _hashSize);
    final gray = img.grayscale(small);

    int total = 0;
    final values = <int>[];
    for (int y = 0; y < _hashSize; y++) {
      for (int x = 0; x < _hashSize; x++) {
        final pixel = gray.getPixel(x, y);
        final v = pixel.r.toInt();
        values.add(v);
        total += v;
      }
    }

    final avg = total ~/ values.length;
    return values.map((v) => v >= avg).toList();
  }

  static double _similarity(List<bool> a, List<bool> b) {
    int matches = 0;
    for (int i = 0; i < a.length; i++) {
      if (a[i] == b[i]) matches++;
    }
    return matches / a.length;
  }

  // Convert YUV420 camera frame to img.Image (Y-only, grayscale)
  static img.Image? cameraImageToGray(CameraImage cameraImage) {
    try {
      final width = cameraImage.width;
      final height = cameraImage.height;
      final yPlane = cameraImage.planes[0];
      final bytes = yPlane.bytes;
      final rowStride = yPlane.bytesPerRow;

      final image = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yVal = bytes[y * rowStride + x];
          image.setPixelRgb(x, y, yVal, yVal, yVal);
        }
      }
      return image;
    } catch (e) {
      debugPrint('ImageMatching: cameraImageToGray error $e');
      return null;
    }
  }

  // Center-crop to square then match
  static String? matchFrame(CameraImage cameraImage) {
    if (!_initialized || _referenceHashes.isEmpty) return null;

    final gray = cameraImageToGray(cameraImage);
    if (gray == null) return null;

    // Center crop to square
    final side = gray.width < gray.height ? gray.width : gray.height;
    final xOff = (gray.width - side) ~/ 2;
    final yOff = (gray.height - side) ~/ 2;
    final cropped = img.copyCrop(gray, x: xOff, y: yOff, width: side, height: side);

    final frameHash = _pHash(cropped);

    String? bestId;
    double bestScore = 0;

    for (final entry in _referenceHashes.entries) {
      final score = _similarity(frameHash, entry.value);
      if (score > bestScore) {
        bestScore = score;
        bestId = entry.key;
      }
    }

    debugPrint('ImageMatching: best=$bestId score=${bestScore.toStringAsFixed(3)}');

    if (bestScore >= _matchThreshold) return bestId;
    return null;
  }

  static bool get isInitialized => _initialized;
  static int get loadedCount => _referenceHashes.length;
}
