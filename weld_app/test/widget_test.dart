// Widget test for WeldVision AI app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:weld_app/screens/login_screen.dart';
import 'package:weld_app/providers/user_provider.dart';

void main() {
  testWidgets('Login screen renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // The login screen should render without errors.
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
