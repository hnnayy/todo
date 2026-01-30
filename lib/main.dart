import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class Task {
  String id;
  String title;
  bool isCompleted;
  int status;

  Task({required this.id, required this.title, this.isCompleted = false, this.status = 1});
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  void _fetchTasks() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('tasks').get();
      final loadedTasks = snapshot.docs.map((doc) {
        final data = doc.data();
        return Task(
          id: doc.id,
          title: data['title'] ?? '',
          isCompleted: data['isCompleted'] ?? false,
          status: data['status'] ?? 1,
        );
      }).where((task) => task.status == 1).toList();

      setState(() {
        _tasks.clear();
        _tasks.addAll(loadedTasks);
      });
    } catch (e) {
      print("Error fetching tasks: $e");
    }
  }

  void _addTask(String title) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('tasks').add({
        'title': title,
        'isCompleted': false,
        'status': 1,
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _tasks.add(Task(id: doc.id, title: title, status: 1));
      });
    } catch (e) {
      // If Firestore write fails, fallback to local-only add
      setState(() {
        _tasks.add(Task(
          id: DateTime.now().toString(),
          title: title,
          status: 1,
        ));
      });
    }
  }

  void _updateTask(String id, String newTitle) {
    // Optionally update Firestore here too if desired, 
    // but focusing on status/delete per request.
    try {
       FirebaseFirestore.instance.collection('tasks').doc(id).update({'title': newTitle});
    } catch (_) {}

    setState(() {
      final task = _tasks.firstWhere((task) => task.id == id);
      task.title = newTitle;
    });
  }

  void _deleteTask(String id) async {
    try {
      // Soft delete: update status to 2
      await FirebaseFirestore.instance.collection('tasks').doc(id).update({'status': 2});
    } catch (e) {
      print("Error soft deleting task: $e");
    }
    setState(() {
      // Remove from UI since we only show status 1
      _tasks.removeWhere((task) => task.id == id);
    });
  }

  void _deleteAllTasks() async {
    // Soft delete all currently visible tasks
    final batch = FirebaseFirestore.instance.batch();
    for (var task in _tasks) {
      final docRef = FirebaseFirestore.instance.collection('tasks').doc(task.id);
      batch.update(docRef, {'status': 2});
    }
    
    try {
      await batch.commit();
    } catch(e) {
      print("Error batch deleting: $e");
    }

    setState(() {
      _tasks.clear();
    });
  }

  void _toggleTask(String id) {
    final task = _tasks.firstWhere((task) => task.id == id);
    final newState = !task.isCompleted;

    try {
       FirebaseFirestore.instance.collection('tasks').doc(id).update({'isCompleted': newState});
    } catch (_) {}

    setState(() {
      task.isCompleted = newState;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _widgetOptions = <Widget>[
      MyHomePage(
        tasks: _tasks,
        onAddTask: _addTask,
        onUpdateTask: _updateTask,
        onDeleteTask: _deleteTask,
        onToggleTask: _toggleTask,
        onDeleteAllTasks: _deleteAllTasks,
      ),
      const UserSettingsPage(),
    ];

    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }
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
      home: const MainScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.tasks,
    required this.onAddTask,
    required this.onUpdateTask,
    required this.onDeleteTask,
    required this.onToggleTask,
    required this.onDeleteAllTasks,
  });

  final List<Task> tasks;
  final Function(String) onAddTask;
  final Function(String, String) onUpdateTask;
  final Function(String) onDeleteTask;
  final Function(String) onToggleTask;
  final Function() onDeleteAllTasks;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('To-Do List'),
        actions: [
          if (widget.tasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Hapus Semua',
              onPressed: () => _showDeleteAllDialog(context),
            ),
        ],
      ),
      body: widget.tasks.isEmpty
          ? const Center(child: Text('Belum ada tugas'))
          : ListView.builder(
              itemCount: widget.tasks.length,
              itemBuilder: (context, index) {
                final task = widget.tasks[index];
                return ListTile(
                  leading: Checkbox(
                    value: task.isCompleted,
                    onChanged: (value) => widget.onToggleTask(task.id),
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
                        onPressed: () => _showEditDialog(context, task),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => widget.onDeleteTask(task.id),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        tooltip: 'Tambah Tugas',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDeleteAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Semua Tugas'),
          content: const Text('Apakah Anda yakin ingin menghapus semua tugas?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                widget.onDeleteAllTasks();
                Navigator.of(context).pop();
              },
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
  }

  void _showAddDialog(BuildContext context) {
    final TextEditingController _controller = TextEditingController();
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
                  widget.onAddTask(_controller.text);
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

  void _showEditDialog(BuildContext context, Task task) {
    final TextEditingController _controller = TextEditingController(text: task.title);
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
                  widget.onUpdateTask(task.id, _controller.text);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }
}
