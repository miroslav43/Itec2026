class User {
  final String socketId;
  final String oderId;
  final String teamId;
  final String username;
  final int joinedAt;
  
  User({
    required this.socketId,
    required this.oderId,
    required this.teamId,
    required this.username,
    required this.joinedAt,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'socketId': socketId,
      'userId': oderId,
      'teamId': teamId,
      'username': username,
      'joinedAt': joinedAt,
    };
  }
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      socketId: json['socketId'] ?? '',
      oderId: json['userId'] ?? '',
      teamId: json['teamId'] ?? '',
      username: json['username'] ?? 'Unknown',
      joinedAt: json['joinedAt'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class Team {
  final String id;
  final String name;
  final String color;
  
  Team({
    required this.id,
    required this.name,
    required this.color,
  });
  
  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      color: json['color'] ?? '#FFFFFF',
    );
  }
}
