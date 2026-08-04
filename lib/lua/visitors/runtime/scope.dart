import 'dart:math';
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';

class Scope {
  /// Entries of all lua object variables. id -> lua object.
  final Map<String, LuaObject> vars = {};

  /// Optional parent. See [findVar].
  /// Can be changed when closures need to point back
  /// to the state of the scope before the closure.
  Scope? parent;

  /// The object context bound to this scope.
  final LuaObject? context;

  /// What level this scope is.
  final int depth;

  /// Returns [true] if [context] is not null.
  /// Otherwise returns [false].
  bool get hasContext => context != null;

  static final Random _rand = Random();

  /// Can be used to generate a random variable id.
  static String randId() {
    final a = _rand.nextInt(100);
    final b = _rand.nextInt(100);
    final c = _rand.nextInt(100);
    return '$a$b$c';
  }

  /// Generic constructor sets depth to [parent]'s depth + 1.
  Scope({this.parent, this.context}) : depth = (parent?.depth ?? 0) + 1;

  /// Print the variable entries in this scope.
  void dump() {
    for (final kv in vars.entries) {
      print('${kv.key} -> ${kv.value.toString()}');
    }
  }

  /// Define a variable [id] with [value].
  /// If the [value] is a [LuaObject] then its
  /// contents are copied. If a [value] is a lua function
  /// given by [LuaObject.isFunc], then a [FuncExpr] definition
  /// must be present on that object. Otherwise an exception is thrown.
  LuaObject defVar(String id, Object? value) {
    final LuaObject luaObject;
    if (value is LuaObject) {
      if (value.skipSemanitcs) {
        luaObject = value.toRef();
      } else if (value.isFunc) {
        final closure = value.value as Function;
        final def = value.funcDef;
        if (def == null) {
          throw '''Internal error: programmer forgot to use LuaFuncBuilder. '''
              '''Please report this error!.''';
        }
        luaObject = LuaObject.func(id, def, closure);
      } else {
        luaObject = value;
      }
    } else /* not LuaObject */ {
      luaObject = LuaObject.variable(id, value);
    }
    vars[id] = luaObject;
    return luaObject;
  }

  /// Tries to find the variable by [id],
  /// If no variable is found in this scope, it
  /// searches [parent]. This continues until the
  /// variable of the same [id] is found or returns [null].
  LuaObject? findVar(String id) {
    Scope? next = this;
    while (next != null) {
      if (next.vars.containsKey(id)) {
        return next.vars[id]!;
      }

      next = next.parent;
    }

    // Not found
    return null;
  }

  /// Find the hidden variable "arg" if the function
  /// parameter list includes the special identifier "...".
  List<LuaObject> findVarArgs() {
    final arg = findVar('arg');
    return arg?.fields?.values.nonNulls.toList() ?? [];
  }
}
