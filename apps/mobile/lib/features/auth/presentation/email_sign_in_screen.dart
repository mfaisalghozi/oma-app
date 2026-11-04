import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class EmailSignInScreen extends StatelessWidget {
  const EmailSignInScreen({this.createAccount = false, super.key});

  final bool createAccount;

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      screenId: createAccount ? 'M04b' : 'M04',
      title: createAccount ? 'Create your account' : 'Sign in with email',
      ticket: 'ONB-FE-04',
    );
  }
}
