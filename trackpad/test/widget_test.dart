import 'package:flutter_test/flutter_test.dart';
import 'package:trackpad/main.dart';

void main() {
  testWidgets('Trackpad app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TrackpadApp());

    // Verify that the app starts. 
    // Since it behaves differently on Desktop vs Mobile, we just check for basic presence.
    expect(find.byType(TrackpadApp), findsOneWidget);
  });
}
