import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:puredartlua/utils.dart';

void main() {
  test('basic for loops', () {
    expect(run(parse('./test/assets/for_loop.lua')!), true);
  });

  test('while loops', () {
    expect(run(parse('./test/assets/while_loops.lua')!), true);
  });

  test('simple assignment', () {
    expect(run(parse('./test/assets/assignment.lua')!), true);
  });

  test('multi value assignment', () {
    expect(run(parse('./test/assets/multivalues.lua')!), true);
  });

  test('scope', () {
    expect(run(parse('./test/assets/scope.lua')!), true);
  });

  test('basic tables', () {
    expect(run(parse('./test/assets/tables.lua')!), true);
  });

  test('bitops', () {
    expect(run(parse('./test/assets/bitops.lua')!), true);
  });

  test('coroutines', () {
    expect(run(parse('./test/assets/coroutines.lua')!), true);
  });
}
