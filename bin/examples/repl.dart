import 'dart:convert';
import 'package:puredartlua/runner.dart';

/// Custom error handlers can act on reported problems however you want.
/// In this example, we just print to conslole via [print].
void handleErrors(List<String> errs) => errs.forEach(print);

/// This example driver demonstrates a very simple REPL interpreter.
/// Read Evaluate Print Loop.
void main() {
  final evaluator = Evaluator();
  print('Press enter to continue on next line.');
  print('Blank lines terminates input.');
  print('Type "exit" to quit.');
  print('Type "dump_scope" to write the global scope to console.');
  print('-------------------');
  String content = '';
  bool loop = true;
  while (loop) {
    stdout.add('\$ '.codeUnits);
    final String input = stdin.readLineSync(encoding: utf8)?.trim() ?? '';

    if (input.isNotEmpty) {
      if(content.isEmpty) {
        // Two special commands take priority:
        // If 'exit' => quit REPL
        // If 'dump_scope' => print the current scope to console.
        // Else => evaluate string as lua script.
        switch (input.toLowerCase()) {
          case 'exit':
            loop = false;
            continue;
          case 'dump_scope':
            evaluator.impl.scope.dump();
            content = '';
            continue;
        }
      }
      // Stitch the lines together.
      content += '$input\n';
      continue;
    } else {
      content += input;
    }

    // Try to parse and consume the input we built.
    final ast = parse(content, onErrors: handleErrors);
    content = '';

    // Errors will already be collected. We cannot execute without a valid AST.
    if (ast == null) continue;

    // Run with a custom evaluator that clears previous results each
    // time the constructor is called.
    final (_, out) = runner(
      ast,
      constructor: () => evaluator..clearResults(),
      onErrors: handleErrors,
    );

    // Display to user in console.
    print(out);
  }
}
