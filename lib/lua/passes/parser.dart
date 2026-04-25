import 'package:puredartlua/lua/visitors/visitor.dart';
import 'package:puredartlua/lua/passes/lexer.dart';

T echo<T extends Stmt>(T t) {
  //final Pretty printer = Pretty();
  //print(t.accept(printer));
  return t;
}

const List<TokenType> vars = [TokenType.kSelf, TokenType.kRaw];

class Parser {
  final List<String> errors = [];
  final List<String> warns = [];
  final List<Token> tokens;
  int curr = 0;

  Parser(this.tokens);

  Token peek({int? offset}) {
    final int idx = curr + (offset ?? 0);
    if (idx >= tokens.length) {
      return Token.eof();
    }

    return tokens[idx];
  }

  bool anyOf(List<TokenType> types) => types.contains(peek().type);

  bool eof() => curr >= tokens.length;

  Token advance() {
    final token = peek();

    do {
      curr++;
    } while (peek().type == TokenType.kNewLine);

    return token;
  }

  T advanceAndThen<T>(T Function() then) {
    advance();
    return then.call();
  }

  Token consume(TokenType expected, String err) {
    final token = advance();
    final found = token.type;

    if (found != expected) {
      throw '${token.pos} Found $found. $err';
    }

    return token;
  }

  void addError(String err) {
    errors.add(err);
  }

  void addWarning(String warn) {
    warns.add(warn);
  }

  AST analyze() {
    final List<Stmt> stmts = [];
    while (!eof()) {
      try {
        final s = stmt();
        if (s == null) {
          continue;
        }
        stmts.add(s);
      } catch (e) {
        addError(e.toString());
        advance();
      }
    }
    return AST(stmts);
  }

  Stmt? stmt() {
    final Token token = peek();

    // Consume tokens which consist of a newline
    // at the start of a statement.
    if (token.type == TokenType.kNewLine) {
      advance();
      return null;
    }

    // Consume comments.
    if ([
      TokenType.kLineComment,
      TokenType.kBlockComment,
    ].contains(token.type)) {
      advance();
      return null;
    }

    // Added feature late: https://www.lua.org/manual/5.5/manual.html#3.3.3
    handleMultiAssignExpr(MathExpr expr) {
      if (peek().type == TokenType.kComma) {
        // Ugly hack. Clearly one term is bound.
        // We can drop the other terms, but we need to
        // collect them.
        if (expr is AssignExpr) {
          while (peek().type == TokenType.kComma) {
            advance();
            math();
          }
        } else {
          return multiAssignExpr(first: expr);
        }
      }
      return expr;
    }

    return echo(switch (token.type) {
      TokenType.kLocal => localStmt(),
      TokenType.kReturn => returnStmt(),
      TokenType.kIf => ifStmt(),
      TokenType.kFor => forLoopStmt(),
      TokenType.kWhile => whileLoopStmt(),
      TokenType.kRepeat => repeatUntilLoopStmt(),
      TokenType.kBreak => breakStmt(),
      TokenType.kGoto => gotoStmt(),
      TokenType.kGotoLabel => gotoLabelStmt(),
      _ => handleMultiAssignExpr(math()),
    });
  }

  AssignExpr assignExpr() {
    final id = consume(
      TokenType.kRaw,
      'Expected a variable name in assignment.',
    );
    final op = consume(TokenType.kAssign, 'Expected "=" for assignment.');
    final rhs = math();
    return AssignExpr(op, lhs: RawExpr(id), rhs: rhs);
  }

  Stmt localStmt() {
    consume(TokenType.kLocal, 'Expected "local" before variable or function.');
    if (peek().type == TokenType.kFunc) {
      return FuncExpr.local(declFuncExpr());
    }

    return declMultiVarStmt();
  }

