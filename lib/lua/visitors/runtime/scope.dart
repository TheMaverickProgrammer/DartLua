import 'dart:math';
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';

class Scope {
  final Map<String, LuaObject> vars = {};
  final Scope? parent;
  final LuaObject? context;
  final int depth;

  bool get hasContext => context != null;

  static final Random _rand = Random();

  static String randId() {
    final a = _rand.nextInt(100);
    final b = _rand.nextInt(100);
    final c = _rand.nextInt(100);
    return '$a$b$c';
  }

  Scope({this.parent, this.context}) : depth = (parent?.depth ?? 0) + 1;

  void dump() {
    for (final kv in vars.entries) {
      print('${kv.key} -> ${kv.value.toString()}');
    }
  }

  LuaObject defVar(String id, Object? value) {
    final LuaObject luaObject;
    if (value is LuaObject) {
      if (value.skipSemanitcs) {
        luaObject = value.toRef();
      } else if (value.isFunc) {
        final closure = value.fieldValueAs<Function>('__call')!;
        final def = value.funcDef;
        if (def == null) {
          throw '''A programmer forgot to use LuaFuncBuilder. '''
              '''Please report this error!.''';
        }
        luaObject = LuaObject.func(id, def, closure);

        // meta method __call is on a special table.
        // therefore we may also have other table fields.
        luaObject.writeFields(value.fields!);
        /*} else if (value.isTable) {
        luaObject = LuaObject.table(id, value.fields);*/
      } else {
        /*luaObject = LuaObject(id);
        luaObject.value = value;*/
        luaObject = value;
      }
    } else /* not LuaObject */ {
      luaObject = LuaObject.variable(id, value);
    }
    vars[id] = luaObject;
    return luaObject;
  }

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

  List<LuaObject> findVarArgs() {
    final arg = findVar('arg');
    return arg?.fields?.values.nonNulls.toList() ?? [];
  }
}
