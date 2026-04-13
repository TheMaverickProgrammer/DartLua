import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import '../bin/runner.dart';

void main() {
  test('basic for loops', () {
    expect(runner('./test/assets/for_loop.lua'), true);
  });

  test('assignment', () {
    expect(runner('./test/assets/hello_world.lua'), true);
  });

  test('scope', () {
    expect(runner('./test/assets/scope.lua'), true);
  });

  test('basic tables', () {
    expect(runner('./test/assets/tables.lua'), true);
  });
}
