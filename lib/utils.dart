import 'package:colorize/colorize.dart';
import 'package:puredartlua/lua/lua.dart';
import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/passes/parser.dart';
import 'dart:io';

String green(Object obj) => obj.toString().green;
String yellow(Object obj) => obj.toString().yellow;
String red(Object obj) => obj.toString().red;
String blue(Object obj) => obj.toString().blue;
String magenta(Object obj) => obj.toString().magenta;

extension ColoredStrings on String {
  String get red => Colorize(this).red().toString();
  String get yellow => Colorize(this).yellow().toString();
  String get green => Colorize(this).green().toString();
  String get blue => Colorize(this).blue().toString();
  String get magenta => Colorize(this).magenta().toString();
}

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

/// Creates an evaluator satisfying [EvaluatorMixin] via [constructor].
/// Then passes [ast] into [EvaluatorMixin.visitAST] to parse
/// and evaluate the scriptlet or program.
///
/// If there was an error returns false.
/// On complete, returns true.
bool runner(AST ast, {required EvaluatorMixin Function() constructor}) {
  final eval = constructor.call();
  final out = eval.visitAST(ast);

  if (displayStdErr(eval.errors, verb: 'running')) return false;
  if (out != null) print(out.toString());

  return true;
}

/// Implementation over [runner] uses [Evaluator] machinery for the runtime.
bool run(AST ast) => runner(ast, constructor: () => Evaluator());