  Stmt declMultiVarStmt() {
    final token = consume(
      TokenType.kRaw,
      'Expected variable name after "local".',
    );

    final tokens = [token];
    while (peek().type == TokenType.kComma) {
      advance();
      tokens.add(
        consume(
          TokenType.kRaw,
          'Expected variable name in multi-variable initializer.',
        ),
      );
    }

    final assign = peek();
    if (assign.type != TokenType.kAssign) {
      return DeclMultiVar.initNils(tokens);
    }

    consume(
      TokenType.kAssign,
      'Expected assignment operator for multi-variable initilaizer.',
    );

    final List<MathExpr> values = [math()];

    while (peek().type == TokenType.kComma) {
      advance();
      values.add(math());
    }

    return DeclMultiVar.initVars(tokens, values);
  }

  Stmt returnStmt() {
    const retTerminals = [
      TokenType.kEnd,
      TokenType.kElse,
      TokenType.kElseIf,
      TokenType.kUntil,
    ];

    consume(TokenType.kReturn, 'Expected "return" keyword.');
    return ReturnStmt(argList(terminals: retTerminals));
  }

  Stmt breakStmt() {
    consume(TokenType.kBreak, 'Expected "break" keyword.');
    return BreakStmt();
  }

  Stmt gotoStmt() {
    consume(TokenType.kGoto, 'Expected "goto" keyword.');
    return GotoStmt(rawExpr());
  }

  Stmt gotoLabelStmt() {
    final token = consume(
      TokenType.kGotoLabel,
      'Expected ::label:: statement.',
    );
    return GotoLabelStmt(token);
  }

  IfStmt ifStmt() {
    final token = consume(TokenType.kIf, 'Expected "if" keyword.');
    return ifStmtBranch(token);
  }

  IfStmt ifStmtBranch(Token token) {
    final lexeme = token.lexeme;
    bool isElseBranch = true;
    MathExpr? condition;

    if (token.type != TokenType.kElse) {
      isElseBranch = false;
      condition = math();
      consume(TokenType.kThen, 'Expected "then" keyword before body.');
    }

    const ifTailList = [TokenType.kEnd, TokenType.kElseIf, TokenType.kElse];
    final body = bodyStmt(terminals: ifTailList);

    // Sanity check. We expect to consume one of the items
    // in the terminal list.
    IfStmt? next;
    final p = peek();
    if (!ifTailList.contains(p.type)) {
      throw '${p.pos} Expected end of "$lexeme" block to match with "elseif", "else", or "end".';
    } else {
      final nextToken = advance();
      if (nextToken.type != TokenType.kEnd) {
        // Add elseif and else chains to this node.
        next = ifStmtBranch(nextToken);
      }
    }

    if (isElseBranch) {
      return IfStmt.terminalElse(token, body: body);
    }

    return IfStmt(token, expr: condition!, body: body, nextIfStmt: next);
  }

  Stmt forLoopStmt() {
    final token = consume(TokenType.kFor, 'Expected "for" keyword.');

    // Look-ahead to determine for-loop type.
    final next = peek(offset: 1);
    if (next.type == TokenType.kComma) {
      // This is an iterator for-loop.
      final key = consume(TokenType.kRaw, 'Expected name for key term.');
      consume(TokenType.kComma, 'Expected "," between key and value terms.');
      final value = consume(TokenType.kRaw, 'Expected name for value term.');
      consume(TokenType.kIn, 'Expected "in" before for-in loop iterator.');
      final iterExpr = math();
      consume(TokenType.kDo, 'Expected "do" before for-in loop body.');
      final body = bodyStmt(terminal: TokenType.kEnd);
      consume(
        TokenType.kEnd,
        'Expected "end" keyword to terminate for-in loop.',
      );
      return ForIterLoopStmt(
        token,
        key: key,
        value: value,
        iterExpr: iterExpr,
        body: body,
      );
    } else if (next.type == TokenType.kAssign) {
      // This is a ranged for-loop.
      final control = assignExpr();
      consume(TokenType.kComma, 'Expected "," before for-loop end term.');
      final endExpr = math();

      final MathExpr stepExpr;
      final pk = peek();
      if (pk.type == TokenType.kDo) {
        // This is a ranged for-loop with implied step of 1.
        stepExpr = NumberLiteral(
          Token(TokenType.kNumber, "1", pk.pos),
          value: 1.0,
        );
      } else {
        consume(TokenType.kComma, 'Expected "," before for-loop step term.');
        stepExpr = math();
      }

      consume(TokenType.kDo, 'Expected "do" before for-loop body.');

      final body = bodyStmt(terminal: TokenType.kEnd);
      consume(TokenType.kEnd, 'Expected for-loop to terminate with "end".');

      return ForLoopStmt(
        token,
        control: control,
        endExpr: endExpr,
        stepExpr: stepExpr,
        body: body,
      );
    } else {
      // There is a problem.
      throw '${next.pos} Unexpected $next in for-loop statement.';
    }
  }

