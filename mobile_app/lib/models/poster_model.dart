class Poster {
  final String id;
  final String name;
  final String? imagePath;
  final int gridSize;
  
  Poster({
    required this.id,
    required this.name,
    this.imagePath,
    this.gridSize = 20,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imagePath': imagePath,
      'gridSize': gridSize,
    };
  }
  
  factory Poster.fromJson(Map<String, dynamic> json) {
    return Poster(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      imagePath: json['imagePath'],
      gridSize: json['gridSize'] ?? 20,
    );
  }
}

class Territory {
  final Map<String, TeamTerritory> teams;
  final String? dominantTeam;
  final int totalCells;
  
  Territory({
    required this.teams,
    this.dominantTeam,
    this.totalCells = 400,
  });
  
  factory Territory.fromJson(Map<String, dynamic> json) {
    final teams = <String, TeamTerritory>{};
    
    json.forEach((key, value) {
      if (key != 'dominant' && key != 'total' && value is Map) {
        teams[key] = TeamTerritory.fromJson(value as Map<String, dynamic>);
      }
    });
    
    return Territory(
      teams: teams,
      dominantTeam: json['dominant'],
      totalCells: json['total'] ?? 400,
    );
  }
  
  int getTeamPercentage(String teamId) {
    return teams[teamId]?.percentage ?? 0;
  }
}

class TeamTerritory {
  final int cells;
  final int percentage;
  final String color;
  
  TeamTerritory({
    required this.cells,
    required this.percentage,
    required this.color,
  });
  
  factory TeamTerritory.fromJson(Map<String, dynamic> json) {
    return TeamTerritory(
      cells: json['cells'] ?? 0,
      percentage: json['percentage'] ?? 0,
      color: json['color'] ?? '#FFFFFF',
    );
  }
}
