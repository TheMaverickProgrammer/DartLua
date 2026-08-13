import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

/// Helper util to quote strings.
String quote(String s) {
  if (s.startsWith('"') && s.endsWith('"')) {
    return s;
  }

  return '"$s"';
}

/// Note that I am color coding the LUA AST as follows:
/// * Memory -> Green
/// * Yellow -> Control Flow
/// * Pink -> Non-Lua AST constructs
/// * Grey -> User variable names
/// * Muave -> Literal Values
/// * Black -> Binary Operators (math)
/// * Blue -> Variable initialization
const String seafoamGreen = '#9FE2BF';
const String muave = '#E0B0FF';
const String skyBlue = '#87CEEB';
const String pink = '#E29FC2';

/// DOT language Graph Viz markup node.
/// Every node is given a unique [key] from the ever-increasing
/// [GzBaseNode.globalKeys] counter. This ensures nodes in the
/// Lua AST can be uniquely identified even if they contain
/// similar content. This is utilized by [GzBaseNode.stubId].
/// If a node's [label] is non-empty, then [GzBaseNode.stubLabel]
/// will construct the expression to set that attribute in DOT language.
///
/// [GzBaseNode.toString] returns the DOT language representation of
/// this node. It must be implemented on all children.
abstract class GzBaseNode {
  late final int key;
  final String id;
  String label;
  String? color, fontColor, shape;
  List<GzBaseNode> children;
  static int globalKeys = 0;

  /// [label] is optional. If null, will become [id].
  /// Side effect: [GzBaseNode.globalKeys] is increased by one.
  GzBaseNode({
    required this.id,
    required this.children,
    String? label,
    this.color,
    this.fontColor,
    this.shape,
  }) : label = label ?? id {
    key = globalKeys++;
  }

  /// Constructs the string stub for the label, if one is provided
  /// and non-empty.
  String get stubLabel => switch (label.isEmpty) {
    true => '',
    false => 'label=${quote(label)}',
  };

  /// Constructs a string stub for the color, if one is provided
  /// and non-null.
  String get stubColor => switch (color) {
    null => '',
    final String s => 'color=${quote(s)}',
  };

  /// Constructs a string stub for the fontColor, if one is provided
  /// and non-null.
  String get stubfontColor => switch (fontColor) {
    null => '',
    final String s => 'fontcolor=${quote(s)}',
  };

  /// Constructs a string stub for the shape, if one is provided
  /// and non-null.
  String get stubShape => switch (shape) {
    null => '',
    final String s => 'shape=${quote(s)}',
  };

  /// Constructs the full attribute DOT lang syntax separated by space.
  String get stubAttrs => [
    stubColor,
    stubLabel,
    stubfontColor,
    stubShape,
  ].where((e) => e.isNotEmpty).join(' ');

  /// Used by [stubId] to convert [id]
  /// to a DOT language compatible id string.
  String get _printableId => 'id_$id'
      .replaceAll(' ', '_')
      .replaceAll('"', '')
      .replaceAll(',', 'CM')
      .replaceAll('=', 'EQ')
      .replaceAll('/', 'DI')
      .replaceAll('.', 'DT')
      .replaceAll('-', 'SU')
      .replaceAll('+', 'AD')
      .replaceAll('*', 'MU')
      .replaceAll('^', 'CA')
      .replaceAll('%', 'MO')
      .replaceAll('>', 'GT')
      .replaceAll('<', 'LT')
      .replaceAll('(', 'PL')
      .replaceAll(')', 'PR');

  String get stubId => '$_printableId$key';

  @override
  String toString();
}

/// Represents the `graph` block in DOT language.
/// Introduces new getters [GzGraph.stubHeaders]
/// and [GzGraph.stubBody] which fill the graph
/// with nodes and links them together respectively.
///
/// [GzGraph.toString] is implemented to return a `graph` block.
class GzGraph extends GzBaseNode {
  GzGraph({
    required super.id,
    super.children = const [],
    super.label,
    super.color,
    super.fontColor,
    super.shape,
  });

  /// Link nodes together. Introduces the "self" node
  /// representing the start of a new graph.
  String get stubHeaders {
    final String childs = children.fold(
      '',
      (v, e) => '$v$stubId -- ${e.stubId};\n',
    );
    final String me = '$stubId [$stubAttrs];\n';
    return me + childs;
  }

