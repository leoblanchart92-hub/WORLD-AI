import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Historique des principales améliorations de WORLD-AI.
class WhatsNewPage extends StatelessWidget {
  const WhatsNewPage({super.key});

  static const List<_ReleaseNotes> _releases = [
    _ReleaseNotes(
      version: '2.1.0',
      title: 'Icône à côté de tes messages',
      icon: Icons.person_pin_rounded,
      changes: [
        'Quand tu es connecté, ton initiale s’affiche à droite de chacun de tes messages.',
        'Si tu es en mode invité, aucun icône n’apparaît et la discussion reste identique.',
      ],
    ),
    _ReleaseNotes(
      version: '2.0.0',
      title: 'Ton compte WORLD-AI',
      icon: Icons.person_rounded,
      changes: [
        'Crée un compte avec ton adresse e-mail et un mot de passe : tu restes connecté d’une session à l’autre.',
        'Le compte se gère depuis le menu latéral : connexion, profil, déconnexion.',
        'Le mot de passe est haché côté serveur et la session vit sur ton appareil ; aucune clé n’est stockée dans l’application.',
        'La discussion reste utilisable sans compte, comme avant.',
      ],
    ),
    _ReleaseNotes(
      version: '1.9.2',
      title: 'Choisir l’IA en deux touches',
      icon: Icons.tune_rounded,
      changes: [
        'La pastille d’IA ouvre une fenêtre de sélection : le bouton Groq, puis ses versions.',
        'Un retour ramène au choix du fournisseur sans quitter la fenêtre.',
      ],
    ),
    _ReleaseNotes(
      version: '1.9.1',
      title: 'Trois IA Groq au choix',
      icon: Icons.swap_horiz_rounded,
      changes: [
        'Toutes les IA Groq qui répondent en français sont maintenant disponibles : GPT-OSS 120B, GPT-OSS 20B et Qwen3 27B.',
        'Touche la pastille au-dessus du clavier pour changer d’IA ; le choix est mémorisé.',
        'Chacune est réglée pour répondre en français, quel que soit le modèle choisi.',
      ],
    ),
    _ReleaseNotes(
      version: '1.9.0',
      title: 'L’IA répond vraiment',
      icon: Icons.auto_awesome_rounded,
      changes: [
        'Les messages envoyés dans la discussion reçoivent désormais une réponse de l’IA Groq.',
        'Aucune clé n’est stockée dans l’application : un relais WORLD-AI la garde côté serveur.',
        'Aucune limite de messages : la discussion reste ouverte aussi longtemps que tu veux.',
      ],
    ),
    _ReleaseNotes(
      version: '1.8.1',
      title: 'Six icônes au choix',
      icon: Icons.apps_rounded,
      changes: [
        'Un bouton dans les paramètres ouvre une fenêtre pour choisir l’icône de l’application parmi six visuels WORLD-AI.',
        'L’icône choisie est appliquée sur l’écran d’accueil Android et mémorisée sur l’appareil.',
      ],
    ),
    _ReleaseNotes(
      version: '1.6.4',
      title: 'Nouvelle icône WORLD-AI',
      icon: Icons.image_outlined,
      changes: [
        'L’icône de l’application a été remplacée par le nouveau visuel WORLD-AI.',
      ],
    ),
    _ReleaseNotes(
      version: '1.6.3',
      title: 'Sélecteur d’IA en préparation',
      icon: Icons.auto_awesome_outlined,
      changes: [
        'Un aperçu du choix de l’intelligence artificielle apparaît au-dessus de la barre de discussion.',
        'La sélection sera disponible dans une prochaine mise à jour.',
      ],
    ),
    _ReleaseNotes(
      version: '1.6.2',
      title: 'Les nouveautés à portée de main',
      icon: Icons.auto_awesome_rounded,
      changes: [
        'Un bouton Nouveauté est accessible depuis la discussion et les paramètres.',
        'Retrouve dans cette page les principales améliorations de l’application, version par version.',
      ],
    ),
    _ReleaseNotes(
      version: '1.6.0',
      title: 'Une discussion plus simple',
      icon: Icons.forum_rounded,
      changes: [
        'Nouvel écran Discussion avec une barre de saisie et les messages de la session.',
        'Menu latéral simplifié, avec les mises à jour et les paramètres regroupés en bas.',
      ],
    ),
    _ReleaseNotes(
      version: '1.5.0',
      title: 'La discussion devient l’accueil',
      icon: Icons.chat_bubble_outline_rounded,
      changes: [
        'Nouvel écran de discussion avec une zone de saisie et un fil de messages pour la session.',
        'Les paramètres de vérification des mises à jour sont conservés sur l’appareil.',
      ],
    ),
    _ReleaseNotes(
      version: '1.4.0',
      title: 'Nouvelle interface et suivi des mises à jour',
      icon: Icons.tune_rounded,
      changes: [
        'Navigation organisée dans un menu latéral.',
        'Téléchargement des mises à jour avec progression et possibilité de reprendre.',
      ],
    ),
    _ReleaseNotes(
      version: '1.3.0',
      title: 'Mise à jour de test',
      icon: Icons.rocket_launch_rounded,
      changes: [
        'Version de validation du système de mise à jour automatique depuis une installation existante.',
      ],
    ),
    _ReleaseNotes(
      version: '1.2.0',
      title: 'Mises à jour sans réinstallation',
      icon: Icons.verified_user_outlined,
      changes: [
        'Signature stable des APK pour installer les prochaines versions par-dessus l’application existante.',
        'Les données de l’application sont conservées lors d’une mise à jour.',
      ],
    ),
    _ReleaseNotes(
      version: '1.1.0',
      title: 'Mises à jour automatiques',
      icon: Icons.system_update_alt_rounded,
      changes: [
        'Vérification des nouvelles versions depuis GitHub, au démarrage ou manuellement.',
        'Téléchargement avec progression et installation directe sur Android.',
      ],
    ),
    _ReleaseNotes(
      version: '1.0.0',
      title: 'Première version',
      icon: Icons.auto_awesome_rounded,
      changes: ['Première version de WORLD-AI pour Android.'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveauté')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const Text(
            'Retrouve ici les principales améliorations de l’application.',
            style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.muted),
          ),
          const SizedBox(height: 20),
          for (final release in _releases) ...[
            _ReleaseCard(release: release),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ReleaseNotes {
  const _ReleaseNotes({
    required this.version,
    required this.title,
    required this.icon,
    required this.changes,
  });

  final String version;
  final String title;
  final IconData icon;
  final List<String> changes;
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release});

  final _ReleaseNotes release;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.seed.withAlpha(35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(release.icon, size: 20, color: AppTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      release.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Version ${release.version}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final change in release.changes)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 6, color: AppTheme.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      change,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppTheme.textSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
