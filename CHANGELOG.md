## 1.0.14
- Functions can return multiple arguments but any field access operation acts on the first argument only.
- Added semicolon support.
- Updated missing features section in the readme.
- Discovered `break` keyword logic was not added yet! Added.
- Weak checks for `,` or `;` tokens while parsing table pairs now strict. Added sanity check test for this.
- Function calls with one argument of either string or table literal can omit parens.
- Added string-to-number coercion under addition. Added relevant test `coercion.lua`.
- `popScope()` -> `restoreScope(next)`.
  - With closures I cannot pop the scope back to the parent b/c the parent for a closure is generally not in the next branch of execution after the closure finishes. Therefore I had to restore the scope everywhere `popScope()` was used. It's a bit uglier but it was necessary. Added test `currying.lua` which tests closures and the new one-argument syntax sugar.
- Slight rewrite to function calls to allow forwarded objects to be passed in by the name of the first argument.
  - Previously forward function calls (via `:`) always wrote to a `self` variable in the new scope. This was wrong to do.
  - Added `functions.lua` test to catch this.
- Added `__call` metamethod support.
- Added `__newindex` metamethod support.
  - This effort required a change in parsing so that assignment exprs are not math exprs. And the assignment visitor explicitly checks to see if the lhs is a table index operation.
- Added `__index` metamethod support.
- Added `rawset(t, k, v)` and `rawget(t, k)`.
- Fixed long-standing out-of-range error calling functions having less arguments than their definition. Unsupplied args are now nil. This is now similar to multivariable declarations which is correct.
- `run`, `runner`, `parse`, and `parseFile` now take optional `RunnerErrorsCallback? onError` to handle errors from trace.
  - So that it does not pollute other projects.
- Assignment expressions can no longer be used as values (value is the result of lhs). This was illegal lua.
- Rename `AssignExpr` -> `AssignStmt`. `AssignMultiExpr` -> `AssignMultiStmt`.
- Added first ever AutoDoc example.

## 1.0.13
- Forgot to drop comments after the lexing phase. This caused runtime problems with the repl.
- Ensured by hand that all the scopes were popped on exceptions. Some cases were missed in ForIterLoop and other loops.
- Fixed `repeat... until` loop condition.
- `LuaObject.value` setter now copies the function definition information so this doesn't have to be repeated in other parts of the codebase.
  - As a consequence, value must be set first and then the function definition is copied in the function special constructor.
- Moved passing tests into `/pass` to prepare for tests that **are** expected to fail in the future.

## 1.0.12
- Fixed `math` function errors causing unhelpful errors because `context.id` is no longer storing current function call information.
- Fixed `math.min` and `math.max` not behaving correctly.

## 1.0.11
- Fixed REPL lower-casing all user input. This prevented global vars from being read.
- `LuaObject.toString()` maps to `table` for table objects. Before it was printing their name if they had an id.

## 1.0.10
- Meta table support added.
- `setmetatable(t, mt)` and `getmetatable(t)` work as expected.
- Metamethods added to runtime.
  - Includes new tests under  `/test/assets/metamethods`.
- Multivalue arg unpacking behaves as expected.
  - Return values support multiple values correctly.
  - Variadic args support multiple values correctly.
- Global upvalues now use `_ENV` and includes legacy `_G` which points to `_ENV`.
- `Coroutine` API added to std library.
  - Note that coroutines do not work at this time.
- Entire `math` library completed.
- Bitwise operations added.
- All functions rethrow now on exceptions unless `callLuaFunction` is used with an exception handler.
- `pcall()` implementation follows from the new function exception behavior.
- Update to `README.md` includes a get starting section and lists the remaining unfinished features.

## 1.0.9
- `token` is now a field on all grammar nodes via `Stmt` base class.
- Started but did not complete coroutines.
- Had to push this premature version because an existing project was expecting some of these changes! Whoops.

## 1.0.8
- `token` field on AST nodes is mutable (non final) to allow in-place transformations for upgrade tools.
- Added `parse(String path)` to construct AST for `runner`.
- Added `-v` flag to cli to dump DOT files as HTML for the input lua script.

## 1.0.7
- The `#` operator bound to the wrong level (binary expressions). Made them bind to memory types (literals, function calls, etc). My small tests seems to fix this.
- Misnamed `include()` -> `require()`.
- Misnamed `IncludeCallback` -> `LuaRequireCallback`.
- Added `LuaObject.unpack()` as a shortcut for lua behavior: return functions for tables with a single field are unpacked.
  
## 1.0.6
- `LuaObject.writeFieldsFrom` takes a list of lua objects whose ID's will become the field keys too.
- constructor `LuaObject.tableFrom` added under similar rationale.
- singular writer `LuaObject.writeFieldFrom` added under similar rationale.
- When invoking a function, the new scope no longer retains context of itself (the caller)
  - b/c this created incorrect behavior when resolving parameters during AST visit.
  - b/c if using `self`, already provides the caller.
  - b/c now has correct outcome in other projects using this lib after removal.

## 1.0.5
- Hotfixes
  - Autodoc crash when evaluating `LuaObjectNoSemantics` type.
  - Fixed table test.
  - Note to self: tests should be modernized in the next update.

## 1.0.4
- `not` keyword was resolving when something was truthy instead of the opposite.
- Moved `onWrite` and `onRead` callbacks to the end of the operation so that programmers can react to changed values and know those values.
- `ReturnStmtCallStackUnwind` and `ReturnStmtDoNotUnwind` added as mixins. These are required to use to form a complete base class for `BaseRuntime`.
  - The former is expected lua runtime behavior. The latter is for cases where users want to perform static analysis.
- `callLuaFunction(luaObject, args)` helper utility function added to `BaseRuntime`.
  - Pushes and pop the scope, handles exceptions, and declares variables in-order of the function definition.
- `toLua(id)` now creates a new lua object with the name `id` in all cases. This is convenient for function calls
- `makeLuaRef()` is a method that returns the exact lua object pointer without making a copy object.
  - If the underlying object is not a `LuaObject`, the null is returned.
- Grammar fix: underlining -> underlying 

## 1.0.3
- Added new token `TokenType.kSpread` for varargs.
- Added support for variadic arguments.
- Fixed for-loop evaluation to allow variables.
- If the end-user does not drop comments, the parser will now skip over them as expected.
- Took out hacks to promote failed assigned values to variables.
  - This may come back to break some things...
- Corected equality checks.
- Only numbers and strings can be concatenated.
- Wrote a bunch of test scripts to begin building a test suite.
- Changed `showDateTime` to `dateTimeFormat` which is a `String?` type.
  - When this is null, it does not show the date.
  - When this is non-null, uses intl package `DateFormat` class.
    - See: https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
- Added `showSidebarIndex` which now paritions the page so that the index is in a sticky sidebar.
- Title, version, and datetime now have css classes `version-title`, `version-number`, `version-datetime` respectively.
- 

## 1.0.2
- Fixed variables without parent objects (non-fields + globals) not generating headers.
- Added optional `js` and `css` parameter to the autodoc. 
  - The autodoc has its own theme defaults but can be replaced with these parameters.
- Added lua classes to the generated headers in the autodoc output.
  - For variables `lua-field`.
  - For functions `lua-func`.
  - For tables `lua-table`.
- Fixed some bad HTML output (tag mismatches or lack thereof).

## 1.0.1
- Added floating return button in the output autodoc to return readers to the top of the index.
- Added optional version subtext to the autodoc.
- Added optional boolean to show or hide timestamp generation.

## 1.0.0
- Initial version.
