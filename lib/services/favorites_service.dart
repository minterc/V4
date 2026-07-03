import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FavoritesService extends ChangeNotifier {
  static const String _boxName = 'favorites_box';
  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  List<String> get favorites =>
      _box.values.map((e) => e.toString()).toList();

  bool isFavorite(String symbol) => _box.containsKey(symbol);

  Future<void> toggle(String symbol) async {
    if (isFavorite(symbol)) {
      await _box.delete(symbol);
    } else {
      await _box.put(symbol, symbol);
    }
    notifyListeners();
  }

  Future<void> add(String symbol) async {
    await _box.put(symbol, symbol);
    notifyListeners();
  }

  Future<void> remove(String symbol) async {
    await _box.delete(symbol);
    notifyListeners();
  }
}
