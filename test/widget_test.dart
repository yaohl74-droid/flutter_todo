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

  testWidgets('添加非空任务并清空输入框', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField), '学习 Flutter');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.text('学习 Flutter'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(4));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('输入为空时不添加任务', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
  });
}
