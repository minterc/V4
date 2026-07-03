import 'dart:math' as math;
import '../models/symbol_model.dart';
import 'indicator_engine.dart';

/// Результат выполнения скрипта — что бот должен сделать
enum BotSignal { none, buy, sell, closeLong, closeShort, openLong, openShort }

class ScriptResult {
  final BotSignal signal;
  final double? qty; // в USDT
  final double? stopLoss; // в % от цены или абсолютная цена
  final bool stopLossIsPercent;
  final double? takeProfit;
  final bool takeProfitIsPercent;
  final int leverage;
  final String? comment;
  final List<String> logs; // для отладки

  ScriptResult({
    this.signal = BotSignal.none,
    this.qty,
    this.stopLoss,
    this.stopLossIsPercent = true,
    this.takeProfit,
    this.takeProfitIsPercent = true,
    this.leverage = 1,
    this.comment,
    this.logs = const [],
  });
}

/// Ошибка в скрипте пользователя
class ScriptError {
  final String message;
  final int? line;
  ScriptError(this.message, {this.line});
  @override
  String toString() => line != null ? 'Строка $line: $message' : message;
}

/// Интерпретатор Pine Script-подобного языка.
/// Поддерживает основное подмножество Pine Script v5:
/// - strategy(), strategy.entry(), strategy.close(), strategy.exit()
/// - ta.rsi(), ta.sma(), ta.ema(), ta.macd(), ta.stoch(), ta.bb()
/// - ta.crossover(), ta.crossunder()
/// - if/else, переменные, арифметика, сравнения, and/or/not
/// - Встроенные переменные: close, open, high, low, volume, bar_index
class PineScriptInterpreter {
  final List<Candle> candles;
  final double currentPrice;
  final bool hasOpenPosition;

  PineScriptInterpreter({
    required this.candles,
    required this.currentPrice,
    this.hasOpenPosition = false,
  });

  // Контекст переменных
  final Map<String, dynamic> _vars = {};
  final List<String> _logs = [];
  BotSignal _signal = BotSignal.none;
  double? _qty;
  double? _sl;
  bool _slIsPercent = true;
  double? _tp;
  bool _tpIsPercent = true;
  int _leverage = 1;
  String? _comment;

  /// Выполнить скрипт и вернуть сигнал
  ScriptResult execute(String script) {
    try {
      _initBuiltins();
      final lines = _preprocess(script);
      _executeLines(lines, 0, lines.length);
      return ScriptResult(
        signal: _signal,
        qty: _qty,
        stopLoss: _sl,
        stopLossIsPercent: _slIsPercent,
        takeProfit: _tp,
        takeProfitIsPercent: _tpIsPercent,
        leverage: _leverage,
        comment: _comment,
        logs: List.from(_logs),
      );
    } on ScriptError catch (e) {
      return ScriptResult(logs: ['❌ Ошибка: $e']);
    } catch (e) {
      return ScriptResult(logs: ['❌ Неожиданная ошибка: $e']);
    }
  }

