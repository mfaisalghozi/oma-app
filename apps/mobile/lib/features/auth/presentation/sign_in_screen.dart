import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M02',
      title: 'Sign in',
      ticket: 'ONB-FE-03',
    );
  }
}
