import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/oma_theme.dart';
import '../features/auth/application/session_controller.dart';
import '../features/device/application/device_registrar.dart';
import 'router.dart';

class OmaApp extends ConsumerWidget {
  const OmaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(sessionControllerProvider, (prev, next) {
      if (next.value is SignedIn && prev?.value is! SignedIn) {
        unawaited(ref.read(deviceRegistrarProvider).retryPending());
      }
    });
    return MaterialApp.router(
      title: 'OMA',
      debugShowCheckedModeBanner: false,
      theme: OmaTheme.lagoon(),
      darkTheme: OmaTheme.deepSea(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
