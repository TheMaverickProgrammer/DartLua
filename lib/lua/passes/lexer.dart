enum TokenType {
  kRaw,
  kNewLine,
  kFunc,
  kEnd,
  kLParen,
  kRParen,
  kLBracket,
  kRBracket,
  kLCurly,
  kRCurly,
  kDot,
  kComma,
  kConcat,
  kString,
  kSemicolon,
  kColon,
  kSelf,
  kLocal,
  kAssign,
  kEQ,
  kLT,
  kLTE,
  kGT,
  kGTE,
  kNEQ,
  kTrue,
  kFalse,
  kNumber,
  kAdd,
  kSub,
  kMult,
  kCarrot,
  kHash,
  kMod,
  kDiv,
  kDivFloor,
  kIf,
  kElseIf,
  kElse,
  kFor,
  kUntil,
  kWhile,
  kRepeat,
  kBreak,
  kIn,
  kDo,
  kNil,
  kAnd,
  kOr,
  kNot,
  kThen,
  kReturn,
  kLCommentBlock,
  kRCommentBlock,
  kLineComment,
  kBitNot,
  kBitAnd,
  kBitOr,
  kGoto,
  kGotoLabel,
  kEOF,
}

final alphanum = RegExp(r'^[A-Za-z0-9_]+$');
final number = RegExp(r'^[0-9]+(\.[0-9]+)?$');

class StreamPos {
  final int col, row;
  final bool synthetic;

  const StreamPos._(this.col, this.row, this.synthetic);
  const StreamPos(this.col, this.row) : synthetic = false;

  static StreamPos get synthesized => StreamPos._(-1, -1, true);
  static StreamPos get eof => StreamPos._(-1, -1, false);

  bool get isEOF => col == row && col == -1;
  bool get isSynthesized => synthetic;

  @override
  operator ==(Object other) {
    if (other is! StreamPos) return false;
    return other.col == col && other.row == row && other.synthetic == synthetic;
  }

  @override
  int get hashCode => Object.hash(col, row, synthetic);

  @override
  String toString() {
    if (isSynthesized) return "[synthesized code]";
    if (isEOF) return "[EOF]";
    final rowfmt = (row + 1).toString().padLeft(4);
    final colfmt = (col + 1).toString().padRight(3);
    return "[$rowfmt:$colfmt]";
  }
}

class Token {
  final TokenType type;
  final String lexeme;
  final StreamPos pos;

  Token(this.type, this.lexeme, this.pos);

  Token.eof() : type = TokenType.kEOF, lexeme = '', pos = StreamPos.eof;

  Token.raw(this.lexeme, this.pos) : type = TokenType.kRaw;

  Token.synthesized(this.lexeme, {TokenType? type})
    : type = type ?? TokenType.kRaw,
      pos = StreamPos.synthesized;

  Token.fromStreamChar(this.type, StreamChar char)
    : lexeme = char.lexeme,
      pos = char.pos;

  bool get isEOF => pos.isEOF;

  @override
  String toString() {
    if (isEOF) return "<EOF>";
    return 'token: $type, lexeme: "$lexeme"';
  }
}

class StreamChar {
  final String lexeme;
  final StreamPos pos;
  const StreamChar(this.lexeme, this.pos);

  factory StreamChar.eof() => StreamChar('', StreamPos.eof);

  Token toToken(TokenType type, {String? lexeme}) =>
      Token(type, lexeme ?? this.lexeme, pos);

  bool sameLexeme(StreamChar char) => char.lexeme == lexeme;

  StreamChar copy({String? lexeme, StreamPos? pos}) =>
      StreamChar(lexeme ?? this.lexeme, pos ?? this.pos);

  @override
  operator ==(Object other) {
    if (other is! StreamChar) return false;
    return other.lexeme == lexeme && other.pos == pos;
  }

  @override
  int get hashCode => Object.hash(lexeme, pos);
}

class Lexer {
  /// The current token index.
  int curr = 0;

  /// The last line break w.r.t current token index.
  /// [col] = [curr] - [lastLineIdx].
  int lastLineIdx = 0;

  /// The current line count.
  int line = 0;

  final String content;
  final List<Token> tokens = [];
  final List<String> errors = [];

  Lexer._(this.content);

  int get col => curr - lastLineIdx;

  /// [col] and [line] are base-0 index. Format to base-1.
  void addError(String msg) => errors.add('[${line + 1}:${col + 1}] $msg');

