import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_screen.dart';

class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      screenId: 'M09',
      title: "Add your photos",
      ticket: 'ONB-FE-09',
    );
  }
}
