import 'dart:io';
import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

import 'prism.dart' as prism;

/// This class builds a single-page html webpage
/// from the documentation of all the global variables
/// in a provided runtime implementation.
/// See [generateDocs].
class LuaAutoDoc {
  /// Build &lt;a&gt; tag hrefs from deeply nested lua tables.
  final List<String> _anchorPath = [];

  /// Maps lua ids to anchor tags.
  final Map<String, String> _anchors = {};

  /// The content of the webpage is built separately from the index.
  final Map<String, String> _indexHtml = {};

  /// The custom js script contents.
  final String js;

  /// The custom css script contents.
  /// Each lua entry will have a <h3></h3>
  /// tag pair and a css class with which
  /// to identify the lua object type for
  /// further styling.
  ///
  /// Lua objects or tables will have the
  /// css class "lua-table".
  ///
  /// Lua functions will have the
  /// css class "lua-func".
  ///
  /// All other lua variables (fields and globals)
  /// will have the css class "lua-field".
  final String css;

  /// The current &lt;body&gt; tag.
  String _body = '';

  /// The current &lt;html&gt; tag.
  String _html = '';

  /// The title which will appear on the webpage.
  final String title;

  /// The optional version text will appear next to the title.
  final String? version;

  /// Optional date time of document generation.
  final bool showDateTime;

  /// Construct an autodoc instance with [title] and [version]
  /// subtext. By default [showDateTime] is false. If set to true,
  /// a datetime stamp stub will appear near the title of the ToC.
  /// By default both [js] and [css] use [prism.js] and [prism.css]
  /// contents respectively. You can replace these and they will
  /// populate the output HTML <script></script> and <style></style>
  /// tags with their corresponding contents.
  LuaAutoDoc(
    this.title, {
    this.version,
    this.showDateTime = false,
    this.js = prism.js,
    this.css = prism.css,
  });

  /// Given a [runtime] implementation and an [outDir],
  /// collects the global variables and extracts their [LuaDoc]
  /// information while traversing lua objects and their properties.
  /// The html will contain [js] and [css] markup to prettify the
  /// document.
  ///
  /// The file will be generated at "[outDir]/index.html".
  void generateDocs(BaseRuntime runtime, {required String outDir}) {
    _html = '<html>';
    _html += '<script>$js</script>';
    _html += '<style>$css</style>';

    /// Start the body output.
    _html += '<body>';
    _html += '<h1>$title</h1>';

    /// Optional versioning.
    if (version != null) {
      _html += '<h4>$version</h4>';
    }

    /// Optional date time of generation.
    if (showDateTime) {
      _html += '<h5>Generated ${DateTime.now()}</h5>';
    }

    /// Add an html button to return the reader to the index.
    _html += '<div id="floater"><a href="#">▲</a></div>';

    /// Sorts content alphabetically.
    final sortedIndex = runtime.global.vars.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    /// Visit each object and construct categories for the index listing.
    for (var MapEntry(:key, :value) in sortedIndex) {
      /// Visit and inspect the lua object for doc configurations.
      /// The return string will decorated html.
      _body += luaObj2Html(key, value);

      final String k = value.doc?.category ?? 'Utils';
      if (!_indexHtml.containsKey(k)) {
        _indexHtml[k] = '';
      }

      /// Build the index separately from the body.
      _indexHtml[k] = '${_indexHtml[k]!}<a href="#$key">$key</a><br/>';
    }

    // <body>> ends with _body.
    _body += '</body>';

    /// Append the index to the output html.
    for (var MapEntry(:key, :value) in _indexHtml.entries) {
      _html += '<h2>$key</h2>';
      _html += value;
    }

    /// Append the body to the output html.
    _html += '<hr>';
    _html += '$_body</html>';

    /// Finally, write out the document on disk.
    final out = '$outDir/index.html';
    File(out).writeAsStringSync(_html);
  }

  /// Deeply nested tables will have their paths preserved
  /// to construct anchor tags. This will also return the current
  /// anchor tag string value.
  ///
  /// See [popPath].
  String pushPath(String label) {
    _anchorPath.add(label);
    return _anchors.putIfAbsent(label, () => _anchorPath.join('.'));
  }

  /// Removes the last id from the anchor path stack.
  /// Returns the anchor tag string value of the updated path.
  String popPath() {
    if (_anchorPath.isNotEmpty) {
      _anchorPath.removeLast();
    }

    return _anchorPath.join('.');
  }

  /// If the object's storage is a primitive value, then
  /// it tries to visit [LuaDoc.keyValueHtml]. If it is not excluded
  /// via [LuaDoc.exclude], then it will render out to html.
  /// If the object's storage is that of a function or a table,
  /// then fields will also be visited and [pushPath] update the
  /// new anchor tag. After visiting, [popPath] is called to restore
  /// the previous depth information. The end result is a [String]
  /// of decorated html for the autodoc.
  String luaObj2Html(String title, LuaObject luaObj, {LuaObject? parent}) {
    String content = '';
    String header = '';
    if (luaObj.skipSemanitcs || (luaObj.isTable && luaObj.isNotFunc)) {
      final String anchor = pushPath(title);
      header += '<a id="$anchor"></a>';
      header +=
          '''
          <h3 class="lua-table">
          <a href="#$anchor">$title</a>: <b>table</b>
          </h3>
          ''';

      content += '<ul>';
      for (var MapEntry(:key, :value) in luaObj.fields.entries) {
        final String valueStr = switch (value) {
          final LuaObject obj => luaObj2Html(key, obj.deref(), parent: luaObj),
          null => '',
        };
        content += valueStr;
      }
      content += '</ul>';
      popPath();
    } else if (luaObj.isFunc) {
      if (luaObj.funcDef != null) {
        final String anchor = pushPath(title);
        final FuncExpr def = luaObj.funcDef!;
        header += '<span>';
        header += '<a id="$anchor"></a>';
        header +=
            '''
            <h3 class="lua-func">
              <a href="#$anchor">${def.id}</a>
              ${def.argsHtml}
            </h3>
            ''';
        header += '</span>';
        popPath();
      } else if (luaObj.hasField('__call')) {
        content += '<i>Callable</i>';
      }
    } else {
      final String anchor = pushPath(title);
      final String dot = switch (parent) {
        null => '',
        _ => '.',
      };

      final Object? value = luaObj.value;
      header +=
          '''
          <span>
            <a id="$anchor"></a>
            <h3 class="lua-field">
              <a href="#$anchor">$dot$title</a>
            </h3>
          </span>
          ''';

      if (value != null) {
        /// Non-null values with a parent must pass the exclusion
        /// filter.
        if (!(parent?.doc?.exclude?.call(luaObj.id) ?? false)) {
          final stub = parent?.doc?.keyValueHtml?.call(luaObj.id) ?? '';
          if (stub.isNotEmpty) {
            content += '<div>$stub</div>';
          }
        }
      }
      popPath();
    }

    if (luaObj.doc?.includeHtml ?? false) {
      // Opinionated styling:
      // Prepend a table's fields and methods
      // with the doc html.
      // Otherwise, append doc html after values
      // and functions.
      content = switch (luaObj.isTable) {
        true => '${luaObj.doc!.html}$content',
        false => '$content${luaObj.doc!.html}',
      };

      content = '<div>$content</div>';
    }

    return '$header$content';
  }
}
