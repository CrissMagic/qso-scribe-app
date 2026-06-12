import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qso_scribe_app/src/ui/qso_scribe_app.dart';

void main() {
  testWidgets('shows first-run setup screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: QsoScribeApp()));
    await tester.pumpAndSettle();

    expect(find.text('Initial Setup'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Real-time streaming'), findsOneWidget);
  });
}
