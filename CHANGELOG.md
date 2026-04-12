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
