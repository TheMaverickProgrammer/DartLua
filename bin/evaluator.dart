import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/bindings/std.dart';

class RuntimeResults extends BaseResults { }

class Evaluator {
	final results = RuntimeResults();
	late final impl = _EvalImpl(results);

	List<String> get errors => results.errors.toList();
	Object? visitAST(ast) => impl.visitAST(ast);
}

class _EvalImpl extends BaseRuntime with Std {
	_EvalImpl(RuntimeResults results) : super(results) {
		initStdRuntime();
		initStdPrint(impl: (str) => print(str));
	}
}
