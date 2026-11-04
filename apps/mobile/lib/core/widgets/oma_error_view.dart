import 'package:flutter/material.dart';

import '../errors/failure.dart';
import '../theme/oma_colors.dart';
import 'oma_button.dart';

class OmaErrorView extends StatelessWidget {
  const OmaErrorView({
    required this.onRetry,
    this.error,
    this.title,
    this.message,
    super.key,
  });

  final Object? error;
  final String? title;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final offline = error is NetworkFailure;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
            child: Icon(
              offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              color: c.primaryStrong,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title ?? (offline ? "You're offline" : "Something didn't load"),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message ??
                (offline
                    ? 'Check your connection and try again.'
                    : 'Nothing was lost. Please try again.'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: 20),
          OmaButton(label: 'Try again', onPressed: onRetry, expand: false),
        ],
      ),
    );
  }
}
