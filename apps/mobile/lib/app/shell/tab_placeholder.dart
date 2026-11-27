import 'package:flutter/material.dart';

import '../../core/widgets/oma_scaffold.dart';

/// A top-level tab that has no screen yet.
class TabPlaceholder extends StatelessWidget {
  const TabPlaceholder({
    required this.title,
    this.ticket,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? ticket;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return OmaScaffold(
      showBack: false,
      title: title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ticket != null)
            Text(
              'Coming in $ticket.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ...actions,
        ],
      ),
    );
  }
}
