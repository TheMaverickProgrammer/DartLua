import 'package:puredartlua/docs/autodoc.dart';
import 'package:puredartlua/runner.dart';

/// This example driver shows the user how to
/// generate custom lua documentation.
void main() async {
  final evaluator = Evaluator();

  // This example shows how to use named arguments.
  final approximate = LuaFuncBuilder.create('approximate')
      .arg('a')
      .arg('b')
      .arg('epsilon')
      .exec(
        call: () {
          final a = evaluator.findVar('a')?.valueAs<num>();
          final b = evaluator.findVar('b')?.valueAs<num>();
          final e = evaluator.findVar('epsilon')?.valueAs<num>();

          if (a == null || b == null || e == null) {
            throw 'Function expects three values: a, b, and epsilon.';
          }

          return (a - b).abs() <= e;
        },
      );

  evaluator.defGlobal(approximate).doc = LuaDoc(
    category: 'My Math Library',
    html: '''
    Given two floating point numbers <code>a</code> and <code>b</code>,
    returns if they are approximate up to a difference of <code>epsilon</code>.
    ''',
  );

  // This example shows how to use var args.
  final avg = LuaFuncBuilder.create('average').varargs().exec(
    call: () {
      final ls = evaluator.findVarArgs();
      final prune = ls?.map((e) => e.valueAs<num>()).nonNulls ?? [];

      if (prune.isEmpty) return 0;
      return prune.reduce((v, n) => v + n) / prune.length.toDouble();
    },
  );

  evaluator.defGlobal(avg).doc = LuaDoc(
    category: 'My Math Library',
    html: '''
    This function takes a variadic list of numbers and
    calculates and returns the average.
    ''',
  );

  // This example shows how to exclude entries from the autodoc.
  evaluator.findVar('coroutine')?.doc = LuaDoc.skip();

  // Ensure the output directory exists first.
  try {
    await Directory('./docs').create();
    LuaAutoDoc(
      'PureDartLua AutoDoc Example',
      showSidebarIndex: true,
    ).generateDocs(evaluator.impl, outDir: './docs');
  } catch (e) {
    print('Failed to generate docs. $e');
    exit(1);
  }

  print('Generated html at ./docs/index.html');
}
