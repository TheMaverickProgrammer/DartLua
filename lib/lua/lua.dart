import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/bindings/std.dart';
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

// AST is as common as the Evaluator.
export 'package:puredartlua/lua/visitors/visitor.dart';

/// A very simple LUA evaluator using
/// a basic implementation of the standard
/// runtime [StdRuntime]. Can be used
/// whereever [EvaluatorMixin] is expected.
/// If someone wants to get started using this library
/// this is what they want to use.
class Evaluator with EvaluatorMixin {
  final results = StdRuntimeResults();
  late final impl = StdRuntime(results);

  @override
  List<String> get errors => results.errors.toList();

  @override
  Object? visitAST(AST ast) => impl.visitAST(ast);
}

/// Enables any class inheritting [BaseRuntime] to be made
/// available as a public-facing runtime API.
mixin EvaluatorMixin {
  List<String> get errors;
  Object? visitAST(AST ast);
}

/// Standard runtime results collects no special information.
class StdRuntimeResults extends BaseResults {}

/// Implement the standard runtime. Initialize the libraries
/// we are interested in using.
class StdRuntime extends BaseRuntime with Std, ReturnStmtCallStackUnwind {
  final Map<int, LuaObject> _cos = {};
  final Map<int, LuaThreadStatus> _statuses = {};
  final Map<int, ControlStructure?> _ctrls = {};

  int _nextAddr = 0x01;
  int _currAddr = 0x00;

  StdRuntime(StdRuntimeResults super.results) {
    initStdRuntime();
    initStdPrint(impl: (str) => print(str));
    initStdCoroutines(
      impl: CoroutineCallbacks(
        onCoroutineCreate: _onCoroutineCreate,
        onCoroutineResume: _onCoroutineResume,
        onCoroutineStatus: _onCoroutineStatus,
        onCoroutineYield: _onCoroutineYield,
      ),
    );
  }

  int _onCoroutineCreate(LuaObject fn) {
    _cos[_nextAddr] = fn;
    _statuses[_nextAddr] = LuaThreadStatus.suspended;
    return _nextAddr++;
  }

  String _onCoroutineStatus(int addr) {
    if (!_statuses.containsKey(addr)) {
      throw 'No such coroutine with address $addr.';
    }

    return _statuses[addr].toString();
  }

  LuaObject _onCoroutineResume(int addr, List<LuaObject> vargs) {
    if (!_cos.containsKey(addr)) {
      throw 'No such coroutine with address $addr.';
    }

    final fn = _cos[addr]!;
    _currAddr = addr;

    if (_ctrls.containsKey(_currAddr)) {
      // Resume the coroutine.
      // Grab the most relevant control structure in the AST
      // and revisit it.
      final cs = _ctrls[_currAddr]!;

      ControlStructure? prev = ctrlStruct;
      bool canResume = true;
      try {
        ctrlStruct = cs;
        final _ = switch (cs.node) {
          final FuncExpr f => f.accept(this),
          final ForLoopStmt f => f.accept(this),
          final ForIterLoopStmt f => f.accept(this),
          final WhileLoopStmt w => w.accept(this),
          final RepeatUntilLoopStmt r => r.accept(this),
          final Object o =>
            throw 'Unsuspending unknown control structure ${o.runtimeType}',
        };
      } catch (e) {
        if (e is LuaReturnValueException) {
          return e.value;
        }
        addError(e.toString());
        canResume = false;
      } finally {
        ctrlStruct = prev;
      }

      // Return if successfully resumed.
      return canResume.toLuaRet();
    }

    // Else, start the coroutine for the first time.
    LuaObject? ret = callLuaFunction(fn, args: vargs);
    return ret ?? LuaObject.nil('ret');
  }

  void _onCoroutineYield(List<LuaObject> args) {
    if (!_statuses.containsKey(_currAddr)) {
      throw 'No running coroutine to yield from.';
    }
    _ctrls[_currAddr] = ctrlStruct;

    _currAddr = 0x00;
    throw LuaReturnValueException(LuaObject.tableFrom('yield_ret', args));
  }
}
