import 'dart:math' as math;
import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
import 'package:puredartlua/lua/visitors/runtime/scope.dart';
import 'package:puredartlua/lua/visitors/runtime/semantics.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

extension ObjectAsTypeOrNull on Object {
  T? as<T>() => switch (this) {
    final T t => t,
    _ => null,
  };
}

/// The function type to respond to the scope being
/// unwound. When reporting errors. See [RuntimeCallbacks].
typedef TraceCallback = void Function(Set<String>);

/// Custom exception handling if needed.
typedef LuaExceptionCallback = void Function(Object);

/// A configuration class enabling the programmer to
/// define what happens [onErrors], [onWarnings], or
/// [onDiagnostics].
///
/// [consumeTraces] consumes the values from [BaseResults]
/// and then clears the result object.
class RuntimeCallbacks {
  TraceCallback? onErrors;
  TraceCallback? onWarnings;
  TraceCallback? onDiagnostics;

  RuntimeCallbacks({this.onErrors, this.onWarnings, this.onDiagnostics});

  void consumeTraces(BaseResults results) {
    onErrors?.call(results.errors);
    onWarnings?.call(results.warns);
    onDiagnostics?.call(results.infos);
    results.errors.clear();
    results.warns.clear();
    results.infos.clear();
  }
}

/// Given an instance of [Object?], return a [String]
/// value of the best-representing lua type.
/// If [o] is [LuaObject], then calls [LuaObject.luaTypeInfo].
/// If the instance cannot be resolved to a lua type, fallback
/// on [Object.runtimeType]. This is used in error reporting to the user
/// so as not to confuse users if a [o] is a type native to dart.
String debugLuaTypeInfo(Object? o) => switch (o) {
  null => 'nil',
  final num _ => 'number',
  final bool _ => 'boolean',
  final Function _ => 'function',
  final LuaObject lo => lo.luaTypeInfo,
  final Object o => o.runtimeType.toString(),
};

/// The result of processing a lua script can omit
/// errors, warnings, or custom diagnostic info.
/// This results class collects such information at run-time
/// and it is up to the user to decide when to reveal the
/// information to the user.
///
/// You must extend this so that you can add your own
/// diagnostic information or even use it to lift
/// other data from the AST.
abstract class BaseResults {
  final Set<String> errors = {};
  final Set<String> warns = {};
  final Set<String> infos = {};

  void addError(String error) => errors.add(error);
  void addAllErrors(List<String> errors) => this.errors.addAll(errors);
  void addWarning(String warn) => warns.add(warn);
  void addAllWarnings(List<String> warns) => this.warns.addAll(warns);
  void addDiagnostic(String info) => infos.add(info);
  void addAllDiagnostics(List<String> infos) => this.infos.addAll(infos);

  /// Wipes the instance of all collected results for re-use.
  void clear() {
    errors.clear();
    warns.clear();
    infos.clear();
  }
}

/// Normal lua runtime behavior implementation for [ReturnStmt].
///
/// Unwind the callstack on return by throwing a special
/// exception [LuaReturnValueException] with the value to return.
/// This value is unpacked correctly by the try-catch
/// handler in function call statements by design.
mixin ReturnStmtCallStackUnwind on BaseRuntime {
  @override
  Object? visitReturnStmt(ReturnStmt expr) {
    throw LuaReturnValueException(expr.values.visitArgPack(this));
  }
}

/// Special lua runtime behavior suitable for static analysis
/// of branching control flows.
///
/// The value returned by evaluating [ReturnStmt]
/// is resolved as normal except that the callstack
/// does not unwind. The AST walker will continue
/// to march forward to the next statements in the block.
mixin ReturnStmtDoNotUnwind on BaseRuntime {
  @override
  Object? visitReturnStmt(ReturnStmt expr) {
    return expr.values.visitArgPack(this);
  }
}

/// NOTE: Incomplete coroutines. May be removed.
/// Whenever a language construct would move the program's execution
/// out of the normal tree walk, we can refer to this structure and obtain
/// the exact location to resume.
class CoCtrlStruct {
  /// The control structure node in the tree.
  Stmt node;

  /// The counter in the control structure's body if applicable.
  num counter;

  /// The end of the [counter] in the control structure if applicable.
  num end;

  /// The child node offset in the control structure.
  /// Often used with the body of some statement list.
  int stmtIdx;

  /// The iterator function for the control structure if applicable.
  Function? iter;

  /// Constructor. Optional [counter], [end], and [iter]
  /// parameters for different types of control structures.
  /// For example, a for-loop would have a counter but
  /// a while loop would have a condition stored in [node].
  CoCtrlStruct(this.node, {num? counter, num? end, int? stmtIdx, this.iter})
    : counter = counter ?? 0,
      end = end ?? 0,
      stmtIdx = stmtIdx ?? 0;

  /// Makes a new pointer with the data at some point in time.
  CoCtrlStruct copy() => CoCtrlStruct(
    node,
    counter: counter,
    end: end,
    stmtIdx: stmtIdx,
    iter: iter,
  );
}

/// Implements common Lua runtime logic.
/// Extend with mixin [ReturnStmtCallStackUnwind]
/// or [ReturnStmtDoNotUnwind].
///
/// The reason the return statement behavior is omitted is
/// b/c this library can be used to perform static analysis
/// as well. In such cases it's desirable to anaylze all
/// control flows instead of aborting early on `return`.
/// This decision allows the users of this library to choose
/// how to configure their desired runtime.
abstract class BaseRuntime extends Visitor<Object?> {
  final BaseResults results;

  /// The top-most scope.
  /// Note globals are actually written to [globalEnv].
  final Scope global = Scope();

  /// _ENV variable.
  final LuaObject globalEnv = LuaObject.table('_ENV');

  /// Legacy _G variable points to _ENV.
  late final LuaObject globalG;

  /// The current scope.
  late Scope scope = global;

  /// For diagnostics or debugging, what the current
  /// script path is. See [onRequireImpl].
  String? debugPath;

