import 'package:puredartlua/lua/lua.dart';

final String _sep = ';';

/// A very simple obfuscator example.
/// Visits every node and generates minified lua.
/// Identifiers are remapped to the next smallest unique id
/// composed of alphanumeric chars.
class Obfuscator extends Visitor<String> {
  /// The output content to write to file.
  String content = '';

  /// Remapped ids.
  final Map<String, String> ids = {};

  /// The next id to use in [writeOrReadNewID].
  /// The leading entry is always '_' because the
  /// simple variable name algorithm bumps the last
  /// entry from a->z, A-Z, then from 0->9 before wrapping back
  /// to letter "a" and appending a new entry. Thus,
  /// to be a valid lua identifier it needs a leading "_".
  final List<String> _nextId = ['_', 'a'];

  /// Constructor walks the AST,
  /// generates a prelude of remapped variables,
  /// and stores the result in [content].
  Obfuscator(AST ast) {
    content = visitAST(ast);
    final prelude = ids.entries.map((m) => '${m.value} = ${m.key}').join(_sep);
    content = '$prelude$_sep$content';
  }

  /// If [id] is not already assigned a new identifier,
  /// then constructs one with [_newId]. The next id
  /// bumps the last letter to the next in the alphabet
  /// set `[a-z, A-Z, 0-9]`.
  /// If the last letter was '9', then flip it back to 'a' and
  /// append a new alphabet entry to the [_newId] list.
  String writeOrReadNewID(String id) {
    if (ids.containsKey(id)) {
      return ids[id]!;
    }

    final newid = ids[id] = _nextId.join();
    final n = _nextId.length - 1;
    if (_nextId.last == 'z') {
      _nextId[n] = 'A';
    } else if (_nextId.last == 'Z') {
      _nextId[n] = '0';
    } else if (_nextId.last == '9') {
      _nextId[n] = 'a';
      _nextId.add('a');
    } else {
      _nextId[n] = String.fromCharCode(_nextId.last.codeUnitAt(0) + 1);
    }

    return newid;
  }

  @override
  String visitAST(AST ast) {
    return ast.stmts.map((e) => e.accept(this)).join(_sep);
  }

  @override
  String visitAssignMultiStmt(AssignMultiStmt assignMultiStmt) {
    final lhs = assignMultiStmt.lhs.map((e) => e.accept(this)).join(',');
    final rhs = assignMultiStmt.rhs.map((e) => e.accept(this)).join(',');
    return '$lhs = $rhs';
  }

  @override
  String visitAssignStmt(AssignStmt assignStmt) {
    final lhs = assignStmt.lhs.accept(this);
    final rhs = assignStmt.rhs.accept(this);
    return '$lhs = $rhs';
  }

  @override
  String visitBinaryExpr(BinaryExpr expr) {
    final lhs = expr.lhs.accept(this);
    final rhs = expr.rhs.accept(this);
    final op = expr.op.lexeme;
    return '$lhs $op $rhs';
  }

  @override
  String visitBooleanLiteral(BooleanLiteral boolean) {
    return boolean.token.lexeme;
  }

  @override
  String visitBreakStmt(BreakStmt stmt) {
    return 'break';
  }

  @override
  String visitDeclArg(DeclArg declArg) {
    return writeOrReadNewID(declArg.lexeme);
  }

  @override
  String visitDeclMultiVar(DeclMultiVar declMultiVar) {
    final lhs = declMultiVar.vars.map((e) => e.accept(this)).join(',');
    final rhs = declMultiVar.vals.map((e) => e.accept(this)).join(',');
    final scp = switch (declMultiVar.local) {
      true => 'local',
      _ => '',
    };

    if (rhs.isEmpty) return '$scp $lhs';
    return '$scp $lhs=$rhs';
  }

  @override
  String visitDeclVar(DeclVar declVar) {
    final id = writeOrReadNewID(declVar.id.lexeme);
    final init = declVar.init?.accept(this);
    final attr = switch (declVar.attr?.lexeme) {
      final String s => ' <$s> ',
      _ => '',
    };

    if (init != null) {
      return '$id$attr=$init';
    }

    return '$id$attr';
  }

