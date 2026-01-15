import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class Task {
  String id;
  String title;
  bool isCompleted;

  Task({required this.id, required this.title, this.isCompleted = false});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'To-Do List',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF00008A)),
      ),
      home: const MyHomePage(title: 'To-Do List'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<Task> _tasks = [];
  final TextEditingController _controller = TextEditingController();

  void _addTask(String title) {
    setState(() {
      _tasks.add(Task(
        id: DateTime.now().toString(),
        title: title,
      ));
    });
    _controller.clear();
  }

  void _updateTask(String id, String newTitle) {
    setState(() {
      final task = _tasks.firstWhere((task) => task.id == id);
      task.title = newTitle;
    });
  }

  void _deleteTask(String id) {
    setState(() {
      _tasks.removeWhere((task) => task.id == id);
    });
  }

  void _toggleTask(String id) {
    setState(() {
      final task = _tasks.firstWhere((task) => task.id == id);
      task.isCompleted = !task.isCompleted;
    });
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tambah Tugas'),
          content: TextField(
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Masukkan tugas'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  _addTask(_controller.text);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Tambah'),
            ),
          ],
        );
      },
    );
  }

  void _showEditDialog(Task task) {
    _controller.text = task.title;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Tugas'),
          content: TextField(
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Edit tugas'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  _updateTask(task.id, _controller.text);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    ).then((_) => _controller.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: _tasks.isEmpty
          ? const Center(child: Text('Belum ada tugas'))
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return ListTile(
                  leading: Checkbox(
                    value: task.isCompleted,
                    onChanged: (value) => _toggleTask(task.id),
                  ),
                  title: Text(
                    task.title,
                    style: TextStyle(
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditDialog(task),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteTask(task.id),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Tambah Tugas',
        child: const Icon(Icons.add),
      ),
    );
  }
}
