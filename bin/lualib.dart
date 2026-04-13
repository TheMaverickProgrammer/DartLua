import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/passes/parser.dart';
import 'package:puredartlua/lua/lua.dart';
import 'dart:io';
import 'evaluator.dart';

void help() {
	print(
	'''
	-h            Show help.
        -e <PATH>     Execute script at PATH.
        [ARG1...ARGN] Space separated args for IO input.
	'''
	);
}

bool displayStdErr(List<String> errs, {required String verb}) {
	for(final String s in errs) {
		print(s);
	}
	
	if(errs.isNotEmpty) {
		print('${errs.length} errors while $verb script.');
		return true;
	}
	
	return false;
}

void main(List<String> args) {
  if(args.isEmpty || args.first == '-h') {
	help();
	return;
  }

  int idx = args.indexWhere((e) => e.contains('-e'));
  if(idx == -1 || idx+1 == args.length) {
       print('Missing script input with flag -e.');
       return;
  }

  final String path = args[++idx];
  final List<String> input = args.sublist(++idx, args.length);

  final File file = File(path);
  final String content;

  try {
	content = file.readAsStringSync();
  } catch(e) {
	print('File not found: $path');
	return;
  }

  final Lexer lexer = Lexer.tokenize(content);

  if(displayStdErr(lexer.errors, verb: 'tokenizing')) return;

  final Parser parser = Parser(lexer.tokens);
  final ast = parser.analyze();

  if(displayStdErr(parser.errors, verb: 'parsing')) return;

  final Evaluator eval = Evaluator();
  final out = eval.visitAST(ast);

  if(displayStdErr(eval.errors, verb: 'running')) return;
  if(out != null) print(out.toString());  
}