  void dropComments() {
    tokens.removeWhere(
      (e) => [
        TokenType.kLineComment,
        TokenType.kLCommentBlock,
        TokenType.kRCommentBlock,
      ].contains(e.type),
    );
  }

  /// TODO: semicolons are needed to disambiguate grammar
  void dropSemicolons() =>
      tokens.removeWhere((e) => e.type == TokenType.kSemicolon);

  factory Lexer.tokenize(String content) {
    final Lexer t = Lexer._(content);

    int prev = t.curr;
    while (!t.eof()) {
      if (prev != t.curr) {
        throw 'Unknown character in tokenizer on line ${t.line}, col ${t.col}. Cannot recover.';
      }
      switch (t.peek().lexeme) {
        case '<':
          t.lt();
        case '>':
          t.gt();
        case '=':
          t.eq();
        case '~':
          t.bitNot();
        case '|':
          t.bitOr();
        case '&':
          t.bitAnd();
        case '[':
          t.lbracket();
        case ']':
          t.rbracket();
        case '(':
          t.lparen();
        case ')':
          t.rparen();
        case '{':
          t.lcurly();
        case '}':
          t.rcurly();
        case '*':
          t.mult();
        case '%':
          t.mod();
        case '/':
          t.div();
        case '+':
          t.add();
        case '-':
          t.sub();
        case ':':
          t.colon();
        case ';':
          t.semicolon();
        case '.':
          t.dot();
        case ',':
          t.comma();
        case '#':
          t.hashtag();
        case '^':
          t.carrot();
        case '"':
          t.str(start: '"', end: '"');
        case '\'':
          t.str(start: '\'', end: '\'');
        case '\t' || '\r' || ' ':
          t.advance();
        case '\n':
          t.newline();
        default:
          t.raw();
      }
      prev = t.curr;
    }

    return t;
  }

  bool eof() {
    return curr >= content.length;
  }

  StreamChar peek({int? offset}) {
    final int idx = curr + (offset ?? 0);
    if (idx >= content.length) {
      return StreamChar.eof();
    }

    return StreamChar(content[idx], StreamPos(col, line));
  }

  StreamChar advance() {
    final prev = peek();
    curr++;
    if (prev.lexeme == '\n') {
      bumpline();
    }
    return prev;
  }

  StreamChar read(String expected) {
    final int len = expected.length;
    final pos = StreamPos(col, line);
    for (int i = 0; i < len; i++) {
      if (content[curr] == '\n') {
        bumpline();
      }

      if (content[curr] != expected[i]) {
        throw 'Expected $expected';
      }

      curr++;
    }

    return StreamChar(expected, pos);
  }

  void advanceWithToken(TokenType type, {String? lexeme}) =>
      tokens.add(advance().toToken(type, lexeme: lexeme));

  void addToken(Token token) => tokens.add(token);

  void lt() {
    final char = advance();

    if (peek().lexeme == '=') {
      advance();
      tokens.add(char.toToken(TokenType.kLTE, lexeme: '<='));
      return;
    }
    tokens.add(char.toToken(TokenType.kLT));
  }

  void gt() {
    final char = advance();

    if (peek().lexeme == '=') {
      advance();
      tokens.add(char.toToken(TokenType.kGTE, lexeme: '>='));
      return;
    }

    tokens.add(char.toToken(TokenType.kGT, lexeme: '>'));
  }

  void eq() {
    final char = advance();

    if (peek().lexeme == '=') {
      advance();
      tokens.add(char.toToken(TokenType.kEQ, lexeme: '=='));
      return;
    }

    tokens.add(char.toToken(TokenType.kAssign, lexeme: '='));
  }

  void bitNot() {
    final char = advance();

    if (peek().lexeme == '=') {
      advance();
      tokens.add(char.toToken(TokenType.kNEQ, lexeme: '~='));
      return;
    }

    tokens.add(char.toToken(TokenType.kBitNot, lexeme: '~'));
  }

  void bitOr() => advanceWithToken(TokenType.kBitOr, lexeme: '|');
  void bitAnd() => advanceWithToken(TokenType.kBitAnd, lexeme: '&');
  void hashtag() => advanceWithToken(TokenType.kHash, lexeme: '#');
  void carrot() => advanceWithToken(TokenType.kCarrot, lexeme: '^');

  void lbracket() {
    // This is a multi-line string. This special case
    // has its own sub-parser.
    if (peek(offset: 1).lexeme == '[') {
      tokens.add(parseDoubleBracketStr());
      return;
    }

    advanceWithToken(TokenType.kLBracket, lexeme: '[');
  }

