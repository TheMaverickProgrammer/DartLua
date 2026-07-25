import 'dart:io';

import 'package:puredartlua/lua/lua.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:puredartlua/utils.dart';

class ExpectationLine {
  final int line;
  final String captured;
  ExpectationLine(this.line, this.captured);
}

/// Parses input text to find lines matching the pattern
/// "-- Expect: x" and extracts the value 'x'.
///
/// The pattern is case-sensitive regarding "Expect: " but ignores
/// leading whitespace.
class ExpectationParser {
  static final RegExp _pattern =
    RegExp(r'^\s*--\s*Expect:\s*(.*)$', caseSensitive: false);

  /// Takes file contents as a string and
  /// returns a list of captured expectations.
  static List<ExpectationLine> parse(String content) {
    final List<String> lines = content.split('\n');
    final results = <ExpectationLine>[];
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final match = _pattern.firstMatch(line);
      if (match != null) {
        String? captured = match.group(1)?.trim();
        if (captured != null && captured.isNotEmpty) {
          if(captured == '\\n') captured = '\n';
          results.add(ExpectationLine(i+1, captured));
        }
      }
    }
    return results;
  }
}

bool runTest(String path) {
  bool ok = true;
  try {
    final String content = File(path).readAsStringSync();

    final AST? ast = parse(content);
    if(ast == null) {
      print('AST was null!');
      return false;
    }
    final Evaluator evaluator = Evaluator();
    ok = runner(ast, constructor: () => evaluator);

    if(!ok) {
      print(evaluator.errors.join('\n'));
      return false;
    }

    print('--- Test Results ---');

    final List<ExpectationLine> expected = ExpectationParser.parse(content);
    final int outLen = evaluator.impl.stdOut.length;
    final int expLen = expected.length;

    for(int i = 0; i < expLen; i++) {
      final int line = expected[i].line;
      final String e = expected[i].captured;
      final String o = switch(i < outLen) {
        true => evaluator.impl.stdOut[i],
        false => 'N/A'
      };

      if(e.compareTo(o) != 0) {
        print('[Line $line] Expected "$e". Was "$o".');
        ok = false;
      }
    }
  } catch (e) {
    print(e.toString());
    ok = false;
  }

  if(ok) print('OK');

  return ok;
}

void main() {
  test('simple assignment', () {
    expect(runTest('./test/assets/assignment.lua'), true);
  });

  test('multi value assignment', () {
    expect(runTest('./test/assets/multivalues.lua'), true);
  });

  test('scope', () {
    expect(runTest('./test/assets/scope.lua'), true);
  });

  test('globals, _ENV, and _G', () {
    expect(runTest('./test/assets/globals.lua'), true);
  });

  test('basic tables', () {
    expect(runTest('./test/assets/tables.lua'), true);
  });

  test('bitops', () {
    expect(runTest('./test/assets/bitops.lua'), true);
  });

  test('basic for loops', () {
    expect(runTest('./test/assets/for_loop.lua'), true);
  });

  test('while loops', () {
    expect(runTest('./test/assets/while_loops.lua'), true);
  });

  group('metamethods', () {
    final dir = './test/assets/metamethods';

    test('__add', () {
      expect(runTest('$dir/__add.lua'), true);
    });

    test('__concat', () {
      expect(runTest('$dir/__concat.lua'), true);
    });
  });

  test('coroutines', () {
    expect(runTest('./test/assets/coroutines.lua'), true);
  });
}