  void _initBuiltins() {
    final ie = IndicatorEngine(candles);

    // Встроенные переменные (как в Pine Script)
    _vars['close'] = ie.close;
    _vars['open'] = ie.open;
    _vars['high'] = ie.high;
    _vars['low'] = ie.low;
    _vars['volume'] = ie.volume;
    _vars['bar_index'] = candles.length - 1;
    _vars['true'] = true;
    _vars['false'] = false;
    _vars['na'] = double.nan;

    // Направления для strategy.entry
    _vars['strategy.long'] = 'long';
    _vars['strategy.short'] = 'short';

    // Функции ta.*
    _vars['__fn_ta.rsi'] = (List args) {
      final src = _resolveList(args[0], ie);
      final period = (args[1] as num).toInt();
      return ie.rsi(src, period);
    };

    _vars['__fn_ta.sma'] = (List args) {
      final src = _resolveList(args[0], ie);
      final period = (args[1] as num).toInt();
      return ie.sma(src, period);
    };

    _vars['__fn_ta.ema'] = (List args) {
      final src = _resolveList(args[0], ie);
      final period = (args[1] as num).toInt();
      return ie.ema(src, period);
    };

    _vars['__fn_ta.macd'] = (List args) {
      final src = _resolveList(args[0], ie);
      final fast = (args[1] as num).toInt();
      final slow = (args[2] as num).toInt();
      final signal = (args[3] as num).toInt();
      final r = ie.macd(src, fast, slow, signal);
      return [r.macd, r.signal, r.hist]; // деструктурируется через [a, b, c] =
    };

    _vars['__fn_ta.stoch'] = (List args) {
      final k = args.length > 0 ? (args[0] as num).toInt() : 14;
      final smooth = args.length > 1 ? (args[1] as num).toInt() : 3;
      final d = args.length > 2 ? (args[2] as num).toInt() : 3;
      final r = ie.stochastic(k, smooth, d);
      return [r.k, r.d];
    };

    _vars['__fn_ta.bb'] = (List args) {
      final src = _resolveList(args[0], ie);
      final period = (args[1] as num).toInt();
      final mult = args.length > 2 ? (args[2] as num).toDouble() : 2.0;
      final r = ie.bollingerBands(src, period, mult);
      return [r.upper, r.middle, r.lower];
    };

    _vars['__fn_ta.crossover'] = (List args) {
      final a = _toDouble(args[0]);
      final b = _toDouble(args[1]);
      // Упрощённо: проверяем предыдущую свечу если доступны данные
      return a > b; // TODO: реализовать через историю
    };

    _vars['__fn_ta.crossunder'] = (List args) {
      final a = _toDouble(args[0]);
      final b = _toDouble(args[1]);
      return a < b;
    };

    _vars['__fn_ta.highest'] = (List args) {
      final src = _resolveList(args[0], ie);
      final period = (args[1] as num).toInt();
      return ie.highest(src, period);
    };

    _vars['__fn_ta.lowest'] = (List args) {
      final src = _resolveList(args[0], ie);
      final period = (args[1] as num).toInt();
      return ie.lowest(src, period);
    };

    _vars['__fn_math.abs'] = (List args) => (_toDouble(args[0])).abs();
    _vars['__fn_math.max'] = (List args) => args.map(_toDouble).reduce(math.max);
    _vars['__fn_math.min'] = (List args) => args.map(_toDouble).reduce(math.min);
    _vars['__fn_nz'] = (List args) {
      final v = args[0];
      if (v == null || (v is double && v.isNaN)) {
        return args.length > 1 ? args[1] : 0.0;
      }
      return v;
    };

    // strategy.* функции (устанавливают сигнал)
    _vars['__fn_strategy'] = (List args) => null; // декларация стратегии — игнорируем

    _vars['__fn_strategy.entry'] = (List args) {
      final id = args.isNotEmpty ? args[0].toString() : '';
      final dir = args.length > 1 ? args[1].toString() : 'long';
      final namedArgs = args.length > 2 && args[2] is Map ? args[2] as Map : {};
      _qty = namedArgs['qty'] != null ? _toDouble(namedArgs['qty']) : _qty ?? 100;
      _leverage = namedArgs['leverage'] != null ? (namedArgs['leverage'] as num).toInt() : _leverage;
      _comment = id;
      _signal = dir == 'long' ? BotSignal.openLong : BotSignal.openShort;
      _logs.add('📈 strategy.entry("$id", $dir, qty=${_qty?.toStringAsFixed(2)})');
    };

    _vars['__fn_strategy.close'] = (List args) {
      final id = args.isNotEmpty ? args[0].toString() : '';
      _signal = BotSignal.sell;
      _comment = 'close $id';
      _logs.add('📉 strategy.close("$id")');
    };

    _vars['__fn_strategy.exit'] = (List args) {
      final namedArgs = args.length > 1 && args[1] is Map ? args[1] as Map : {};
      if (namedArgs.containsKey('stop')) {
        _sl = _toDouble(namedArgs['stop']);
        _slIsPercent = false;
      }
      if (namedArgs.containsKey('limit')) {
        _tp = _toDouble(namedArgs['limit']);
        _tpIsPercent = false;
      }
      if (namedArgs.containsKey('loss')) {
        _sl = _toDouble(namedArgs['loss']);
        _slIsPercent = true;
      }
      if (namedArgs.containsKey('profit')) {
        _tp = _toDouble(namedArgs['profit']);
        _tpIsPercent = true;
      }
      _logs.add('🛡️ strategy.exit(sl=$_sl, tp=$_tp)');
    };

    _vars['__fn_strategy.risk.max_position_size'] = (List args) => null;

    _vars['__fn_plotshape'] = (List args) => null;
    _vars['__fn_plot'] = (List args) => null;
    _vars['__fn_bgcolor'] = (List args) => null;
    _vars['__fn_alertcondition'] = (List args) => null;
    _vars['__fn_label.new'] = (List args) => null;
  }

