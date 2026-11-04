import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

/// M04 Sign in and M04b Create account are tabs on one screen; the route
/// picks the starting tab.
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
