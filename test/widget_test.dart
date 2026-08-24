// Widget tests for Bus Time Saver.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:bus_time_saver/main.dart';

void main() {
  testWidgets('BusTimeSaverApp renders without crashing',
      (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const BusTimeSaverApp());

    // The app should display the home screen title.
    expect(find.text('Bus Time Saver'), findsOneWidget);
  });
}
