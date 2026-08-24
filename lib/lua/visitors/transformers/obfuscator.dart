import 'package:puredartlua/lua/lua.dart';
import 'package:puredartlua/lua/passes/lexer.dart';

/// Line separator. Placed here for debugging.
final String _sep = ';';

/// A simple lexical scope to track the lifetime of variables.
/// This helps our mapping algorithm preserve variable correctness
/// across the entire program.
class Scope {
  /// Optional parent scope. If null, this is global scope.
  final Scope? parent;

  /// ID or constant -> remapped id.
  final Map<String, String> ids = {};

  /// The next id to use in [mapID].
  final List<String> _nextId = [];

  /// Advances the next ID and returns it using the following
  /// collection as a sequence of combinations: `[a-zA-Z0-9]
  /// where all digits except the first can include [0-9] b/c
  /// the first digit in the sequence must be a valid lua
  /// variable name. 1 million unique variables can fit
  /// comfortably in 4 digit generations using this scheme.
  void advanceNextId() {
    bump(int n) {
      if(n-1 >= 0) {
        _nextId[n-1] = 'a';
      }

      if(n == _nextId.length) return false;
      if(_nextId[n] == 'z') {
        _nextId[n] = 'A';
      } else if(_nextId[n] == 'Z') {
        if(n == 0) {
          return bump(n+1);
        }else {
          _nextId[n] = '0';
        }
      }
      else if(_nextId[n] == '9') {
        return bump(n+1);
      } else {
        _nextId[n] = String.fromCharCode(_nextId[n].codeUnitAt(0) + 1);
      }
      return true;
    }

    do {
      if(!bump(0)) {
        for(int i = 0; i < _nextId.length; i++) {
          _nextId[i] = 'a';
        }
        _nextId.add('a');
      }

    } while(keywords.contains(_nextId.join()));
  }

  /// Clears [_nextId] and copies the contents of
  /// the [other]'s own [nextId].
  /// This should be used with caution as the two scopes could
  /// shadow variables where this is not wanted.
  void resetNextIdFrom(Scope other) {
    _nextId..clear()..addAll(other._nextId);
  }

  /// If [id] is not already assigned a new identifier,
  /// then constructs one with [_newId]. Then advances
  /// the new id set via [advanceNextId].
  String createID(String id) {
    if(_nextId.isEmpty) {
      _nextId.add('a');
    }

    final newid = ids[id] =  _nextId.join();
    advanceNextId();
    return newid;
  }

  /// Returns the mapped [id] stored in [ids].
  /// If the mapped [id] is not found in this scope,
  /// then walks up the [Scope.parent] chain until it
  /// is found. In this way we preserve lexical scoping
  /// and globals. If no id is found, null is returned.
  String? getID(String id) {
    if(ids.containsKey(id)) {
      return ids[id]!;
    } else {
      final String? result = parent?.getID(id);
      if(result != null) {
        return result;
      }
    }

    return null;
  }

  /// Ctor.
  Scope([this.parent]);
}

/// A very simple obfuscator example.
/// Visits every node and generates minified lua.
/// Identifiers are remapped to the next smallest unique id
/// composed of strictly lower-case alphanumeric chars. An
/// optional prelude of terms to include at the top of the
/// script can be provided in the constructor.
/// See [Obfuscator.new].
class Obfuscator extends Visitor<String> {
  /// Global scope.
  late Scope global;

  /// Prelude scope. These entries will be first
  /// written out before the final [content].
  late Scope pscope;

  /// Current scope.
  late Scope current;

  /// The output content to write to file.
  String content = '';

  /// Constructor walks the AST,
  /// generates a [prelude] of remapped variables,
  /// and stores the result in [content].
  Obfuscator(AST ast, {List<String> prelude = const []}) {
    pscope = _populatePrelude(prelude);
    global = Scope(pscope)..resetNextIdFrom(pscope);
    current = global;
    content = visitAST(ast);

    // Identifiers for std library needs to be preserved
    // so lua VMs can run them.
    final p =
      pscope.ids.entries.map((m) => '${m.value} = ${m.key}').join(_sep);

    content = '$p$_sep$content';
  }

  /// Forwards call to [current]'s [Scope.createID].
  /// Exception: metamethods have their IDs preserved
  String createID(String id) {
    const List<String> meta = [
      '__newindex',
      '__index',
      '__call',
      '__add',
      '__sub',
      '__band',
      '__bnot',
      '__bor',
      '__bxor',
      '__call',
      '__concat',
      '__div',
      '__eq',
      '__idiv',
      '__le',
      '__lt',
      '__len',
      '__mod',
      '__mul',
      '__pow',
      '__shl',
      '__shr',
      '__unm',
    ];

    if(meta.contains(id)) {
      current.ids[id] = id;
      return id;
    }

    return current.createID(id);
  }

