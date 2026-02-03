import 'package:lualib/lua/passes/lexer.dart';

/// Base grammar node.
abstract class Stmt {
  R accept<R>(Visitor<R> v);
}

/// The entry node of any lua program.
/// A program is a collection of [stmts].
class AST extends Stmt {
  List<Stmt> stmts;

  AST(this.stmts);

  @override
  R accept<R>(Visitor<R> v) => v.visitAST(this);
}

/// This node tells the grammar how to
/// compose a function's argument list.
///
/// If a parameter [isOptional], then the
/// runtime won't include its cound in the
/// call expression.
///
/// Additionally. [isOptional] will decorate
/// this parameter in the generated docs.
class DeclArg extends Stmt {
  /// The name of this parameter.
  /// This is also the lexeme and pos in the doc.
  final Token id;

  /// Optional parameters must be last.
  /// Undefined behavior will follow if this rule is not.
  final bool isOptional;

  DeclArg(this.id, {this.isOptional = false});

  /// Shorthand for [id.lexeme].
  String get lexeme => id.lexeme;

  @override
  R accept<R>(Visitor<R> v) => v.visitDeclArg(this);
}

/// This represents a variable declaration in lua.
/// The variable name will be [id]. It may have
/// initialization terms provided by [init].
class DeclVar extends Stmt {
  final Token id;
  final MathExpr? init;

  /// Convenience to construct nil lua grammar node.
  DeclVar.initNil(this.id) : init = null;

  /// Constructor expects a [value]. If constructing
  /// a nil variable, see [DeclVar.initNil].
  DeclVar.initValue(this.id, {required MathExpr value}) : init = value;

  @override
  R accept<R>(Visitor<R> v) => v.visitDeclVar(this);
}

/// Lua supports multivariable assignment.
/// Therefore it supports multivariable declarations.
class DeclMultiVar extends Stmt {
  /// The list of [DeclVar] nodes.
  final List<DeclVar> vars;

  DeclMultiVar._(this.vars);

  /// Convenience constructor.
  /// See [DeclVar].
  factory DeclMultiVar.initNils(List<Token> tokens) {
    return DeclMultiVar._(
      tokens.map((e) => DeclVar.initNil(e)).toList(growable: false),
    );
  }

  /// Constructs a multivariable assignment expression
  /// from a list of [values]. If there are more [tokens]
  /// than there are [values], then the remaining [vars]
  /// will be associated with [DeclVar.initNil].
  factory DeclMultiVar.initVars(List<Token> tokens, List<MathExpr> values) {
    final List<DeclVar> vars = [];
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (i < values.length) {
        final val = values[i];
        vars.add(DeclVar.initValue(token, value: val));
      } else {
        vars.add(DeclVar.initNil(token));
      }
    }

    return DeclMultiVar._(vars);
  }

  @override
  R accept<R>(Visitor<R> v) => v.visitDeclMultiVar(this);
}

/// Represents a linked list of conditional statements.
/// Consider the chain if -> elif -> elif -> else.
/// Therefore else statements are [IfStmt] without an [expr].
/// See [IfStmt.terminalElse] constructor.
class IfStmt extends Stmt {
  /// The lexeme and pos in the doc.
  final Token token;
  final MathExpr? expr;
  final IfStmt? nextIfStmt;
  final bool isTerminalElse;
  final List<Stmt> body;

  IfStmt(
    this.token, {
    required MathExpr this.expr,
    required this.body,
    this.nextIfStmt,
  }) : isTerminalElse = false;

  IfStmt.terminalElse(this.token, {required this.body})
    : isTerminalElse = true,
      expr = null,
      nextIfStmt = null;

  @override
  R accept<R>(Visitor<R> v) => v.visitIfStmt(this);
}

/// Lua while-do loop grammar node.
class WhileLoopStmt extends Stmt {
  /// The lexeme and pos in the doc.
  final Token token;

  /// The conditional.
  final MathExpr expr;

  /// The body of code to visit if [expr] is truthy.
  final List<Stmt> body;

  WhileLoopStmt(this.token, {required this.expr, required this.body});

  @override
  R accept<R>(Visitor<R> v) => v.visitWhileLoopStmt(this);
}

/// The step-wise variant of lua's for-loop control structure.
class ForLoopStmt extends Stmt {
  /// The lexeme and pos in the doc.
  final Token token;

  /// The control term begins as an assignment.
  final AssignExpr control;

  /// Step-wise for-loops increase by [stepExpr]
  /// and the [body] executes until [control]
  /// reaches or exceeds [endExpr].
  final MathExpr endExpr, stepExpr;

  /// The body of code to visit.
  final List<Stmt> body;

