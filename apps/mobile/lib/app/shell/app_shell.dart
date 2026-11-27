import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/oma_tab_bar.dart';

/// The four top-level tabs. Shared with tests so goldens and production agree.
const appTabDestinations = [
  OmaTabDestination(
    label: 'Discover',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
  ),
  OmaTabDestination(
    label: 'Likes you',
    icon: Icons.favorite_border_rounded,
    selectedIcon: Icons.favorite_rounded,
  ),
  OmaTabDestination(
    label: 'Matches',
    icon: Icons.chat_bubble_outline_rounded,
    selectedIcon: Icons.chat_bubble_rounded,
  ),
  OmaTabDestination(
    label: 'Profile',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

/// Hosts the four top-level tabs. Each branch keeps its own navigator stack.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: OmaTabBar(
        destinations: appTabDestinations,
        currentIndex: navigationShell.currentIndex,
        onSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
