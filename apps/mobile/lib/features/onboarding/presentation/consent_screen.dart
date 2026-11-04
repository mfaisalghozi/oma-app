import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M05',
      title: "Consent",
      ticket: 'ONB-FE-05',
    );
  }
}
