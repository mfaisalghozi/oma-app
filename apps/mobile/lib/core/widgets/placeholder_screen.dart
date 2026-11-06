import 'package:flutter/material.dart';

import 'oma_scaffold.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.screenId,
    required this.title,
    this.ticket,
    this.actions = const [],
    super.key,
  });

  final String screenId;
  final String title;
  final String? ticket;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return OmaScaffold(
      showBack: false,
      title: '$screenId · $title',
      subtitle: ticket == null ? null : 'Coming in $ticket.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in actions) ...[a, const SizedBox(height: 12)],
        ],
      ),
    );
  }
}
