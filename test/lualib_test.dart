import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:puredartlua/runner.dart';

/// A simple utility class for holding the location
/// of the expectation [line] and the content [captured].
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
  static final RegExp _pattern = RegExp(
    r'^\s*--\s*Expect:\s*(.*)\r?$',
    caseSensitive: false,
  );

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
          if (captured == '\\n') captured = '\n';
          results.add(ExpectationLine(i + 1, captured));
        }
      }
    }
    return results;
  }
}

/// Handles the setup and execution of the test suite.
/// It loads a file, parsees the lua [AST], and calls
/// [runner] with a custom [Evaluator] so we can read
/// values collected during execution.
bool runTest(String path) {
  bool ok = true;
  try {
    final String content = File(path).readAsStringSync();

    final AST? ast = parse(content);
    if (ast == null) {
      print('AST was null!');
      return false;
    }
    final Evaluator evaluator = Evaluator();
    (ok, _) = runner(ast, constructor: () => evaluator);

    if (!ok) {
      print(evaluator.errors.join('\n'));
      return false;
    }

    print('--- Test Results ---');

    final List<ExpectationLine> expected = ExpectationParser.parse(content);
    final int outLen = evaluator.impl.stdOut.length;
    final int expLen = expected.length;

    for (int i = 0; i < expLen; i++) {
      final int line = expected[i].line;
      final String e = expected[i].captured;
      final String o = switch (i < outLen) {
        true => evaluator.impl.stdOut[i],
        false => 'N/A',
      };

      if (e.compareTo(o) != 0) {
        print('[Line $line] Expected "$e". Was "$o".');
        ok = false;
      }
    }
  } catch (e) {
    print(e.toString());
    ok = false;
  }

  if (ok) print('OK');

  return ok;
}

void main() {
  test('simple assignment', () {
    expect(runTest('./test/assets/pass/assignment.lua'), true);
  });

  test('multi value assignment', () {
    expect(runTest('./test/assets/pass/multivalues.lua'), true);
  });

  test('scope', () {
    expect(runTest('./test/assets/pass/scope.lua'), true);
  });

  test('globals, _ENV, and _G', () {
    expect(runTest('./test/assets/pass/globals.lua'), true);
  });

  test('basic tables', () {
    expect(runTest('./test/assets/pass/tables.lua'), true);
  });

  test('bitops', () {
    expect(runTest('./test/assets/pass/bitops.lua'), true);
  });

  test('basic for loops', () {
    expect(runTest('./test/assets/pass/for_loop.lua'), true);
  });

  test('while loops', () {
    expect(runTest('./test/assets/pass/while_loops.lua'), true);
  });

  test('functions', () {
    expect(runTest('./test/assets/pass/functions.lua'), true);
  });

  test('pcall', () {
    expect(runTest('./test/assets/pass/pcall.lua'), true);
  });

  test('coercion', () {
    expect(runTest('./test/assets/pass/coercion.lua'), true);
  });

  test('currying', () {
    expect(runTest('./test/assets/pass/currying.lua'), true);
  });

  group('metamethods', () {
    final dir = './test/assets/pass/metamethods';

    test('__call', () {
      expect(runTest('$dir/__call.lua'), true);
    });

    test('__eq', () {
      expect(runTest('$dir/__eq.lua'), true);
    });

    test('__lt', () {
      expect(runTest('$dir/__lt.lua'), true);
    });

    test('__le', () {
      expect(runTest('$dir/__le.lua'), true);
    });

    test('__add', () {
      expect(runTest('$dir/__add.lua'), true);
    });

    test('__sub', () {
      expect(runTest('$dir/__sub.lua'), true);
    });

    test('__mul', () {
      expect(runTest('$dir/__mul.lua'), true);
    });

    test('__div', () {
      expect(runTest('$dir/__div.lua'), true);
    });

    test('__idiv', () {
      expect(runTest('$dir/__idiv.lua'), true);
    });

    test('__pow', () {
      expect(runTest('$dir/__pow.lua'), true);
    });

    test('__mod', () {
      expect(runTest('$dir/__mod.lua'), true);
    });

    test('__shr', () {
      expect(runTest('$dir/__shr.lua'), true);
    });

    test('__shl', () {
      expect(runTest('$dir/__shl.lua'), true);
    });

    test('__concat', () {
      expect(runTest('$dir/__concat.lua'), true);
    });

    test('__len', () {
      expect(runTest('$dir/__len.lua'), true);
    });

    test('__unm', () {
      expect(runTest('$dir/__unm.lua'), true);
    });

    test('__band', () {
      expect(runTest('$dir/__band.lua'), true);
    });

    test('__bor', () {
      expect(runTest('$dir/__bor.lua'), true);
    });

    test('__bxor', () {
      expect(runTest('$dir/__bxor.lua'), true);
    });

    test('__bnot', () {
      expect(runTest('$dir/__bnot.lua'), true);
    });
  });

  test('coroutines', () {
    expect(runTest('./test/assets/pass/coroutines.lua'), true);
  });
}
