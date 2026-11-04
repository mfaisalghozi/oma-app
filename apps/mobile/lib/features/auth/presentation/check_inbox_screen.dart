import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class CheckInboxScreen extends StatelessWidget {
  const CheckInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M04c',
      title: 'Check your email',
      ticket: 'ONB-FE-04',
    );
  }
}
