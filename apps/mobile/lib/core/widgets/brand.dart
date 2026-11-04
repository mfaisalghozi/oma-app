import 'package:flutter/material.dart';

abstract final class BrandAssets {
  static const appIcon = 'assets/brand/oma-app-icon.png';
  static const wordmark = 'assets/brand/oma-wordmark.png';
}

class OmaAppIcon extends StatelessWidget {
  const OmaAppIcon({this.size = 148, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.23),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0B5554),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.23),
        child: Image.asset(
          BrandAssets.appIcon,
          width: size,
          height: size,
          semanticLabel: 'OMA',
        ),
      ),
    );
  }
}
