import 'package:puredartlua/lua/visitors/visualizer.dart';
import 'package:puredartlua/runner.dart';

void help() {
  print('''  -h            Show help.
  -e <PATH>     Execute script at PATH.
  -v <PATH>     Generate DOT file HTML for input <PATH>.
  [ARG1...ARGN] Space separated args for IO input.
	''');
}

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
  int idx = args.indexWhere((e) => e.contains('-v'));
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

  // Check for -e flag.
  idx = args.indexWhere((e) => e.contains('-e'));
  if (idx == -1 || idx + 1 == args.length) {
    print('Missing script input with flag -e.');
    return;
  }

  final String path = args[++idx];
  try {
    // Try to construct an AST.
    final ast = parseFile(path);
    if (ast == null) return;

    final List<String> input = args.sublist(idx, args.length);

    make() {
      final evaluator = Evaluator();

        evaluator.impl.defGlobal(
          LuaObject.tableFrom('arg',
          [ for(int i = 0; i < input.length; i++) input[i].toLua('$i') ]
        ));

      return evaluator;
    }
    // Interpret by walking the AST.
    runner(ast, constructor: make);
  } catch (e) {
    // Print any run-time errors.
    print(e);
    return;
  }
}
