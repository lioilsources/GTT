import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/main.dart';

void main() {
  testWidgets('shows the loading screen first', (tester) async {
    await tester.pumpWidget(const MetropoleApp());
    await tester.pump();
    expect(find.textContaining('New York'), findsOneWidget);
  });
}
