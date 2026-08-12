import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home/home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = false;

  Future<void> _continue() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your name')));

      return;
    }

    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('user_name', name);

    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  void dispose() {
    _nameController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [
              const Spacer(),

              // Logo
              Center(
                child: Container(
                  width: 100,
                  height: 100,

                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,

                    shape: BoxShape.circle,
                  ),

                  child: const Center(
                    child: Text('🙏', style: TextStyle(fontSize: 48)),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Text(
                'Hare Krishna',
                textAlign: TextAlign.center,

                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Welcome to BhaktiChart',
                textAlign: TextAlign.center,

                style: theme.textTheme.titleMedium,
              ),

              const SizedBox(height: 8),

              Text(
                'Track your daily sadhana\n'
                'and grow steadily.',
                textAlign: TextAlign.center,

                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 40),

              Text(
                'What should we call you?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: _nameController,

                textCapitalization: TextCapitalization.words,

                decoration: const InputDecoration(
                  hintText: 'Enter your name',

                  prefixIcon: Icon(Icons.person_outline),
                ),

                onSubmitted: (_) => _continue(),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 54,

                child: FilledButton(
                  onPressed: _isLoading ? null : _continue,

                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'CONTINUE',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const Spacer(),

              Text(
                'Your data stays on your device.',
                textAlign: TextAlign.center,

                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
