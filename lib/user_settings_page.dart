import 'package:flutter/material.dart';

class UserSettingsPage extends StatelessWidget {
  const UserSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan User'),
      ),
      body: const Center(
        child: Text('Halaman Pengaturan User'),
      ),
    );
  }
}