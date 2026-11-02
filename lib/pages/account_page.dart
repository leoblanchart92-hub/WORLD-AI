import 'package:flutter/material.dart';

import '../auth/auth_client.dart';
import '../settings_store.dart';
import '../theme/app_theme.dart';

/// Compte WORLD-AI : inscription, connexion et profil.
///
/// La session est enregistrée sur l'appareil pour rester connecté au prochain
/// lancement ; le mot de passe n'y est jamais conservé.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.auth,
    required this.settings,
    required this.session,
    required this.onSessionChanged,
  });

  final AuthService auth;
  final SettingsStore settings;
  final StoredSession? session;
  final ValueChanged<StoredSession?> onSessionChanged;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  StoredSession? _session;
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _email.text = widget.session?.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;

    if (!AuthClient.emailPattern.hasMatch(email)) {
      setState(() => _error = 'Écris une adresse e-mail valide.');
      return;
    }
    if (password.length < AuthClient.minPasswordLength) {
      setState(
        () => _error =
            'Le mot de passe doit faire au moins '
            '${AuthClient.minPasswordLength} caractères.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final session = _register
          ? await widget.auth.register(email, password)
          : await widget.auth.login(email, password);
      await widget.settings.saveSession(session);
      if (!mounted) return;
      setState(() {
        _session = session;
        _busy = false;
        _password.clear();
        _notice = _register
            ? 'Compte créé. Tu es connecté.'
            : 'Content de te revoir.';
      });
      widget.onSessionChanged(session);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Connexion impossible. Réessaie.';
      });
    }
  }

  Future<void> _signOut() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    await widget.auth.logout(session.token);
    await widget.settings.clearSession();
    if (!mounted) return;
    setState(() {
      _session = null;
      _busy = false;
      _password.clear();
      _register = false;
      _notice = 'Tu es déconnecté.';
    });
    widget.onSessionChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_session == null ? 'Compte' : 'Mon compte')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: _session == null ? _signedOut() : _signedIn(_session!),
      ),
    );
  }

  List<Widget> _signedIn(StoredSession session) {
    final initial = session.email.isEmpty
        ? 'W'
        : session.email.substring(0, 1).toUpperCase();
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.email,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Compte WORLD-AI · discussion et choix de l’IA synchronisés',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (_notice != null) ...[
        const SizedBox(height: 14),
        _Banner(text: _notice!, tone: AppTheme.success),
      ],
      const SizedBox(height: 20),
      TextButton.icon(
        onPressed: _busy ? null : _signOut,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text('Se déconnecter'),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF8A9B),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'La déconnexion retire la session de cet appareil. Ton compte et son '
        'adresse restent enregistrés côté serveur : reconnecte-toi quand tu veux.',
        style: TextStyle(fontSize: 11.5, height: 1.5, color: AppTheme.muted),
      ),
    ];
  }

  List<Widget> _signedOut() {
    return [
      const Text(
        'Connecte-toi pour retrouver ton compte WORLD-AI sur cet appareil.',
        style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textSoft),
      ),
      const SizedBox(height: 18),
      _Segmented(
        register: _register,
        onChanged: (value) => setState(() {
          _register = value;
          _error = null;
        }),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const ValueKey('account-email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        cursorColor: AppTheme.accent,
        style: const TextStyle(fontSize: 14, color: AppTheme.text),
        decoration: _fieldDecoration(
          'Adresse e-mail',
          Icons.alternate_email_rounded,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('account-password'),
        controller: _password,
        obscureText: _obscure,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        cursorColor: AppTheme.accent,
        style: const TextStyle(fontSize: 14, color: AppTheme.text),
        decoration: _fieldDecoration(
          'Mot de passe',
          Icons.lock_outline_rounded,
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
            color: AppTheme.muted,
            tooltip: _obscure ? 'Afficher' : 'Masquer',
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _Banner(text: _error!, tone: const Color(0xFFFF8A9B)),
      ],
      if (_notice != null) ...[
        const SizedBox(height: 12),
        _Banner(text: _notice!, tone: AppTheme.success),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _busy ? null : _submit,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: AppTheme.seed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                _register ? 'Créer mon compte' : 'Se connecter',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Ton mot de passe est haché côté serveur : il n’est jamais stocké en '
        'clair, ni dans l’application, ni dans le relais.',
        style: TextStyle(fontSize: 11.5, height: 1.5, color: AppTheme.muted),
      ),
    ];
  }

  InputDecoration _fieldDecoration(
    String hint,
    IconData icon, {
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppTheme.outline),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: AppTheme.muted),
      prefixIcon: Icon(icon, size: 18, color: AppTheme.muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppTheme.surfaceHigh,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppTheme.seed.withAlpha(180), width: 1.4),
      ),
    );
  }
}

/// Bascule entre « Se connecter » et « Créer un compte ».
class _Segmented extends StatelessWidget {
  const _Segmented({required this.register, required this.onChanged});

  final bool register;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          _tab(context, 'Se connecter', false),
          _tab(context, 'Créer un compte', true),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, bool value) {
    final selected = register == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.seed.withAlpha(60) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppTheme.text : AppTheme.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tone.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withAlpha(70)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, height: 1.4, color: tone),
      ),
    );
  }
}
