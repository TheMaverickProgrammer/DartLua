import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/bindings/std.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

class RuntimeResults extends BaseResults {}

class Evaluator {
  final results = RuntimeResults();
  late final impl = _EvalImpl(results);

  List<String> get errors => results.errors.toList();
  Object? visitAST(AST ast) => impl.visitAST(ast);
}

class _EvalImpl extends BaseRuntime with Std {
  _EvalImpl(RuntimeResults super.results) {
    initStdRuntime();
    initStdPrint(impl: (str) => print(str));
  }
}