  /// Describes to do when lua processes the `require()` function.
  LuaRequireCallback? onRequireImpl;

  /// Configures _ENV and _ENV._G in the global scope.
  BaseRuntime(this.results) {
    globalG = LuaObject.variable('_G', globalEnv);
    globalEnv.writeFieldFrom(globalG);

    /// Registering tghese so they can be reached from any [Scope.parent].
    global.defVar(globalEnv.id, globalEnv);
    global.defVar(globalG.id, globalG);
  }

  /// For variables, return (row, col) as a virtual identifier stub.
  /// This is useful for debugging.
  String lineTag(Token token) => '_<${token.pos.row + 1},${token.pos.col + 1}>';

  /// Given a [Token], return that token's line information.
  /// This is useful for debugging.
  String lineInfo(Token token) => token.pos.toString();

  /// Given a [Token], construct a lua identifier stub.
  /// If [prefix] is non null, then the stub will have that prefix.
  String tokenId(Token token, {String? prefix}) {
    final id = 'id${lineTag(token)}';
    if (prefix == null) {
      return id;
    }

    return '${prefix}_$id';
  }

  /// Setter for [debugPath].
  void debugSetPath(String? path) => debugPath = path;

  /// Build a meaningful error message from the current
  /// runtime information and original message [err].
  void addError(String err) {
    final msg = switch (debugPath) {
      final String path => '$err\n\t... in "$path".',
      _ => err,
    };

    results.addError(msg);
  }

  /// Build a meaningful warning message from the current
  /// runtime information and original message [warn].
  void addWarning(String warn) {
    final msg = switch (debugPath) {
      final String path => '$warn\n\t... in "$path".',
      _ => warn,
    };

    results.addWarning(msg);
  }

  /// Build a meaningful diagnostic message from the current
  /// runtime information and original message [info].
  void addDiagnostic(String info) {
    final msg = switch (debugPath) {
      final String path => '$info\n\t... in "$path".',
      _ => info,
    };

    results.addDiagnostic(msg);
  }

  /// A reverse linked list implementation where tail
  /// points towards head (the parent chain). Calling this function
  /// adds a new [Scope] node in the linked list as the new tail
  /// and sets [scope] to point to the latest tail node. Every
  /// node points to its [Scope.parent].
  ///
  /// If [parent] is non-null, then the new [Scope.parent]
  /// will point to it.
  void pushScope({LuaObject? context, Scope? parent}) {
    // scope.dump();
    scope = Scope(parent: parent ?? scope, context: context);
    // print('scope depth: ${scope.depth}');
  }

  void restoreScope(Scope next) {
    scope = next;
  }

  /// Shorthand for [scope.context].
  LuaObject? get context => scope.context;

  /// Shorthand for [scope.hasContext].
  bool get hasContext => scope.hasContext;

  /// Defines a local variable in the current [scope] with
  /// lua object [value].
  LuaObject defLocal(LuaObject value) {
    return scope.defVar(value.id, value);
  }

  /// Defines a global variable in the [global] scope with
  /// lua object [value].
  LuaObject defGlobal(LuaObject value) {
    final luaObject = globalEnv.writeFieldFrom(value);
    return global.defVar(value.id, luaObject)..doc = value.doc;
  }

  /// Searches for a variable with the identifier [id]
  /// in the current scope. The implementation details
  /// also searches the parents in order if not found locally
  /// until such an [id] is found.
  ///
  /// If no [id] is found, null is returned signifying no
  /// such variable with that [id] exists.
  LuaObject? findVar(String id) {
    return scope.findVar(id);
  }

  /// First finds [field] inside object "self"
  /// in the current [scope]. If neither can be found,
  /// [or] is returned cast [toLua].
  /// If [or] is not provided, null is returned.
  ///
  /// Otherwise if "self" is found, then
  /// returns the property with name [field]
  /// with the same name as a [LuaObject].
  LuaObject? findOnSelf(String field, {Object? or}) {
    return findVar('self')?.readField(field)?.toLua(field) ?? or?.toLua(field);
  }

  /// Search the current [scope] for the special `...` identifier.
  List<LuaObject>? findVarArgs() {
    return scope.findVarArgs();
  }

  /// Given a callable lua [obj] and a list of [args], configure
  /// a new scope with the provided [args] as parameters based on
  /// the [LuaObject.funcDef] record. Args exceeding the parameter list
  /// will be dropped. Any remaining parameters will be filled by
  /// [LuaObject.nil] values. Any exceptions are caught and tracked
  /// for the trace back later. The scope is popped and any return
  /// result [LuaObject]s are returned as an argpack.
  List<LuaObject> callLuaFunction(
    LuaObject obj, {
    List<Object?> args = const [],
    LuaExceptionCallback? onException,
  }) {
    LuaObject? callable;
    if (obj.isFunc) {
      callable = obj;
    } else if (obj.isCallable) {
      callable = switch (obj.readMetatable('__call')) {
        final LuaObject lo => lo,
        _ => null,
      };
    }

    if (callable == null) {
      final type = obj.luaTypeInfo;
      final varname = obj.id;
      throw 'Attempt to call a $type value "$varname".';
    }

    List<LuaObject> res = [];
    final prevScope = scope;
    pushScope(parent: callable.scope);

    try {
      final defArgs = callable.funcDef!.args;
      final nilCount = defArgs.length - args.length;

      for (int i = 0; i < defArgs.length; i++) {
        final id = defArgs[i].lexeme;
        defLocal(args[i]?.toLua(id) ?? LuaObject.nil(id));
      }

      for (int i = 0; i < nilCount; i++) {
        defLocal(LuaObject.nil(defArgs[args.length + i].lexeme));
      }

      // For the public API utilites,
      // we expect friendly non-null values.
      // Return an empty list if null.
      final temp = callable.call();
      res = switch (temp) {
        final List<LuaObject?> ls => ls.nonNulls.toList(),
        final List<Object?> ls => ls.map((e) => e?.toLuaRet()).nonNulls.toList(),
        final Object o => [o.toLuaRet()],
        null => [],
      };
    } catch (e) {
      if (e is LuaReturnValueException) {
        res = e.argpack;
      } else if (onException != null) {
        onException.call(e);
      } else {
        rethrow;
      }
    } finally {
      restoreScope(prevScope);
    }

    return res;
  }