  void rbracket() => advanceWithToken(TokenType.kRBracket, lexeme: ']');
  void lcurly() => advanceWithToken(TokenType.kLCurly, lexeme: '{');
  void rcurly() => advanceWithToken(TokenType.kRCurly, lexeme: '}');
  void lparen() => advanceWithToken(TokenType.kLParen, lexeme: '(');
  void rparen() => advanceWithToken(TokenType.kRParen, lexeme: ')');
  void mult() => advanceWithToken(TokenType.kMult, lexeme: '*');
  void add() => advanceWithToken(TokenType.kAdd, lexeme: '+');
  void mod() => advanceWithToken(TokenType.kMod, lexeme: '%');

  void div() {
    final char = advance();

    if (peek().lexeme == '/') {
      advance();
      tokens.add(char.toToken(TokenType.kDivFloor, lexeme: '//'));
      return;
    }

    tokens.add(char.toToken(TokenType.kDiv, lexeme: '/'));
  }

  void sub() {
    final char = advance();

    // NOTE: This is not preserving comments at this time.
    if (peek().lexeme == '-') {
      // Check for left block comment token
      if (peek(offset: 1).lexeme == '[' && peek(offset: 2).lexeme == '[') {
        // Consume this extra '-' char in the stream.
        advance();
        final substr = parseDoubleBracketStr();
        tokens.add(
          char.toToken(TokenType.kLCommentBlock, lexeme: '--${substr.lexeme}'),
        );
        return;
      }

      tokens.add(char.toToken(TokenType.kLCommentBlock, lexeme: '--'));

      // Consume until newline terminator
      while (!eof() && peek().lexeme != '\n') {
        advance();
      }
      return;
    }

    tokens.add(char.toToken(TokenType.kSub));
  }

  void colon() {
    final char = advance();

    // A ::label:: token is used in goto statements.
    // The name of a label follows the same conventions as variables.
    if (peek().lexeme == ':') {
      // Consume that second colon.
      advance();
      // Read the name.
      final raw = parseRawName();
      // Consume the following two tokens, throwing if not found.
      read('::');
      // Finally, add the token and return.
      tokens.add(raw.toToken(TokenType.kGotoLabel));
      return;
    }

    tokens.add(char.toToken(TokenType.kColon));
  }

  void semicolon() => advanceWithToken(TokenType.kSemicolon);
  void comma() => advanceWithToken(TokenType.kComma);

  void dot() {
    final char = advance();

    // Lua supports numbers beginning with "." which indicates
    // the leading whole part is a zero. e.g. ".3" == "0.3".
    if (number.hasMatch(peek().lexeme)) {
      final token = parseNumber();
      tokens.add(Token(token.type, token.lexeme, char.pos));
      return;
    }

    if (peek().lexeme == '.') {
      advance();
      tokens.add(char.toToken(TokenType.kConcat, lexeme: '..'));
      return;
    }

    tokens.add(char.toToken(TokenType.kDot));
  }

  Token parseNumber() {
    String lexeme = '';
    int offset = 0;

    StreamChar start = peek();
    String next = start.lexeme;

    while (number.hasMatch(next)) {
      lexeme = next;

      final rawChar = peek(offset: ++offset).lexeme;
      next += rawChar;

      if (rawChar == '.') {
        next += peek(offset: ++offset).lexeme;
      } else if (rawChar == '') {
        break;
      }
    }

    if (lexeme.isNotEmpty) {
      curr += lexeme.length;
    } else {
      addError('Expected number but was empty.');
    }

    return start.toToken(TokenType.kNumber, lexeme: lexeme);
  }

  StreamChar parseRawName() {
    String lexeme = '';
    int offset = 0;
    StreamChar start = peek();
    String next = start.lexeme;
    while (alphanum.hasMatch(next)) {
      lexeme = next;
      next += peek(offset: ++offset).lexeme;

      // At EOF [parse] is the empty char ('').
      if (lexeme == next) {
        break;
      }
    }

    if (lexeme.isNotEmpty) {
      curr += lexeme.length;
    }

    return start.copy(lexeme: lexeme);
  }

  void bumpline() {
    lastLineIdx = curr;
    line++;
  }

  void newline() {
    tokens.add(advance().toToken(TokenType.kNewLine));
  }