  /// Convenience method to return all non-null expressions.
  List<MathExpr> get exprList => [control, endExpr, stepExpr].nonNulls.toList();

  ForLoopStmt(
    this.token, {
    required this.control,
    required this.endExpr,
    required this.stepExpr,
    required this.body,
  });

  @override
  R accept<R>(Visitor<R> v) => v.visitForLoopStmt(this);
}

/// The key-value variant of lua's for-loop control structure.
/// Unlike the step-wise variant, this destructures [iterExpr]
/// into [key] and [value] in each loop until there's nothing
/// left to destructure.
class ForIterLoopStmt extends Stmt {
  /// The lexeme and pos in the doc.
  final Token token;

  /// The key lexeme to be introduced in scope.
  final Token key;

  /// The value lexeme to be introduced in scope.
  final Token value;

  /// The iterator to advanced and destructure.
  final MathExpr iterExpr;

  /// The body of code to visit.
  final List<Stmt> body;

  ForIterLoopStmt(
    this.token, {
    required this.key,
    required this.value,
    required this.iterExpr,
    required this.body,
  });

  @override
  R accept<R>(Visitor<R> v) => v.visitForIterLoopStmt(this);
}

/// Similar to a while-loop but conditional
/// expression [untilExpr] is the termination condition.
class RepeatUntilLoopStmt extends Stmt {
  /// The lexeme and pos in the doc.
  final Token token;

  /// Termination condition expression.
  final MathExpr untilExpr;

  /// The body of code to visit.
  final List<Stmt> body;

  RepeatUntilLoopStmt(
    this.token, {
    required this.untilExpr,
    required this.body,
  });

  @override
  R accept<R>(Visitor<R> v) => v.visitRepeatUntilLoopStmt(this);
}

/// Represents the keyword 'return' in lua.
/// This keyword can return whole expressions
/// comma separated. See [values].
class ReturnStmt extends Stmt {
  final List<MathExpr> values;

  ReturnStmt(this.values);

  @override
  R accept<R>(Visitor<R> v) => v.visitReturnStmt(this);
}

/// Represents the keyword 'break' in lua.
class BreakStmt extends Stmt {
  BreakStmt();

  @override
  R accept<R>(Visitor<R> v) => v.visitBreakStmt(this);
}

/// Represents the 'goto' keyword in lua.
/// https://www.lua.org/manual/5.5/manual.html#3.3.4
class GotoStmt extends Stmt {
  /// The Name to jump to.
  final RawExpr expr;
  GotoStmt(this.expr);

  @override
  R accept<R>(Visitor<R> v) => v.visitGotoStmt(this);
}

/// Represents labels which goto statements use.
class GotoLabelStmt extends Stmt {
  /// The Name for the jump.
  final Token label;
  GotoLabelStmt(this.label);

  @override
  R accept<R>(Visitor<R> v) => v.visitGotoLabelStmt(this);
}

abstract class MathExpr extends Stmt {}

/// Function declarations can be assigned to variables
/// and are therefore math expressions.
class FuncExpr extends MathExpr {
  /// The lexeme and pos in the doc.
  final Token token;
  final List<RawExpr> idParts;
  final List<DeclArg> args;
  final List<Stmt> body;

  /// Whether or not this function was declare
  /// with 'local' keyword.
  final bool local;

  /// Functions that are declared without an
  /// [id] are anonymous functions.
  bool get isAnonymous => idParts.isEmpty;

  /// The identifier for this function.
  /// Generally the name of the function in scope.
  /// It can be composed of a chain of memory access
  /// expressions. e.g. `foo:bar().doh`.
  String get id => idParts.map((e) => e.token.lexeme).join('.');

  /// Convenience method to generate html stubs
  /// when generating documentation.
  String get argsHtml {
    String html = '';
    int brackets = 0;
    for (final DeclArg arg in args) {
      final String lexeme = arg.lexeme;

      decorate(String s) {
        if (arg.isOptional) {
          brackets++;
          return '[$s';
        }
        return s;
      }

      html = switch (html.isEmpty) {
        true => decorate(lexeme),
        false => '$html ${decorate(', $lexeme')}',
      };
    }

    while (brackets-- > 0) {
      html = '$html]';
    }

    return '($html)';
  }

  /// Construct a function with an [id].
  FuncExpr.named(
    this.token, {
    required this.body,
    required this.args,
    required this.idParts,
  }) : local = false;

  /// Construct a function without an [id].
  FuncExpr.anonymous(this.token, {required this.body, required this.args})
    : idParts = [],
      local = false;

