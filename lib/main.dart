// lib/main.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

const String serverIp = '127.0.0.1'; // 윈도우에서 실행 중이므로 localhost로 설정

void main() {
  runApp(const MyApp());
}

// -------------------------------------------------------------
// 새로운 MyApp 클래스 추가 (앱의 최상단 위젯)
// -------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Table Order App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const TableOrderApp(),
    );
  }
}

// -------------------------------------------------------------
// 1. 서버에서 가져올 데이터의 형태(모델) 정의하기
// -------------------------------------------------------------
class Category {
  final int id;
  final String name;

  Category({required this.id, required this.name});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
    );
  }
}

class MenuItem {
  final int id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isSoldOut;

  MenuItem({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.isSoldOut,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      price: (json['price'] as num).toDouble(),
      imageUrl: json['imageUrl'],
      isSoldOut: json['isSoldOut'] ?? false,
    );
  }
}

// -------------------------------------------------------------
// 2. 주문 정보를 담을 데이터 모델 (장바구니)
// -------------------------------------------------------------
class OrderItemRequest {
  final int menuItemId;
  int quantity;

  OrderItemRequest({required this.menuItemId, required this.quantity});

  Map<String, dynamic> toJson() {
    return {
      'menuItemId': menuItemId,
      'quantity': quantity,
    };
  }
}

class OrderRequestDto {
  final int tableNumber;
  final List<OrderItemRequest> orderItems;

  OrderRequestDto({required this.tableNumber, required this.orderItems});

  Map<String, dynamic> toJson() {
    return {
      'tableNumber': tableNumber,
      'orderItems': orderItems.map((item) => item.toJson()).toList(),
    };
  }
}

// -------------------------------------------------------------
// 3. 메인 어플리케이션 위젯 (상태를 관리하는 StatefulWidget)
// -------------------------------------------------------------
class TableOrderApp extends StatefulWidget {
  const TableOrderApp({super.key});

  @override
  State<TableOrderApp> createState() => _TableOrderAppState();
}

class _TableOrderAppState extends State<TableOrderApp> {
  final int tableNumber = 3; // 👉 임시 테이블 번호 (테스트용)

  List<Category> categories = [];
  List<MenuItem> menuItems = [];
  int? selectedCategoryId;
  bool isLoading = true;

