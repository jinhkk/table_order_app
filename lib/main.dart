// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_order_app/table_setup_screen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// 🚨🚨🚨 중요: 이 주소는 반드시 본인 PC의 IP 주소로 설정해야 해! 🚨🚨🚨
// (예: Windows에서 cmd 열고 'ipconfig' 쳐서 나오는 IPv4 주소)
const String serverIp = '172.16.30.5'; // <--- ★★★★★★★ 이 IP를 본인 PC IP로 수정하세요! ★★★★★★★

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final tableNumber = prefs.getInt('tableNumber');
  runApp(MyApp(initialTableNumber: tableNumber));
}

class MyApp extends StatelessWidget {
  final int? initialTableNumber;
  const MyApp({super.key, this.initialTableNumber});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Table Order App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: initialTableNumber == null
          ? const TableSetupScreen()
          : TableOrderApp(tableNumber: initialTableNumber!),
    );
  }
}

// =============================================================
// 데이터 모델 클래스 (Data Models)
// =============================================================
class Category {
  final int id;
  final String name;
  Category({required this.id, required this.name});
  factory Category.fromJson(Map<String, dynamic> json) => Category(id: json['id'], name: json['name']);
}

class MenuItem {
  final int id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isSoldOut;
  MenuItem({required this.id, required this.name, this.description, required this.price, this.imageUrl, required this.isSoldOut});
  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
      id: json['id'], name: json['name'], description: json['description'],
      price: (json['price'] as num).toDouble(), imageUrl: json['imageUrl'], isSoldOut: json['isSoldOut'] ?? false);
}

class AggregatedOrderItem {
  final String menuName;
  final int totalQuantity;
  final double totalPrice;
  AggregatedOrderItem({required this.menuName, required this.totalQuantity, required this.totalPrice});
  factory AggregatedOrderItem.fromJson(Map<String, dynamic> json) => AggregatedOrderItem(
      menuName: json['menuName'], totalQuantity: json['totalQuantity'], totalPrice: (json['totalPrice'] as num).toDouble());
}

class OrderItemRequest {
  final int menuItemId;
  int quantity;
  OrderItemRequest({required this.menuItemId, required this.quantity});
  Map<String, dynamic> toJson() => {'menuItemId': menuItemId, 'quantity': quantity};
}

class OrderRequestDto {
  final int tableNumber;
  final List<OrderItemRequest> orderItems;
  OrderRequestDto({required this.tableNumber, required this.orderItems});
  Map<String, dynamic> toJson() => {'tableNumber': tableNumber, 'orderItems': orderItems.map((item) => item.toJson()).toList()};
}

// =============================================================
// 메인 앱 위젯 (Main App Widget)
// =============================================================
class TableOrderApp extends StatefulWidget {
  final int tableNumber;
  const TableOrderApp({super.key, required this.tableNumber});
  @override
  State<TableOrderApp> createState() => _TableOrderAppState();
}

class _TableOrderAppState extends State<TableOrderApp> {
  late final int tableNumber;
  final _streamController = StreamController.broadcast();

  List<AggregatedOrderItem> _unpaidOrders = [];
  List<Category> categories = [];
  List<MenuItem> menuItems = [];
  int? selectedCategoryId;
  bool isLoading = true;
  bool _isPlacingOrder = false;
  final Map<int, MenuItem> _allMenuItems = {};
  final Map<int, OrderItemRequest> _cart = {};

  @override
  void initState() {
    super.initState();
    tableNumber = widget.tableNumber;
    _initialize();
    _connectWebSocket();
    _listenToWebSocketEvents();
  }

  @override
  void dispose() {
    _streamController.close();
    super.dispose();
  }

  void _connectWebSocket() {
    final channel = WebSocketChannel.connect(Uri.parse('ws://$serverIp:8080/ws/order'));
    print("✅ [WebSocket] 연결 시도... (주소: ws://$serverIp:8080/ws/order)");

    channel.stream.listen((message) {
      _streamController.add(message);
    }, onError: (error) {
      print("❌ [WebSocket] 오류 발생: $error. 5초 후 재연결합니다.");
      Future.delayed(const Duration(seconds: 5), _connectWebSocket);
    }, onDone: () {
      print("ℹ️ [WebSocket] 연결 종료됨. 5초 후 재연결합니다.");
      Future.delayed(const Duration(seconds: 5), _connectWebSocket);
    });
  }

  void _listenToWebSocketEvents() {
    _streamController.stream.listen((message) {
      if (!mounted) return;
      print("✅ [메인 화면] 메시지 수신: $message");
      final data = jsonDecode(message);

      if (data['type'] == 'PAYMENT_COMPLETED' && data['tableNumber'].toString() == tableNumber.toString()) {
        print("🎉 [메인 화면] 내 테이블($tableNumber) 결제 완료! 로컬 주문 목록을 즉시 비웁니다.");
        setState(() {
          _unpaidOrders.clear();
        });
      }
    });
  }