  /// The starting point of all lua programs.
  /// This will visit every node in the tree.
  /// The default result will be a program which
  /// ran to completion.
  ///
  /// It can be changed to suit other needs.
  @override
  Object? visitAST(AST ast) {
    Object? ret;
    for (final e in ast.stmts) {
      try {
        ret = e.accept(this);
      } catch (e) {
        if (e is LuaReturnValueException) {
          ret = e.argpack;
          break;
        } else {
          addError(e.toString());
        }
      }
    }
    return ret;
  }

  @override
  Object? visitFuncExpr(FuncExpr expr) {
    closure() {
      int start = 0;

      Object? ret;
      final int len = expr.body.length;
      for (int i = start; i < len; i++) {
        final Stmt stmt = expr.body[i];
        try {
          ret = stmt.accept(this);
        } catch (e) {
          if (e is LuaReturnValueException) {
            ret = e.argpack;
            break;
          } else {
            rethrow;
          }
        }
      }
      return ret;
    }

    // Spec reference: https://www.lua.org/manual/5.4/manual.html#3.4.11
    // We need to "build" the function if it's a method on an existing object.
    // This means the first node must be the object when node length is more than one
    // or the function name if the node length is exactly one.
    // We must manually check if the object is not-null in the case that we are adding a field.
    // For example. Given an object `t = {}`, we can define `function t.f() end`, however
    // we cannot define `function t.a.f() end` without the existence of `t.a = {}` beforehand.

    final List<RawExpr> idParts = [...expr.idParts];
    final String id = switch (expr.id.isEmpty) {
      true => '<anonymous fn>',
      false => expr.id,
    };

    final String linePos = lineInfo(expr.token);

    LuaObject luaObj;
    if (idParts.length > 1) {
      // Object methods cannot be local. This is a syntax error that we will prevent
      // here rather than in the parser for simple implementation.
      // TODO: move this into the parser.
      if (expr.local) {
        addError('$linePos Object methods cannot be defined locally.');
        return null;
      }

      // Walk the nodes and create a new method on the object.
      LuaObject? parent;

      // By virtue of entering this branch in the conditionals,
      // we know that idParts.length > 1, therefore, a well-formed
      // function declaration must consist of the form `t0.t1. ... .tn`.
      // In other words, there's a parent object which this method
      // will live inside of as a field.
      String field = '';
      while (idParts.isNotEmpty) {
        field = idParts.removeAt(0).token.lexeme;
        final obj = switch (parent) {
          null => findVar(field),
          final LuaObject p => p.readField(field)?.toLuaRet(),
        };

        if (obj == null) break;
        parent = obj;
      }

      // The very last id part should have been consumed.
      // If there are still parts left, there was a term
      // in the chain that was not defined. This is not alllowed in lua.
      if (idParts.isNotEmpty) {
        if (parent != null) {
          final parentId = parent.id;
          addError('$linePos No such field "$field" in "$parentId".');
        } else {
          // The parser should have prevented this.
          addError(
            '$linePos Impossible grammar not caught by Parser. Please report!',
          );
        }
        return null;
      }

      // If we got here, then we have a parent and an object.
      // If the object is null, it will be created.
      // If the object is not null, it will be overwritten.
      luaObj = LuaObject.func(id, expr, closure, scope);
      parent!.writeField(field, luaObj);
    } else {
      // Case: This is a function, not a "method" on an object.
      luaObj = LuaObject.func(id, expr, closure, scope);

      // Only non-anonymous functions can populate
      // the environment with their name.
      if (idParts.isNotEmpty) {
        if (expr.local) {
          defLocal(luaObj);
        } else {
          defGlobal(luaObj);
        }
      }
    }

    return luaObj;
  }

  /// Visits rhs first and then evaluate lhs.
  @override
  Object? visitAssignStmt(AssignStmt assignStmt) {
    final rhs = assignStmt.rhs.accept(this)?.unpack();
    Object? lhs;

    // Special behavior happens in lua when we update a value
    // in a table by key. In order to avoid triggering __index
    // by visiting the memory access node, we partially inspect
    // it here. We only need enough information to obtain:
    // 1. the table
    // 2. the key
    // 3. and we have the incoming value (rhs).
    if (assignStmt.lhs is MemoryAccess) {
      // We need to check if this is a table update operation by key.
      final MemoryAccess mem = assignStmt.lhs as MemoryAccess;
      final StreamPos linePos = mem.op.pos;

      if (mem.type == MemoryAccessType.table) {
        lhs = mem.callee.accept(this)?.unpack();
        final key = mem.args.firstOrNull?.accept(this);

        // We need to check if it's actually a table.
        if (lhs is LuaObject && lhs.isTable) {
          final newindex = lhs.readMetatable('__newindex');

          // Now check if we have __newindex defined.
          if (newindex is LuaObject) {
            if (newindex.isFunc) {
              return callLuaFunction(newindex, args: [lhs, key, rhs]);
            } else if (newindex.isTable) {
              // TODO: table lookup shortcut
            }

            throw '$linePos Object for __newindex is not a valid type. Was "${debugLuaTypeInfo(newindex)}".';
          } else if (newindex == null) {
            // Regular table update operation by key.
            lhs.writeField(key ?? LuaObject.nil('key'), rhs);
          } else {
            throw '$linePos Indexing on non-table type "${debugLuaTypeInfo(lhs)}".';
          }
        }
      }
      // No further inspection required.
      // Fallthrough to codepath below.
    }

    lhs = assignStmt.lhs.accept(this);

    if (lhs == null && assignStmt.lhs is RawExpr) {
      // If this variable is not defined, it is now
      // and is also in the global scope.
      final id = (assignStmt.lhs as RawExpr).token.lexeme;
      return defGlobal(LuaObject.variable(id, rhs));
    } else if (lhs is LuaObject) {
      // Check if this object has a <const> attribute.
      if(lhs.attr == 'const') {
        final StreamPos linePos = assignStmt.token.pos;
        throw '$linePos Attempt to re-assign a constant variable ${lhs.id}.';
      }
      if (rhs is LuaObject) {
        if (lhs.deref() != rhs.deref()) {
          // EDGE CASE. Promote functions up to the lhs value.
          // This is because the `fieldValueAs<Function>()` method
          // expects the [LuaObject] with a field name for a function
          // to be resolved correclty.
          if (rhs.isFunc) {
            lhs.value = rhs.value;
            lhs.funcDef = rhs.funcDef;
            lhs.scope = rhs.scope;
          } else {
            lhs.value = rhs;
          }
        }
      } else {
        lhs.value = rhs;
      }
    }

    return lhs;
  }

