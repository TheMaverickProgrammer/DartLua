import 'dart:io';
import 'package:lualib/lua/visitors/runtime/base.dart';
import 'package:lualib/lua/visitors/runtime/luaobject.dart';
import 'package:lualib/lua/visitors/visitor.dart';

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

  /// The current &lt;body&gt; tag.
  String _body = '';

  /// The current &lt;html&gt; tag.
  String _html = '';

  /// The title which will appear on the webpage.
  final String title;
  LuaAutoDoc(this.title);

  /// Given a [runtime] implementation and an [outDir],
  /// collects the global variables and extracts their [LuaDoc]
  /// information while traversing lua objects and their properties.
  /// The html will contain prism.js and css markup to prettify the
  /// document.
  ///
  /// The file will be generated at "[outDir]/index.html".
  void generateDocs(BaseRuntime runtime, {required String outDir}) {
    _html = '<html>';
    _html += '<h1>$title</h1>';
    _html += '<h5>Generated ${DateTime.now()}</h5>';
    _html += '<script>${prism.js}</script>';
    _html +=
        '''<style>
        ${prism.css}
        
        html {
          background-color: #F8F8F8 ;
        }

        h1, h2, h3, h4, h5 {
          color: #000080;
          font-family: Verdana, Geneva, sans-serif;
          font-weight: normal;
          font-style: normal;
          text-align: left;
        }

        a:link {
          color: #000080;
        }

        a:link:hover {
          background-color: #D0D0FF;
          color: #000080;
          border-radius: 4px;
        }

        code {
          font-size: 12pt;
        }

        body {
          background-color: #FFFFFF ;
          color: #000000 ;
          font-family: Helvetica, Arial, sans-serif ;
          text-align: justify ;
          line-height: 1.25 ;
          margin: 16px auto ;
          padding: 32px ;
          border: solid #ccc 1px ;
          border-radius: 20px ;
          max-width: 70em ;
          width: 90% ;
        }
        </style>
        ''';
    _body = '<body>';

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
      header += '<a href="#$anchor"><h3>$title</a>: <b>table</b></h3>';

      content += '<ul>';
      for (var MapEntry(:key, :value) in luaObj.fields.entries) {
        final String valueStr = switch (value) {
          final LuaObject obj => luaObj2Html(key, obj.deref(), parent: luaObj),
          null => '',
        };
        content += '<div>$valueStr</div>';
      }
      content += '</ul>';
      popPath();
    } else if (luaObj.isFunc) {
      if (luaObj.funcDef != null) {
        final String anchor = pushPath(title);
        final FuncExpr def = luaObj.funcDef!;
        header += '<span>';
        header += '<a id="$anchor"></a>';
        header += '<a href="#$anchor"><h3>${def.id}</a> ${def.argsHtml}</h3>';
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
      header += '<span>';
      header += '<a id="$anchor"></a>';
      header += '<a href="#$anchor"></a>';
      header += '</span>';

      final String stub =
          '''
          <a id="$anchor"></a>
          <a href="#$anchor">
            <h3>$dot$title</h3>
          </a>
          ''';

      if (value != null) {
        /// Non-null values with a parent must pass the exclusion
        /// filter.
        if (!(parent?.doc?.exclude?.call(luaObj.id) ?? false)) {
          content += stub;
          content += parent?.doc?.keyValueHtml?.call(luaObj.id) ?? '';
        }
      } else if (parent == null) {
        /// Otherwise, null global variables without a parent
        /// can render out.
        content += stub;
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
        true => '<p>${luaObj.doc!.html}</p>$content',
        false => '$content<p>${luaObj.doc!.html}</p>',
      };
    }

    return '<div>$header$content</div>';
  }
}
