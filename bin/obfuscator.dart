import 'package:puredartlua/lua/lua.dart';

class Obfuscator extends Visitor<String> {
  String content = '';

  final Map<String, String> ids = {};
  final List<String> _nextId = ['a'];

  Obfuscator(AST ast) {
    content = visitAST(ast);
    final prelude = ids.entries.map((m) => '${m.value} = ${m.key}').join(';');
    content = '$prelude;$content';
  }

  String writeOrReadNewID(String id) {
    if(ids.containsKey(id)) {
      return ids[id]!;
    }

    final newid = ids[id] =  _nextId.join();
    if(_nextId.last == 'z') {
      _nextId[_nextId.length-1] = 'a';
      _nextId.add('a');
    } else {
      _nextId[_nextId.length-1] = String.fromCharCode(_nextId.last.codeUnitAt(0)+1);
    }

    return newid;
  }

  @override
  visitAST(AST ast) {
    return ast.stmts.map((e) => e.accept(this)).join(';');
  }

  @override
  visitAssignMultiStmt(AssignMultiStmt assignMultiStmt) {
    final lhs = assignMultiStmt.lhs.map((e) => e.accept(this)).join(',');
    final rhs = assignMultiStmt.rhs.map((e) => e.accept(this)).join(',');
    return '$lhs = $rhs';
  }

  @override
  visitAssignStmt(AssignStmt assignStmt) {
    final lhs = assignStmt.lhs.accept(this);
    final rhs = assignStmt.rhs.accept(this);
    return '$lhs = $rhs';
  }

  @override
  visitBinaryExpr(BinaryExpr expr) {
    final lhs = expr.lhs.accept(this);
    final rhs = expr.rhs.accept(this);
    final op  = expr.op.lexeme;
    return '$lhs $op $rhs';
  }

  @override
  visitBooleanLiteral(BooleanLiteral boolean) {
    return boolean.token.lexeme;
  }

  @override
  visitBreakStmt(BreakStmt stmt) {
    return 'break';
  }

  @override
  visitDeclArg(DeclArg declArg) {
    return writeOrReadNewID(declArg.lexeme);
  }

  @override
  visitDeclMultiVar(DeclMultiVar declMultiVar) {
    final lhs = declMultiVar.vars.map((e) => e.accept(this)).join(',');
    final rhs = declMultiVar.vals.map((e) => e.accept(this)).join(',');
    final scp = switch(declMultiVar.local) { true => 'local', _ => ''};
    return '$scp $lhs=$rhs';
  }

  @override
  visitDeclVar(DeclVar declVar) {
    final id = writeOrReadNewID(declVar.id.lexeme);
    final init = declVar.init?.accept(this);

    if(init != null) {
      return '$id=$init';
    }

    return id;
  }

  @override
  visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt) {
    final head = forIterLoopStmt.vars.map((e) => writeOrReadNewID(e.lexeme)).join(',');
    final tail = forIterLoopStmt.exprs.map((e) => e.accept(this)).join(',');
    final body = forIterLoopStmt.body.map((e) => e.accept(this)).join(';');
    return 'for $head in $tail do;$body;end';
  }

  @override
  visitForLoopStmt(ForLoopStmt forLoopStmt) {
    final expr = forLoopStmt.exprList.map((e) => e.accept(this)).join(',');
    final body = forLoopStmt.body.map((e) => e.accept(this)).join(';');
    return 'for $expr do;$body;end';
  }

  @override
  visitFuncExpr(FuncExpr expr) {
    final id = expr.idParts.map((e) => e.accept(this)).join('.');
    final args = expr.args.map((e) => e.accept(this)).join(',');
    final body = expr.body.map((e) => e.accept(this)).join(';');
    return 'function $id($args);$body;end';
  }

  @override
  visitGotoLabelStmt(GotoLabelStmt gotoLabelStmt) {
    return '::${writeOrReadNewID(gotoLabelStmt.label.lexeme)}::';
  }

  @override
  visitGotoStmt(GotoStmt gotoStmt) {
    final label = gotoStmt.expr.accept(this);
    return 'goto $label';
  }

  @override
  visitGroupExpr(GroupExpr groupExpr) {
    final expr = groupExpr.expr.accept(this);
    return '($expr)';
  }

  @override
  visitIfStmt(IfStmt stmt) {
    final expr = stmt.expr?.accept(this);
    final body = stmt.body.map((e) => e.accept(this));

    final next = switch(stmt.isTerminalElse) {
      true => 'else;$body',
      false => switch(stmt.nextIfStmt?.accept(this)) {
        final String n => 'else $n',
        null => '',
      }
    };

    return 'if $expr do;$body;$next;end';
  }

  @override
  visitKeyValStmt(KeyValStmt keyval) {
    final key = keyval.key?.accept(this);
    final val = keyval.value.accept(this);
    if(key == null) {
      return val;
    }
    return '$key=$val';
  }

  @override
  visitMemoryAccess(MemoryAccess memoryAccess) {
    final id = memoryAccess.callee.accept(this);
    final field = memoryAccess.field?.accept(this);
    final args = memoryAccess.args.map((e) => e.accept(this)).join(',');

    return switch(memoryAccess.type) {
      MemoryAccessType.field => '$id.$field',
      MemoryAccessType.table => '$id[$field]',
      MemoryAccessType.call => '$id($args)',
    };
  }

  @override
  visitNilLiteral(NilLiteral nil) {
    return 'nil';
  }

  @override
  visitNotExpr(NotExpr notExpr) {
    final expr = notExpr.expr.accept(this);
    return 'not $expr';
  }

  @override
  visitNumberLiteral(NumberLiteral number) {
    return number.token.lexeme;
  }

  @override
  visitRawExpr(RawExpr rawExpr) {
    return writeOrReadNewID(rawExpr.token.lexeme);
  }

  @override
  visitRepeatUntilLoopStmt(RepeatUntilLoopStmt repeatUntilLoopStmt) {
    final expr = repeatUntilLoopStmt.untilExpr.accept(this);
    final body = repeatUntilLoopStmt.body.map((e) => e.accept(this)).join(';');
    return 'repeat;$body;until($expr)';
  }

  @override
  visitReturnStmt(ReturnStmt expr) {
    final args = expr.values.map((e) => e.accept(this)).join(',');

    if(args.isEmpty) {
      return 'return';
    }
    return 'return $args';
  }

  @override
  visitSelfExpr(SelfExpr selfExpr) {
    return writeOrReadNewID(selfExpr.token.lexeme);
  }

  @override
  visitStringLiteral(StringLiteral string) {
    return '"${string.value}"';
  }

  @override
  visitTableLiteral(TableLiteral table) {
    final pairs = table.pairs.map((e) => e.accept(this)).join(';');
    return '{$pairs}';
  }

  @override
  visitUnaryExpr(UnaryExpr expr) {
    final rhs = expr.rhs.accept(this);
    final op = expr.prefix.lexeme;
    return '$op$rhs';
  }

  @override
  visitWhileLoopStmt(WhileLoopStmt whileLoopStmt) {
    final expr = whileLoopStmt.expr.accept(this);
    final body = whileLoopStmt.body.map((e) => e.accept(this)).join(';');
    return 'while $expr do;$body;end';
  }
}