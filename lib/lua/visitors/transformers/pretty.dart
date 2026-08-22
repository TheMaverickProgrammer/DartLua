import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

class Pretty extends Visitor<String> {
  @override
  String visitAST(AST ast) {
    return ast.stmts.map((e) => e.accept(this)).join('\n');
  }

  @override
  String visitBreakStmt(BreakStmt stmt) => 'break';

  @override
  String visitReturnStmt(ReturnStmt expr) {
    if (expr.values.isEmpty) {
      return 'return';
    }

    final args = expr.values.map((e) => e.accept(this)).join(',');
    return 'return $args';
  }

  @override
  String visitBinaryExpr(BinaryExpr expr) {
    final lhs = expr.lhs.accept(this);
    final rhs = expr.rhs.accept(this);
    final op = expr.op.lexeme;
    return '$lhs $op $rhs';
  }

  @override
  String visitUnaryExpr(UnaryExpr expr) {
    final prefix = expr.prefix.lexeme;
    final rhs = expr.rhs.accept(this);
    return '$prefix$rhs';
  }

  @override
  String visitAssignStmt(AssignStmt assignStmt) {
    final lhs = assignStmt.lhs.accept(this);
    final rhs = assignStmt.rhs.accept(this);
    final op = assignStmt.token.lexeme;
    return '$lhs $op $rhs';
  }

  @override
  String visitAssignMultiStmt(AssignMultiStmt assignMultiStmt) {
    final lhs = assignMultiStmt.lhs.map((e) => e.accept(this)).join(',');
    final rhs = assignMultiStmt.rhs.map((e) => e.accept(this)).join(',');
    final op = assignMultiStmt.token.lexeme;
    return '$lhs $op $rhs';
  }

  @override
  String visitDeclArg(DeclArg declArg) {
    final arg = declArg.id.lexeme;
    return arg;
  }

  @override
  String visitDeclVar(DeclVar declVar) {
    final id = declVar.id.lexeme;
    final value = declVar.init?.accept(this);
    final attr = switch(declVar.attr?.lexeme) {
      final String s => ' <$s> ',
      _ => '',
    };

    if (value == null) {
      return 'local $id$attr';
    }

    return 'local $id$attr = $value';
  }

  @override
  String visitDeclMultiVar(DeclMultiVar declMultiVar) {
    return declMultiVar.vars.fold('', (v, e) => v + e.accept(this));
  }

  @override
  String visitFuncExpr(FuncExpr expr) {
    final id = switch (expr.id) {
      '' => '<anonymous>',
      final String s => s,
    };

    final args = expr.args.map((e) => e.id.lexeme).join(',');
    final body = expr.body.map((e) => e.accept(this)).join('\n');

    return 'function $id($args)\n$body\nend';
  }

  @override
  String visitIfStmt(IfStmt stmt) {
    String str = '';
    final String body = stmt.body.map((e) => e.accept(this)).join('\n');

    if (stmt.isTerminalElse) {
      return '\n$body';
    }

    final String ifExpr = stmt.expr!.accept(this);
    str = 'if $ifExpr then\n$body';
    if (stmt.nextIfStmt != null) {
      str = '$str\nelse${stmt.nextIfStmt!.accept(this)}';
    }

    return '$str\nend';
  }

  @override
  String visitGroupExpr(GroupExpr groupExpr) {
    final str = groupExpr.expr.accept(this);
    return '($str)';
  }

  @override
  String visitNotExpr(NotExpr notExpr) {
    final str = notExpr.expr.accept(this);
    return 'not $str';
  }

  String _printFieldAccess(MemoryAccess mem) {
    final id = mem.callee.accept(this);
    final op = mem.op.lexeme;
    final field = mem.args.first.accept(this);
    return '$id$op$field';
  }

  String _printTableAccess(MemoryAccess mem) {
    final id = mem.callee.accept(this);
    final field = mem.args.first.accept(this);
    return '$id[$field]';
  }

  String _printCallable(MemoryAccess mem) {
    final callee = mem.callee.accept(this);
    final args = mem.args.map((e) => e.accept(this)).join(',');

    if (mem.op.type == TokenType.kColon) {
      return '$callee:$args';
    }

    return '$callee($args)';
  }

  @override
  String visitMemoryAccess(MemoryAccess memoryAccess) {
    return switch (memoryAccess.type) {
      MemoryAccessType.field => _printFieldAccess(memoryAccess),
      MemoryAccessType.table => _printTableAccess(memoryAccess),
      MemoryAccessType.call => _printCallable(memoryAccess),
    };
  }

  @override
  String visitRawExpr(RawExpr rawExpr) {
    return rawExpr.token.lexeme;
  }

  @override
  String visitSelfExpr(SelfExpr selfExpr) {
    return 'self';
  }

  @override
  String visitBooleanLiteral(BooleanLiteral boolean) {
    return boolean.value.toString();
  }

  @override
  String visitNumberLiteral(NumberLiteral number) {
    return number.value.toString();
  }

  @override
  String visitStringLiteral(StringLiteral string) {
    return '"${string.value}"';
  }

  @override
  String visitNilLiteral(NilLiteral nil) {
    return 'nil';
  }

  @override
  String visitTableLiteral(TableLiteral table) {
    final args = table.pairs.map((e) => e.accept(this)).join(',');
    return '{$args}';
  }

  @override
  String visitKeyValStmt(KeyValStmt keyval) {
    final k = keyval.key?.accept(this);
    final v = keyval.value.accept(this);

    if (k == null) {
      return v;
    }

    return '$k=$v';
  }

  @override
  String visitForLoopStmt(ForLoopStmt forLoopStmt) {
    final exprs = forLoopStmt.exprList.map((e) => e.accept(this)).join(',');
    final body = forLoopStmt.body.map((e) => e.accept(this)).join('/n');
    return 'for $exprs do\n$body\nend';
  }

  @override
  String visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt) {
    final vars = forIterLoopStmt.vars.map((e) => e.lexeme).join(',');
    final exprs = forIterLoopStmt.exprs.map((e) => e.accept(this)).join(',');
    final body = forIterLoopStmt.body.map((e) => e.accept(this)).join('/n');
    return 'for $vars in $exprs do\n$body\nend';
  }

  @override
  String visitRepeatUntilLoopStmt(RepeatUntilLoopStmt repeatUntilLoopStmt) {
    final body = repeatUntilLoopStmt.body.map((e) => e.accept(this)).join('/n');
    final expr = repeatUntilLoopStmt.untilExpr.accept(this);

    return 'repeat\n$body\nuntil $expr';
  }

  @override
  String visitWhileLoopStmt(WhileLoopStmt whileLoopStmt) {
    final exprs = whileLoopStmt.expr.accept(this);
    final body = whileLoopStmt.body.map((e) => e.accept(this)).join('/n');
    return 'while $exprs do\n$body\nend';
  }

  @override
  String visitGotoStmt(GotoStmt gotoStmt) {
    return 'goto ${gotoStmt.expr.accept(this)}';
  }

  @override
  String visitGotoLabelStmt(GotoLabelStmt stmt) {
    return '::${stmt.label.lexeme}::';
  }
}
