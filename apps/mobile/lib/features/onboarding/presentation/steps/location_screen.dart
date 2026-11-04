import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M10',
      title: "Find people near you",
      ticket: 'ONB-FE-10',
    );
  }
}