  Future<void> _initialize() async {
    await _fetchCategories();
    await _fetchUnpaidOrders();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await http.get(Uri.parse('http://$serverIp:8080/api/categories'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        if (!mounted) return;
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
      if (mounted) setState(() { isLoading = false; });
    }
  }

  Future<void> _fetchMenuItems(int categoryId) async {
    if (!mounted) return;
    setState(() { isLoading = true; });
    try {
      final response = await http.get(Uri.parse('http://$serverIp:8080/api/categories/$categoryId/menu-items'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        final fetchedItems = data.map((json) => MenuItem.fromJson(json)).toList();
        if (!mounted) return;
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
      if (mounted) setState(() { isLoading = false; });
    }
  }

  Future<void> _fetchUnpaidOrders() async {
    try {
      final response = await http.get(Uri.parse('http://$serverIp:8080/api/orders/table/$tableNumber/unpaid'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _unpaidOrders = (data as List).map((json) => AggregatedOrderItem.fromJson(json)).toList();
            print("🔄 [데이터 갱신] 미결제 주문 목록을 새로고침했습니다. 현재 ${_unpaidOrders.length}건.");
          });
        }
      } else {
        throw Exception('Failed to load unpaid orders with status code: ${response.statusCode}');
      }
    } catch (e) {
      print('미결제 주문 로딩 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _unpaidOrders.clear();
        });
      }
    }
  }

  Future<void> _placeOrder() async {
    if (_cart.isEmpty || _isPlacingOrder) return;
    setState(() { _isPlacingOrder = true; });
    final orderDto = OrderRequestDto(tableNumber: tableNumber, orderItems: _cart.values.toList());
    try {
      final response = await http.post(
        Uri.parse('http://$serverIp:8080/api/orders/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(orderDto.toJson()),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchUnpaidOrders(); // 주문 후에는 최신 주문 내역을 다시 불러온다.
        setState(() {
          _cart.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('주문이 성공적으로 접수되었습니다!')),);
      } else {
        final responseBody = utf8.decode(response.bodyBytes);
        final errorBody = jsonDecode(responseBody);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('주문 실패: ${errorBody['message']}')),);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('주문 실패: ${e.toString()}')),);
    } finally {
      if (mounted) {
        setState(() { _isPlacingOrder = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double orderAmount = _cart.values.fold(0.0, (sum, item) {
      final menuItem = _allMenuItems[item.menuItemId];
      return sum + (menuItem?.price ?? 0.0) * item.quantity;
    });

    return Scaffold(
      appBar: AppBar(title: Text('$tableNumber번 테이블')),
      body: Row(
        children: [
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
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, childAspectRatio: 0.8, crossAxisSpacing: 10, mainAxisSpacing: 10,
              ),
              itemCount: menuItems.length,
              padding: const EdgeInsets.all(10),
              itemBuilder: (context, index) {
                final menuItem = menuItems[index];
                return InkWell(
                  onTap: menuItem.isSoldOut || _isPlacingOrder ? null : () {
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
                                  _cart[menuItem.id] = OrderItemRequest(menuItemId: menuItem.id, quantity: quantity);
                                }
                              });
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text('${menuItem.name} ${quantity}개를 담았습니다.'), duration: const Duration(milliseconds: 1000)),
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
                        Expanded(child: Image.network(menuItem.imageUrl ?? 'https://via.placeholder.com/150', fit: BoxFit.cover)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(menuItem.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('${menuItem.price.toStringAsFixed(0)}원'),
                              Text(menuItem.description ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
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
          SizedBox(
            width: 250,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('주문 목록', style: Theme.of(context).textTheme.headlineSmall),
                ),
                ElevatedButton(
                  onPressed: (_cart.isEmpty && _unpaidOrders.isEmpty) || _isPlacingOrder ? null : () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return OrderSummaryModal(
                          cart: _cart,
                          allMenuItems: _allMenuItems,
                          initialUnpaidOrders: _unpaidOrders,
                          stream: _streamController.stream,
                          tableNumber: tableNumber,
                        );
                      },
                    );
                  },
                  child: const Text('주문 내역 확인'),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart.values.elementAt(index);
                      final menuItem = _allMenuItems[item.menuItemId];
                      if (menuItem == null) return const SizedBox();
                      return ListTile(
                        title: Text(menuItem.name),
                        subtitle: Text('${(menuItem.price * item.quantity).toStringAsFixed(0)}원'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: _isPlacingOrder ? null : () {
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
                              onPressed: _isPlacingOrder ? null : () { setState(() { item.quantity++; }); },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.grey[200],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('주문 금액', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text('${orderAmount.toStringAsFixed(0)}원', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _cart.isEmpty || _isPlacingOrder ? null : _placeOrder,
                        child: _isPlacingOrder
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                            : const Text('주문하기'),
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

// =============================================================
// 모달 위젯 (Modal Widgets)
// =============================================================
class AddMenuItemModal extends StatefulWidget {
  final MenuItem menuItem;
  final Function(int) onAdd;
  const AddMenuItemModal({super.key, required this.menuItem, required this.onAdd});
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
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Image.network(widget.menuItem.imageUrl ?? 'https://via.placeholder.com/200', fit: BoxFit.cover),
        const SizedBox(height: 16),
        Text(widget.menuItem.description ?? '설명 없음'),
        const SizedBox(height: 16),
        Text('가격: ${totalPrice.toStringAsFixed(0)}원'),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.remove), onPressed: () { setState(() { if (_quantity > 1) _quantity--; }); }),
          Text('수량: $_quantity'),
          IconButton(icon: const Icon(Icons.add), onPressed: () { setState(() { _quantity++; }); }),
        ],),
      ],),),
      actions: [
        TextButton(onPressed: () { Navigator.of(context).pop(); }, child: const Text('취소')),
        ElevatedButton(onPressed: () { widget.onAdd(_quantity); Navigator.of(context).pop(); }, child: const Text('장바구니에 담기')),
      ],
    );
  }
}

class OrderSummaryModal extends StatefulWidget {
  final Map<int, OrderItemRequest> cart;
  final Map<int, MenuItem> allMenuItems;
  final List<AggregatedOrderItem> initialUnpaidOrders;
  final Stream<dynamic> stream;
  final int tableNumber;

  const OrderSummaryModal({
    super.key,
    required this.cart,
    required this.allMenuItems,
    required this.initialUnpaidOrders,
    required this.stream,
    required this.tableNumber,
  });

  @override
  State<OrderSummaryModal> createState() => _OrderSummaryModalState();
}

class _OrderSummaryModalState extends State<OrderSummaryModal> {
  late List<AggregatedOrderItem> unpaidOrders;
  StreamSubscription? _streamSubscription;

  @override
  void initState() {
    super.initState();
    unpaidOrders = List.from(widget.initialUnpaidOrders);
    _streamSubscription = widget.stream.listen((message) {
      if (!mounted) return;
      print("✅ [팝업창] 메시지 수신: $message");
      final data = jsonDecode(message);

      if (data['type'] == 'PAYMENT_COMPLETED' && data['tableNumber'].toString() == widget.tableNumber.toString()) {
        print("🎉 [팝업창] 내 테이블 결제 완료! 팝업 내역을 비웁니다.");
        setState(() {
          unpaidOrders.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double unpaidTotal = unpaidOrders.fold(0.0, (sum, item) => sum + item.totalPrice);
    double cartTotal = widget.cart.values.fold(0.0, (sum, item) {
      final menuItem = widget.allMenuItems[item.menuItemId];
      return sum + (menuItem?.price ?? 0.0) * item.quantity;
    });
    double totalPaymentAmount = unpaidTotal + cartTotal;
    List<Widget> listItems = [];

    if (unpaidOrders.isNotEmpty) {
      listItems.add(const ListTile(title: Text("--- 주문 완료된 내역 ---", style: TextStyle(color: Colors.grey))));
      for (var item in unpaidOrders) {
        listItems.add(ListTile(title: Text(item.menuName), subtitle: Text('총 ${item.totalQuantity}개'), trailing: Text('${item.totalPrice.toStringAsFixed(0)}원')));
      }
    }
    if (widget.cart.isNotEmpty) {
      listItems.add(const ListTile(title: Text("--- 장바구니 ---", style: TextStyle(color: Colors.blue))));
      for (var cartItem in widget.cart.values) {
        final menuItem = widget.allMenuItems[cartItem.menuItemId]!;
        listItems.add(ListTile(title: Text(menuItem.name), subtitle: Text('${menuItem.price.toStringAsFixed(0)}원 x ${cartItem.quantity}'), trailing: Text('${(menuItem.price * cartItem.quantity).toStringAsFixed(0)}원', style: const TextStyle(color: Colors.blue))));
      }
    }
    if (listItems.isEmpty) {
      listItems.add(const ListTile(title: Center(child: Text("결제가 완료되었거나 주문 내역이 없습니다."))));
    }

    return AlertDialog(
      title: const Text('현재 주문 내역'),
      content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: ListView(shrinkWrap: true, children: listItems)),
        const Divider(),
        Padding(padding: const EdgeInsets.only(top: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('총 결제 금액', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text('${totalPaymentAmount.toStringAsFixed(0)}원', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],),),
      ],),),
      actions: [ TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')), ],
    );
  }
}