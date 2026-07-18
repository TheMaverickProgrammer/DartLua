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
  final Map<int, CoCtrlStruct?> _ctrls = {};

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
        onCoroutinePopScope: _onCoroutinePopScope,
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

    if(_statuses[addr] == LuaThreadStatus.dead) {
      return LuaObject.table('co_ret', {
      '1': false,
      '2': 'Cannot resume dead coroutine.',
      });
    }

    final fn = _cos[addr]!;
    bool canResume = true;
    LuaObject? ret;

    _currAddr = addr;
    _statuses[_currAddr] = LuaThreadStatus.running;

    if (_ctrls.containsKey(_currAddr)) {
      // Resume the coroutine.
      // Grab the most relevant control structure in the AST
      // and revisit it.
      final cs = _ctrls[_currAddr]!;

      CoCtrlStruct? prev = coCtrlStruct;

      try {
        coCtrlStruct = cs;
        final _ = switch (cs.node) {
          final FuncExpr f => f.accept(this),
          final ForLoopStmt f => f.accept(this),
          final ForIterLoopStmt f => f.accept(this),
          final WhileLoopStmt w => w.accept(this),
          final RepeatUntilLoopStmt r => r.accept(this),
          final Object o =>
            throw 'Unsuspending unknown control structure ${o.runtimeType}',
        };
        canResume = false;
      } catch (e) {
        if (e is LuaReturnValueException) {
          ret = e.value;
        } else {
          ret = e.toString().toLua('error');
        }
      } finally {
        coCtrlStruct = prev;
      }
    } else {
      // Else, start the coroutine for the first time.
      ret = callLuaFunction(fn, args: vargs);
    }

    if(!canResume) {
      _statuses[_currAddr] = LuaThreadStatus.dead;
    }

    return LuaObject.table('co_ret', {
      '1': canResume,
      '2': ?ret,
    });
  }

  void _onCoroutineYield(List<LuaObject> args) {
    if (!_statuses.containsKey(_currAddr)) {
      throw 'No running coroutine to yield from.';
    }
    _ctrls[_currAddr] = coCtrlStruct?.copy();
    _statuses[_currAddr] = LuaThreadStatus.suspended;
    _currAddr = 0x00;
    throw LuaReturnValueException(LuaObject.tableFrom('yield_ret', args));
  }

  void _onCoroutinePopScope(CoCtrlStruct coCtrlStruct) {
    if (!_statuses.containsKey(_currAddr)) {
      return;
    }

    _ctrls[_currAddr] = coCtrlStruct.copy();
  }
}
