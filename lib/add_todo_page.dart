import 'package:flutter/material.dart';

class AddTodoPage extends StatefulWidget {
  final Function(String) onAddTask;

  const AddTodoPage({super.key, required this.onAddTask});

  @override
  State<AddTodoPage> createState() => _AddTodoPageState();
}

class _AddTodoPageState extends State<AddTodoPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tambah To-Do'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Masukkan tugas baru',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  widget.onAddTask(_controller.text);
                  _controller.clear();
                  // Kembali ke home atau tetap di halaman ini
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tugas ditambahkan!')),
                  );
                }
              },
              child: const Text('Tambah'),
            ),
          ],
        ),
      ),
    );
  }
}