import 'package:flutter/material.dart';

class AlarmScreen extends StatelessWidget {
  final String homeTeam;
  final String awayTeam;
  final String kickoffTime;
  final String alarmTime;
  final String alarmMessage;
  final VoidCallback onStop;

  const AlarmScreen({
    super.key,
    this.homeTeam = 'FC Barcelona',
    this.awayTeam = 'Opponent',
    this.kickoffTime = 'Kickoff time unavailable',
    this.alarmTime = 'Alarm time unavailable',
    this.alarmMessage = 'MATCH STARTS IN 5 MINUTES',
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF101522),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.alarm_rounded,
                  color: Color(0xFFFF4444),
                  size: 65,
                ),
                const SizedBox(height: 20),

                const Text(
                  'MATCH ALARM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'MATCH STARTS IN',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  '05:00',
                  style: TextStyle(
                    color: Color(0xFFF5D51D),
                    fontSize: 62,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 35),

                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2638),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _team(homeTeam, const Color(0xFF1546A0)),

                      const Text(
                        'VS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      _team(awayTeam, const Color(0xFFF5D51D)),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                Text(
                  alarmMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 18),

                _timeDetail(Icons.sports_soccer, 'Kickoff', kickoffTime),

                const SizedBox(height: 12),

                _timeDetail(Icons.alarm, 'Alarm time', alarmTime),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  height: 62,
                  child: ElevatedButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text(
                      'STOP ALARM',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB51E36),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'MATCH ALARM • FOOTBALL REMINDER',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeDetail(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white60, size: 17),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _team(String name, Color color) {
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: color,
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
