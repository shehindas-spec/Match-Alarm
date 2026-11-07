import 'package:flutter_test/flutter_test.dart';
import 'package:match_alarm/main.dart';

void main() {
  testWidgets('Match Alarm application loads',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MatchAlarmApp());

    expect(find.text('MATCH ALARM'), findsOneWidget);
    expect(find.text('YOUR TEAMS'), findsOneWidget);
  });
}