  Stmt whileLoopStmt() {
    final token = consume(TokenType.kWhile, 'Expected "while" keyword.');
    final expr = math();
    consume(TokenType.kDo, 'Expected while-loop to begin with "do" keyword.');
    final body = bodyStmt(terminal: TokenType.kEnd);
    consume(
      TokenType.kEnd,
      'Expected while-loop to terminate with "end" keyword.',
    );
    return WhileLoopStmt(token, expr: expr, body: body);
  }

  Stmt repeatUntilLoopStmt() {
    final token = consume(TokenType.kRepeat, 'Expected "repeat" keyword.');
    final body = bodyStmt(terminal: TokenType.kUntil);
    consume(
      TokenType.kUntil,
      'Expected repeat-loop to terminate with "until" expression.',
    );
    final expr = math();
    return RepeatUntilLoopStmt(token, untilExpr: expr, body: body);
  }

  FuncExpr declFuncExpr() {
    consume(TokenType.kFunc, 'Expected "function" before declaration.');
    final List<RawExpr> idParts = [];
    final Token start = peek();
    Token token = start;

    bool desugarSelf = false;

    // Assume true. The next step will read a name, if any,
    // and change this to false if no name was read.
    if (token.type == TokenType.kRaw) {
      addIDPart() {
        idParts.add(
          RawExpr(
            consume(
              TokenType.kRaw,
              'Expected valid identifier in function name.',
            ),
          ),
        );
      }

      do {
        addIDPart();
        switch (peek().type) {
          case TokenType.kDot:
            advance();
          case TokenType.kColon:
            advance();
            // Break early. The grammar allows only the last
            // ID part to contain a colon.
            desugarSelf = true;
            addIDPart();
            break;
          default:
        }
        token = peek();
      } while (token.type != TokenType.kLParen);

      consume(
        TokenType.kLParen,
        'Missing left parentheses after function name.',
      );
    } else {
      consume(
        TokenType.kLParen,
        'Expected an unnamed function to have an argument list wrapped in parentheses.',
      );
    }

    final List<DeclArg> args = [
      if (desugarSelf)
        DeclArg(Token.synthesized('self', type: TokenType.kSelf)),
    ];

    while (peek().type != TokenType.kRParen) {
      final arg = advance();

      if (!vars.contains(arg.type)) {
        throw '${arg.pos} Expected argument name in declaration.';
      }

      args.add(DeclArg(arg));
      if (peek().type == TokenType.kComma) {
        advance();
      }
    }

    if (args.isNotEmpty) {
      final int count = args
          .where((e) => e.id.type == TokenType.kSpread)
          .length;
      if (count > 1 || (count == 1 && args.last.id.type != TokenType.kSpread)) {
        throw 'Varargs can only appear once at the end of an argument list.';
      }
    }

    consume(
      TokenType.kRParen,
      'Expected closing parentheses after argument list.',
    );

    final List<Stmt> body = bodyStmt(terminal: TokenType.kEnd);

    consume(TokenType.kEnd, 'Expected "end" after function body.');

    // No name expression was found. This must be an anonymous function.
    if (idParts.isEmpty) {
      return FuncExpr.anonymous(start, body: body, args: args);
    }

    return FuncExpr.named(start, body: body, args: args, idParts: idParts);
  }

  MathExpr math() {
    final lhs = logicalOrExpr();
    final op = peek();

    return switch (op.type) {
      TokenType.kAssign => AssignExpr(
        op,
        lhs: lhs,
        rhs: advanceAndThen(logicalOrExpr),
      ),
      _ => lhs,
    };
  }