  @override
  Object? visitAssignMultiStmt(AssignMultiStmt assignMultiStmt) {
    // rhs gauranteed to be the same length by AssignMultiExpr ctor.
    final int len = assignMultiStmt.lhs.length;
    final Token op = assignMultiStmt.token;

    for (int i = 0; i < len; i++) {
      final lhs = assignMultiStmt.lhs[i];
      final rhs = assignMultiStmt.rhs[i];
      // Desugaring
      visitAssignStmt(AssignStmt(op, lhs: lhs, rhs: rhs));
    }

    return null;
  }

  @override
  Object? visitBinaryExpr(BinaryExpr expr) {
    final String lineInfo = this.lineInfo(expr.op);
    final op = expr.op.type;

    LuaObject asLua(Object? obj, String id) =>
        obj?.makeLuaRef() ?? LuaObject.variable(id, obj);

    Object? metamethod(String name, Object? lhs, Object? rhs) {
      final l = asLua(lhs, 'lhs');
      final r = asLua(rhs, 'rhs');

      LuaObject? mm = l.readMetatable(name)?.as<LuaObject>();
      if (mm != null) {
        return callLuaFunction(mm, args: [l, r]);
      }

      mm = r.readMetatable(name)?.as<LuaObject>();
      if (mm != null) {
        return callLuaFunction(mm, args: [l, r]);
      }

      // Metamethod not handled by operands.
      return null;
    }

    num coerceString(String str) {
      final i = num.tryParse(str);
      if (i == null) throw 'Math operation on non-coercible string.';
      return i;
    }

    num asNum(Object? obj) {
      if (obj == null) throw 'Operand was null for binary $op.';
      if (obj is LuaObject) {
        final s = obj.value;
        if (s is String) {
          return coerceString(s);
        }
        final value = obj.valueAs<num>();
        if (value == null) {
          throw 'Failed to coerce lua type "${obj.luaTypeInfo}" to "number".';
        }
        return value;
      } else if (obj is num) {
        return obj;
      } else if (obj is String) {
        return coerceString(obj);
      }

      throw 'Unexpected type while coercing to "number". Found "${obj.runtimeType}".';
    }

    int asInt(Object? obj) => asNum(obj).toInt();

    String strConcat(Object? lhs, Object? rhs) {
      check(LuaObject obj) {
        final mm = switch (obj.readMetatable('__concat')) {
          final LuaObject o => o,
          _ => null,
        };

        if (!(obj.valueAsInt() is int || obj.value is String)) {
          if (mm != null) return mm;
          throw 'Attempt to concat ${obj.luaTypeInfo} value.';
        }

        return null;
      }

      final luaLhs = asLua(lhs, 'lhs');
      final mmLhs = check(luaLhs);

      final luaRhs = asLua(rhs, 'rhs');
      final mmRhs = check(luaRhs);

      if (mmLhs != null) {
        return callLuaFunction(
              mmLhs,
              args: [luaLhs, luaRhs],
            ).firstOrNull?.toString() ??
            'nil';
      }

      if (mmRhs != null) {
        return callLuaFunction(
              mmRhs,
              args: [luaLhs, luaRhs],
            ).firstOrNull?.toString() ??
            'nil';
      }

      final strL = luaLhs.toString();
      final strR = luaRhs.toString();
      return strL + strR;
    }

    bool isEqual(LuaObject? lhs, LuaObject? rhs) {
      if ((lhs?.isTable ?? false) && (rhs?.isTable ?? false)) {
        final ok = metamethod('__eq', lhs, rhs)?.unpack();
        if (ok != null) return ok.isTruthy;
      }

      Object? lval = lhs;
      if (lhs is LuaObject) {
        lval = lhs.value;
      }

      Object? rval = rhs;
      if (rhs is LuaObject) {
        rval = rhs.value;
      }

      return lval == rval;
    }

    bool isLessThan(LuaObject? lhs, LuaObject? rhs) {
      final ok = metamethod('__lt', lhs, rhs)?.unpack();
      if (ok != null) return ok.isTruthy;

      return switch ((lhs?.value, rhs?.value)) {
        (final String s, final String t) => s.compareTo(t) < 0,
        (final num n, final num m) => n < m,
        (final Object? l, final Object? r) =>
          throw 'Operation ${debugLuaTypeInfo(l)} < ${debugLuaTypeInfo(r)} failed.',
      };
    }

    bool isLessThanOrEqual(LuaObject? lhs, LuaObject? rhs) {
      if ((lhs?.isTable ?? false) || (rhs?.isTable ?? false)) {
        final ok = metamethod('__le', lhs, rhs)?.unpack();
        if (ok != null) return ok.isTruthy;
      }

      return switch ((lhs?.value, rhs?.value)) {
        (final String s, final String t) => s.compareTo(t) <= 0,
        (final num n, final num m) => n <= m,
        (final Object? l, final Object? r) =>
          throw 'Operation ${debugLuaTypeInfo(l)} <= ${debugLuaTypeInfo(r)} failed.',
      };
    }

    try {
      final lhs = expr.lhs.accept(this)?.unpack();
      final rhs = expr.rhs.accept(this)?.unpack();

      switch (op) {
        case TokenType.kConcat:
          return strConcat(lhs, rhs);
        case TokenType.kMod:
          final ok = metamethod('__mod', lhs, rhs);
          if (ok != null) return ok;
          return asInt(lhs) % asInt(rhs);
        case TokenType.kAnd:
          if (lhs.isTruthy) return rhs;
          return lhs;
        case TokenType.kOr:
          if (lhs.isTruthy) return lhs;
          return rhs;
        case TokenType.kBitNot:
          final ok = metamethod('__bxor', lhs, rhs);
          if (ok != null) return ok;
          return asInt(lhs) ^ asInt(rhs);
        case TokenType.kBitAnd:
          final ok = metamethod('__band', lhs, rhs);
          if (ok != null) return ok;
          return asInt(lhs) & asInt(rhs);
        case TokenType.kBitOr:
          final ok = metamethod('__bor', lhs, rhs);
          if (ok != null) return ok;
          return asInt(lhs) | asInt(rhs);
        case TokenType.kBitLShift:
          final ok = metamethod('__shl', lhs, rhs);
          if (ok != null) return ok;
          return asInt(lhs) << asInt(rhs);
        case TokenType.kBitRShift:
          final ok = metamethod('__shr', lhs, rhs);
          if (ok != null) return ok;
          return asInt(lhs) >> asInt(rhs);
        case TokenType.kCarrot:
          final ok = metamethod('__pow', lhs, rhs);
          if (ok != null) return ok;
          return math.pow(asNum(lhs), asNum(rhs));
        case TokenType.kDiv:
          final ok = metamethod('__div', lhs, rhs);
          if (ok != null) return ok;
          return asNum(lhs) /
              switch (asNum(rhs)) {
                == 0.0 => throw 'Divide by zero.',
                final num n => n,
              };
        case TokenType.kDivFloor:
          final ok = metamethod('__idiv', lhs, rhs);
          if (ok != null) return ok;
          final d =
              asNum(lhs) /
              switch (asNum(rhs)) {
                == 0.0 => throw 'Divide by zero.',
                final num n => n,
              };
          return d.floor();
        case TokenType.kSub:
          final ok = metamethod('__sub', lhs, rhs);
          if (ok != null) return ok;
          return asNum(lhs) - asNum(rhs);
        case TokenType.kAdd:
          final ok = metamethod('__add', lhs, rhs);
          if (ok != null) return ok;
          return asNum(lhs) + asNum(rhs);
        case TokenType.kMult:
          final ok = metamethod('__mul', lhs, rhs);
          if (ok != null) return ok;
          return asNum(lhs) * asNum(rhs);
        case TokenType.kLTE:
          return isLessThanOrEqual(lhs, rhs);
        case TokenType.kLT:
          return isLessThan(lhs, rhs);
        case TokenType.kGT:
          return isLessThan(rhs, lhs);
        case TokenType.kGTE:
          return isLessThanOrEqual(rhs, lhs);
        case TokenType.kEQ:
          return isEqual(lhs, rhs);
        case TokenType.kNEQ:
          return !isEqual(lhs, rhs);
        default:
          throw 'Unsupported binary operation $op.';
      }
    } catch (e) {
      throw '$lineInfo ${e.toString()}';
    }
  }

