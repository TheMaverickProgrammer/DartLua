import 'dart:io';

import 'package:puredartlua/lua/visitors/visualizer.dart';

import 'runner.dart';

void help() {
  print('''
	-h            Show help.
  -e <PATH>     Execute script at PATH.
  -v <PATH>     Generate DOT file HTML for input <PATH>.
  [ARG1...ARGN] Space separated args for IO input.
	''');
}

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
    final ast = parse(path);

    // Abort early on error.
    if (ast == null) return;

    final viz = Visualizer();
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

  // ignore: unused_local_variable
  final List<String> input = args.sublist(++idx, args.length);

  try {
    // Try to construct an AST.
    final ast = parse(path);
    if (ast == null) return;

    // Interpret by walking the AST.
    runner(ast);
  } catch (e) {
    // Print any run-time errors.
    print(e);
    return;
  }
}
