import 'dart:math';
import 'package:colorize/colorize.dart';
import 'package:puredartlua/lua/passes/lexer.dart';

String green(Object obj) => obj.toString().green;
String yellow(Object obj) => obj.toString().yellow;
String red(Object obj) => obj.toString().red;
String blue(Object obj) => obj.toString().blue;
String magenta(Object obj) => obj.toString().magenta;

extension ColoredStrings on String {
  String get red => Colorize(this).red().toString();
  String get yellow => Colorize(this).yellow().toString();
  String get green => Colorize(this).green().toString();
  String get blue => Colorize(this).blue().toString();
  String get magenta => Colorize(this).magenta().toString();
}

String colorize(String content, {int tabWeight = 2}) {
  final Lexer lexer = Lexer.tokenize(content);

  const newBlockTokens = [
    TokenType.kThen,
    TokenType.kDo,
    TokenType.kWhile,
    TokenType.kRepeat,
  ];

  const endBlockTokens = [TokenType.kElseIf, TokenType.kElse, TokenType.kEnd];

  bool newLineStart = false;
  int tabs = 0;
  String prettyContent = '';

  for (final Token t in lexer.tokens) {
    final TokenType type = t.type;
    String nextContent = pretty(t).toString();

    if (type == TokenType.kNewLine) {
      newLineStart = true;
      nextContent = '$nextContent\n';
    } else if (newBlockTokens.contains(type)) {
      tabs++;
    } else if (endBlockTokens.contains(type)) {
      tabs = max(0, tabs - 1);
    }

    if (newLineStart && type != TokenType.kNewLine) {
      nextContent = '${indent(tabs * tabWeight)}$nextContent';
      newLineStart = false;
    }

    prettyContent += ' $nextContent';
  }

  return prettyContent;
}

String indent(int spaces) {
  StringBuffer buffer = StringBuffer();
  while (spaces > 0) {
    spaces--;
    buffer.writeCharCode(32);
  }

  return buffer.toString();
}

Colorize pretty(Token token) => switch (token.type) {
  TokenType.kIf ||
  TokenType.kElseIf ||
  TokenType.kElse ||
  TokenType.kFor ||
  TokenType.kWhile ||
  TokenType.kDo ||
  TokenType.kRepeat ||
  TokenType.kFunc ||
  TokenType.kEnd ||
  TokenType.kIn ||
  TokenType.kThen ||
  TokenType.kColon => Colorize(token.lexeme).yellow(),
  TokenType.kComma ||
  TokenType.kDot ||
  TokenType.kEQ ||
  TokenType.kNEQ ||
  TokenType.kGT ||
  TokenType.kGTE ||
  TokenType.kLT ||
  TokenType.kLTE ||
  TokenType.kLParen ||
  TokenType.kRParen ||
  TokenType.kLBracket ||
  TokenType.kRBracket ||
  TokenType.kLCurly ||
  TokenType.kRCurly ||
  TokenType.kConcat => Colorize(token.lexeme).lightGray(),
  TokenType.kAdd ||
  TokenType.kSub ||
  TokenType.kDiv ||
  TokenType.kDivFloor ||
  TokenType.kMult ||
  TokenType.kCarrot ||
  TokenType.kBitAnd ||
  TokenType.kBitOr ||
  TokenType.kBitNot => Colorize(token.lexeme).magenta(),
  TokenType.kReturn ||
  TokenType.kBreak ||
  TokenType.kAssign ||
  TokenType.kLocal ||
  TokenType.kNot ||
  TokenType.kAnd ||
  TokenType.kOr => Colorize(token.lexeme).green(),
  TokenType.kTrue ||
  TokenType.kFalse ||
  TokenType.kNil ||
  TokenType.kSelf => Colorize(token.lexeme).lightBlue(),
  TokenType.kNumber => Colorize(token.lexeme).lightCyan(),
  TokenType.kString => Colorize('"${token.lexeme}"').bold().yellow(),
  TokenType.kLineComment ||
  TokenType.kBlockComment => Colorize(token.lexeme).darkGray(),
  _ => Colorize(token.lexeme).white(),
};