  /// Populate the graph with nodes.
  String get stubBody => children.fold('', (v, e) => '$v$e\n');

  @override
  String toString() => 'graph graph__$stubId {\n$stubBody$stubHeaders}';
}

/// Represents a chunk in a DOT graph as the AST visits every
/// Lua node. It introduces new nodes and links them together
/// in the [GzChunk.toString] implementation which should be
/// called in [GzGraph.toString] only.
class GzChunk extends GzGraph {
  GzChunk({
    required super.id,
    super.children = const [],
    super.label,
    super.color,
    super.fontColor,
    super.shape,
  });

  @override
  String toString() => '$stubBody$stubHeaders';
}

/// Represents a DOT node that has no children.
///
/// Implements [GzNode.toString].
class GzNode extends GzBaseNode {
  GzNode({
    required super.id,
    super.label,
    super.color,
    super.fontColor,
    super.shape,
  }) : super(children: []);

  @override
  String toString() => '$stubId [$stubAttrs]';
}

/// A shorthand util that constructs either a [GzChunk] node
/// or a [GzNode] based on whether or not [children] are provided.
GzBaseNode node(
  String id, {
  List<GzBaseNode>? children,
  String? label,
  String? color,
  String? fontColor,
  String? shape,
}) => switch (children) {
  final List<GzBaseNode> ls => GzChunk(
    id: id,
    children: ls,
    label: label,
    color: color,
    fontColor: fontColor,
    shape: shape,
  ),
  null => GzNode(
    id: id,
    label: label,
    color: color,
    fontColor: fontColor,
    shape: shape,
  ),
};

/// Walks the AST and generates a new AST corresponding to DOT language
/// nodes which can render a graph for visualizing in DOT preview tools.
/// The highest node will be a [GzGraph] whose [GzGraph.label] is "Program".
///
/// Usage: Pass [AST] into [Visualizer.generateHTML] and it produces
/// the HTML contents of the graph. This can then be written directly
/// to a file and viewed by a web browser.
class Visualizer extends Visitor<GzBaseNode> {
  final String path;

  Visualizer(this.path);

  String generateHTML(AST ast) {
    final root = visitAST(ast)..label = path.split(RegExp(r'[/\\]')).last;
    return _html.replaceFirst('%%DOTFILE%%', root.toString());
  }

  @override
  GzBaseNode visitAST(AST ast) {
    final stmts = ast.stmts.map((e) => e.accept(this)).toList();
    return GzGraph(id: 'Program', children: stmts, color: seafoamGreen);
  }

  @override
  GzBaseNode visitBreakStmt(BreakStmt stmt) =>
      node('break', color: 'yellow', shape: 'box');

  @override
  GzBaseNode visitReturnStmt(ReturnStmt expr) {
    final args = expr.values.map((e) => e.accept(this)).toList();
    return node('return', children: args, color: 'yellow', shape: 'box');
  }

  @override
  GzBaseNode visitBinaryExpr(BinaryExpr expr) {
    final lhs = expr.lhs.accept(this);
    final rhs = expr.rhs.accept(this);
    final op = expr.op.lexeme;

    return node(op, children: [lhs, rhs], color: 'black', fontColor: 'white');
  }

  @override
  GzBaseNode visitUnaryExpr(UnaryExpr expr) {
    final prefix = expr.prefix.lexeme;
    final rhs = expr.rhs.accept(this);

    return node(prefix, color: 'black', fontColor: 'white', children: [rhs]);
  }

  @override
  GzBaseNode visitAssignExpr(AssignStmt assignExpr) {
    final lhs = assignExpr.lhs.accept(this);
    final rhs = assignExpr.rhs.accept(this);
    final op = assignExpr.token.lexeme;

    return node(op, color: 'black', fontColor: 'white', children: [lhs, rhs]);
  }

  @override
  GzBaseNode visitAssignMultiExpr(AssignMultiStmt assignMultiExpr) {
    final lhs = assignMultiExpr.lhs.map((e) => e.accept(this)).toList();
    final rhs = assignMultiExpr.rhs.map((e) => e.accept(this)).toList();
    final op = assignMultiExpr.token.lexeme;
    return node(
      op,
      color: 'black',
      fontColor: 'white',
      children: [
        node('lhs', color: pink, children: lhs),
        node('rhs', color: pink, children: rhs),
      ],
    );
  }

