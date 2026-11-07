import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'screens/alarm_screen.dart';
import 'services/alarm_service.dart';
import 'services/fixture_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

const MethodChannel nativeAlarmChannel = MethodChannel(
  'com.example.match_alarm/native_alarm',
);

bool alarmScreenIsOpen = false;
String? pendingAlarmPayload;
Map<String, dynamic>? pendingMatchDetails;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AlarmService.instance.initialize(
    onAlarmOpened: _handleAlarmNotification,
  );

  final launchDetails = await AlarmService.instance.notifications
      .getNotificationAppLaunchDetails();

  if (launchDetails?.didNotificationLaunchApp ?? false) {
    pendingAlarmPayload =
        launchDetails?.notificationResponse?.payload ?? 'test_alarm';
  }

  runApp(const MatchAlarmApp());
}

void _handleAlarmNotification(String? payload) {
  _openAlarmScreen(payload ?? 'test_alarm');
}

void _openAlarmScreen(
  String payload, {
  Map<String, dynamic>? details,
}) {
  pendingAlarmPayload = payload;
  pendingMatchDetails = details;
  _showPendingAlarmScreen();
}

void _showPendingAlarmScreen() {
  final navigator = appNavigatorKey.currentState;

  if (navigator == null || pendingAlarmPayload == null || alarmScreenIsOpen) {
    return;
  }

  pendingAlarmPayload = null;
  alarmScreenIsOpen = true;

  final details = pendingMatchDetails;
  pendingMatchDetails = null;

  navigator
      .push(
        MaterialPageRoute<void>(
          builder: (context) => AlarmScreen(
            homeTeam: details?['homeTeam']?.toString() ?? 'FC Barcelona',
            awayTeam: details?['awayTeam']?.toString() ?? 'Opponent',
            kickoffTime: details?['kickoffTime']?.toString() ?? 'Test alarm',
            alarmTime: details?['alarmTime']?.toString() ?? 'Not available',
            alarmMessage: 'MATCH STARTS IN 5 MINUTES',
            onStop: () async {
              // Stop only the currently ringing sound. Future match alarms remain scheduled.
              await nativeAlarmChannel.invokeMethod<bool>('stopAlarmSound');
              if (navigator.canPop()) {
                navigator.pop();
              }
              alarmScreenIsOpen = false;
            },
          ),
        ),
      )
      .then((_) {
        alarmScreenIsOpen = false;
      });
}

const Color barcaBlue = Color(0xFF1546A0);
const Color barcaRed = Color(0xFFB51E36);
const Color blastersYellow = Color(0xFFF5D51D);
const Color darkBackground = Color(0xFF101522);
const Color darkCard = Color(0xFF1B2638);

class MatchAlarmApp extends StatefulWidget {
  const MatchAlarmApp({super.key});

  @override
  State<MatchAlarmApp> createState() => _MatchAlarmAppState();
}

class _MatchAlarmAppState extends State<MatchAlarmApp> {
  ThemeMode themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();

    // Receive the alarm-open event when Android brings the app to the foreground.
    nativeAlarmChannel.setMethodCallHandler((call) async {
      if (call.method == 'openAlarmScreen') {
        try {
          final details = await nativeAlarmChannel
              .invokeMapMethod<String, dynamic>('consumeAlarmPayload');

          await nativeAlarmChannel.invokeMethod<bool>('consumeAlarmLaunch');

          _openAlarmScreen('native_alarm', details: details);
        } catch (error) {
          debugPrint('Could not read match alarm details: $error');
          _openAlarmScreen('native_alarm');
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check whether Android launched this app from the alarm notification.
      try {
        final details = await nativeAlarmChannel
            .invokeMapMethod<String, dynamic>('consumeAlarmPayload');

        final shouldOpen = await nativeAlarmChannel.invokeMethod<bool>(
          'consumeAlarmLaunch',
        );

        if (shouldOpen == true) {
          _openAlarmScreen('native_alarm', details: details);
        }
      } on PlatformException catch (error) {
        debugPrint('Could not check alarm launch: ${error.message}');
      } on MissingPluginException catch (error) {
        debugPrint('Native alarm channel unavailable: $error');
      }

      _showPendingAlarmScreen();
    });
  }

  void toggleTheme() {
    setState(() {
      themeMode = themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'MATCH ALARM',
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: barcaBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F5F9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: barcaBlue,
          brightness: Brightness.dark,
          surface: darkBackground,
        ),
        scaffoldBackgroundColor: darkBackground,
      ),
      home: MatchHomeShell(
        isDark: themeMode == ThemeMode.dark,
        onThemeToggle: toggleTheme,
      ),
    );
  }
}