  @override
  Object? visitBooleanLiteral(BooleanLiteral boolean) {
    return boolean.value;
  }

  @override
  Object? visitBreakStmt(BreakStmt stmt) {
    throw LuaBreakStmtException();
  }

  @override
  Object? visitGotoStmt(GotoStmt stmt) {
    // TODO: Needs bytecode
    addDiagnostic(
      'Semantics skipped the following statement: goto ${stmt.expr.token.lexeme}',
    );
    return null;
  }

  @override
  Object? visitGotoLabelStmt(GotoLabelStmt stmt) {
    // TODO: Needs bytecode
    addDiagnostic(
      'Semantics skipped the following statement: ::${stmt.label.lexeme}::',
    );
    return null;
  }

  @override
  Object? visitDeclArg(DeclArg declArg) {
    return defLocal(LuaObject.variable(declArg.lexeme, null));
  }

  @override
  Object? visitDeclVar(DeclVar declVar) {
    final id = declVar.id.lexeme;
    final value = declVar.init?.accept(this) ?? LuaObject.nil(id);
    final attr = declVar.attr?.lexeme;
    return defLocal(LuaObject.variable(id, value, attr));
  }

  // See [VisitArgPack] extension.
  // Each evaluated value returns one value
  // unless it is the last evaluated value.
  // Then those values are assigned to the lhs items.
  @override
  Object? visitDeclMultiVar(DeclMultiVar declMultiVar) {
    final List<LuaObject> vals = declMultiVar.vals.visitArgPack(this);

    final int len = declMultiVar.vars.length;
    for (int i = 0; i < len; i++) {
      final declVar = declMultiVar.vars[i];
      final LuaObject? o = declVar.accept(this)?.makeLuaRef();

      if (i < vals.length) {
        o?.value = vals[i];
      }
    }
    return null;
  }