  final Map<int, MenuItem> _allMenuItems = {};
  final Map<int, OrderItemRequest> _cart = {};

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await http.get(Uri.parse('http://$serverIp:8080/api/categories'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          categories = data.map((json) => Category.fromJson(json)).toList();
          if (categories.isNotEmpty) {
            selectedCategoryId = categories.first.id;
            _fetchMenuItems(selectedCategoryId!);
          }
        });
      } else {
        throw Exception('Failed to load categories');
      }
    } catch (e) {
      print('카테고리 로딩 실패: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _fetchMenuItems(int categoryId) async {
    setState(() {
      isLoading = true;
    });
    try {
      final response = await http.get(Uri.parse('http://$serverIp:8080/api/categories/$categoryId/menu-items'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        final fetchedItems = data.map((json) => MenuItem.fromJson(json)).toList();

        setState(() {
          menuItems = fetchedItems;
          for (var item in fetchedItems) {
            _allMenuItems[item.id] = item;
          }
        });
      } else {
        throw Exception('Failed to load menu items');
      }
    } catch (e) {
      print('메뉴 로딩 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _placeOrder() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장바구니가 비어있습니다. 메뉴를 담아주세요.')),
      );
      return;
    }

    final orderItems = _cart.values.toList();
    final orderDto = OrderRequestDto(
      tableNumber: tableNumber,
      orderItems: orderItems,
    );


    try {
      final response = await http.post(
        Uri.parse('http://$serverIp:8080/api/orders/'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(orderDto.toJson()),
      );


      if (response.statusCode == 200 || response.statusCode == 201) {
        _cart.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주문이 성공적으로 접수되었습니다!')),
        );
        setState(() {});
      } else if (response.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증이 필요합니다. 로그인 후 다시 시도하세요.')),
        );
      } else if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('접근 권한이 없습니다.')),
        );
      } else {
        final responseBody = response.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주문 실패 (${response.statusCode}): $responseBody')),
        );
      }
    } catch (e) {
      print('주문 전송 중 예외 발생: $e');
      if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버에 연결할 수 없습니다. 서버가 실행 중인지 확인하세요.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('네트워크 오류: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalAmount = _cart.values.fold(0.0, (sum, item) {
      final menuItem = _allMenuItems[item.menuItemId];
      return sum + (menuItem?.price ?? 0.0) * item.quantity;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('테이블 오더'),
      ),
      body: Row(
        children: [
          // 왼쪽: 카테고리 목록
          SizedBox(
            width: 150,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                return ListTile(
                  title: Text(category.name),
                  selected: selectedCategoryId == category.id,
                  onTap: () {
                    setState(() {
                      selectedCategoryId = category.id;
                      _fetchMenuItems(selectedCategoryId!);
                    });
                  },
                );
              },
            ),
          ),
          // 가운데: 메뉴 목록
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: menuItems.length,
              padding: const EdgeInsets.all(10),
              itemBuilder: (context, index) {
                final menuItem = menuItems[index];
                return InkWell(
                  onTap: menuItem.isSoldOut
                      ? null
                      : () {
                    showDialog(
                      context: context,
                      builder: (BuildContext dialogContext) {
                        return AddMenuItemModal(
                          menuItem: menuItem,
                          onAdd: (quantity) {
                            if (quantity > 0) {
                              setState(() {
                                if (_cart.containsKey(menuItem.id)) {
                                  _cart[menuItem.id]!.quantity += quantity;
                                } else {
                                  _cart[menuItem.id] = OrderItemRequest(
                                    menuItemId: menuItem.id,
                                    quantity: quantity,
                                  );
                                }
                              });
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text('${menuItem.name} ${quantity}개를 담았습니다.'),
                                  duration: const Duration(milliseconds: 1000),
                                ),
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Image.network(
                            menuItem.imageUrl ?? 'https://via.placeholder.com/150',
                            fit: BoxFit.cover,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                menuItem.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('${menuItem.price.toStringAsFixed(0)}원'),
                              Text(
                                menuItem.description ?? '',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 오른쪽: 장바구니 목록과 총액
          SizedBox(
            width: 250,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('주문 목록', style: Theme.of(context).textTheme.headlineSmall),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart.values.elementAt(index);
                      final menuItem = _allMenuItems[item.menuItemId];

                      if (menuItem == null) {
                        return const SizedBox();
                      }

                      return ListTile(
                        title: Text(menuItem.name),
                        subtitle: Text('${(menuItem.price * item.quantity).toStringAsFixed(0)}원'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: () {
                                setState(() {
                                  if (item.quantity > 1) {
                                    item.quantity--;
                                  } else {
                                    _cart.remove(item.menuItemId);
                                  }
                                });
                              },
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                setState(() {
                                  item.quantity++;
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // 총액과 주문 버튼
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.grey[200],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('총 결제 금액', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text('${totalAmount.toStringAsFixed(0)}원', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _cart.isEmpty ? null : _placeOrder,
                        child: const Text('주문하기'),
                      ),
                    ],
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


// -------------------------------------------------------------
// 6. 모달 위젯
// -------------------------------------------------------------
class AddMenuItemModal extends StatefulWidget {
  final MenuItem menuItem;
  final Function(int) onAdd;

  const AddMenuItemModal({
    super.key,
    required this.menuItem,
    required this.onAdd,
  });

  @override
  State<AddMenuItemModal> createState() => _AddMenuItemModalState();
}

class _AddMenuItemModalState extends State<AddMenuItemModal> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    double totalPrice = widget.menuItem.price * _quantity;

    return AlertDialog(
      title: Text(widget.menuItem.name),
      contentPadding: const EdgeInsets.all(20),
      content: SizedBox(
        width: 400, // 고정 너비
        height: 500, // 고정 높이
        child: Column(
          children: [
            // 이미지 영역 (고정 크기)
            Container(
              width: 350,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.menuItem.imageUrl ?? 'https://via.placeholder.com/350x250',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.image_not_supported,
                            size: 50,
                            color: Colors.grey),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 설명 영역 (고정 높이, 스크롤 가능)
            Container(
              height: 80,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.menuItem.description ?? '설명 없음',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 가격 표시
            Text(
              '가격: ${totalPrice.toStringAsFixed(0)}원',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),

            const SizedBox(height: 16),

            // 수량 선택
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle, size: 30),
                  onPressed: _quantity > 1 ? () {
                    setState(() {
                      _quantity--;
                    });
                  } : null,
                ),
                Container(
                  width: 80,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, size: 30),
                  onPressed: () {
                    setState(() {
                      _quantity++;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onAdd(_quantity);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('장바구니에 담기'),
        ),
      ],
    );
  }
}