  MathExpr multiAssignExpr({required MathExpr first}) {
    final bool ok = canMultAssignWith(first);
    if (!ok) {
      final linePos = peek().pos;
      throw '$linePos Leading term in mutli-assignment was not a variable.';
    }

    final lhs = [first];
    int i = 2;
    while (peek().type == TokenType.kComma) {
      advance();
      final next = memoryExpr();
      if (canMultAssignWith(next)) {
        lhs.add(next);
      } else {
        final linePos = peek().pos;
        throw '$linePos Term #$i in mutli-assignment was not a variable.';
      }
      i++;
    }

    final assign = peek();
    final linePos = assign.pos;

    if (assign.type != TokenType.kAssign) {
      throw '$linePos Expected "=" in multi-variable assignment expression.';
    }
    advance();

    final List<MathExpr> rhs = [math()];
    while (peek().type == TokenType.kComma) {
      advance();
      rhs.add(math());
    }

    if (lhs.length != rhs.length) {
      final int lhsLen = lhs.length;
      final int rhsLen = rhs.length;
      addWarning(
        '$linePos lhs of assignment has $lhsLen var(s) but rhs has $rhsLen val(s).',
      );
    }
    return AssignMultiExpr.resize(assign, lhs: lhs, rhs: rhs);
  }

  MathExpr logicalOrExpr() {
    MathExpr expr = logicalAndExpr();

    Token? op = peek();
    while (TokenType.kOr == op?.type) {
      advance();
      expr = BinaryExpr(op!, lhs: expr, rhs: logicalAndExpr());
      op = peek();
    }

    return expr;
  }

  MathExpr logicalAndExpr() {
    MathExpr expr = compareExpr();

    Token? op = peek();
    while (TokenType.kAnd == op?.type) {
      advance();
      expr = BinaryExpr(op!, lhs: expr, rhs: compareExpr());
      op = peek();
    }

    return expr;
  }

  MathExpr compareExpr() {
    MathExpr expr = binaryExpr();

    final binaries = [
      TokenType.kLT,
      TokenType.kLTE,
      TokenType.kGT,
      TokenType.kGTE,
      TokenType.kEQ,
      TokenType.kNEQ,
    ];

    Token? op = peek();
    while (binaries.contains(op?.type)) {
      advance();
      expr = BinaryExpr(op!, lhs: expr, rhs: binaryExpr());
      op = peek();
    }

    return expr;
  }

  MathExpr binaryExpr() {
    MathExpr expr = factorExpr();

    final binaries = [
      TokenType.kAdd,
      TokenType.kSub,
      TokenType.kMod,
      TokenType.kConcat,
    ];

    Token? op = peek();
    while (binaries.contains(op?.type)) {
      advance();
      expr = BinaryExpr(op!, lhs: expr, rhs: factorExpr());
      op = peek();
    }

    return expr;
  }

  MathExpr factorExpr() {
    MathExpr expr = bitwiseExpr();

    final factors = [
      TokenType.kMult,
      TokenType.kDiv,
      TokenType.kDivFloor,
      TokenType.kCarrot,
    ];

    Token? op = peek();
    while (factors.contains(op?.type)) {
      advance();
      expr = BinaryExpr(op!, lhs: expr, rhs: bitwiseExpr());
      op = peek();
    }

    return expr;
  }

  MathExpr bitwiseExpr() {
    MathExpr expr = unaryExpr();

    final bitops = [TokenType.kBitAnd, TokenType.kBitOr];

    Token? op = peek();
    while (bitops.contains(op?.type)) {
      advance();
      expr = BinaryExpr(op!, lhs: expr, rhs: unaryExpr());
      op = peek();
    }

    return expr;
  }

  MathExpr unaryExpr() {
    final token = peek();

    final expr = switch (token.type) {
      TokenType.kNot => notExpr(),
      TokenType.kBitNot ||
      TokenType.kHash ||
      TokenType.kSub => UnaryExpr(token, rhs: advanceAndThen(math)),
      _ => null,
    };

    if (expr != null) {
      return expr;
    }

    return objectExpr();
  }