  List<double> _resolveList(dynamic src, IndicatorEngine ie) {
    if (src is List<double>) return src;
    if (src == 'close' || src == ie.close) return ie.closes;
    if (src == 'high' || src == ie.high) return ie.highs;
    if (src == 'low' || src == ie.low) return ie.lows;
    if (src == 'volume' || src == ie.volume) return ie.volumes;
    // Если src — скалярное значение (результат вычисления)
    return ie.closes; // fallback
  }

  List<String> _preprocess(String script) {
    return script
        .split('\n')
        .map((line) {
          // Убираем комментарии
          final commentIdx = line.indexOf('//');
          if (commentIdx >= 0) return line.substring(0, commentIdx);
          return line;
        })
        .map((l) => l.trimRight())
        .toList();
  }

  void _executeLines(List<String> lines, int start, int end) {
    int i = start;
    while (i < end) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('//') || line.startsWith('//@')) {
        i++;
        continue;
      }

      // if-блок
      if (line.startsWith('if ')) {
        final condStr = line.substring(3).replaceAll(RegExp(r'\s*$'), '');
        final cond = _evalExpr(condStr);

        // Находим тело if (следующие строки с отступом)
        final ifBody = <String>[];
        final elseBody = <String>[];
        bool inElse = false;
        int j = i + 1;
        while (j < end) {
          final bodyLine = lines[j];
          if (bodyLine.isNotEmpty && !bodyLine.startsWith(' ') && !bodyLine.startsWith('\t')) break;
          final trimmed = bodyLine.trim();
          if (trimmed == 'else') { inElse = true; j++; continue; }
          if (inElse) elseBody.add(bodyLine);
          else ifBody.add(bodyLine);
          j++;
        }

        if (_isTruthy(cond)) {
          _executeLines(ifBody, 0, ifBody.length);
        } else if (elseBody.isNotEmpty) {
          _executeLines(elseBody, 0, elseBody.length);
        }
        i = j;
        continue;
      }

      // Деструктурирующее присваивание [a, b, c] = fn(...)
      final destructMatch = RegExp(r'^\[([^\]]+)\]\s*=\s*(.+)$').firstMatch(line);
      if (destructMatch != null) {
        final names = destructMatch.group(1)!.split(',').map((s) => s.trim()).toList();
        final val = _evalExpr(destructMatch.group(2)!);
        if (val is List) {
          for (int k = 0; k < names.length && k < val.length; k++) {
            _vars[names[k]] = val[k];
          }
        }
        i++;
        continue;
      }

      // Присваивание: var = expr или type var = expr
      final assignMatch = RegExp(r'^(?:var\s+|float\s+|int\s+|bool\s+|string\s+)?(\w[\w.]*)\s*:?=\s*(.+)$').firstMatch(line);
      if (assignMatch != null) {
        final name = assignMatch.group(1)!;
        if (!_isKeyword(name)) {
          _vars[name] = _evalExpr(assignMatch.group(2)!.trim());
          i++;
          continue;
        }
      }

      // Вызов функции без присваивания: strategy.entry(...), strategy.close(...)
      final callMatch = RegExp(r'^([\w.]+)\s*\((.*)$').firstMatch(line);
      if (callMatch != null) {
        _callFunction(callMatch.group(1)!, line);
      }

