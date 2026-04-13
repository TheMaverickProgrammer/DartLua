import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/passes/parser.dart';
import 'dart:io';
import 'evaluator.dart';

bool displayStdErr(List<String> errs, {required String verb}) {
  for (final String s in errs) {
    print(s);
  }

  if (errs.isNotEmpty) {
    print('${errs.length} errors while $verb script.');
    return true;
  }

  return false;
}

bool runner(String path) {
  final File file = File(path);
  final String content = file.readAsStringSync();

  final Lexer lexer = Lexer.tokenize(content);

  if (displayStdErr(lexer.errors, verb: 'tokenizing')) return false;

  final Parser parser = Parser(lexer.tokens);
  final ast = parser.analyze();

  if (displayStdErr(parser.errors, verb: 'parsing')) return false;

  final Evaluator eval = Evaluator();
  final out = eval.visitAST(ast);

  if (displayStdErr(eval.errors, verb: 'running')) return false;
  if (out != null) print(out.toString());
  return true;
}