  @override
  Object? visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt) {
    final prevScope = scope;
    pushScope();
    final String lineInfo = this.lineInfo(forIterLoopStmt.token);

    try {
      final List<String> vars = forIterLoopStmt.vars.map((e) => e.lexeme).toList(growable: false);
      final List<LuaObject> exprs = [];
      final int len = forIterLoopStmt.exprs.length;
      for(int i = 0; i < len; i++) {
        final expr = forIterLoopStmt.exprs[i];
        if(i == len-1) {
          final List<LuaObject> ls = switch(expr.accept(this)) {
            final LuaArgPack ls => ls,
            final List<Object> ls => ls.map((e) => e.toLuaRet()).toList(growable: false),
            final Object o => [o.toLuaRet()],
            _ => [LuaObject.nil('expr$i')],
          };
          exprs.addAll(ls);
        } else {
          exprs.add(expr.accept(this)?.unpack() ?? LuaObject.nil('expr$i'));
        }
      }

      // Read only the first 3 evaluated expression result values.
      // See: https://www.lua.org/pil/7.2.html
      LuaObject f = exprs.elementAt(0);
      if(f.isCallable) {
        f = f.readMetatable('__call')?.unpack() ?? LuaObject.nil('iter');
      } else if(f.isNotFunc) {
        throw '$lineInfo Expected an iterator found ${f.luaTypeInfo}.';
      }

      final LuaObject s = exprs.elementAtOrNull(1) ?? LuaObject.nil('state');
      LuaObject v = exprs.elementAtOrNull(2) ?? LuaObject.nil('value');

      for(final String v in vars) {
        defLocal(LuaObject.nil(v));
      }

      bool loop = true;
      while(loop) {
        final args = callLuaFunction(f, args: [s, v]);

        for(int i = 0; i < vars.length; i++) {
          LuaObject vs = findVar(vars[i])!;
          if(i >= args.length) {
            vs.value = null;
            continue;
          }
          vs.value = args[i];
          if(i == 0) {
            v = vs;
          }
        }

        if(v.isNil) {
          loop = false;
          break;
        }

        for (Stmt stmt in forIterLoopStmt.body) {
          try {
            stmt.accept(this);
          } on LuaBreakStmtException {
            loop = false;
            break;
          } catch (e) {
            loop = false;
            addError(e.toString());
          }
        }
      }
    } catch (e) {
      rethrow;
    } finally {
      restoreScope(prevScope);
    }

    return null;
  }

  @override
  Object? visitForLoopStmt(ForLoopStmt forLoopStmt) {
    final prevScope = scope;
    pushScope();

    try {
      Object? control = forLoopStmt.control.accept(this);

      evalVar(Object? v) {
        if (v is LuaObject && v.valueAsInt() is int) {
          final String id = v.id;
          return (id, v.valueAsInt()!);
        } else {
          final String lineInfo = this.lineInfo(forLoopStmt.token);
          throw '$lineInfo For-loop control did not evaluate to a variable!';
        }
      }

      evalNum(LuaObject? n, String label) {
        if (n == null) {
          return 1;
        } else if (n.valueAs<num>() != null) {
          return n.valueAs<num>();
        }

        // n is not num
        throw '$lineInfo For-loop $label did not evaluate to a number!';
      }

      final String controlId;
      num ncontrol;
      (controlId, ncontrol) = evalVar(control);

      final num end = evalNum(forLoopStmt.endExpr.accept(this)?.unpack(), 'end')!;
      final num step = evalNum(forLoopStmt.stepExpr.accept(this)?.unpack(), 'step')!;

      while (ncontrol <= end) {
        defLocal(LuaObject.variable(controlId, ncontrol));

        for (int i = 0; i < forLoopStmt.body.length; i++) {
          final stmt = forLoopStmt.body[i];
          try {
            stmt.accept(this);
          } on LuaBreakStmtException {
            break;
          } on LuaReturnValueException {
            rethrow;
          } catch (e) {
            addError(e.toString());
          }
        }
        ncontrol += step;
      }
    } catch (e) {
      rethrow;
    } finally {
      restoreScope(prevScope);
    }

    return null;
  }

  @override
  Object? visitGroupExpr(GroupExpr groupExpr) {
    return groupExpr.expr.accept(this);
  }

  @override
  Object? visitIfStmt(IfStmt stmt) {
    // Set to true in order to handle `else` branch.
    bool visitBody = true;

    if (!stmt.isTerminalElse) {
      visitBody = stmt.expr!.accept(this)?.toLua('ctrl').isTruthy ?? false;
    }

    if (visitBody) {
      Object? res;
      final prevScope = scope;
      pushScope();
      try {
        for (Stmt s in stmt.body) {
          final out = s.accept(this);

          // One of these code paths must be non-null
          // unless all paths are null.
          // TODO: better value inference.
          if (out != null) {
            res = out;
          }
        }
      } catch (e) {
        rethrow;
      } finally {
        restoreScope(prevScope);
      }

      return res;
    }

    return stmt.nextIfStmt?.accept(this);
  }

  @override
  Object? visitKeyValStmt(KeyValStmt keyval) {
    // Unused grammar rule during evaluation.
    throw 'Reached unused grammar visitKeyValStmt';
  }

  @override
  Object? visitMemoryAccess(MemoryAccess memoryAccess) {
    // Debugger print info
    final StreamPos linePos = memoryAccess.op.pos;
    final String lineTag = this.lineTag(memoryAccess.op);

    // Recursively descends to the deepest lhs node expression.
    // The result must be a lua object in order to be correct.
    // Otherwise a value is incorrect and an error can be thrown.
    Object? callee = memoryAccess.callee.accept(this)?.unpack();

    if (callee is! LuaObject) {
      final v = debugLuaTypeInfo(callee);
      throw '$linePos Expected lua object for operator "${memoryAccess.op.lexeme}". Was $v.';
    }

    // After the parser, fields and table keys behave the same.
    final bool indexedTable = switch (memoryAccess.type) {
      MemoryAccessType.table || MemoryAccessType.field => true,
      _ => false,
    };

    final bool funcInvocation = memoryAccess.type == MemoryAccessType.call;
    bool fwdSelfArg = memoryAccess.isSelfFwd;

    if (callee.skipSemanitcs) {
      // Check if special case of skipping semantics and evaluation.
      // Regardless is this is a method or field, we don't process it.
      // Visit args and return early.
      //
      // Note that it's not necessary to forward "self"
      // b/c no function body will be executed in this case.
      if (!fwdSelfArg) {
        for (MathExpr expr in memoryAccess.args) {
          expr.accept(this);
        }
      }

      final ret = LuaObjectNoSemantics('ret_nosemantic$lineTag');
      return ret;
    } else if (indexedTable) {
      if (memoryAccess.args.length > 1) {
        throw '$linePos Multiple indexes on "$callee".';
      }

      final Object? idx = memoryAccess.field?.accept(this);
      if (callee.isTable) {
        getValue(v) => switch (v) {
          final LuaObject lo => getValue(lo.value),
          final Object o => o,
          null => null,
        };

        final Object key = switch (memoryAccess.type) {
          MemoryAccessType.field => memoryAccess.field!.token.lexeme,
          _ => getValue(idx),
        };

        if (callee.hasField(key)) {
          return callee.readField(key);
        } else {
          final midx = callee.readMetatable('__index');
          if (midx == null) {
            final res = callee.writeField(key, LuaObject.nil(key.toString()))!;
            return res;
          }
          if (midx is! LuaObject) {
            throw '$linePos Metamethod __index was an invalid type "${debugLuaTypeInfo(midx)}"';
          }

          if (midx.isFunc) {
            return callLuaFunction(midx, args: [callee, key]);
          }

          // Else, expect table for __index.
          return midx.readField(key);
        }
      }

      throw '$linePos Indexing on "$callee" with index "$idx".';
    } else if (funcInvocation) {
      // Depending on whether or not this is a normal function call
      // using the dot "." notation or if this is a special function call
      // using the colon ":" notation, we may need to peak into the rhs
      // which will contain the special (latter) case. If so, we want to
      // use these supplied arguments for invocation.
      LuaObject? callable = callee;
      int argsInLen;
      List<LuaObject> args;
      String callableId = callee.id;

      // This indicates the node is two parts: (lhs, (functioncall))
      // where the lhs is the lua object and the functioncall is a
      // callable property on the object. This will forward lhs
      // as a new first argument.
      if (fwdSelfArg) {
        final rhsMemoryAccess = switch (memoryAccess.field) {
          final MemoryAccess ma => ma,
          _ =>
            throw '$linePos Expected function call after colon ":" operator.',
        };

        // Update the callsite context and fetch the new callableId.
        callableId = switch (rhsMemoryAccess.callee) {
          final RawExpr r => r.token.lexeme,
          final Object? obj =>
            throw '$linePos Expected name after colon ":" operator. Found $obj.',
        };

        // This must be a method on the original callee (lhs).
        callable = switch (callee.deref().readField(callableId)) {
          final LuaObject lua => lua,
          _ => null,
        };

        // Use the rhs args for invocation.
        args = rhsMemoryAccess.args.visitArgPack(this);

        // +1 to include implied self.
        argsInLen = args.length + 1;
      } else {
        args = memoryAccess.args.visitArgPack(this);
        argsInLen = args.length;
      }

      final mcall = switch (callable?.readMetatable('__call')) {
        final LuaObject lo => lo,
        _ => null,
      };

      FuncExpr? func = callable?.funcDef ?? mcall?.funcDef;
      Scope? pscope = callable?.scope ?? mcall?.scope;

      // The first argument to __call is self.
      if (mcall != null) {
        fwdSelfArg = true;
      }

      if (func == null) {
        throw '$linePos Attempt to call a nil value (field "$callableId").';
      }

      final int defInLen = func.args.length;
      final String funcId = switch (func.id) {
        '' => '<anonymous fn>',
        final String s => s,
      };

      // The earlier parser stage would catch if this wasn't true.
      final bool isVariadic =
          func.args.lastOrNull?.id.type == TokenType.kSpread;

      if (!isVariadic && argsInLen != defInLen) {
        // There are a few functions that have "overloads".
        // This means there is acceptable behavior in the lua routine
        // even with less the max number of args.
        // This warning can be supressed on a case-by-case basis.
        final suppressList = [global.findVar('table')?.readField('insert')];

        if (!suppressList.contains(callable)) {
          addWarning(
            '$linePos Function "$funcId" has $defInLen arguments but received $argsInLen.',
          );
        }
      }

      final prevScope = scope;
      pushScope(parent: pscope);
      Object? ret;

      try {
        final List<LuaObject> varg = [];
        final int argCount = switch (isVariadic) {
          true => args.length,
          false => defInLen,
        };

        if (fwdSelfArg && argCount > 0) {
          args.insert(0, LuaObject.variable(func.args.first.lexeme, callee));
        }

        bool buildVarArgTable = false;

        for (int i = 0; i < argCount; i++) {
          // Var args are bundled under a hidden variable
          // named `arg`. They do not count towards the
          // function definition parameter list.
          String lexeme = 'arg$i';
          if (i < func.args.length) {
            final arg = func.args.elementAt(i);
            if (arg.id.type == TokenType.kSpread) {
              buildVarArgTable = true;
            } else {
              lexeme = arg.lexeme;
            }
          }

          final arg = switch (i < args.length) {
            true => args.elementAt(i),
            false => null,
          };

          final next = LuaObject.variable(lexeme, arg);

          if (buildVarArgTable) {
            varg.add(next);
          } else {
            defLocal(next);
          }
        }

        defLocal(
          LuaObject.table('arg', {
            for (int i = 0; i < varg.length; i++) '${i + 1}': varg[i],
          }),
        );

        ret = mcall?.call() ?? callable!.call();
      } on LuaReturnValueException {
        rethrow;
      } catch (e) {
        throw '$linePos ${e.toString()}';
      } finally {
        restoreScope(prevScope);
      }

      return ret;
    }

    throw 'Unexpected code path while accessing memory on $callee.';
  }

  @override
  Object? visitNilLiteral(NilLiteral nil) {
    return LuaObject.nil('<nil>');
  }

  @override
  Object? visitNotExpr(NotExpr notExpr) {
    final val = notExpr.expr.accept(this);
    return val.isNotTruthy;
  }

  @override
  Object? visitNumberLiteral(NumberLiteral number) {
    return number.value;
  }

  @override
  Object? visitRawExpr(RawExpr rawExpr) {
    final id = rawExpr.token.lexeme;

    if (hasContext) {
      final field = context!.readField(id);
      if (field == null) {
        final variable = findVar(id);
        if (variable == null) {
          // Promote this field to a new object.
          // Likely is the case that this object
          // will be given a value in the next
          // statement as an assignment statement.
          return context!.writeField(id, LuaObject.nil(id));
        } else {
          return variable;
        }
      }
      return field;
    }

    return findVar(id);
  }

  @override
  Object? visitRepeatUntilLoopStmt(RepeatUntilLoopStmt repeatUntilLoopStmt) {
    final prevScope = scope;
    pushScope();
    while (true) {
      try {
        for (Stmt stmt in repeatUntilLoopStmt.body) {
          try {
            stmt.accept(this);
          } on LuaBreakStmtException {
            rethrow;
          } catch (e) {
            addError(e.toString());
          }
        }
        final cond = repeatUntilLoopStmt.untilExpr.accept(this);
        if (cond?.isTruthy ?? false) {
          break;
        }
      } on LuaBreakStmtException {
        break;
      } catch (e) {
        addError(e.toString());
        break;
      }
    }
    restoreScope(prevScope);
    return null;
  }

  @override
  Object? visitSelfExpr(SelfExpr selfExpr) {
    return visitRawExpr(RawExpr(Token.raw('self', selfExpr.token.pos)));
  }

  @override
  Object? visitStringLiteral(StringLiteral string) {
    return string.value;
  }

  @override
  Object? visitTableLiteral(TableLiteral table) {
    final t = LuaFieldsMap();

    int next = 0;
    for (var e in table.pairs) {
      final Object? k = switch (e.key) {
        final RawExpr expr => expr.token.lexeme,
        final MathExpr expr => expr.accept(this),
        _ => ++next,
      };

      if(k == null) {
        throw 'Table key could not be parsed!';
      }

      final v = e.value.accept(this);
      t[k] = v?.toLua(k.toString());
    }

    return LuaObject.table('table', t);
  }

  @override
  Object? visitUnaryExpr(UnaryExpr expr) {
    final op = expr.prefix.type;
    final rhs = expr.rhs.accept(this);

    if (op == TokenType.kHash) {
      if (rhs is LuaObject) {
        final mm = rhs.readMetatable('__len')?.as<LuaObject>();

        final v = rhs.value;
        if (v is! String && mm != null) {
          return callLuaFunction(mm, args: [rhs]);
        }

        if (v is String) {
          return v.length;
        }

        if (rhs.isNotTable) {
          throw 'Length operator # used on a value.';
        }

        return rhs.tableSize;
      } else if (rhs == null) {
        throw 'Length operator # used on nil value.';
      }
      // else ...
      throw 'Length operator # used on type ${rhs.runtimeType}.';
    } else if (op == TokenType.kBitNot) {
      String type = rhs.runtimeType.toString();
      Object? v = rhs;
      if (rhs is LuaObject) {
        type = rhs.luaTypeInfo;

        if (rhs.isTable) {
          final mm = rhs.readMetatable('__bnot')?.as<LuaObject>();
          if (mm != null) {
            return callLuaFunction(mm, args: [rhs]);
          }
        } else {
          v = rhs.value;
        }
      }

      // ... else
      return switch (v) {
        final num n => ~n.toInt(),
        _ => throw 'Unsupported bitwise NOT on $type.',
      };
    } else if (op == TokenType.kSub) {
      String type = rhs.runtimeType.toString();
      Object? v = rhs;
      if (rhs is LuaObject) {
        type = rhs.luaTypeInfo;

        if (rhs.isTable) {
          final mm = rhs.readMetatable('__unm')?.as<LuaObject>();
          if (mm != null) {
            return callLuaFunction(mm, args: [rhs, rhs]);
          }
        } else {
          v = rhs.value;
        }
      }

      // ... else
      return switch (v) {
        final num n => -n,
        _ => throw 'Unsupported negation on $type.',
      };
    }

    throw 'Unsupported unary operator ${op.toString()}';
  }

  @override
  Object? visitWhileLoopStmt(WhileLoopStmt whileLoopStmt) {
    while (true) {
      final prevScope = scope;
      pushScope();
      try {
        final cond = switch (whileLoopStmt.expr.accept(this)) {
          final List ls => ls.firstOrNull?.isTruthy,
          final Object? o => o.isTruthy,
        };

        if (!cond) break;

        for (Stmt stmt in whileLoopStmt.body) {
          try {
            stmt.accept(this);
          } on LuaBreakStmtException {
            rethrow;
          } catch (e) {
            addError(e.toString());
          }
        }
      } on LuaBreakStmtException {
        break;
      } catch (e) {
        rethrow;
      } finally {
        restoreScope(prevScope);
      }
    }
    return null;
  }
}