class MatchHomeShell extends StatefulWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;

  const MatchHomeShell({
    super.key,
    required this.isDark,
    required this.onThemeToggle,
  });

  @override
  State<MatchHomeShell> createState() => _MatchHomeShellState();
}

class _MatchHomeShellState extends State<MatchHomeShell> {
  int selectedIndex = 0;
  int selectedTeam = 0;

  bool barcaAlarm = true;
  bool blastersAlarm = true;
  bool masterAlarm = true;

  List<MatchFixture> _loadedFixtures = [];
  bool _isSyncingFixtures = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFixtures(showMessage: false);
    });
  }

  bool _isBarcelonaFixture(MatchFixture fixture) {
    final names = '${fixture.homeTeam} ${fixture.awayTeam}'.toLowerCase();
    return names.contains('barcelona');
  }

  bool _isBlastersFixture(MatchFixture fixture) {
    final names = '${fixture.homeTeam} ${fixture.awayTeam}'.toLowerCase();
    return names.contains('kerala blasters');
  }

  Future<void> _syncFixtures({bool showMessage = true}) async {
    if (_isSyncingFixtures || !masterAlarm) return;

    setState(() => _isSyncingFixtures = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final permissionsGranted =
          await AlarmService.instance.requestPermissions();

      if (!mounted) return;

      if (!permissionsGranted) {
        if (showMessage) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Allow notifications, exact alarms and full-screen alerts to schedule match alarms.',
              ),
            ),
          );
        }
        return;
      }

      final fixtures = await FixtureService.instance.fetchUpcomingFixtures();
      if (!mounted) return;

      setState(() => _loadedFixtures = fixtures);

      final enabledFixtures = fixtures.where((fixture) {
        final isBarca = _isBarcelonaFixture(fixture);
        final isBlasters = _isBlastersFixture(fixture);
        return (isBarca && barcaAlarm) ||
            (isBlasters && blastersAlarm);
      }).toList();

      final count = await AlarmService.instance
          .scheduleMatchAlarms(enabledFixtures);

      if (!mounted) return;

      if (showMessage) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('$count match alarm(s) scheduled.'),
          ),
        );
      }
    } catch (error) {
      debugPrint('Fixture sync failed: $error');
      if (mounted && showMessage) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not update match alarms: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingFixtures = false);
      } else {
        _isSyncingFixtures = false;
      }
    }
  }

  Future<void> _applyAlarmSettings() async {
    // Cancel alarms for teams that are switched off.
    for (final fixture in _loadedFixtures) {
      if ((!masterAlarm) ||
          (_isBarcelonaFixture(fixture) && !barcaAlarm) ||
          (_isBlastersFixture(fixture) && !blastersAlarm)) {
        await AlarmService.instance.cancelMatchAlarm(fixture.gameId);
      }
    }

    if (masterAlarm) {
      await _syncFixtures(showMessage: false);
    }
  }

  Future<void> _runTestAlarm() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final permissionsGranted = await AlarmService.instance
          .requestPermissions();

      if (!mounted) return;

      if (!permissionsGranted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Please allow notifications, exact alarms and full-screen alerts in Android settings.',
            ),
          ),
        );
        return;
      }

      await AlarmService.instance.scheduleTestAlarm();

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Test alarm scheduled for one minute from now.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not schedule test alarm: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        selectedTeam: selectedTeam,
        onTeamChanged: (value) {
          setState(() => selectedTeam = value);
        },
        fixtures: _loadedFixtures,
        isSyncing: _isSyncingFixtures,
        onRefresh: () => _syncFixtures(),
        alarmEnabled: masterAlarm &&
            (selectedTeam == 0 ? barcaAlarm : blastersAlarm),
      ),
      MatchesPage(fixtures: _loadedFixtures),
      SettingsPage(
        isDark: widget.isDark,
        onThemeToggle: widget.onThemeToggle,
        masterAlarm: masterAlarm,
        barcaAlarm: barcaAlarm,
        blastersAlarm: blastersAlarm,
        onMasterChanged: (value) {
          setState(() => masterAlarm = value);
          _applyAlarmSettings();
        },
        onBarcaChanged: (value) {
          setState(() => barcaAlarm = value);
          _applyAlarmSettings();
        },
        onBlastersChanged: (value) {
          setState(() => blastersAlarm = value);
          _applyAlarmSettings();
        },
        onTestAlarm: _runTestAlarm,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final int selectedTeam;
  final ValueChanged<int> onTeamChanged;
  final List<MatchFixture> fixtures;
  final bool isSyncing;
  final VoidCallback onRefresh;
  final bool alarmEnabled;

  const HomePage({
    super.key,
    required this.selectedTeam,
    required this.onTeamChanged,
    required this.fixtures,
    required this.isSyncing,
    required this.onRefresh,
    required this.alarmEnabled,
  });

  bool _belongsToSelectedTeam(MatchFixture fixture) {
    final names = '${fixture.homeTeam} ${fixture.awayTeam}'.toLowerCase();
    return selectedTeam == 0
        ? names.contains('barcelona')
        : names.contains('kerala blasters');
  }

  String _date(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const weekdays = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ];
    return '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]} ${value.year}';
  }

  String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'} IST';
  }

  @override
  Widget build(BuildContext context) {
    final isBarca = selectedTeam == 0;
    final accent = isBarca ? barcaBlue : blastersYellow;
    final teamFixtures = fixtures.where(_belongsToSelectedTeam).toList()
      ..sort((a, b) => a.kickoffIst.compareTo(b.kickoffIst));
    final nextMatch = teamFixtures.isEmpty ? null : teamFixtures.first;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 45,
                  width: 45,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [barcaBlue, barcaRed]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.alarm_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MATCH ALARM', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: 1.2)),
                      Text('YOUR FOOTBALL. YOUR REMINDER.', style: TextStyle(fontSize: 9, letterSpacing: 1.1, color: Colors.grey)),
                    ],
                  ),
                ),
                Icon(Icons.notifications_active_outlined, color: Theme.of(context).colorScheme.onSurface),
              ],
            ),
            const SizedBox(height: 30),
            const Text('YOUR TEAMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TeamSelector(name: 'BARCELONA', subtitle: 'FCB', color: barcaBlue, selected: selectedTeam == 0, onTap: () => onTeamChanged(0))),
                const SizedBox(width: 12),
                Expanded(child: TeamSelector(name: 'BLASTERS', subtitle: 'KBFC', color: blastersYellow, selected: selectedTeam == 1, onTap: () => onTeamChanged(1))),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('NEXT MATCH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.4)),
                Text(isBarca ? 'FC BARCELONA' : 'KERALA BLASTERS', style: TextStyle(fontSize: 9, color: accent, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(19),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isBarca
                      ? const [Color(0xFF173D79), Color(0xFF18243E), Color(0xFF401B35)]
                      : const [Color(0xFF49431A), Color(0xFF292D29), Color(0xFF1B2638)],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: nextMatch == null
                  ? Column(
                      children: [
                        Icon(isSyncing ? Icons.sync : Icons.event_busy_outlined, color: Colors.white70, size: 34),
                        const SizedBox(height: 12),
                        Text(
                          isSyncing ? 'Loading upcoming fixtures...' : 'No upcoming fixture found',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 7),
                        const Text('Pull down to refresh match information.', style: TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: isSyncing ? null : onRefresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh fixtures'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                              child: Text('UPCOMING', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                            Flexible(child: Text(nextMatch.league, style: const TextStyle(color: Colors.white70, fontSize: 10), textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 25),
                        Row(
                          children: [
                            Expanded(child: _MatchTeamLabel(name: nextMatch.homeTeam, isHome: true)),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('VS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 19))),
                            Expanded(child: _MatchTeamLabel(name: nextMatch.awayTeam, isHome: false)),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 12),
                        _MatchDetailRow(icon: Icons.calendar_month_outlined, label: 'DATE', value: _date(nextMatch.kickoffIst)),
                        const SizedBox(height: 12),
                        _MatchDetailRow(icon: Icons.schedule_rounded, label: 'KICKOFF', value: _time(nextMatch.kickoffIst)),
                        const SizedBox(height: 12),
                        _MatchDetailRow(icon: Icons.alarm_rounded, label: 'ALARM', value: _time(nextMatch.alarmTimeIst)),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Icon(alarmEnabled ? Icons.notifications_active : Icons.notifications_off, color: accent, size: 18),
                              const SizedBox(width: 9),
                              Expanded(child: Text(alarmEnabled ? 'Match alarm enabled' : 'Match alarm disabled in Settings', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                              Text('5 MIN BEFORE', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('UPCOMING FIXTURES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.3)),
                Text('${teamFixtures.length} found', style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 10),
            if (teamFixtures.length > 1)
              ...teamFixtures.skip(1).take(5).map((fixture) => Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${fixture.homeTeam}  vs  ${fixture.awayTeam}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        Text('${fixture.league}  •  ${_date(fixture.kickoffIst)}  •  ${_time(fixture.kickoffIst)}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                      ],
                    ),
                  ))
            else if (nextMatch != null)
              const Text('This is the only upcoming fixture currently returned by the provider.', style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: isSyncing ? null : onRefresh, icon: const Icon(Icons.refresh), label: Text(isSyncing ? 'Updating fixtures...' : 'Refresh fixtures'))),
          ],
        ),
      ),
    );
  }
}

/// Looks up a club badge from TheSportsDB and caches the resolved URL.
/// Exact team-name matching avoids accidentally displaying another club's crest.
class TeamLogoService {
  TeamLogoService._();

  static final Map<String, Future<String?>> _cache = {};

  static Future<String?> badgeFor(String teamName) {
    final key = teamName.trim().toLowerCase();
    return _cache.putIfAbsent(key, () => _lookup(teamName));
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<String?> _lookup(String teamName) async {
    final name = teamName.trim();
    final normalName = _normalise(name);

    // Search using the full fixture name. The old code shortened Barcelona
    // and Kerala Blasters and blindly used the first search result, which
    // could be a different club or have no badge.
    final queries = <String>[name];
    if (normalName.contains('barcelona') && name != 'FC Barcelona') {
      queries.add('FC Barcelona');
    }
    if (normalName.contains('keralablasters') && name != 'Kerala Blasters FC') {
      queries.add('Kerala Blasters FC');
    }

    for (final query in queries) {
      try {
        final uri = Uri.https(
          'www.thesportsdb.com',
          '/api/v1/json/3/searchteams.php',
          {'t': query},
        );
        final response = await http.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'MatchAlarm/1.0',
        }).timeout(const Duration(seconds: 12));

        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        final teams = decoded is Map ? decoded['teams'] : null;
        if (teams is! List) continue;

        // Prefer an exact/near-exact team name rather than teams.first.
        Map? bestMatch;
        for (final item in teams) {
          if (item is! Map) continue;
          final candidate = _normalise(item['strTeam']?.toString() ?? '');
          if (candidate == normalName) {
            bestMatch = item;
            break;
          }
          if (bestMatch == null &&
              candidate.isNotEmpty &&
              (candidate.contains(normalName) || normalName.contains(candidate))) {
            bestMatch = item;
          }
        }

        final badge = bestMatch?['strBadge']?.toString();
        if (badge != null && badge.startsWith('https://')) return badge;
      } catch (error) {
        debugPrint('Logo lookup failed for "$query": $error');
      }
    }
    return null;
  }
}

class TeamCrest extends StatelessWidget {
  final String teamName;
  final double size;
  final Color fallbackColor;
  const TeamCrest({super.key, required this.teamName, this.size = 54, this.fallbackColor = barcaBlue});

  String get _initials => teamName.trim().split(RegExp(r'\s+')).take(2)
      .map((part) => part.isEmpty ? '' : part[0]).join().toUpperCase();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: TeamLogoService.badgeFor(teamName),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return CircleAvatar(radius: size / 2, backgroundColor: fallbackColor.withValues(alpha: .2),
            child: Text(_initials, style: TextStyle(color: fallbackColor, fontWeight: FontWeight.w900, fontSize: size * .23)));
        }
        return SizedBox(width: size, height: size,
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain,
            placeholder: (_, __) => CircleAvatar(radius: size / 2, backgroundColor: fallbackColor.withValues(alpha: .12),
              child: const Icon(Icons.shield_outlined, color: Colors.grey)),
            errorWidget: (_, __, ___) => CircleAvatar(radius: size / 2, backgroundColor: fallbackColor.withValues(alpha: .2),
              child: Text(_initials, style: TextStyle(color: fallbackColor, fontWeight: FontWeight.w900))),
          ));
      },
    );
  }
}

