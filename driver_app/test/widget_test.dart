import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_tracker/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const FleetTrackerApp());
    expect(find.text('Fleet Tracker'), findsOneWidget);
  });
}
