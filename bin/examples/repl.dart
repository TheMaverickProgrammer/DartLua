import 'dart:convert';
import 'package:puredartlua/runner.dart';

/// This example driver demonstrates a very simple lua interpreter.
/// Read Evaluate Print Loop.
/// Enter "exit" to quit.
void main() {
  final evaluator = Evaluator();

  while(true) {
    final String input = stdin.readLineSync(encoding: utf8)?.trim().toLowerCase() ?? '';
    if(input == 'exit') break;

    final ast = parse(input);
    if(ast == null) continue;

    final (ok, out) = runner(ast, constructor: () => evaluator..clearResults());
    print(out);
  }
}