  /// For every id in [from], calls [Scope.createID]
  /// on the [prelude] scope.
  Scope _populatePrelude(List<String> from) {
    final prelude = Scope();
    for(final String f in from) {
      prelude.createID(f);
    }
    return prelude;
  }

  /// Forwards call to [current]'s [Scope.getID].
  /// Exception: metamethods have their IDs preserved
  String? getID(String id) => current.getID(id);

  /// Create a new [Scope] with parent [prev].
  void pushScope(Scope prev) {
    current = Scope(prev);
  }

  /// Pops scope and restores [current] to the
  /// previous scope [Scope.parent];
  void popScope() {
    if(current.parent != null) {
      current = current.parent!;
    }
  }

  /// Utility to wrap contents in [block] with
  /// [pushScope] and [popScope] respectively.
  /// Preserves the parent scope [prev].
  void wrapScope(Scope prev, {required Function() block}) {
    pushScope(prev);
    block();
    popScope();
  }

  @override
  String visitAST(AST ast) {
    return ast.stmts.map((e) => e.accept(this)).join(_sep);
  }

  @override
  String visitAssignMultiStmt(AssignMultiStmt assignMultiStmt) {
    final lhs = assignMultiStmt.lhs.map((e) => e.accept(this)).join(',');
    final rhs = assignMultiStmt.rhs.map((e) => e.accept(this)).join(',');
    return '$lhs=$rhs';
  }

  @override
  String visitAssignStmt(AssignStmt assignStmt) {
    final lhs = assignStmt.lhs.accept(this);
    final rhs = assignStmt.rhs.accept(this);
    return '$lhs=$rhs';
  }

  @override
  String visitBinaryExpr(BinaryExpr expr) {
    final lhs = expr.lhs.accept(this);
    final rhs = expr.rhs.accept(this);
    final op  = expr.op.lexeme;

    return switch(expr.op.type) {
      TokenType.kAnd || TokenType.kOr => '$lhs $op $rhs',
      _ => '$lhs$op$rhs',
    };
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
    return createID(declArg.lexeme);
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
    final id = createID(declVar.id.lexeme);
    final init = declVar.init?.accept(this);
    final attr = switch(declVar.attr?.lexeme) {
      final String s => '<$s>',
      _ => '',
    };

    if (init != null) {
      return '$id$attr=$init';
    }

    return '$id$attr';
  }

  @override
  String visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt) {
    final head = forIterLoopStmt.vars.map((e) => createID(e.lexeme)).join(',');
    final tail = forIterLoopStmt.exprs.map((e) => e.accept(this)).join(',');
    late final String body;
    wrapScope(current, block: () {
      body = forIterLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    });
    return 'for $head in $tail do$_sep$body${_sep}end';
  }

  @override
  String visitForLoopStmt(ForLoopStmt forLoopStmt) {
    final expr = forLoopStmt.exprList.map((e) => e.accept(this)).join(',');
    late final String body;
    wrapScope(current, block: () {
      body = forLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    });
    return 'for $expr do$_sep$body${_sep}end';
  }

  @override
  String visitFuncExpr(FuncExpr expr) {
    final id = expr.idParts.map((e) => e.accept(this)).join('.');
    final args = expr.args.map((e) => e.accept(this)).join(',');
    late final String body;
    wrapScope(current, block: () {
      body = expr.body.map((e) => e.accept(this)).join(_sep);
    });
    return 'function $id($args)$_sep$body${_sep}end';
  }

  @override
  String visitGotoLabelStmt(GotoLabelStmt gotoLabelStmt) {
    return '::${createID(gotoLabelStmt.label.lexeme)}::';
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
    late final String body;

    wrapScope(current, block: () {
      body = stmt.body.map((e) => e.accept(this)).join(_sep);
    });

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
    final id = rawExpr.token.lexeme;
    final out = getID(id);
    if(out == null) {
      return createID(id);
    }
    return out;
  }

  @override
  String visitRepeatUntilLoopStmt(RepeatUntilLoopStmt repeatUntilLoopStmt) {
    final expr = repeatUntilLoopStmt.untilExpr.accept(this);
    late final String body;
    wrapScope(current, block: () {
      body = repeatUntilLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    });
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
    return createID(selfExpr.token.lexeme);
  }

  @override
  String visitStringLiteral(StringLiteral string) {
    return global.createID('"${string.value}"');
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
  String visitDoBlockStmt(DoBlockStmt doBlockStmt) {
    late final String body;
    wrapScope(current, block: (){
      body = doBlockStmt.body.map((e) => e.accept(this)).join(_sep);
    });
    return 'do$_sep$body${_sep}end';
  }

  @override
  String visitWhileLoopStmt(WhileLoopStmt whileLoopStmt) {
    final expr = whileLoopStmt.expr.accept(this);
    late final String body;
    wrapScope(current, block: (){
      body = whileLoopStmt.body.map((e) => e.accept(this)).join(_sep);
    });
    return 'while $expr do$_sep$body${_sep}end';
  }
}
