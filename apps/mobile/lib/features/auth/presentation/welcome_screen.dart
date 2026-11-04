import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M01',
      title: 'Welcome',
      ticket: 'ONB-FE-02',
    );
  }
}
