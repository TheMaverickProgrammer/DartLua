import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/passes/parser.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';
import 'dart:io';
import 'evaluator.dart';

/// Prints [errs] using [verb] for readability.
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

/// Reads the lua file at [path].
/// If there was an error, calls [displayStdErr] an returns null.
/// Otherwise returns the constructed [AST].
AST? parse(String path) {
  final File file = File(path);
  final String content = file.readAsStringSync();

  final Lexer lexer = Lexer.tokenize(content);

  if (displayStdErr(lexer.errors, verb: 'tokenizing')) return null;

  final Parser parser = Parser(lexer.tokens);
  final ast = parser.analyze();

  if (displayStdErr(parser.errors, verb: 'parsing')) return null;

  return ast;
}

/// Build an [AST] to pass in with [parse].
/// If there was an error returns false.
/// On complete, returns true.
bool runner(AST ast) {
  final Evaluator eval = Evaluator();
  final out = eval.visitAST(ast);

  if (displayStdErr(eval.errors, verb: 'running')) return false;
  if (out != null) print(out.toString());

  return true;
}
