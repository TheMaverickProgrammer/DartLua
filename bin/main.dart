import 'package:puredartlua/lua/visitors/transformers/visualizer.dart';
import 'package:puredartlua/runner.dart';
import 'package:path/path.dart' as p;
import 'package:puredartlua/lua/visitors/transformers/obfuscator.dart';

/// Show the help dialog.
void help() {
  print('''  -h            Show help.
  -e <PATH>     Execute script at PATH.
  -v <PATH>     Generate DOT file HTML for input at PATH.
  -f <PATH>     Outputs obfuscated script at PATH with prefix "fog".
  [ARG1...ARGN] Space separated args for IO input.
	''');
}

/// Standard libs prelude for the obfuscation option.
const stdLibsPrelude = [
  'rawget',
  'rawset',
  'rawequal',
  'math',
  'next',
  'ipairs',
  'pairs',
  'table',
  'print',
  'type',
  'string',
  'coroutine',
  'setmetatable',
  'getmetatable',
  'tostring',
  'tonumber',
];

/// Pipe each string in [errs] to [print].
void onErrors(List<String> errs) => errs.forEach(print);

/// This driver runs lua scripts given by path in `-e` and accepts input arguments.
/// Generate helpful DOT file graphs in HTML with `-v` command.
/// Print help menu by running with `-h`.
void main(List<String> args) {
  // Help user.
  if (args.isEmpty || args.first == '-h') {
    help();
    return;
  }

  // Check for -v flag.
  int idx = args.indexWhere((e) => e == '-v');
  if (idx > -1) {
    if (idx + 1 == args.length) {
      print('Missing script input with flag -e.');
      return;
    }

    final path = args[++idx];
    final ast = parseFile(path);

    // Abort early on error.
    if (ast == null) return;

    final viz = Visualizer(path);
    final dotfile = viz.generateHTML(ast);
    final File file = File.fromUri(Uri.file('$path.html', windows: true));
    file.writeAsStringSync(dotfile);

    // Done.
    return;
  }

  // Check for -f flag.
  // Both -f and -e flags have similar code paths and requirements
  // so they share the mechanics below.
  final bool obfuscate = args[idx + 1] == '-f';

  if (!obfuscate) {
    // Check for -e flag.
    if (args[idx + 1] != '-e') {
      print('Missing script input with flag -e.');
      return;
    }
  }

  idx++;

  final String path = args[++idx];
  AST? ast;
  try {
    // Try to construct an AST.
    ast = parseFile(path);
    if (ast == null) return;

    if (obfuscate) {
      final obf = Obfuscator(ast, prelude: stdLibsPrelude);

      /*
      // Useful for debugging.
      int line = 0;
      final s = obf.content.split('\n').map((e) => '[${++line}] $e').join('\n');
      print(s);
      */

      if (parse(obf.content) == null) {
        print(
          'There was a problem parsing the obfuscated contents. Send a report.',
        );
        return;
      }
      final parts = p.split(path);
      parts[parts.length - 1] = 'fog.${parts.last}';
      final fogPath = p.joinAll(parts);
      final file = File(fogPath);
      file.writeAsStringSync(obf.content);
      print('Write OK $fogPath');
      // Done.
      return;
    }

    // Code path for script evaluation reached.
    // Collect inut arguments and pass them into the runner constructor.
    final List<String> input = args.sublist(idx, args.length);

    make() {
      final evaluator = Evaluator();

      evaluator.impl.defGlobal(
        LuaObject.tableFrom('arg', [
          for (int i = 0; i < input.length; i++) input[i].toLua('$i'),
        ]),
      );

      return evaluator;
    }

    // Interpret by walking the AST.
    runner(ast, constructor: make, onErrors: onErrors);
  } catch (e) {
    // Print any system file errors.
    print(e);
    return;
  }
}
