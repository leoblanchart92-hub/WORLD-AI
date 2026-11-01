import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// Fond d'écran proposé dans les paramètres.
class WallpaperOption {
  const WallpaperOption({required this.id, required this.label, this.asset});

  /// Identifiant enregistré dans les préférences.
  final String id;

  /// Libellé affiché sous la vignette.
  final String label;

  /// Image du fond ; `null` pour le fond sombre d'origine.
  final String? asset;

  bool get isDefault => asset == null;
}

/// Fonds disponibles, le premier étant le fond sombre d'origine.
const List<WallpaperOption> wallpapers = [
  WallpaperOption(id: 'default', label: 'Aucun'),
  WallpaperOption(
    id: 'image4',
    label: 'Fond 1',
    asset: 'assets/wallpapers/image4.png',
  ),
  WallpaperOption(
    id: 'image5',
    label: 'Fond 2',
    asset: 'assets/wallpapers/image5.png',
  ),
  WallpaperOption(
    id: 'image6',
    label: 'Fond 3',
    asset: 'assets/wallpapers/image6.png',
  ),
];

/// Retombe sur le fond sombre si l'identifiant enregistré n'existe plus.
WallpaperOption wallpaperFor(String id) {
  for (final wallpaper in wallpapers) {
    if (wallpaper.id == id) return wallpaper;
  }
  return wallpapers.first;
}

/// Fond d'écran des écrans principaux.
///
/// Un voile sombre dégradé recouvre l'image pour que les textes et les cartes
/// restent lisibles, quelle que soit la luminosité du visuel choisi.
class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final wallpaper = wallpaperFor(id);
    final asset = wallpaper.asset;
    if (asset == null) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(asset, fit: BoxFit.cover, alignment: Alignment.center),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xD908060F), Color(0xB308060F), Color(0xE608060F)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Vignette carrée d'un fond, utilisée par le sélecteur des paramètres.
class WallpaperThumbnail extends StatelessWidget {
  const WallpaperThumbnail({
    super.key,
    required this.wallpaper,
    this.size = 48,
    this.radius = 12,
  });

  final WallpaperOption wallpaper;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final asset = wallpaper.asset;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: asset == null
            ? const ColoredBox(
                color: AppTheme.surfaceHigh,
                child: Icon(
                  Icons.dark_mode_rounded,
                  size: 22,
                  color: AppTheme.muted,
                ),
              )
            : Image.asset(
                asset,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
              ),
      ),
    );
  }
}
