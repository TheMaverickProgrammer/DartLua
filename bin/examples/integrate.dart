import 'package:puredartlua/runner.dart';

/// This example driver shows the user how to define custom methods in dart,
/// run lua programs calling custom methods,
/// and find the result from lua back to dart.
void main() {
  final evaluator = Evaluator();

  final addOne = LuaFuncBuilder.create('add_one')
      .arg('n')
      .exec(
        call: () {
          final n = evaluator.findVar('n')?.valueAsInt() ?? 0;
          return n + 1;
        },
      );

  evaluator.defGlobal(addOne);

  runner(parse("x = add_one(6)")!, constructor: () => evaluator);

  int? result = evaluator.findVar('x')?.valueAsInt();

  // Prints: 7
  print(result);
}
