import 'runner.dart';

void help() {
  print('''
	-h            Show help.
        -e <PATH>     Execute script at PATH.
        [ARG1...ARGN] Space separated args for IO input.
	''');
}

void main(List<String> args) {
  if (args.isEmpty || args.first == '-h') {
    help();
    return;
  }

  int idx = args.indexWhere((e) => e.contains('-e'));
  if (idx == -1 || idx + 1 == args.length) {
    print('Missing script input with flag -e.');
    return;
  }

  final String path = args[++idx];

  // ignore: unused_local_variable
  final List<String> input = args.sublist(++idx, args.length);

  try {
    runner(path);
  } catch (e) {
    print(e);
    return;
  }
}
