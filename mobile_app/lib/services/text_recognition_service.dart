import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class TextRecognitionService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  // Keywords per poster - from most unique to least unique
  // afis1: BOOST YOUR SOCIAL PRESENCE (blue)
  // afis2: Digital Marketing Agency white/red, phone +123-456-7891
  // afis3: DIGITAL MARKETING AGENCY purple, JOIN US
  // afis4: Creează fără limite (red can)
  // afis5: Best Burger in Town
  // afis6: FORM FOLLOWS FUNCTION BEAUTY FOLLOWS PASSION
  // afis7: EXPLORE THE WORLD, VISA SERVICES
  // afis8: Fashion BusinessS fbb23 (pink)
  // afis9: EXCLUSIVE EDITION SNEAKER 50% DISCOUNT
  // afis10: just <itec> yellow - handled by pHash fallback
  static const Map<String, List<String>> _keywords = {
    'afis6': ['FORM FOLLOWS', 'BEAUTY FOLLOWS', 'PASSION', 'BRINGING ART', 'WASHINGTON STREET'],
    'afis5': ['BEST BURGER', 'BURGER IN TOWN', 'BURGER'],
    'afis7': ['EXPLORE THE WORLD', 'VISA SERVICES', 'HOTEL BOOKING', 'AIR TICKETS', 'TRAVEL GUIDE'],
    'afis9': ['EXCLUSIVE EDITION', 'SNEAKER', '50%', 'DISCOUNT'],
    'afis8': ['FBB23', 'FASHION BUSINESS', 'FULL TIME', 'MARCH 2023'],
    'afis4': ['FARA LIMITE', 'CREAZA', 'LIMITE'],
    'afis1': ['SOCIAL PRESENCE', 'BOOST YOUR', 'CAPTIVATE AUDIENCES', 'SOCIAL MEDIA'],
    'afis2': ['123-456-7891', 'FACEBOOK BOOSTING', 'DIGITAL MARKETING AGENCY'],
    'afis3': ['JOIN US', 'CONTENT WRITING', 'CALL US FOR DETAILS', '0001234'],
  };

  Future<String?> recognizePoster(InputImage inputImage) async {
    try {
      final result = await _recognizer.processImage(inputImage);
      final text = result.text.toUpperCase().replaceAll('\n', ' ');
      debugPrint('TextRecognition: "$text"');

      for (final entry in _keywords.entries) {
        for (final keyword in entry.value) {
          if (text.contains(keyword.toUpperCase())) {
            debugPrint('TextRecognition: matched ${entry.key} via "$keyword"');
            return entry.key;
          }
        }
      }
    } catch (e) {
      debugPrint('TextRecognition error: $e');
    }
    return null;
  }

  void dispose() => _recognizer.close();
}