/// Helper to convert [Object] to a lua `true` or `false`
/// equivalent used in boolean expressions.
///
/// Introduces [isTruthy] and [isNotTruthy].
extension Truthy on Object? {
  bool get isTruthy => switch (this) {
    final LuaObject obj => obj.isTruthy,
    false || null => false,
    _ => true,
  };

  bool get isNotTruthy => !isTruthy;
}

// Following https://www.lua.org/pil/5.1.html
// Any argument pack would need to be evaluated
// so that the returned values are the first item
// in any pack list unless it's the last item, then
// all the values can be returned.
// The output is a flat list to be read from directly.
extension VisitArgPack on List<MathExpr> {
  List<LuaObject> visitArgPack(Visitor visitor) {
    final List<LuaObject> out = [];
    for (int i = 0; i < length; i++) {
      final LuaArgPack vs = switch (this[i].accept(visitor)) {
        final LuaArgPack p => switch (i + 1 == length) {
          true => p,
          false => [?p.firstOrNull],
        },
        final LuaObject o => [o],
        // final Object? o => [?o?.toLua('arg$i')],
        final Object? o => [o?.toLua('arg$i') ?? LuaObject.nil('arg$i')],
      }.nonNulls.toList(growable: false);
      out.addAll(vs);
    }
    return out;
  }
}
