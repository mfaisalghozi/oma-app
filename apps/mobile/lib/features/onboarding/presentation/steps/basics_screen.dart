import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class BasicsScreen extends StatelessWidget {
  const BasicsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M06',
      title: "The basics",
      ticket: 'ONB-FE-07',
    );
  }
}
