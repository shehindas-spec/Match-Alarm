import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

/// Details of one football match.
class MatchFixture {
  final String gameId;
  final String league;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoffIst;

  const MatchFixture({
    required this.gameId,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffIst,
  });

  /// Alarm time is exactly five minutes before kickoff.
  DateTime get alarmTimeIst => kickoffIst.subtract(const Duration(minutes: 5));
}

/// Fetches fixtures for FC Barcelona and Kerala Blasters FC.
class FixtureService {
  FixtureService._();

  static final FixtureService instance = FixtureService._();

  static const String _apiBaseUrl =
      'https://api.api-ninjas.com/v1/soccermatches';

  static const String _apiKey = String.fromEnvironment('API_NINJAS_KEY');

  static const int _season = 2026;

  static const Map<String, String> _teams = {
    'soccer-barcelona': 'FC Barcelona',
    'soccer-kerala-blasters-fc': 'Kerala Blasters FC',
  };

  /// Fetch upcoming scheduled fixtures for both teams.
  Future<List<MatchFixture>> fetchUpcomingFixtures() async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'API key is missing. Configure API_NINJAS_KEY before running the app.',
      );
    }

    final List<MatchFixture> allFixtures = [];

    for (final teamId in _teams.keys) {
      final fixtures = await _fetchTeamFixtures(teamId);
      allFixtures.addAll(fixtures);
    }

    // Remove duplicate games.
    final Map<String, MatchFixture> uniqueFixtures = {};

    for (final fixture in allFixtures) {
      uniqueFixtures[fixture.gameId] = fixture;
    }

    final result = uniqueFixtures.values.toList();

    // Sort by kickoff time.
    result.sort((a, b) => a.kickoffIst.compareTo(b.kickoffIst));

    return result;
  }

  Future<List<MatchFixture>> _fetchTeamFixtures(String teamId) async {
    final uri = Uri.parse(
      _apiBaseUrl,
    ).replace(queryParameters: {'team': teamId, 'season': _season.toString()});

    final response = await http
        .get(uri, headers: {'X-Api-Key': _apiKey, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'Fixture API failed for ${_teams[teamId]}. '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      throw Exception('Unexpected fixture API response for ${_teams[teamId]}.');
    }

    final List<MatchFixture> fixtures = [];

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final status = item['status']?.toString().toLowerCase();

      // Only schedule alarms for matches that have not started.
      if (status != 'scheduled') {
        continue;
      }

      final gameId = item['game_id']?.toString();
      final homeTeamData = item['home_team'];
      final awayTeamData = item['away_team'];

      final homeTeam = homeTeamData is Map
          ? homeTeamData['name']?.toString()
          : homeTeamData?.toString();

      final awayTeam = awayTeamData is Map
          ? awayTeamData['name']?.toString()
          : awayTeamData?.toString();
      final startTime = item['start_time']?.toString();
      final league = item['league']?.toString() ?? 'Football';

      if (gameId == null ||
          gameId.isEmpty ||
          homeTeam == null ||
          awayTeam == null ||
          startTime == null) {
        continue;
      }

      final parsedKickoff = DateTime.tryParse(startTime);

      if (parsedKickoff == null) {
        continue;
      }

      // Convert the API kickoff time to India Standard Time.
      final kickoffIst = tz.TZDateTime.from(
        parsedKickoff.toUtc(),
        tz.getLocation('Asia/Kolkata'),
      );

      // Ignore matches that have already reached their alarm time.
      final nowIst = tz.TZDateTime.now(tz.getLocation('Asia/Kolkata'));

      final alarmTime = kickoffIst.subtract(const Duration(minutes: 5));

      if (!alarmTime.isAfter(nowIst)) {
        continue;
      }

      fixtures.add(
        MatchFixture(
          gameId: gameId,
          league: league,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffIst: kickoffIst,
        ),
      );
    }

    return fixtures;
  }
}