  @override
  GzBaseNode visitDeclArg(DeclArg declArg) {
    final arg = declArg.id.lexeme;
    return node(arg, color: skyBlue, shape: 'box');
  }

  @override
  GzBaseNode visitDeclVar(DeclVar declVar) {
    final id = declVar.id.lexeme;
    final value = declVar.init?.accept(this);

    return node(
      'local $id',
      color: skyBlue,
      shape: 'box',
      children: value != null ? [value] : null,
    );
  }

  @override
  GzBaseNode visitDeclMultiVar(DeclMultiVar declMultiVar) {
    return node(
      'init',
      color: seafoamGreen,
      children: declMultiVar.vars.map((e) => e.accept(this)).toList(),
    );
  }

  @override
  GzBaseNode visitFuncExpr(FuncExpr expr) {
    final id = switch (expr.id) {
      '' => '<anonymous>',
      final String s => s,
    };

    final args = expr.args
        .map((e) => node(e.id.lexeme, color: 'lightgrey', shape: 'box'))
        .toList();
    final body = expr.body.map((e) => e.accept(this)).toList();

    return node(
      'func $id',
      color: seafoamGreen,
      shape: 'box',
      children: [
        node('stmts', children: body, color: pink),
        node('args', children: args, color: pink),
      ],
    );
  }

  @override
  GzBaseNode visitIfStmt(IfStmt stmt) {
    final body = stmt.body.map((e) => e.accept(this)).toList();

    if (stmt.isTerminalElse) {
      return node('stmts', color: pink, children: body);
    }

    return node(
      'if',
      shape: 'diamond',
      color: 'yellow',
      children: [
        node('expr', color: pink, children: [stmt.expr!.accept(this)]),
        node('stmts', color: pink, children: body),
        if (stmt.nextIfStmt != null)
          node('else', color: muave, children: [stmt.nextIfStmt!.accept(this)]),
      ],
    );
  }

  @override
  GzBaseNode visitGroupExpr(GroupExpr groupExpr) {
    final expr = groupExpr.expr.accept(this);
    return node(
      'parens',
      label: '( expr )',
      color: 'black',
      fontColor: 'white',
      children: [expr],
    );
  }

  @override
  GzBaseNode visitNotExpr(NotExpr notExpr) {
    final expr = notExpr.expr.accept(this);
    return node('not', children: [expr], color: pink);
  }

  GzBaseNode _printFieldAccess(MemoryAccess mem) {
    final id = mem.callee.accept(this);
    final field = mem.args.first.accept(this);
    return node('__index', color: seafoamGreen, children: [id, field]);
  }

  GzBaseNode _printTableAccess(MemoryAccess mem) {
    final id = mem.callee.accept(this);
    final field = mem.args.first.accept(this);

    return node('__index', color: seafoamGreen, children: [id, field]);
  }

  GzBaseNode _printCallable(MemoryAccess mem) {
    final id = mem.callee.accept(this);
    final args = mem.args.map((e) => e.accept(this)).toList();

    String str = switch (mem.op.type) {
      TokenType.kColon => 'forward',
      TokenType.kLParen => 'exec',
      final Object o => 'Unknown (${o.toString()})',
    };

    return node(
      str,
      color: seafoamGreen,
      children: [
        id,
        node('args', children: args, color: pink),
      ],
    );
  }

  @override
  GzBaseNode visitMemoryAccess(MemoryAccess memoryAccess) {
    return switch (memoryAccess.type) {
      MemoryAccessType.field => _printFieldAccess(memoryAccess),
      MemoryAccessType.table => _printTableAccess(memoryAccess),
      MemoryAccessType.call => _printCallable(memoryAccess),
    };
  }

  @override
  GzBaseNode visitRawExpr(RawExpr rawExpr) {
    return node(rawExpr.token.lexeme, color: 'lightgrey', shape: 'box');
  }

  @override
  GzBaseNode visitSelfExpr(SelfExpr selfExpr) {
    return node('self', color: muave, shape: 'box');
  }

  @override
  GzBaseNode visitBooleanLiteral(BooleanLiteral boolean) {
    return node(boolean.value.toString(), color: muave, shape: 'box');
  }

  @override
  GzBaseNode visitNumberLiteral(NumberLiteral number) {
    return node(number.value.toString(), color: muave, shape: 'box');
  }

