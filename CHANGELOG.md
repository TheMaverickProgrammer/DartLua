## 1.0.7
- The `#` operator bound to the wrong level (binary expressions). Made them bind to literals and groups. My small test seems to fix this.

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