  MathExpr objectExpr() {
    final token = peek();

    return switch (token.type) {
      TokenType.kLCurly => tableExpr(),
      _ => memoryExpr(),
    };
  }

  MathExpr groupExpr() {
    final token = consume(TokenType.kLParen, 'Expected opening parentheses.');
    final expr = math();
    consume(TokenType.kRParen, 'Expected closing parentheses.');
    return GroupExpr(token, expr);
  }

  MathExpr tableExpr() {
    final token = consume(TokenType.kLCurly, 'Expected opening curly brace.');
    final pairs = tablePairsList();
    return TableLiteral(token, pairs: pairs);
  }

  List<KeyValStmt> tablePairsList() {
    List<KeyValStmt> pairs = [];

    Token? next = peek();
    while (!eof() && next?.type != TokenType.kRCurly) {
      pairs.add(tablePairExpr());
      next = peek();

      if (next.type == TokenType.kComma) {
        advance();
        next = peek();
      }
    }

    consume(TokenType.kRCurly, 'Expected closing curly brace.');
    return pairs;
  }

  KeyValStmt tablePairExpr() {
    /*
      Key-value statement pairs used in table declarations
      can be one of three:
        - Just a value (keyless).
        - An __expression__ wrapped in brackets.
        - A symbol (a string without quotes).
    */

    final Token first = peek();
    bool usedBracketNotation = false;
    MathExpr? expr;
    int offset = 1;
    if (first.type == TokenType.kLBracket) {
      advance();
      expr = math();
      consume(TokenType.kRBracket, 'Expecting closing bracket for table key.');
      usedBracketNotation = true;
      offset = 0;
    } else if (first.type == TokenType.kLCurly) {
      return KeyValStmt.autokey(math());
    }

    if (peek(offset: offset).type == TokenType.kAssign) {
      expr ??= rawExpr();

      // Literal keys cannot be used unless inside bracket notation
      final bool isLiteral = switch (expr) {
        final BooleanLiteral _ => true,
        final StringLiteral _ => true,
        final NumberLiteral _ => true,
        _ => false,
      };

      if (!usedBracketNotation && isLiteral) {
        throw '${first.pos} Literal keys cannot be used unless inside bracket notation.';
      }
      advance();

      return KeyValStmt(key: expr, value: math());
    }

    return KeyValStmt.autokey(expr ?? math());
  }

  // Support https://www.lua.org/manual/5.5/manual.html#3.3.3
  // In multi-assignment expressions:
  //  - Literals are NOT allowed.
  //  - Function invocation is NOT allowed.
  //  - Group expressions (...) are NOT allowed.
  //  - Fields are OK.
  //  - Table access by index is OK.
  bool canMultAssignWith(MathExpr term) => switch (term) {
    final GroupExpr _ => false,
    final FuncExpr _ => false,
    final RawExpr r => switch (r.token.type) {
      TokenType.kRaw => true,
      _ => false,
    },
    final MemoryAccess m => switch (m.type) {
      MemoryAccessType.call => false,
      MemoryAccessType.field => true,
      MemoryAccessType.table => true,
    },
    _ => false,
  };

  MathExpr memoryExpr() {
    MathExpr lhs = literal();
    Token op = peek();

    const memOps = [
      TokenType.kDot,
      TokenType.kColon,
      TokenType.kLBracket,
      TokenType.kLParen,
    ];

    while (memOps.contains(op.type)) {
      lhs = switch (op.type) {
        TokenType.kDot => MemoryAccess.field(op, lhs, advanceAndThen(rawExpr)),
        TokenType.kLBracket => () {
          final arg = advanceAndThen(math);
          consume(TokenType.kRBracket, 'Expecting closing bracket.');
          return MemoryAccess.table(op, lhs, arg);
        }(),
        TokenType.kColon => () {
          advance();
          // Special case: the colon operator forwards the lhs object
          // into a function arg list as the new first argument.
          // Therefore, we need to be sugar that a function expression
          // follows and becomes our rhsExpr node.
          //
          // functioncall ::= prefixexp ':' Name args
          final MathExpr funcName = literal();
          final parenToken = consume(
            TokenType.kLParen,
            'Expected function call after colon ":" operator.',
          );
          final args = argList(terminal: TokenType.kRParen);
          consume(TokenType.kRParen, 'Expecting closing parentheses.');
          final rhsExpr = MemoryAccess.call(parenToken, funcName, args);

          // With the function node packed together, map this to lhs.
          final callee = lhs;
          final colon = op;
          return MemoryAccess.call(colon, callee, [rhsExpr]);
        }(),
        TokenType.kLParen => () {
          advance();
          final args = argList(terminal: TokenType.kRParen);
          consume(TokenType.kRParen, 'Expecting closing parentheses.');
          return MemoryAccess.call(op, lhs, args);
        }(),
        _ => lhs,
      };
      op = peek();
    }
    return lhs;
  }

