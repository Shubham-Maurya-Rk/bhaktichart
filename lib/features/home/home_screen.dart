import 'package:flutter/material.dart';

import '../onboarding/onboarding_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OnboardingRepository _repository = OnboardingRepository();

  String _name = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _repository.getUser();

    if (!mounted) return;

    setState(() {
      _name = user?.name ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('BhaktiChart')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Hare Krishna 🙏',
              style: Theme.of(context).textTheme.headlineSmall,
            ),

            const SizedBox(height: 10),

            Text('Welcome, $_name'),

            const SizedBox(height: 30),

            const Text('Calendar coming next...'),
          ],
        ),
      ),
    );
  }
}