  @override
  GzBaseNode visitStringLiteral(StringLiteral string) {
    return node(
      string.value,
      label: '\'\'${string.value}\'\'',
      color: muave,
      shape: 'box',
    );
  }

  @override
  GzBaseNode visitNilLiteral(NilLiteral nil) {
    return node('nil', color: muave, shape: 'box');
  }

  @override
  GzBaseNode visitTableLiteral(TableLiteral table) {
    final args = table.pairs.map((e) => e.accept(this)).toList();
    return node('table', children: args, color: seafoamGreen);
  }

  @override
  GzBaseNode visitKeyValStmt(KeyValStmt keyval) {
    final k = keyval.key?.accept(this);
    final v = keyval.value.accept(this);

    return node('kv', color: pink, children: [?k, v]);
  }

  @override
  GzBaseNode visitForLoopStmt(ForLoopStmt forLoopStmt) {
    final ctrl = forLoopStmt.exprList.map((e) => e.accept(this)).toList();
    final body = forLoopStmt.body.map((e) => e.accept(this)).toList();

    return node(
      'for',
      color: 'yellow',
      shape: 'diamond',
      children: [
        node('ctrl', color: 'pink', children: ctrl),
        node('do', color: 'yellow', children: body),
      ],
    );
  }

  @override
  GzBaseNode visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt) {
    final key = forIterLoopStmt.key.lexeme;
    final val = forIterLoopStmt.value?.lexeme;
    final iter = forIterLoopStmt.iterExpr.accept(this);
    final body = forIterLoopStmt.body.map((e) => e.accept(this)).toList();

    return node(
      'for',
      color: 'yellow',
      shape: 'diamond',
      children: [
        node(
          'key',
          color: pink,
          children: [node(key, color: skyBlue)],
        ),
        if (val != null)
          node(
            'val',
            color: pink,
            children: [node(val, color: muave)],
          ),
        node('in', color: pink, children: [iter]),
        node('do', color: 'yellow', children: body),
      ],
    );
  }

  @override
  GzBaseNode visitRepeatUntilLoopStmt(RepeatUntilLoopStmt repeatUntilLoopStmt) {
    final body = repeatUntilLoopStmt.body.map((e) => e.accept(this)).toList();
    final expr = repeatUntilLoopStmt.untilExpr.accept(this);

    return node(
      'repeat',
      shape: 'diamond',
      color: 'yellow',
      children: [
        node('expr', color: pink, children: [expr]),
        node('until', color: 'yellow', children: body),
      ],
    );
  }

  @override
  GzBaseNode visitWhileLoopStmt(WhileLoopStmt whileLoopStmt) {
    final exprs = whileLoopStmt.expr.accept(this);
    final body = whileLoopStmt.body.map((e) => e.accept(this)).toList();

    return node(
      'while',
      shape: 'diamond',
      color: 'yellow',
      children: [
        node('expr', color: pink, children: [exprs]),
        node('do', color: 'yellow', children: body),
      ],
    );
  }

  @override
  GzBaseNode visitGotoStmt(GotoStmt gotoStmt) {
    return node(
      'goto',
      shape: 'rpromoter',
      children: [gotoStmt.expr.accept(this)],
      color: seafoamGreen,
    );
  }

  @override
  GzBaseNode visitGotoLabelStmt(GotoLabelStmt stmt) {
    return node(
      '::${stmt.label.lexeme}::',
      color: seafoamGreen,
      shape: 'triangle',
    );
  }
}

const String _html = '''<!DOCTYPE html>
<html lang="en">
  <head>
    <title>Network</title>
    <script
      type="text/javascript"
      src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"
    ></script>
    <style type="text/css">
        body {
            height: 100vh;
        }
      #mynetwork {
        width: 100%;
        height: 100%;
        border: 1px solid lightgray;
      }
    </style>
  </head>
  <body>
    <div id="mynetwork"></div>
    <script type="text/javascript">
      // create a network
      var container = document.getElementById("mynetwork");
      var data = vis.parseDOTNetwork(`%%DOTFILE%%`);

      var options = {
        edges: {
          smooth: {
            type: "cubicBezier",
            forceDirection:"vertical",
            roundness: 0.4,
          },
        },
        layout: {
          hierarchical: {
            direction: 'UD',
            sortMethod: 'directed',
          },
        },
        physics: false,
      };
      var network = new vis.Network(container, data, options);
    </script>
  </body>
</html>''';
