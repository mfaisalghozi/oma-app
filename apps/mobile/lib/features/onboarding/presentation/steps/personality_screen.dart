import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class PersonalityScreen extends StatelessWidget {
  const PersonalityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M08',
      title: "Personality and hobbies",
      ticket: 'ONB-FE-07',
    );
  }
}
