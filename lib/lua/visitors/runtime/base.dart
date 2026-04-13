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

typedef TraceCallback = void Function(Set<String>);

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
}

abstract class BaseRuntime extends Visitor<Object?> {
  final BaseResults results;
  final Scope global = Scope();
  late Scope scope = global;
  String? debugPath;
  IncludeCallback? onIncludeImpl;

  BaseRuntime(this.results);

  String lineTag(Token token) => '_<${token.pos.row + 1},${token.pos.col + 1}>';
  String lineInfo(Token token) => token.pos.toString();

  String tokenId(Token token, {String? prefix}) {
    final id = 'id${lineTag(token)}';
    if (prefix == null) {
      return id;
    }

    return '${prefix}_$id';
  }

  void debugSetPath(String? path) => debugPath = path;

  void addError(String err) {
    final msg = switch (debugPath) {
      final String path => '$err\n\t... in "$path".',
      _ => err,
    };

    results.addError(msg);
  }

  void addWarning(String warn) {
    final msg = switch (debugPath) {
      final String path => '$warn\n\t... in "$path".',
      _ => warn,
    };

    results.addWarning(msg);
  }

  void addDiagnostic(String info) {
    final msg = switch (debugPath) {
      final String path => '$info\n\t... in "$path".',
      _ => info,
    };

    results.addDiagnostic(msg);
  }

  void pushScope({LuaObject? context}) {
    // scope.dump();
    scope = Scope(parent: scope, context: context);
    // print('scope depth: ${scope.depth}');
  }

  void popScope() {
    if (scope.parent == null) return;
    //scope.dump();
    scope = scope.parent!;
  }

  LuaObject? get context => scope.context;
  bool get hasContext => scope.hasContext;

  LuaObject defLocal(LuaObject value) {
    return scope.defVar(value.id, value);
  }

  LuaObject defGlobal(LuaObject value) {
    return global.defVar(value.id, value);
  }

  LuaObject? findVar(String id) {
    return scope.findVar(id);
  }

  /// First finds [field] inside object "self"
  /// in [Scope]. If neither can be found,
  /// [or] is returned cast [toLua].
  /// If [or] is not provided, null is returned.
  ///
  /// Otherwise if "self" is found, then
  /// returns the property with name [field]
  /// with the same name as a [LuaObject].
  LuaObject? findOnSelf(String field, {Object? or}) {
    return findVar('self')?.readField(field)?.toLua(field) ?? or?.toLua(field);
  }

  List<LuaObject>? findVarArgs() {
    return scope.findVarArgs();
  }

  @override
  Object? visitAST(AST ast) {
    Object? ret;
    for (final e in ast.stmts) {
      try {
        ret = e.accept(this);
      } catch (e) {
        addError(e.toString());
      }
    }
    return ret;
  }

