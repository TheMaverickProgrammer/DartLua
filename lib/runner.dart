import 'package:puredartlua/lua/lua.dart';
import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/passes/parser.dart';
import 'dart:io';

import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';

export 'package:puredartlua/lua/lua.dart';
export 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
export 'dart:io';

typedef RunnerErrorsCallback = void Function(List<String>);

/// Reads a [File] at [path] and calls [parse].
/// Forwards [onErrors] to [parse].
AST? parseFile(String path, {RunnerErrorsCallback? onErrors}) =>
    parse(File(path).readAsStringSync(), onErrors: onErrors);

/// Reads the lua file at [path].
/// If there was an error, calls [onErrors] with those errors
/// and returns null.
/// Otherwise returns the constructed [AST].
AST? parse(String content, {RunnerErrorsCallback? onErrors}) {
  final Lexer lexer = Lexer.tokenize(content)..dropComments();

  if (lexer.errors.isNotEmpty) {
    onErrors?.call(lexer.errors);
    return null;
  }

  final Parser parser = Parser(lexer.tokens);
  final ast = parser.analyze();

  if (parser.errors.isNotEmpty) {
    onErrors?.call(parser.errors);
    return null;
  }

  return ast;
}

/// Creates an evaluator satisfying [EvaluatorMixin] via [constructor].
/// Then passes [ast] into [EvaluatorMixin.visitAST] to parse
/// and evaluate the scriptlet or program.
///
/// Returns a tuple [(bool, LuaObject)] containing the result, if any.
/// If there was an error returns a tuple [(false, LuaObject.nil)].
/// Additionally, the [onErrors] callback will be invoked with those errors.
/// If the result would be [null], then returns an instance of [LuaObject.nil].
(bool, LuaObject) runner(
  AST ast, {
  required EvaluatorMixin Function() constructor,
  RunnerErrorsCallback? onErrors,
}) {
  final eval = constructor.call();
  final out = eval.visitAST(ast);

  if (eval.errors.isNotEmpty) {
    onErrors?.call(eval.errors);
    return (false, LuaObject.nil('out'));
  }

  return (true, out?.toLua('out') ?? LuaObject.nil('out'));
}

/// Implementation over [runner] uses [Evaluator] machinery for the runtime.
/// Uses [print] for the default [RunnerErrorsCallback] value if not provided.
(bool, LuaObject) run(AST ast, {RunnerErrorsCallback? onErrors}) => runner(
  ast,
  constructor: () => Evaluator(),
  onErrors: onErrors ?? (errs) => errs.forEach(print),
);
