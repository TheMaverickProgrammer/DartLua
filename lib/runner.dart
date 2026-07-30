import 'package:puredartlua/lua/lua.dart';
import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/passes/parser.dart';
import 'dart:io';

import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';

export 'package:puredartlua/lua/lua.dart';
export 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
export 'dart:io';

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

/// Reads a [File] at [path] and calls [parse].
AST? parseFile(String path) =>
  parse(File(path).readAsStringSync());

/// Reads the lua file at [path].
/// If there was an error, calls [displayStdErr] an returns null.
/// Otherwise returns the constructed [AST].
AST? parse(String content) {
  final Lexer lexer = Lexer.tokenize(content)..dropComments();

  if (displayStdErr(lexer.errors, verb: 'tokenizing')) return null;

  final Parser parser = Parser(lexer.tokens);
  final ast = parser.analyze();

  if (displayStdErr(parser.errors, verb: 'parsing')) return null;

  return ast;
}

/// Creates an evaluator satisfying [EvaluatorMixin] via [constructor].
/// Then passes [ast] into [EvaluatorMixin.visitAST] to parse
/// and evaluate the scriptlet or program.
///
/// If there was an error returns false.
/// On complete, returns a tuple [(bool, LuaObject)] containing the result, if any.
/// If the result would be [null], then returns an instance of [LuaObject.nil].
(bool, LuaObject) runner(AST ast, {required EvaluatorMixin Function() constructor}) {
  final eval = constructor.call();
  final out = eval.visitAST(ast);

  if (displayStdErr(eval.errors, verb: 'running')) return (false, LuaObject.nil('out'));

  return (true, out?.toLua('out') ?? LuaObject.nil('out'));
}

/// Implementation over [runner] uses [Evaluator] machinery for the runtime.
(bool, LuaObject) run(AST ast) => runner(ast, constructor: () => Evaluator());

