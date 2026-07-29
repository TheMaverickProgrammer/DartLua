import 'dart:convert';
import 'package:puredartlua/runner.dart';

/// This example driver demonstrates a very simple REPL interpreter.
/// Read Evaluate Print Loop.
void main() {
  final evaluator = Evaluator();
  print('Inputs ending with "\\" continue next line.');
  print('Type "exit" to quit.');
  print('-------------------');
  String content = '';
  while (true) {
    stdout.add('\$ '.codeUnits);
    final String input =
        stdin.readLineSync(encoding: utf8)?.trim().toLowerCase() ?? '';

    if (input.endsWith('\\')) {
      // Stitch the lines together.
      content += '${input.substring(0, input.length - 1)}\n';
      continue;
    } else {
      content += input;
    }

    if (content == 'exit') break;

    final ast = parse(content);
    content = '';
    if (ast == null) continue;

    final (ok, out) = runner(ast, constructor: () => evaluator..clearResults());
    print(out);
  }
}