  MathExpr literal() {
    final token = peek();

    return switch (token.type) {
      TokenType.kFunc => declFuncExpr(),
      TokenType.kTrue => trueExpr(),
      TokenType.kFalse => falseExpr(),
      TokenType.kNumber => numberLiteral(),
      TokenType.kString => stringLiteral(),
      TokenType.kNil => nilLiteral(),
      TokenType.kRaw => rawExpr(),
      TokenType.kSelf => selfExpr(),
      TokenType.kLParen => groupExpr(),
      final TokenType type => advanceAndThen(
        () =>
            throw '${token.pos} Expected literal value or variable. Found $type.',
      ),
    };
  }

  List<MathExpr> argList({TokenType? terminal, List<TokenType>? terminals}) {
    assert(
      (terminal != null) ^ (terminals != null),
      'Expected a single terminal or list of terminals.',
    );

    if (terminal != null) {
      terminals = [terminal];
    }
    // B/c of the steps above, it must be the case
    // that the list is not null.
    terminals!;

    final List<MathExpr> args = [];

    while (!eof() && !terminals.contains(peek().type)) {
      try {
        args.add(math());
      } catch (e) {
        addError(e.toString());
      }

      if (peek().type == TokenType.kComma) {
        advance();
      }
    }

    return args;
  }

  List<Stmt> bodyStmt({TokenType? terminal, List<TokenType>? terminals}) {
    assert(
      (terminal != null) ^ (terminals != null),
      'Expected a single terminal or list of terminals.',
    );

    if (terminal != null) {
      terminals = [terminal];
    }
    // B/c of the steps above, it must be the case
    // that the list is not null.
    terminals!;

    final List<Stmt> stmts = [];
    while (!eof() && !terminals.contains(peek().type)) {
      try {
        final s = stmt();
        if (s == null) continue;
        stmts.add(s);
      } catch (e) {
        addError(e.toString());
        advance();
      }
    }

    return stmts;
  }

  MathExpr notExpr() {
    final token = consume(TokenType.kNot, 'Expected "not" keyword.');
    return NotExpr(token, math());
  }

  RawExpr rawExpr() {
    final token = consume(TokenType.kRaw, 'Expected value or variable.');
    return RawExpr(token);
  }

  MathExpr trueExpr() {
    final token = consume(TokenType.kTrue, 'Expected "true".');
    return BooleanLiteral.asTrue(token);
  }

  MathExpr falseExpr() {
    final token = consume(TokenType.kFalse, 'Expected "false".');
    return BooleanLiteral.asFalse(token);
  }

  MathExpr numberLiteral() {
    final token = consume(TokenType.kNumber, 'Expected number literal.');
    final value = double.tryParse(token.lexeme);
    if (value == null) {
      throw '${token.pos} Number literal did not evaluate!';
    }
    return NumberLiteral(token, value: value);
  }

  MathExpr stringLiteral() {
    final token = consume(TokenType.kString, 'Expected string literal.');
    return StringLiteral(token, value: token.lexeme);
  }

  MathExpr nilLiteral() {
    final token = consume(TokenType.kNil, 'Expected "nil" keyword.');
    return NilLiteral(token);
  }

  MathExpr selfExpr() {
    final token = consume(TokenType.kSelf, 'Expected "self" keyword.');
    return SelfExpr(token);
  }
}
