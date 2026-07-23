# PureDartLua

<!-- TOC -->
- [PureDartLua](#puredartlua)
  - [Getting Started](#getting-started)
    - [Run The Driver](#run-the-driver)
    - [Use In Your Own Code](#use-in-your-own-code)
    - [Custom Data](#custom-data)
  - [DOT File Visualizer](#dot-file-visualizer)
  - [All Features](#all-features)
- [Tests](#tests)
- [Work In Progress!](#work-in-progress)
  - [Missing Lua Lang Support](#missing-lua-lang-support)
  - [Extra Goals](#extra-goals)
<!-- /TOC -->

This is a custom a custom `Lua 5.5` interpreter and utilities written from scratch in pure Dart.
I wrote this as a part of a series of learning exercises on how to write my own compilers and programming languages.

## Getting Started
This package exports a full fledged library and a simple executable for running lua scripts.

### Run The Driver
To get started, run `bin/input.lua`. Everything after the file path is passed into the `run()`
starter as input arguments table `arg`.

```bash
dart bin/main.dart -e bin/input.lua hello world!
```

### Use In Your Own Code
It's easy. Just include the utilities file that includes default runtime behaviors and the Std library.

```dart
import 'package:puredartlua/utils.dart';

void main() {
  run(parse("print('hello, world!')")!);
}
```

This will execute and print `hello, world!` to the console.

### Custom Data
But you probably want to define your own tables and functions in lua. And probably read those
values back in dart too.

For this, you need a custom runtime via the `Evaluator` class and
use the specific `runner(AST, constructor)` utility function.

```dart
import 'package:puredartlua/utils.dart';

void main() {
  final evaluator = Evaluator();

  final add_one = LuaFuncBuilder.create('add_one')
          .arg('n')
          .exec(call: () {
            final n = findVar('n')?.valueAsInt() ?? 0;
            return n+1;
          });

  evaluator.defGlobal(add_one);

  runner(parse("x = add_one(5)")!, constructor: () => evaluator);

  int? result = evaluator.impl.globals.findVar('x')?.valueAsInt();

  // Do something with `result`.
}
```
See the implementation for the ready-to-use `Evaluator` class in [`lib/lua/lua.dart`](./lib/lua/lua.dart).

## DOT File Visualizer
Run

```bash
dart bin/main.dart -v my_script.lua
```

The DOT file will be embedded in an HTML page `my_script.lua.html`.

## All Features
- Command Line Interface (cli).
- MIT Licensed.
- No FFI or extra dependencies.
- DOT file visualiser.
- [Autodoc][AUTODOC] API so your own libs can generate docs to share with your consumers.
- Register your own custom runtime userdata.
- Emit custom warnings, diagnostic info, or errors.
- Aims to be Lua 5.5 compliant.
  - See this [section](#missing-lua-lang-support) for remaining issues.
- Parser, Evaluator, Interpreter classes extensible and modifiable.
- `Truthy` and `Native2Lua` Dart class extensions for convenient bridge between userdata and lua types.
- Function builder API to conveniently build complex lua functions.
- Standard lua runtime libs (partial implementation).
  - strings
  - include
  - ipairs
  - pairs
  - table
  - print
  - math

> Because this is a pure dart lua interpreter, it is not expected to be as fast
> as the C ffi alternative libs for Dart. However, it is much more programmer friendly!

# Tests
All tests are under the `/test/` directory. The driver is [`test/lualib_test.dart`](./test/lualib_test.dart).
The test scripts are under `/test/assets/`.

The driver uses a custom preflight setup that extracts every
comment of the form `-- Expected: ...` and compares the output in `Evaluator.impl.stdOut`. If the output
does not match the expected string, then it is an error. This allows the scripts to contain the data
needed for the checks without requiring additional setup.

For example:
```lua
-- This is why we're here.
local str = 'Hello, world'

-- Expect: Hello, world
print(str)

-- Testing variadic args in print.

-- Expect: 1 2 3 nil true
print(1, 2, 3, nil, true)

-- Expect: \n
print()

-- Expect: 1
print(1)
```

Running this test will result:
```lua
Hello, world
1 2 3 nil true
1
--- Test Results ---
OK
```

Note that your terminal (VSCode) may supress dart's `print(...)` newlines `\n` and empty string tokens `''`. The standard
lua `print(...)` method will capture these even if they do not show up in the terminal.

# Work In Progress!
I am using this in my own projects and as such I have not created tutorials or get started guides.
I will get around to that when I can!

## Missing Lua Lang Support
Here's what's left to be compliant with the `Lua 5.5` specification:
- Missing a semantics pass for `goto` and `::label::` statements.
- Metamethods.
  - Particularly there is no support for metamethods except for `___call`.
  - But metamethods are just function objects with a few places that lua calls as defined.
- `<const>` is not added.
- `Coroutines` library is added but the runtime needs bytecode to make use of it.
- Lua uses semicolons for grammar disambiguities. Semicolons are not in this implementation atm.
- Lua supports dropping the parenthesis for singular arg function args e.g. `print "hello!"`.

## Extra Goals
- Semantics: code path type unification.
  - `return` statements could have the function's final type identified.
  - Nondeterministic functions should be identified as such.
    - This would allow invariant code paths to be protomoted to constant value generation.

[AUTODOC]: ./lib/docs/autodoc.dart