  void str({required String start, required String end}) {
    // Consume the lexeme used as quotes.
    final streamChar = advance();

    final int startIdx = curr, startLine = line;
    String lexeme = '';
    StreamChar prev = peek(offset: -1);
    bool loop = true;

    while (!eof() && loop) {
      // NOTE: will consume the terminating quote
      // as a side-effect.
      final next = advance();
      final bool found = next.lexeme == end;

      prev = peek(offset: -2);
      loop = !found || (found && prev.lexeme == '\\');

      // Only append to the string if the lexeme is not used
      // as a terminating quote.
      if (loop) {
        lexeme += next.lexeme;
      }
    }

    if (eof()) {
      final String lineInfo = '$startLine:$startIdx';
      addError('Unterminated string starting on line $lineInfo');

      // There's no recovering from EOF.
      return;
    }

    tokens.add(streamChar.toToken(TokenType.kString, lexeme: lexeme));
  }

  Token parseDoubleBracketStr() {
    final char = peek();
    String lexeme = read('[[').lexeme;

    while (!eof()) {
      // Look for terminating right block token
      final bool foundTerminal =
          peek().lexeme == ']' && peek(offset: 1).lexeme == ']';

      if (foundTerminal) {
        lexeme += read(']]').lexeme;
        break;
      }

      lexeme += advance().lexeme;
    }

    return char.toToken(TokenType.kString, lexeme: lexeme);
  }

  void raw() {
    if (number.hasMatch(peek().lexeme)) {
      tokens.add(parseNumber());
      return;
    }

    final StreamChar raw = parseRawName();

    switch (raw.lexeme) {
      case 'local':
        local(raw);
      case 'self':
        self(raw);
      case 'function':
        function(raw);
      case 'end':
        end(raw);
      case 'if':
        termIf(raw);
      case 'elseif':
        termElseIf(raw);
      case 'else':
        termElse(raw);
      case 'for':
        termFor(raw);
      case 'then':
        termThen(raw);
      case 'not':
        termNot(raw);
      case 'and':
        termAnd(raw);
      case 'or':
        termOr(raw);
      case 'do':
        termDo(raw);
      case 'in':
        termIn(raw);
      case 'nil':
        nil(raw);
      case 'repeat':
        repeat(raw);
      case 'return':
        termReturn(raw);
      case 'until':
        until(raw);
      case 'while':
        termWhile(raw);
      case 'break':
        termBreak(raw);
      case 'true':
        termTrue(raw);
      case 'false':
        termFalse(raw);
      case 'goto':
        goto(raw);
      case '':
        throw 'Unrecoverable error in tokenizer at $line:$col.';
      default:
        addToken(raw.toToken(TokenType.kRaw));
    }
  }

  void local(StreamChar char) => addToken(char.toToken(TokenType.kLocal));
  void self(StreamChar char) => addToken(char.toToken(TokenType.kSelf));
  void function(StreamChar char) => addToken(char.toToken(TokenType.kFunc));
  void end(StreamChar char) => addToken(char.toToken(TokenType.kEnd));
  void termIf(StreamChar char) => addToken(char.toToken(TokenType.kIf));
  void termElseIf(StreamChar char) => addToken(char.toToken(TokenType.kElseIf));
  void termElse(StreamChar char) => addToken(char.toToken(TokenType.kElse));
  void termFor(StreamChar char) => addToken(char.toToken(TokenType.kFor));
  void termThen(StreamChar char) => addToken(char.toToken(TokenType.kThen));
  void termNot(StreamChar char) => addToken(char.toToken(TokenType.kNot));
  void termAnd(StreamChar char) => addToken(char.toToken(TokenType.kAnd));
  void termOr(StreamChar char) => addToken(char.toToken(TokenType.kOr));
  void termDo(StreamChar char) => addToken(char.toToken(TokenType.kDo));
  void termIn(StreamChar char) => addToken(char.toToken(TokenType.kIn));
  void nil(StreamChar char) => addToken(char.toToken(TokenType.kNil));
  void repeat(StreamChar char) => addToken(char.toToken(TokenType.kRepeat));
  void termReturn(StreamChar char) => addToken(char.toToken(TokenType.kReturn));
  void until(StreamChar char) => addToken(char.toToken(TokenType.kUntil));
  void termWhile(StreamChar char) => addToken(char.toToken(TokenType.kWhile));
  void termTrue(StreamChar char) => addToken(char.toToken(TokenType.kTrue));
  void termFalse(StreamChar char) => addToken(char.toToken(TokenType.kFalse));
  void termBreak(StreamChar char) => addToken(char.toToken(TokenType.kBreak));
  void goto(StreamChar char) => addToken(char.toToken(TokenType.kGoto));
}
