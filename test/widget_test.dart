import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_todo/main.dart';

void main() {
  testWidgets('显示待办清单', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('我的待办'), findsOneWidget);
    expect(find.text('买菜'), findsOneWidget);
    expect(find.text('写代码'), findsOneWidget);
    expect(find.text('跑步'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
  });
}
