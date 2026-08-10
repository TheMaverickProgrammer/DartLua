import 'dart:convert';
import 'package:puredartlua/runner.dart';

/// This example driver demonstrates a very simple REPL interpreter.
/// Read Evaluate Print Loop.
void main() {
  final evaluator = Evaluator();
  print('Inputs ending with "\\" continue next line.');
  print('Type "exit" to quit.');
  print('Type "dump_scope" to write the global scope to console.');
  print('-------------------');
  String content = '';
  bool loop = true;
  while (loop) {
    stdout.add('\$ '.codeUnits);
    final String input = stdin.readLineSync(encoding: utf8)?.trim() ?? '';

    if (input.endsWith('\\')) {
      // Stitch the lines together.
      content += '${input.substring(0, input.length - 1)}\n';
      continue;
    } else {
      content += input;
    }

    switch (content.toLowerCase()) {
      case 'exit':
        loop = false;
        continue;
      case 'dump_scope':
        evaluator.impl.scope.dump();
        content = '';
        continue;
    }

    final ast = parse(content, onErrors: (errs) => errs.forEach(print));
    content = '';
    if (ast == null) continue;

    final (ok, out) = runner(
      ast,
      constructor: () => evaluator..clearResults(),
      onErrors: (errs) => errs.forEach(print),
    );
    print(out);
  }
}
