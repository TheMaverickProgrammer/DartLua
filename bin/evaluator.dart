import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/bindings/std.dart';
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

/// Implement our runtime results.
/// If we needed to collect runtime data, we can
/// do so here.
class RuntimeResults extends BaseResults {}

/// Use our runtime implementation and visit the AST.
/// This is our public-facing runtime proxy.
class Evaluator {
  final results = RuntimeResults();
  late final impl = _EvalImpl(results);

  List<String> get errors => results.errors.toList();
  Object? visitAST(AST ast) => impl.visitAST(ast);
}

/// Implement our runtime. Initialize the libraries
/// we are interested in using.
class _EvalImpl extends BaseRuntime with Std, ReturnStmtCallStackUnwind {
  final Map<int, LuaObject> _cos = {};
  final Map<int, LuaThreadStatus> _statuses = {};
  int _nextAddr = 0x01;
  int _currAddr = 0x00;

  _EvalImpl(RuntimeResults super.results) {
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

    LuaObject? ret;

    // Simulate lua protected mode. Errors are not propogated up.
    onException(e) {
      if (e is LuaReturnValueException) {
        ret = e.value;
      } else {
        addError(e.toString());
      }
    }

    // Note we only set ret if not set by the exception handler.
    ret ??= callLuaFunction(fn, args: vargs, onException: onException);

    return ret ?? LuaObject.nil('ret');
  }

  void _onCoroutineYield(List<LuaObject> args) {
    if (!_statuses.containsKey(_currAddr)) {
      throw 'No running coroutine to yield from.';
    }

    _currAddr = 0x00;
    throw LuaReturnValueException(LuaObject.tableFrom('yield_ret', args));
  }
}
