import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/poster_model.dart';
import '../models/user_model.dart';

class AppStateProvider extends ChangeNotifier {
  // User state
  String _oderId = const Uuid().v4();
  String _username = '';
  String _teamId = 'blue';
  
  // Connection state
  bool _isConnected = false;
  String? _currentPosterId;
  Poster? _currentPoster;
  
  // Territory state
  Territory? _territory;
  int _userCount = 0;

  // Per-poster conquest state (populated as battles happen)
  final Map<String, Territory> _posterTerritories = {};
  
  // Poster detection state
  bool _isPosterDetected = false;
  String? _detectedPosterId;
  
  // Getters
  String get oderId => _oderId;
  String get username => _username.isEmpty ? 'User_${_oderId.substring(0, 4)}' : _username;
  String get teamId => _teamId;
  bool get isConnected => _isConnected;
  String? get currentPosterId => _currentPosterId;
  Poster? get currentPoster => _currentPoster;
  Territory? get territory => _territory;
  int get userCount => _userCount;
  Map<String, Territory> get posterTerritories => Map.unmodifiable(_posterTerritories);
  bool get isPosterDetected => _isPosterDetected;
  String? get detectedPosterId => _detectedPosterId;
  
  // Available teams
  final List<Team> teams = [
    Team(id: 'red', name: 'Red Team', color: '#FF0040'),
    Team(id: 'blue', name: 'Blue Team', color: '#00D4FF'),
    Team(id: 'green', name: 'Green Team', color: '#00FF88'),
    Team(id: 'purple', name: 'Purple Team', color: '#9D00FF'),
  ];
  
  // Available posters
  final Map<String, Poster> posters = {
    'afis1': Poster(id: 'afis1', name: 'Social Presence', imagePath: 'assets/posters/afis1.png'),
    'afis2': Poster(id: 'afis2', name: 'Digital Marketing', imagePath: 'assets/posters/afis2.png'),
    'afis3': Poster(id: 'afis3', name: 'Tech Innovation', imagePath: 'assets/posters/afis3.png'),
    'afis4': Poster(id: 'afis4', name: 'Creative Design', imagePath: 'assets/posters/afis4.png'),
    'afis5': Poster(id: 'afis5', name: 'Cloud Computing', imagePath: 'assets/posters/afis5.png'),
    'afis6': Poster(id: 'afis6', name: 'AI Revolution', imagePath: 'assets/posters/afis6.png'),
    'afis7': Poster(id: 'afis7', name: 'Cyber Security', imagePath: 'assets/posters/afis7.png'),
    'afis8': Poster(id: 'afis8', name: 'Data Science', imagePath: 'assets/posters/afis8.png'),
    'afis9': Poster(id: 'afis9', name: 'Mobile Future', imagePath: 'assets/posters/afis9.png'),
    'afis10': Poster(id: 'afis10', name: 'Web3 World', imagePath: 'assets/posters/afis10.png'),
  };
  
  void setUsername(String name) {
    _username = name;
    notifyListeners();
  }
  
  void setTeam(String teamId) {
    _teamId = teamId;
    notifyListeners();
  }
  
  void setConnectionStatus(bool connected) {
    _isConnected = connected;
    notifyListeners();
  }
  
  void setCurrentPoster(String? posterId) {
    _currentPosterId = posterId;
    _currentPoster = posterId != null ? posters[posterId] : null;
    notifyListeners();
  }
  
  void setTerritory(Territory territory) {
    _territory = territory;
    notifyListeners();
  }

  void updatePosterTerritory(String posterId, Territory territory) {
    _posterTerritories[posterId] = territory;
    notifyListeners();
  }
  
  void setUserCount(int count) {
    _userCount = count;
    notifyListeners();
  }
  
  void setPosterDetected(bool detected, String? posterId) {
    _isPosterDetected = detected;
    _detectedPosterId = posterId;
    notifyListeners();
  }
  
  void reset() {
    _currentPosterId = null;
    _currentPoster = null;
    _territory = null;
    _userCount = 0;
    _isPosterDetected = false;
    _detectedPosterId = null;
    notifyListeners();
  }
}
