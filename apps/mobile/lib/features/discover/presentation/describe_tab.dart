import 'package:flutter/material.dart';

import '../../../core/theme/oma_colors.dart';

/// M13 input screen. DSB-FE-01 replaces this empty state.
class DescribeTab extends StatelessWidget {
  const DescribeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Describe who you want',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: c.text),
          ),
          const SizedBox(height: 8),
          Text(
            'Type who you are looking for and OMA finds the closest matches near you.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}
