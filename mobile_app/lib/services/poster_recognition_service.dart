import 'dart:async';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'image_matching_service.dart';
import 'text_recognition_service.dart';

class PosterRecognitionService {
  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  final TextRecognitionService _textRecognizer = TextRecognitionService();

  bool _isProcessing = false;
  DateTime? _lastProcessTime;
  static const _processingInterval = Duration(milliseconds: 500);
  
  // Poster QR code mapping (QR content -> poster ID)
  // For hackathon MVP: use QR codes with poster IDs
  static const Map<String, String> qrToPosterMap = {
    'ITEC_AFIS1': 'afis1',
    'ITEC_AFIS2': 'afis2',
    'ITEC_AFIS3': 'afis3',
    'ITEC_AFIS4': 'afis4',
    'ITEC_AFIS5': 'afis5',
    'ITEC_AFIS6': 'afis6',
    'ITEC_AFIS7': 'afis7',
    'ITEC_AFIS8': 'afis8',
    'ITEC_AFIS9': 'afis9',
    'ITEC_AFIS10': 'afis10',
    // Also support direct poster IDs
    'afis1': 'afis1',
    'afis2': 'afis2',
    'afis3': 'afis3',
    'afis4': 'afis4',
    'afis5': 'afis5',
    'afis6': 'afis6',
    'afis7': 'afis7',
    'afis8': 'afis8',
    'afis9': 'afis9',
    'afis10': 'afis10',
  };
  
  Future<PosterDetectionResult?> processImage(CameraImage image, int rotation, {bool enableImageMatching = false}) async {
    // Rate limiting
    if (_isProcessing) return null;
    if (_lastProcessTime != null && 
        DateTime.now().difference(_lastProcessTime!) < _processingInterval) {
      return null;
    }
    
    _isProcessing = true;
    _lastProcessTime = DateTime.now();
    
    try {
      final inputImage = _convertCameraImage(image, rotation);
      if (inputImage == null) {
        _isProcessing = false;
        return null;
      }
      
      // Scan for QR codes
      final barcodes = await _barcodeScanner.processImage(inputImage);
      
      // 1. Try QR code scanning first (fast, reliable)
      for (final barcode in barcodes) {
        final rawValue = barcode.rawValue;
        if (rawValue != null) {
          final posterId = qrToPosterMap[rawValue] ?? qrToPosterMap[rawValue.toUpperCase()];
          if (posterId != null) {
            _isProcessing = false;
            return PosterDetectionResult(
              posterId: posterId,
              confidence: 1.0,
              detectionMethod: DetectionMethod.qrCode,
            );
          }
        }
      }

      // 2. Text recognition (primary auto-detect, every 500ms same as QR)
      final textMatchId = await _textRecognizer.recognizePoster(inputImage!);
      if (textMatchId != null) {
        _isProcessing = false;
        return PosterDetectionResult(
          posterId: textMatchId,
          confidence: 0.9,
          detectionMethod: DetectionMethod.imageMatching,
        );
      }

      // 3. Fallback: image hash matching (throttled to every 2s)
      if (enableImageMatching) {
        final matchedId = ImageMatchingService.matchFrame(image);
        if (matchedId != null) {
          _isProcessing = false;
          return PosterDetectionResult(
            posterId: matchedId,
            confidence: 0.80,
            detectionMethod: DetectionMethod.imageMatching,
          );
        }
      }

      _isProcessing = false;
      return null;
    } catch (e) {
      debugPrint('Error processing image: $e');
      _isProcessing = false;
      return null;
    }
  }
  
  InputImage? _convertCameraImage(CameraImage image, int rotation) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;
      
      final plane = image.planes.first;
      
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(rotation) ?? InputImageRotation.rotation0deg,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }
  
  void dispose() {
    _barcodeScanner.close();
    _textRecognizer.dispose();
  }
}

class PosterDetectionResult {
  final String posterId;
  final double confidence;
  final DetectionMethod detectionMethod;
  
  PosterDetectionResult({
    required this.posterId,
    required this.confidence,
    required this.detectionMethod,
  });
}

enum DetectionMethod {
  qrCode,
  imageMatching,
  manual,
}