  @override
  Object? visitFuncExpr(FuncExpr expr) {
    // Before we determine what the name of this function is, and whether
    // or not it should follow local function conventions or not, we can
    // construct a closure.
    closure() {
      Object? res;
      final int len = expr.body.length;
      for (int i = 0; i < len; i++) {
        final Stmt stmt = expr.body[i];
        try {
          res = stmt.accept(this);
        } catch (e) {
          addError(e.toString());
        }
      }

      if (res is LuaObject) {
        // Unpack the result if its arity is one.
        if (res.length == 1) res = res.readField('1');
      }
      return res;
    }

    // Spec reference: https://www.lua.org/manual/5.4/manual.html#3.4.11
    // We need to "build" the function if it's a method on an existing object.
    // This means the first node must be the object when node length is more than one
    // or the function name if the node length is exactly one.
    // We must manually check if the object is not-null in the case that we are adding a field.
    // For example. Given an object `t = {}`, we can define `function t.f() end`, however
    // we cannot define `function t.a.f() end` without the existence of `t.a = {}` beforehand.

    final List<RawExpr> idParts = [...expr.idParts];
    final String id = expr.id;
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
        final obj = findVar(field);

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
      luaObj = LuaObject.func(id, expr, closure);
      parent!.writeField(field, luaObj);
    } else {
      // Case: This is a function, not a "method" on an object.
      luaObj = LuaObject.func(id, expr, closure);

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

  @override
  Object? visitAssignExpr(AssignExpr assignExpr) {
    Object? lhs = assignExpr.lhs.accept(this);
    final rhs = assignExpr.rhs.accept(this);

    if (lhs == null && assignExpr.lhs is RawExpr) {
      final id = (assignExpr.lhs as RawExpr).token.lexeme;
      final foundVar = findVar(id);

      // TODO: determine if local or global
      return defLocal(LuaObject.variable(id, rhs));
    } else if (lhs is LuaObject) {
      if (rhs is LuaObject) {
        if (lhs.deref() != rhs.deref()) {
          lhs.value = rhs;
        }
      } else {
        lhs.value = rhs;
      }
    }

    return lhs;
  }

  @override
  Object? visitAssignMultiExpr(AssignMultiExpr assignMultiExpr) {
    // rhs gauranteed to be the same length by AssignMultiExpr ctor.
    final int len = assignMultiExpr.lhs.length;
    final Token op = assignMultiExpr.op;

    for (int i = 0; i < len; i++) {
      final lhs = assignMultiExpr.lhs[i];
      final rhs = assignMultiExpr.rhs[i];
      // Desugaring
      visitAssignExpr(AssignExpr(op, lhs: lhs, rhs: rhs));
    }

    return null;
  }

  @override
  Object? visitBinaryExpr(BinaryExpr expr) {
    final String lineInfo = this.lineInfo(expr.op);
    final op = expr.op.type;

    int asInt(Object? obj) {
      if (obj == null) throw '$lineInfo Operand was null for binary $op.';
      if (obj is LuaObject) {
        final value = obj.valueAs<num>();
        if (value == null) {
          throw '$lineInfo Failed to convert lua type "${obj.typeinfo}" to "int".';
        }
        return value.toInt();
      } else if (obj is num) {
        return obj.toInt();
      }

      throw '$lineInfo Unexpected type while casting to "int". Found "${obj.runtimeType}".';
    }

    num asNum(Object? obj) {
      if (obj == null) throw '$lineInfo Operand was null for binary $op.';
      if (obj is LuaObject) {
        final value = switch (obj.value) {
          final num n => n,
          _ => null,
        };
        if (value == null) {
          throw '$lineInfo Failed to convert lua type "${obj.typeinfo}" to "int".';
        }
        return value;
      } else if (obj is num) {
        return obj;
      }

      throw '$lineInfo Unexpected type while casting to "num". Found "${obj.runtimeType}".';
    }

    /*
    bool asBool(Object? obj) {
      if (obj == null) throw '$lineInfo Operand was null for binary $op.';
      if (obj is LuaObject) {
        final value = obj.valueAs<bool>();
        if (value == null) {
          throw '$lineInfo Failed to convert lua type "${obj.typeinfo}" to "bool".';
        }
        return value;
      } else if (obj is bool) {
        return obj;
      }

      throw '$lineInfo Unexpected type while casting to "bool". Found "${obj.runtimeType}".';
    }*/

    String str(Object? obj) {
      if (obj == null) return 'nil';
      return obj.toString();
    }

    String strConcat(Object? lhs, Object? rhs) {
      check(Object? obj) {
        if(obj is LuaObject) {
     	   if(!(obj.valueAsInt() is int || obj.value is String)) {
     	     throw 'Attempt to concat ${obj.value.runtimeType} value.';
     	  }
     	 } else if(!(obj is int || obj is String)) {
     	   throw 'Attempt to concat ${obj.runtimeType} value.';
     	 }
      }
      check(lhs);
      final strL = str(lhs);
      check(rhs);
      final strR = str(rhs);

      return strL + strR;
    }

    try {
      final lhs = expr.lhs.accept(this);
      final rhs = expr.rhs.accept(this);

      switch (op) {
        case TokenType.kConcat:
          return strConcat(lhs, rhs);
        case TokenType.kMod:
          return asInt(lhs) % asInt(rhs);
        case TokenType.kAnd:
          if (lhs.isTruthy) return rhs;
          return lhs;
        case TokenType.kOr:
          if (lhs.isTruthy) return lhs;
          return rhs;
        case TokenType.kBitAnd:
          return asInt(lhs) & asInt(rhs);
        case TokenType.kBitOr:
          return asInt(lhs) | asInt(rhs);
        case TokenType.kCarrot:
          return math.pow(asNum(lhs), asNum(rhs));
        case TokenType.kDiv:
          return asNum(lhs) /
              switch (asNum(rhs)) {
                == 0.0 => throw '$lineInfo Divide by zero.',
                final num n => n,
              };
        case TokenType.kDivFloor:
          return asNum(lhs) /
              switch (asNum(rhs)) {
                == 0.0 => throw '$lineInfo Divide by zero.',
                final num n => asNum(n.floor()),
              };
        case TokenType.kSub:
          return asNum(lhs) - asNum(rhs);
        case TokenType.kAdd:
          return asNum(lhs) + asNum(rhs);
        case TokenType.kMult:
          return asNum(lhs) * asNum(rhs);
        case TokenType.kLTE:
          return asNum(lhs) <= asNum(rhs);
        case TokenType.kLT:
          return asNum(lhs) < asNum(rhs);
        case TokenType.kGT:
          return asNum(lhs) > asNum(rhs);
        case TokenType.kGTE:
          return asNum(lhs) >= asNum(rhs);
        case TokenType.kEQ:
          Object? lval = lhs;
          
          if(lhs is LuaObject) {
            lval = lhs.deref().value;
          }

          Object? rval = rhs;
         
          if(rhs is LuaObject) {
            rval = rhs.deref().value;
          }

          return lval == rval;
        case TokenType.kNEQ:
          return lhs != rhs;
        default:
          throw '$lineInfo Unsupported binary operation $op.';
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
    return null;
  }

  @override
  Object? visitGotoStmt(GotoStmt stmt) {
    // TODO: suffer
    addDiagnostic(
      'Semantics skipped the following statement: goto ${stmt.expr.token.lexeme}',
    );
    return null;
  }

  @override
  Object? visitGotoLabelStmt(GotoLabelStmt stmt) {
    // TODO: suffer
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
    return defLocal(LuaObject.variable(id, value));
  }

  @override
  Object? visitDeclMultiVar(DeclMultiVar declMultiVar) {
    for (final declVar in declMultiVar.vars) {
      declVar.accept(this);
    }
    return null;
  }

  @override
  Object? visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt) {
    pushScope();

    final key = forIterLoopStmt.key.lexeme;
    final val = forIterLoopStmt.value.lexeme;

    final iterExpr = forIterLoopStmt.iterExpr.accept(this);
    if (iterExpr is! LuaObject || !iterExpr.isTable) {
      final String lineInfo = this.lineInfo(forIterLoopStmt.token);
      popScope();
      throw '$lineInfo Evaluation has encountered an unrecoverable scenario: iterator expression was not a table.';
    }

    final iterLen = iterExpr.length;
    defLocal(LuaObject.nil(key));
    defLocal(LuaObject.nil(val));

    for (int i = 0; i < iterLen; i++) {
      final iterKey = findVar(key);
      final iterVal = findVar(val);
      final entry = iterExpr.fields.entries.elementAtOrNull(i);
      iterKey?.value = entry?.key;
      iterVal?.value = entry?.value;

      for (Stmt stmt in forIterLoopStmt.body) {
        try {
          stmt.accept(this);
        } catch (e) {
          addError(e.toString());
        }
      }
    }
    popScope();

    return null;
  }

  @override
  Object? visitForLoopStmt(ForLoopStmt forLoopStmt) {
    pushScope();
    Object? control = forLoopStmt.control.accept(this);

    evalVar(Object? v) {
      if (v is LuaObject && v.valueAsInt() is int) {
        final String id = v.id;
        return (id, v.valueAsInt()!);
      } else {
        final String lineInfo = this.lineInfo(forLoopStmt.token);
        popScope();
        throw '$lineInfo For-loop control did not evaluate to a variable!';
      }
    }

    evalNum(Object? n, String label) {
      if(n == null) {
        return 1;
      }
      else if(n is LuaObject && n.valueAsInt() is int) {
        return n.valueAsInt();
      } else if (n is num) {
        return n;
      }
      
      // n is not num
      popScope();
      throw '$lineInfo For-loop $label did not evaluate to an integer value!';
    }

    final String controlId;
    num ncontrol;
    (controlId, ncontrol) = evalVar(control);

    final num end = evalNum(forLoopStmt.endExpr.accept(this), 'end')!;
    final num step = evalNum(forLoopStmt.stepExpr.accept(this), 'step')!;
    final ctrl = defLocal(LuaObject.variable(controlId, ncontrol));

    while (ncontrol <= end) {
      for (Stmt stmt in forLoopStmt.body) {
        try {
          stmt.accept(this);
        } catch (e) {
          addError(e.toString());
        }
      }
      ncontrol += step;
      ctrl.value = ncontrol;
    }

    popScope();
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
      pushScope();
      for (Stmt stmt in stmt.body) {
        final out = stmt.accept(this);

        // One of these code paths must be non-null
        // unless all paths are null.
        // TODO: better value inference.
        if (out != null) {
          res = out;
        }
      }
      popScope();
      return res?.toLua('ret');
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
    Object? callee = memoryAccess.callee.accept(this);

    if (callee is! LuaObject) {
      throw '$linePos Expected a lua object for operator "${memoryAccess.op.lexeme}", found value: $callee.';
    }

    final bool indexedTable = memoryAccess.type == MemoryAccessType.table;
    final bool funcInvocation = memoryAccess.type == MemoryAccessType.call;
    final bool fwdSelfArg = memoryAccess.op.type == TokenType.kColon;

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
        addError('$linePos Multiple indexes on "$callee".');
        return null;
      }

      Object? idx = memoryAccess.field?.accept(this);
      if (idx == null || (idx is LuaObject && idx.value == null)) {
        addError('$linePos Indexing on "$callee" with nil index.');
        return null;
      }

      // Unpack first.
      if (idx is LuaObject) {
        idx = idx.value;
      }

      if (callee.isTable) {
        final String? key = switch (idx) {
          final String s => s,
          final num n => n.toInt().toString(),
          final Object o => o.toString(),
          null => null,
        };

        if (key == null) {
          addError('$linePos Attempt to index a table with a nil key.');
          return null;
        }

        if (callee.hasField(key)) {
          return callee.readField(key);
        } else {
          return callee.writeField(key, LuaObject.nil(key.toString()));
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
      int argsInLen = memoryAccess.args.length;
      List<MathExpr> args = memoryAccess.args;
      String callableId = callee.id;
      String context = callableId;

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
        context = callableId;
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
        args = rhsMemoryAccess.args;

        // +1 to include implied self.
        argsInLen = rhsMemoryAccess.args.length + 1;
      }

      final func = switch (callable) {
        final LuaObject lua => lua.funcDef,
        _ => null,
      };

      if (func == null) {
        throw '$linePos Attempt to call a nil value (field "$callableId").';
      }

      final int defInLen = func.args.length;
      final String funcId = switch (func.id) {
        '' => '<anonymous>',
        final String s => s,
      };

      // The earlier parser stage would catch if this wasn't true.
      final bool isVariadic = func.args.lastOrNull?.id.type == TokenType.kSpread;

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

      final int fwdArgCount = fwdSelfArg ? 1 : 0;
      while (args.length + fwdArgCount < defInLen) {
        args.add(NilLiteral(Token.synthesized('nil')));
      }

      pushScope(context: callee);

      if (fwdSelfArg) {
        defLocal(LuaObject.variable('self', callee));
      }
 
      final List<LuaObject> varg = [];
      final int argCount = switch(isVariadic) {
        true => args.length - fwdArgCount,
        false => defInLen - fwdArgCount,
      };

      bool buildVarArgTable = false;

      for (int i = 0; i < argCount; i++) {
        // Var args are bundled under a hidden variable
        // named `arg`. They do not count towards the
        // function definition parameter list.
        String lexeme = 'arg${i + fwdArgCount}';
        if(i + fwdArgCount < func.args.length) {
          final arg = func.args.elementAt(i + fwdArgCount);
          if(arg.id.type == TokenType.kSpread) {
            buildVarArgTable = true;
          } else {
            lexeme = arg.lexeme;
          }
	}

        final expr = args.elementAt(i);
        final next = LuaObject.variable(lexeme, expr.accept(this));

        if(buildVarArgTable) {
          varg.add(next);
        } else {
          defLocal(next);
        }
      }
 
      defLocal(LuaObject.table('arg', {for(int i = 0; i < varg.length; i++) '${i+1}': varg[i]}));

      Object? ret;
      try {
        ret = callable!.call();
      } catch (e) {
        throw '$linePos ${e.toString()}';
      } finally {
        popScope();
      }

      return ret?.toLua('ret');
    }

    // Else this must be a field on an object.
    assert(
      memoryAccess.type == MemoryAccessType.field,
      'Codepath expected function invocation.',
    );

    final String fieldName = switch (memoryAccess.field) {
      final RawExpr r => r.token.lexeme,
      final Object? other =>
        throw '$linePos Expected a valid property name on $callee, found: $other',
    };

    // Primitives cannot have fields.
    if (callee.type == LuaType.value) {
        throw '$linePos "$callee" is a ${callee.luaTypeInfo} and cannot have fields.';
    }

    if (callee.hasField(fieldName)) return callee.readField(fieldName);

    // Else, create the field.
    return callee.writeField(fieldName, LuaObject.nil(fieldName));
  }

  @override
  Object? visitNilLiteral(NilLiteral nil) {
    return null;
  }

  @override
  Object? visitNotExpr(NotExpr notExpr) {
    final val = notExpr.expr.accept(this);
    return val.isTruthy;
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
    for (Stmt stmt in repeatUntilLoopStmt.body) {
      stmt.accept(this);
    }
    final _ = repeatUntilLoopStmt.untilExpr.accept(this);
    return null;
  }

  @override
  Object? visitReturnStmt(ReturnStmt expr) {
    int idx = 1;
    final table = LuaObject.table('ret', {});

    for (MathExpr value in expr.values) {
      table.writeField(idx.toString(), value.accept(this));
      idx++;
    }

    return table;
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
    final t = LuaTable();

    int next = 0;
    for (var e in table.pairs) {
      final Object k = switch (e.key) {
        final RawExpr r => r.token.lexeme,
        _ => ++next,
      };
      final v = e.value.accept(this);

      t[k.toString()] = v?.toLua(k.toString());
    }

    return t;
  }

  @override
  Object? visitUnaryExpr(UnaryExpr expr) {
    final op = expr.prefix.type;
    if (op == TokenType.kHash) {
      final rhs = expr.rhs.accept(this);
      if (rhs is LuaObject) {
        return rhs.length;
      } else if (rhs != null) {
        return 1;
      } else {
        final String lineInfo = this.lineInfo(expr.prefix);
        throw '$lineInfo Length operator # used on nil value.';
      }
    } else {
      final ret = expr.rhs.accept(this);
      if (ret != null) {
        if (op == TokenType.kSub) {
          return switch (ret) {
            final int i => -i,
            final double d => -d,
            _ => ret,
          };
        }
      }

      return ret;
    }
  }

  @override
  Object? visitWhileLoopStmt(WhileLoopStmt whileLoopStmt) {
    final _ = whileLoopStmt.expr.accept(this);
    for (Stmt stmt in whileLoopStmt.body) {
      stmt.accept(this);
    }
    return null;
  }
}

extension Truthy on Object? {
  bool get isTruthy => switch (this) {
    final LuaObject obj => obj.isTruthy,
    false || null => false,
    _ => true,
  };
}
