import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M11b',
      title: "Setting up your profile",
      ticket: 'ONB-FE-11',
    );
  }
}
