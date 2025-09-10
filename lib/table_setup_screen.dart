// lib/table_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_order_app/main.dart'; // 메인 페이지 import

class TableSetupScreen extends StatefulWidget {
  const TableSetupScreen({super.key});

  @override
  State<TableSetupScreen> createState() => _TableSetupScreenState();
}

class _TableSetupScreenState extends State<TableSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  final String _tableNumberKey = 'tableNumber';

  void _saveTableNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final tableNumber = int.tryParse(_controller.text);

    if (tableNumber != null && tableNumber > 0) {
      await prefs.setInt(_tableNumberKey, tableNumber);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => TableOrderApp(tableNumber: tableNumber)),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효한 테이블 번호를 입력해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('테이블 번호 설정'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '이 태블릿에 할당할 테이블 번호를 입력하세요.',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '테이블 번호',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveTableNumber,
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}