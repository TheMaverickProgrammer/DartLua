import 'dart:typed_data';

import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/passes/parser.dart';
import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

typedef Scripts2Bytes = Map<String, Uint8List>;

AST? readLuaAST(BaseResults results, Uint8List content) {
  final buffer = String.fromCharCodes(content);
  final Lexer t;

  try {
    t = Lexer.tokenize(buffer)
      ..dropComments()
      ..dropSemicolons();
  } catch (e) {
    results.addError(e.toString());
    return null;
  }

  // final int len = t.tokens.length;
  // for(int i = 0; i < len; i++) {
  //   final token = t.tokens[i];
  //   print('[$i]: $token');
  // }

  results.addAllErrors(t.errors);

  final Parser checker = Parser(t.tokens);
  final AST ast = checker.analyze();

  if (checker.errors.isNotEmpty) {
    results.addAllErrors(checker.errors);

    // Do not try to recover from errors.
    return null;
  }

  if (checker.warns.isNotEmpty) {
    results.addAllWarnings(checker.warns);
  }

  /*
  final Pretty printer = Pretty();
  final String content = printer.visitAST(ast);
  final String output = colorize(content);
  print(output);
  */

  return ast;
}