  @override
  String visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt) {
    final head = forIterLoopStmt.vars
        .map((e) => writeOrReadNewID(e.lexeme))
        .join(',');
    final tail = forIterLoopStmt.exprs.map((e) => e.accept(this)).join(',');
    final body = forIterLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    return 'for $head in $tail do$_sep$body${_sep}end';
  }

  @override
  String visitForLoopStmt(ForLoopStmt forLoopStmt) {
    final expr = forLoopStmt.exprList.map((e) => e.accept(this)).join(',');
    final body = forLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    return 'for $expr do$_sep$body${_sep}end';
  }

  @override
  String visitFuncExpr(FuncExpr expr) {
    final id = expr.idParts.map((e) => e.accept(this)).join('.');
    final args = expr.args.map((e) => e.accept(this)).join(',');
    final body = expr.body.map((e) => e.accept(this)).join(_sep);
    return 'function $id($args)$_sep$body${_sep}end';
  }

  @override
  String visitGotoLabelStmt(GotoLabelStmt gotoLabelStmt) {
    return '::${writeOrReadNewID(gotoLabelStmt.label.lexeme)}::';
  }

  @override
  String visitGotoStmt(GotoStmt gotoStmt) {
    final label = gotoStmt.expr.accept(this);
    return 'goto $label';
  }

  @override
  String visitGroupExpr(GroupExpr groupExpr) {
    final expr = groupExpr.expr.accept(this);
    return '($expr)';
  }

  @override
  String visitIfStmt(IfStmt stmt) {
    final expr = stmt.expr?.accept(this);
    final body = stmt.body.map((e) => e.accept(this)).join(_sep);

    if (stmt.isTerminalElse) {
      return '$_sep$body${_sep}end';
    }

    final next = switch (stmt.nextIfStmt?.accept(this)) {
      final String n => '${_sep}else$n',
      null => '${_sep}end',
    };

    return 'if $expr then$_sep$body$next';
  }

  @override
  String visitKeyValStmt(KeyValStmt keyval) {
    final key = keyval.key?.accept(this);
    final val = keyval.value.accept(this);
    if (key == null) {
      return val;
    }
    return '$key=$val';
  }

  @override
  String visitMemoryAccess(MemoryAccess memoryAccess) {
    final id = memoryAccess.callee.accept(this);
    final field = memoryAccess.field?.accept(this);
    final args = memoryAccess.args.map((e) => e.accept(this)).join(',');

    return switch (memoryAccess.type) {
      MemoryAccessType.field => '$id.$field',
      MemoryAccessType.table => '$id[$field]',
      MemoryAccessType.call => switch (memoryAccess.isSelfFwd) {
        true => '$id:$args',
        false => '$id($args)',
      },
    };
  }

  @override
  String visitNilLiteral(NilLiteral nil) {
    return 'nil';
  }

  @override
  String visitNotExpr(NotExpr notExpr) {
    final expr = notExpr.expr.accept(this);
    return 'not $expr';
  }

  @override
  String visitNumberLiteral(NumberLiteral number) {
    return number.token.lexeme;
  }

  @override
  String visitRawExpr(RawExpr rawExpr) {
    return writeOrReadNewID(rawExpr.token.lexeme);
  }

  @override
  String visitRepeatUntilLoopStmt(RepeatUntilLoopStmt repeatUntilLoopStmt) {
    final expr = repeatUntilLoopStmt.untilExpr.accept(this);
    final body = repeatUntilLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    return 'repeat$_sep$body${_sep}until($expr)';
  }

  @override
  String visitReturnStmt(ReturnStmt expr) {
    final args = expr.values.map((e) => e.accept(this)).join(',');

    if (args.isEmpty) {
      return 'return';
    }
    return 'return $args';
  }

  @override
  String visitSelfExpr(SelfExpr selfExpr) {
    return writeOrReadNewID(selfExpr.token.lexeme);
  }

  @override
  String visitStringLiteral(StringLiteral string) {
    return writeOrReadNewID('"${string.value}"');
  }

  @override
  String visitTableLiteral(TableLiteral table) {
    final pairs = table.pairs.map((e) => e.accept(this)).join(',');
    return '{$pairs}';
  }

  @override
  String visitUnaryExpr(UnaryExpr expr) {
    final rhs = expr.rhs.accept(this);
    final op = expr.prefix.lexeme;
    return '$op$rhs';
  }

  @override
  String visitWhileLoopStmt(WhileLoopStmt whileLoopStmt) {
    final expr = whileLoopStmt.expr.accept(this);
    final body = whileLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    return 'while $expr do$_sep$body${_sep}end';
  }
}