      i++;
    }
  }

  bool _isKeyword(String name) => ['if', 'else', 'for', 'while', 'true', 'false'].contains(name);

  dynamic _evalExpr(String expr) {
    expr = expr.trim();
    if (expr.isEmpty) return null;

    // Строковые литералы
    if ((expr.startsWith('"') && expr.endsWith('"')) ||
        (expr.startsWith("'") && expr.endsWith("'"))) {
      return expr.substring(1, expr.length - 1);
    }

    // Булевы литералы
    if (expr == 'true') return true;
    if (expr == 'false') return false;
    if (expr == 'na') return double.nan;

    // Числовые литералы
    final num = double.tryParse(expr);
    if (num != null) return num;

    // Оператор not
    if (expr.startsWith('not ')) return !_isTruthy(_evalExpr(expr.substring(4)));

    // Вызов функции
    final fnMatch = RegExp(r'^([\w.]+)\s*\((.*)$').firstMatch(expr);
    if (fnMatch != null) {
      return _callFunction(fnMatch.group(1)!, expr);
    }

    // Переменная
    if (_vars.containsKey(expr)) return _vars[expr];

    // Бинарные операторы (простой парсер)
    return _evalBinary(expr);
  }

  dynamic _evalBinary(String expr) {
    // Разбиваем по операторам (в порядке приоритета)
    for (final op in ['or', 'and', '>=', '<=', '!=', '==', '>', '<', '+', '-', '*', '/']) {
      final idx = _findOperator(expr, op);
      if (idx >= 0) {
        final left = _evalExpr(expr.substring(0, idx).trim());
        final right = _evalExpr(expr.substring(idx + op.length).trim());
        return _applyOp(op, left, right);
      }
    }
    return _vars[expr] ?? double.nan;
  }

  int _findOperator(String expr, String op) {
    int depth = 0;
    for (int i = 0; i < expr.length - op.length + 1; i++) {
      if (expr[i] == '(') depth++;
      else if (expr[i] == ')') depth--;
      else if (depth == 0 && expr.substring(i).startsWith(op)) {
        // Убедиться что это отдельное слово (для or/and)
        if (op == 'or' || op == 'and') {
          final before = i > 0 ? expr[i - 1] : ' ';
          final after = i + op.length < expr.length ? expr[i + op.length] : ' ';
          if (RegExp(r'\w').hasMatch(before) || RegExp(r'\w').hasMatch(after)) continue;
        }
        return i;
      }
    }
    return -1;
  }

  dynamic _applyOp(String op, dynamic left, dynamic right) {
    switch (op) {
      case 'and': return _isTruthy(left) && _isTruthy(right);
      case 'or': return _isTruthy(left) || _isTruthy(right);
      case '>': return _toDouble(left) > _toDouble(right);
      case '<': return _toDouble(left) < _toDouble(right);
      case '>=': return _toDouble(left) >= _toDouble(right);
      case '<=': return _toDouble(left) <= _toDouble(right);
      case '==': return left == right;
      case '!=': return left != right;
      case '+': return _toDouble(left) + _toDouble(right);
      case '-': return _toDouble(left) - _toDouble(right);
      case '*': return _toDouble(left) * _toDouble(right);
      case '/': {
        final r = _toDouble(right);
        return r == 0 ? double.nan : _toDouble(left) / r;
      }
      default: return null;
    }
  }

  dynamic _callFunction(String name, String fullExpr) {
    final argsStr = _extractArgs(fullExpr, name);
    final fn = _vars['__fn_$name'];
    if (fn == null) {
      _logs.add('⚠️ Неизвестная функция: $name');
      return null;
    }
    final args = _parseArgs(argsStr);
    return fn(args);
  }

  String _extractArgs(String expr, String fnName) {
    final start = expr.indexOf('(', fnName.length);
    if (start < 0) return '';
    int depth = 1;
    int i = start + 1;
    while (i < expr.length && depth > 0) {
      if (expr[i] == '(') depth++;
      else if (expr[i] == ')') depth--;
      i++;
    }
    return expr.substring(start + 1, i - 1);
  }

  List<dynamic> _parseArgs(String argsStr) {
    if (argsStr.trim().isEmpty) return [];
    final args = <dynamic>[];
    final namedArgs = <String, dynamic>{};
    final parts = _splitArgs(argsStr);

    for (final part in parts) {
      final named = RegExp(r'^(\w+)\s*=\s*(.+)$').firstMatch(part.trim());
      if (named != null) {
        namedArgs[named.group(1)!] = _evalExpr(named.group(2)!);
      } else {
        args.add(_evalExpr(part.trim()));
      }
    }
    if (namedArgs.isNotEmpty) args.add(namedArgs);
    return args;
  }

  List<String> _splitArgs(String s) {
    final result = <String>[];
    int depth = 0;
    int start = 0;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '(' || s[i] == '[') depth++;
      else if (s[i] == ')' || s[i] == ']') depth--;
      else if (s[i] == ',' && depth == 0) {
        result.add(s.substring(start, i));
        start = i + 1;
      }
    }
    result.add(s.substring(start));
    return result;
  }

  bool _isTruthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is double) return !v.isNaN && v != 0;
    if (v is int) return v != 0;
    return v.toString().isNotEmpty;
  }

  double _toDouble(dynamic v) {
    if (v == null) return double.nan;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is bool) return v ? 1.0 : 0.0;
    return double.tryParse(v.toString()) ?? double.nan;
  }
}
