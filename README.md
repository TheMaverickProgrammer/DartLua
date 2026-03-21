# PureDartLua

- [PureDartLua](#puredartlua)
  - [Features](#features)
- [Work In Progress!](#work-in-progress)
  - [Missing Lua Lang Support](#missing-lua-lang-support)

This is a custom a custom `Lua 5.5` interpretter and evaluator written from scratch in pure Dart.
I wrote this as a part of a series of learning exercises on how to write my own compilers and programming languages.

## Features
- MIT Licensed.
- Register your own custom runtime userdata.
- No FFI or extra dependencies.
- Emit warnings, diagnostic info, or errors.
- Lua 5.5 compliant.
  - See this [section](#missing-lua-lang-support) for remaining issues.
- Parser, Evaluator, Interpreter classes you can extend or modify.
- `Truthy` and `Native2Lua` Dart class extensions.
  - Makes for convenient bridge between userdata and lua types.
- Standard lua runtime libs (partial implementation).
  - strings
  - include
  - ipairs
  - pairs
  - table
  - print
  - math
- [Autodoc][AUTODOC] API so your own libs can generate docs to share with your consumers.
- Function builder API to conveniently build complex lua functions.

> Because this is a pure dart lua interpreter, it is not expected to be as fast
> as the C ffi alternative libs for Dart. However, it is much more programmer friendly!

# Work In Progress!
I am using this in my own projects and as such I have not created tutorials or get started guides.
I will get around to that when I can!

## Missing Lua Lang Support
Here's what's left to be compliant with the `Lua 5.5` specification:
- Better callsite context evaluation.
  - Currently stuffing the `callee` into the scope's context but this has edge cases and should be corrected.
- Missing a semantics pass for `goto` and `::label::` statements.
- Metamethods.
  - Particularly there is no support for metamethods except for `___call`.
  - But metamethods are just function objects with a few places that lua calls as defined.
- `<const>` is not added.
- Coroutines are not added.
- I may have missed one variant of function [declarations](https://www.lua.org/manual/5.5/manual.html#3.4.11).
- Code path correctness.
  - `return` statements should have the function's final type unified.
  - Nondeterministic functions should be identified as such.
    - This would allow invariant code paths to be protomoted to constant value generation.

[AUTODOC]: ./lib/docs/autodoc.dart