import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/ui/widgets/status_timeline.dart';

void main() {
  Future<void> pumpTimeline(WidgetTester tester, OrderStatus status) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StatusTimeline(status: status)),
    ),
  );

  /// The icon drawn in the row of the step called [label].
  IconData iconOf(WidgetTester tester, String label) {
    final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
    return tester.widget<Icon>(find.descendant(of: row, matching: find.byType(Icon))).icon!;
  }

  testWidgets('ticks off the steps behind a preparing order and marks where it is', (tester) async {
    await pumpTimeline(tester, OrderStatus.preparing);

    expect(iconOf(tester, 'Placed'), Icons.check_circle);
    expect(iconOf(tester, 'Accepted'), Icons.check_circle);
    expect(iconOf(tester, 'Preparing'), Icons.radio_button_checked);
    expect(iconOf(tester, 'Ready for pickup'), Icons.radio_button_unchecked);
    expect(iconOf(tester, 'On the way'), Icons.radio_button_unchecked);
    expect(iconOf(tester, 'Delivered'), Icons.radio_button_unchecked);
  });

  testWidgets('ticks off every step of a delivered order', (tester) async {
    await pumpTimeline(tester, OrderStatus.delivered);

    expect(find.byIcon(Icons.check_circle), findsNWidgets(6));
  });

  testWidgets('shows a cancelled order as cancelled instead of as steps', (tester) async {
    await pumpTimeline(tester, OrderStatus.cancelled);

    expect(find.text('This order was cancelled'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.text('Placed'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });
}
