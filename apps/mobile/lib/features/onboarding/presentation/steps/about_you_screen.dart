import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class AboutYouScreen extends StatelessWidget {
  const AboutYouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M07',
      title: "About you",
      ticket: 'ONB-FE-07',
    );
  }
}
