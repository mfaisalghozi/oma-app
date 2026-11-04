import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/oma_theme.dart';
import 'router.dart';

class OmaApp extends ConsumerWidget {
  const OmaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