class _MatchTeamLabel extends StatelessWidget {
  final String name;
  final bool isHome;

  const _MatchTeamLabel({required this.name, required this.isHome});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TeamCrest(teamName: name, size: 54, fallbackColor: Colors.white),
        const SizedBox(height: 9),
        Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 3),
        Text(isHome ? 'HOME' : 'AWAY', style: const TextStyle(color: Colors.white60, fontSize: 8, letterSpacing: 1)),
      ],
    );
  }
}

class _MatchDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MatchDetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 9),
        SizedBox(width: 62, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold))),
        Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

class TeamSelector extends StatelessWidget {
  final String name;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const TeamSelector({
    super.key,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            TeamCrest(teamName: subtitle == 'FCB' ? 'FC Barcelona' : 'Kerala Blasters FC', size: 36, fallbackColor: color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: color, size: 17),
          ],
        ),
      ),
    );
  }
}

class TeamBadge extends StatelessWidget {
  final String shortName;
  final String teamName;
  final Color color;

  const TeamBadge({
    super.key,
    required this.shortName,
    required this.teamName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TeamCrest(teamName: teamName, size: 56, fallbackColor: color),
        const SizedBox(height: 9),
        Text(
          teamName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 13),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class MatchesPage extends StatelessWidget {
  final List<MatchFixture> fixtures;
  const MatchesPage({super.key, required this.fixtures});

  bool _isBarca(MatchFixture f) => '${f.homeTeam} ${f.awayTeam}'.toLowerCase().contains('barcelona');
  bool _isBlasters(MatchFixture f) => '${f.homeTeam} ${f.awayTeam}'.toLowerCase().contains('kerala blasters');

  @override
  Widget build(BuildContext context) {
    final sorted = [...fixtures]..sort((a, b) => a.kickoffIst.compareTo(b.kickoffIst));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        const Text('MATCH CENTRE', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Upcoming fixtures for your teams', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 24),
        MatchSection(title: 'FC BARCELONA', subtitle: 'All competitions', color: barcaBlue,
          fixtures: sorted.where(_isBarca).toList()),
        const SizedBox(height: 18),
        MatchSection(title: 'KERALA BLASTERS', subtitle: 'All competitions', color: blastersYellow,
          fixtures: sorted.where(_isBlasters).toList()),
      ],
    );
  }
}

class MatchSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<MatchFixture> fixtures;

  const MatchSection({super.key, required this.title, required this.subtitle, required this.color, required this.fixtures});

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'} IST';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: color, width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 14),
        if (fixtures.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: Text('No upcoming fixtures available.', style: TextStyle(color: Colors.grey, fontSize: 12))))
        else
          ...fixtures.take(12).map((f) => Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(f.league, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Column(children: [TeamCrest(teamName: f.homeTeam, size: 42, fallbackColor: color), const SizedBox(height: 6), Text(f.homeTeam, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))])),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey))),
                Expanded(child: Column(children: [TeamCrest(teamName: f.awayTeam, size: 42, fallbackColor: color), const SizedBox(height: 6), Text(f.awayTeam, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))])),
              ]),
              const SizedBox(height: 10),
              Text('${_date(f.kickoffIst)}  •  ${_time(f.kickoffIst)}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ]),
          )),
      ]),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;
  final bool masterAlarm;
  final bool barcaAlarm;
  final bool blastersAlarm;
  final ValueChanged<bool> onMasterChanged;
  final ValueChanged<bool> onBarcaChanged;
  final ValueChanged<bool> onBlastersChanged;
  final VoidCallback onTestAlarm;

  const SettingsPage({
    super.key,
    required this.isDark,
    required this.onThemeToggle,
    required this.masterAlarm,
    required this.barcaAlarm,
    required this.blastersAlarm,
    required this.onMasterChanged,
    required this.onBarcaChanged,
    required this.onBlastersChanged,
    required this.onTestAlarm,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        const Text(
          'SETTINGS',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          'Manage your match reminders',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 28),

        SettingsTile(
          icon: Icons.alarm_rounded,
          title: 'Master alarm',
          subtitle: 'Enable or disable the shared alarm system',
          value: masterAlarm,
          onChanged: onMasterChanged,
        ),
        const SizedBox(height: 12),
        SettingsTile(
          icon: Icons.shield_rounded,
          title: 'Barcelona alarm',
          subtitle: 'FC Barcelona match reminders',
          value: barcaAlarm,
          onChanged: onBarcaChanged,
          color: barcaBlue,
        ),
        const SizedBox(height: 12),
        SettingsTile(
          icon: Icons.sports_soccer_rounded,
          title: 'Kerala Blasters alarm',
          subtitle: 'Kerala Blasters match reminders',
          value: blastersAlarm,
          onChanged: onBlastersChanged,
          color: blastersYellow,
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Row(
            children: [
              Icon(Icons.timer_outlined, color: barcaRed, size: 25),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alarm timing',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '5 minutes before kickoff',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text('05:00', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onTestAlarm,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('TEST ALARM (RINGS IN 1 MINUTE)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: barcaRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),
        const Text(
          'APPEARANCE',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        SettingsTile(
          icon: isDark ? Icons.dark_mode : Icons.light_mode,
          title: 'Dark theme',
          subtitle: 'Switch between dark and light appearance',
          value: isDark,
          onChanged: (_) => onThemeToggle(),
        ),

        const SizedBox(height: 28),
        const Center(
          child: Text(
            'MATCH ALARM  •  VERSION 1.0',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.color = barcaRed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
