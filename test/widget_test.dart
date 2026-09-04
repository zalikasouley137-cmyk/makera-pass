import 'package:flutter_test/flutter_test.dart';
import 'package:makera_agent_pass/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MakeraAgentApp(hasSession: false));
    expect(find.byType(MakeraAgentApp), findsOneWidget);
  });
}
