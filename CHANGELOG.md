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
