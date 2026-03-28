import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthUser {
  final int id;
  final String email;
  final String username;

  const AuthUser({required this.id, required this.email, required this.username});

  factory AuthUser.fromJson(Map<String, dynamic> j) =>
      AuthUser(id: j['id'] as int, email: j['email'] as String, username: j['username'] as String);
}

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  static String serverUrl = 'http://10.27.252.100:3000';

  // ── Token storage ──────────────────────────────────────────

  static Future<void> saveToken(String token, AuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode({'id': user.id, 'email': user.email, 'username': user.username}));
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<AuthUser?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  // ── API calls ──────────────────────────────────────────────

  static Future<({String token, AuthUser user})> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$serverUrl/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) throw body['error'] as String? ?? 'Register failed';
    return (token: body['token'] as String, user: AuthUser.fromJson(body['user'] as Map<String, dynamic>));
  }

  static Future<({String token, AuthUser user})> login({
    required String email,
    required String password,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$serverUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) throw body['error'] as String? ?? 'Login failed';
    return (token: body['token'] as String, user: AuthUser.fromJson(body['user'] as Map<String, dynamic>));
  }

  static Future<bool> verifyToken(String token) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$serverUrl/api/auth/verify'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Returns stored user if token still valid, null otherwise
  static Future<AuthUser?> checkAuth() async {
    final token = await getToken();
    if (token == null) return null;
    final valid = await verifyToken(token);
    if (!valid) {
      await clearSession();
      return null;
    }
    return getStoredUser();
  }
}
