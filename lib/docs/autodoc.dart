import 'dart:io';
import 'package:intl/intl.dart';
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
  /// If this is set, datetime will appear in the html output
  /// formatted using the intl package DateFormat specification:
  /// https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
  final String? dateTimeFormat;

  /// Optional flag to move the index into a sidebar on the page
  /// that sticks to the reader's screen while they scroll.
  /// This will also remove the floating carrot button
  /// that normally takes the user to the top of the page where the index
  /// was.
  ///
  /// The header information for the doc generation (title, version, date)
  /// will be place in a toolbar at the top.
  final bool showSidebarIndex;

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
    this.dateTimeFormat,
    this.showSidebarIndex = false,
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

    /// Start the toolbar
    _html += '''
      <header style="
        flex: 0 0 50px;
        display: flex;
        flex-direction: row;
        align-items: center;
        top: 0;
        z-index: 10;
        padding-left: 30px;
        padding-right: 30px;
        justify-content: center;
        ">''';
    _html += '<div class="version-info" style="margin:10px">';
    _html += '<span class="version-title" style="margin:10px">$title</span>';

    /// Optional versioning.
    if (version != null) {
      _html +=
          '<span class="version-number" style="margin:10px">$version</span>';
    }

    /// Optional date time of generation.
    if (dateTimeFormat != null) {
      _html +=
          '''
          <span class="version-datetime" 
          style="margin:10px">
          Generated ${DateFormat(dateTimeFormat).format(DateTime.now())}
          </span>
          ''';
    }

    _html += '</div>';
    _html += '''
      </header>
    ''';

    /// Start the main content output.

    _html += switch (showSidebarIndex) {
      true =>
        '''
        <main style="
          flex: 1;
          display: flex;
          flex-direction: row;
        ">
        ''',
      false => '<main>',
    };

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

    if (showSidebarIndex) {
      /// Write out the content inside a sidebar div.
      _html += '''
        <div class="sidebar"
          style="
          order:1;
          position: sticky;
          top: 90px;
          flex: 0 1 230px;
          min-height: 0%;
          max-height: 95%;
          height: 90vh;
          overflow-y: auto;
          ">
        ''';
      _html += renderIndex();
      _html += '</div>';
    } else {
      /// Add an html button to return the reader to the top page index.
      _html += '<div id="floater"><a href="#">▲</a></div>';
      _html += renderIndex();

      /// Separate the index from the docs.
      _html += '<hr>';
    }

    /// Append the body to the output html.
    if (showSidebarIndex) {
      _html += '<div style="order:2;flex:1;padding:20px;">$_body</div>';
    } else {
      _html += '<div style="padding: 20px">$_body</div>';
    }
    _html += '</main>';
    _html += '</html>';

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

  String renderIndex() {
    String out = '';

    /// Output index information collected earlier.
    for (var MapEntry(:key, :value) in _indexHtml.entries) {
      out += '<h2>$key</h2>';
      out += value;
    }
    return out;
  }
}
