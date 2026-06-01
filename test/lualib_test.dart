import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import '../bin/runner.dart';

void main() {
  test('basic for loops', () {
    expect(runner(parse('./test/assets/for_loop.lua')!), true);
  });

  test('assignment', () {
    expect(runner(parse('./test/assets/hello_world.lua')!), true);
  });

  test('scope', () {
    expect(runner(parse('./test/assets/scope.lua')!), true);
  });

  test('basic tables', () {
    expect(runner(parse('./test/assets/tables.lua')!), true);
  });

  test('coroutines', () {
    expect(runner(parse('./test/assets/coroutines.lua')!), true);
  });
}
