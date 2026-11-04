import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M11',
      title: "Don't miss a match",
      ticket: 'ONB-FE-10',
    );
  }
}