  /// Constructs a local function out of [from].
  FuncExpr.local(FuncExpr from)
    : token = from.token,
      idParts = from.idParts,
      body = from.body,
      args = from.args,
      local = true;

  @override
  R accept<R>(Visitor<R> v) => v.visitFuncExpr(this);
}

/// Represents identifiers in lua.
/// Anything that is not a keyword or an expression
/// is likely an identifier like a variable name or
/// table fields. The spec defines labels as identifiers
/// but those are encoded in this lib by [GotoLabelStmt].
class RawExpr extends MathExpr {
  final Token token;

  RawExpr(this.token);

  @override
  R accept<R>(Visitor<R> v) => v.visitRawExpr(this);
}

/// The token for 'self'.
/// While not a keyword in lua,
/// it is encoded as one in this lib
/// for convenience.
class SelfExpr extends MathExpr {
  final Token token;

  SelfExpr(this.token);

  @override
  R accept<R>(Visitor<R> v) => v.visitSelfExpr(this);
}

/// Any binary expression (lhs op rhs) is encoded by this node.
/// [op] is the operator used on [lhs] and [rhs] expressions.
class BinaryExpr extends MathExpr {
  final Token op;
  final MathExpr lhs;
  final MathExpr rhs;

  BinaryExpr(this.op, {required this.lhs, required this.rhs});

  @override
  R accept<R>(Visitor<R> v) => v.visitBinaryExpr(this);
}

/// Any tightly bound unary [prefix] is encoded by this node.
class UnaryExpr extends MathExpr {
  final Token prefix;
  final MathExpr rhs;

  UnaryExpr(this.prefix, {required this.rhs});

  @override
  R accept<R>(Visitor<R> v) => v.visitUnaryExpr(this);
}

/// Memory access on a variable is in the form of
/// - a field using the dot operator
/// - a table using the brackets [...]
/// - a function call using parens (...)
enum MemoryAccessType { field, table, call }

/// Memory access node encodes which operator [op]
/// was used, the [callee] resolved on the left-hand side,
/// the [type] for convenience, and the input [args].
class MemoryAccess extends MathExpr {
  final Token op;
  final MathExpr callee;
  final MemoryAccessType type;
  final List<MathExpr> args;

  /// If this grammar is used to obtain a field,
  /// then the first entry of [args] has the field.
  MathExpr? get field => args.firstOrNull;

  /// Constructor to encode [field] access on a var [callee].
  MemoryAccess.field(this.op, this.callee, MathExpr field)
    : type = MemoryAccessType.field,
      args = [field];

  /// Constructor to encode table lookup by [key] on [callee].
  MemoryAccess.table(this.op, this.callee, MathExpr key)
    : type = MemoryAccessType.table,
      args = [key];

  /// Constructor to encode function calls on [callee] with [args].
  MemoryAccess.call(this.op, this.callee, this.args)
    : type = MemoryAccessType.call;

  @override
  R accept<R>(Visitor<R> v) => v.visitMemoryAccess(this);
}

/// Variables can be reassigned. This node encodes this operation.
/// While technically a binary operation by its format,
/// a rewrite required that it was evaluated in a different
/// grammar rule. Maybe in the future this encoding will be corrected.
class AssignExpr extends MathExpr {
  final Token op;
  final Stmt lhs;
  final Stmt rhs;

  AssignExpr(this.op, {required this.lhs, required this.rhs});

  @override
  R accept<R>(Visitor<R> v) => v.visitAssignExpr(this);
}

/// Like [DeclMultiVar], multiple variables can be reassigned at once.
class AssignMultiExpr extends MathExpr {
  final Token op;
  final List<Stmt> lhs;
  final List<Stmt> rhs;

  /// See: https://www.lua.org/manual/5.5/manual.html#3.4.12
  factory AssignMultiExpr.resize(
    Token op, {
    required List<Stmt> lhs,
    required List<Stmt> rhs,
  }) {
    final int len = lhs.length;
    final int other = rhs.length;
    List<Stmt> newRhs = [];

    for (int i = 0; i < len; i++) {
      if (i >= other) {
        newRhs.add(NilLiteral(Token.synthesized('multires_$i')));
        continue;
      }
      newRhs.add(rhs[i]);
    }
    return AssignMultiExpr._(op, lhs, rhs);
  }

  AssignMultiExpr._(this.op, this.lhs, this.rhs);

  @override
  R accept<R>(Visitor<R> v) => v.visitAssignMultiExpr(this);
}

/// Group expressions are expressions wrapped in parents (...).
class GroupExpr extends MathExpr {
  final Token token;
  final MathExpr expr;

  GroupExpr(this.token, this.expr);

  @override
  R accept<R>(Visitor<R> v) => v.visitGroupExpr(this);
}

/// In Lua, the not operator is used to negate a boolean value,
/// meaning it converts true to false and false to true.
class NotExpr extends MathExpr {
  final Token token;
  final MathExpr expr;

  NotExpr(this.token, this.expr);

  @override
  R accept<R>(Visitor<R> v) => v.visitNotExpr(this);
}

/// [BooleanLiteral.asTrue] encodes the literal `true`.
/// [BooleanLiteral.asFalse] encodes the literal `false`.
class BooleanLiteral extends MathExpr {
  final Token token;
  final bool value;

  BooleanLiteral.asTrue(this.token) : value = true;
  BooleanLiteral.asFalse(this.token) : value = false;

  @override
  R accept<R>(Visitor<R> v) => v.visitBooleanLiteral(this);
}

/// Integers and real literals are encoded as this node.
class NumberLiteral extends MathExpr {
  final Token token;
  final double value;
  NumberLiteral(this.token, {required this.value});

  @override
  R accept<R>(Visitor<R> v) => v.visitNumberLiteral(this);
}

/// String literals are encoded as this node.
class StringLiteral extends MathExpr {
  final Token token;
  final String value;
  StringLiteral(this.token, {required this.value});

  @override
  R accept<R>(Visitor<R> v) => v.visitStringLiteral(this);
}

/// Nil literals are encoded as this node.
class NilLiteral extends MathExpr {
  final Token token;
  NilLiteral(this.token);

  @override
  R accept<R>(Visitor<R> v) => v.visitNilLiteral(this);
}

/// For convenience, table `{key, value}` expressions
/// are encoded as this node.
class KeyValStmt extends Stmt {
  /// Lua table entries have implied keys if none are provided.
  final MathExpr? key;

  /// The value part of the pair.
  final MathExpr value;

  /// Constructs the pair with a given [key].
  KeyValStmt({required MathExpr this.key, required this.value});

  /// Constructs the pair without a key.
  /// Lua assigns an integer key in this situation.
  KeyValStmt.autokey(this.value) : key = null;

  @override
  R accept<R>(Visitor<R> v) => v.visitKeyValStmt(this);
}

/// Table literal expressions `{...}` are encoded by this node.
class TableLiteral extends MathExpr {
  final Token token;

  /// Tables may have zero or more [KeyValStmt] pairs.
  final List<KeyValStmt> pairs;
  TableLiteral(this.token, {required this.pairs});

  @override
  R accept<R>(Visitor<R> v) => v.visitTableLiteral(this);
}

/// This abstraction visits every node class variant.
/// Visitors are the staple of this runtime implementation.
/// They can be used to implement semantic checks as well
/// as implement runtimes. Additionally custom visitors c
/// an walk the [AST] of a program and generate lua bytecode.
abstract class Visitor<T> {
  T visitAST(AST ast);
  T visitFuncExpr(FuncExpr expr);
  T visitDeclArg(DeclArg declArg);
  T visitDeclVar(DeclVar declVar);
  T visitDeclMultiVar(DeclMultiVar declMultiVar);
  T visitIfStmt(IfStmt stmt);
  T visitBreakStmt(BreakStmt stmt);
  T visitMemoryAccess(MemoryAccess memoryAccess);
  T visitRawExpr(RawExpr rawExpr);
  T visitSelfExpr(SelfExpr selfExpr);
  T visitAssignExpr(AssignExpr assignExpr);
  T visitAssignMultiExpr(AssignMultiExpr assignMultiExpr);
  T visitGroupExpr(GroupExpr groupExpr);
  T visitNotExpr(NotExpr notExpr);
  T visitBooleanLiteral(BooleanLiteral boolean);
  T visitNumberLiteral(NumberLiteral number);
  T visitStringLiteral(StringLiteral string);
  T visitNilLiteral(NilLiteral nil);
  T visitBinaryExpr(BinaryExpr expr);
  T visitUnaryExpr(UnaryExpr expr);
  T visitReturnStmt(ReturnStmt expr);
  T visitTableLiteral(TableLiteral table);
  T visitKeyValStmt(KeyValStmt keyval);
  T visitWhileLoopStmt(WhileLoopStmt whileLoopStmt);
  T visitForLoopStmt(ForLoopStmt forLoopStmt);
  T visitForIterLoopStmt(ForIterLoopStmt forIterLoopStmt);
  T visitRepeatUntilLoopStmt(RepeatUntilLoopStmt repeatUntilLoopStmt);
  T visitGotoStmt(GotoStmt gotoStmt);
  T visitGotoLabelStmt(GotoLabelStmt gotoLabelStmt);
}
