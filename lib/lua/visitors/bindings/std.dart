import 'dart:math' as math;
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

const catRuntime = 'Runtime';
const catModules = 'Modules';

typedef StdPrintCallback = void Function(String);

/// If one implementation for coroutines are needed, then
/// all implementations for the coroutine API are needed.
/// This class provides a quick configuration for all methods.
class CoroutineCallbacks {
  /// This is called by the closure defined in [initStdCoroutines].
  /// The callback expects a [LuaObject] argument which will have
  /// satisfied [LuaObject.isFunc]. The implementation expected
  /// to return an [int] address value of the designated coroutine.
  int Function(LuaObject fn) onCoroutineCreate;

  /// Given a coroutine [int] address, return the status of the
  /// coroutine as a [String].
  String Function(int addr) onCoroutineStatus;

  /// Given a coroutine [int] address and optional [vargs],
  /// resume that coroutine and return a value. Multiple values will
  /// be unpacked by the runtime.
  LuaArgPack Function(int addr, List<LuaObject> vargs) onCoroutineResume;

  /// Given a list of lua value [args], perform the coroutine
  /// yield behavior.
  LuaArgPack Function(List<LuaObject> args) onCoroutineYield;

  /// Handle the scope pop to collect the stack information
  /// via [BaseRuntime.coCtrlStruct] before it is set to null.
  void Function(CoCtrlStruct) onCoroutinePopScope;

  CoroutineCallbacks({
    required this.onCoroutineCreate,
    required this.onCoroutineResume,
    required this.onCoroutineStatus,
    required this.onCoroutineYield,
    required this.onCoroutinePopScope,
  });
}

/// Implements the lua standard libraries.
/// Some implementations need further defining by the programmer
/// such as [Std.onRequireImpl] called in [initStdRequire].
///
/// The entry point is [Std.initStdRuntime].
mixin Std on BaseRuntime {
  /// This is called by the closure defined in [initStdRequire]
  /// after the call to [Std.onRequireImpl]. In this way,
  /// programmers can configure the implementation details
  /// of `require` on a case-by-case basis (if needed) while
  /// still performing general book keeping for each.
  void Function(String)? onRequireImplComplete;

  /// Support coroutines by setting this field to a
  /// non-null implementation.
  CoroutineCallbacks? coroutineImpls;

  void initStdRuntime() {
    initStdMetatables();
    initStdStrings();
    initStdRequire();
    initStdIPairs();
    initStdPairs();
    initStdTable();
    initStdPrint();
    initStdMath();
    initMiscRuntime();
  }

  /// Defines the following global functions:
  /// - setmetatable(t, mt)
  /// - getmetatable(t)
  /// - rawset(t,k,v)
  /// - rawget(t,k)
  void initStdMetatables() {
    final defSetMetatable = LuaFuncBuilder.create('setmetatable')
        .arg('t')
        .arg('mt')
        .exec(
          call: () {
            final t = findVar('t');
            final mt = findVar('mt');

            if (t == null || t.isNotTable) {
              throw 'Expected lua table as first argument.';
            }

            if (mt == null || mt.isNotTable) {
              throw 'Expected lua table as second argument.';
            }

            t.setMetatable(mt);
          },
        );

    defGlobal(defSetMetatable).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Given lua table <code>t</code> and a table of functions <code>mt</code>,
      sets <code>t</code>'s metatable to <code>mt</code>.
      ''',
    );

    final defGetMetatable = LuaFuncBuilder.create('getmetatable')
        .arg('t')
        .exec(
          call: () {
            final t = findVar('t');

            if (t == null || t.isNotTable) {
              throw 'Expected lua table as first argument.';
            }

            return t.getMetatable();
          },
        );

    defGlobal(defGetMetatable).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Given lua table <code>t</code>, returns the metatable used
      by <code>t</code> or <code>nil</code> if no metatable is set.
      ''',
    );

    final defRawSet = LuaFuncBuilder.create('rawset')
        .arg('t')
        .arg('k')
        .arg('v')
        .exec(
          call: () {
            final t = findVar('t');

            if (t?.isNotTable ?? true) {
              throw 'Expected lua table as first argument.';
            }

            final k = findVar('k');

            if (k?.isNil ?? true) {
              throw 'Expected non-null key for second argument';
            }

            final v = findVar('v');

            // TODO: Keys can be anything except nil!
            t!.writeField(k.toString(), v);
            return t;
          },
        );

    defGlobal(defRawSet).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Given lua table <code>t</code>, sets the value <code>v</code>
      to the table's <code>k</code> key index. This does not trigger
      <code>__newindex</code>.<br/>Returns <code>t</code>.
      ''',
    );

    final defRawGet = LuaFuncBuilder.create('rawget')
        .arg('t')
        .arg('k')
        .exec(
          call: () {
            final t = findVar('t');

            if (t?.isNotTable ?? true) {
              throw 'Expected lua table as first argument.';
            }

            final k = findVar('k');

            if (k?.isNil ?? true) {
              throw 'Expected non-null key for second argument';
            }

            // TODO: keys can be anything except nil!
            return t!.readField(k.toString());
          },
        );

    defGlobal(defRawGet).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Given lua table <code>t</code>, returns the value in the table
      by key <code>k</code>. This does not trigger
      <code>__index</code>.
      ''',
    );
  }

  void initStdStrings() {
    final defToString = LuaFuncBuilder.create('tostring')
        .arg('value')
        .exec(
          call: () {
            final value = findVar('value');
            if (value == null) return 'nil';
            return value.toString();
          },
        );

    defGlobal(defToString).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Converts any lua object into a printable string.</br>
      Depending on the runtime implementation, calling
      <code>tostring</code> on tables 
      and functions print their address.
      ''',
    );

    // https://www.lua.org/pil/2.html
    final defType = LuaFuncBuilder.create('type')
        .arg('obj')
        .exec(
          call: () {
            final obj = findVar('obj');
            switch (obj) {
              case null:
                // Case: internal form.
                return 'nil';
              case final LuaObject lua:
                if (lua.isFunc) return 'function';
                if (lua.isTable) return 'table';
                if (lua.isNil) return 'nil';
                return switch (lua.value) {
                  final String _ => 'string',
                  final num _ => 'number',
                  final bool _ => 'boolean',
                  _ => 'userdata',
                };
            }
          },
        );

    defGlobal(defType).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Returns the name of the lua object's type as a <code>string</code>.<br/>
      The supported types are:
      <ol>
      <li>function</li>
      <li>table</li>
      <li>nil</li>
      <li>string</li>
      <li>number</li>
      <li>boolean</li>
      </ol>
      If the runtime detects a value other than the
      primitives listed above, then <code>"userdata"</code>
      is returned.
      ''',
    );
  }

  void initStdRequire() {
    exec() {
      final path = findVar('path');
      final v = path?.valueAs<String>();
      if (v == null) {
        final type = v.runtimeType;
        throw 'Expected string for "path" in `require(path)`. Was $type.';
      }

      Object? result;
      final prevScope = scope;
      try {
        pushScope();
        result = onRequireImpl?.call(v, this);
      } catch (e) {
        addError(e.toString());
      } finally {
        restoreScope(prevScope);
      }

      onRequireImplComplete?.call(v);

      return result;
    }

    final token = Token.synthesized('require');
    final defRequire = FuncExpr.named(
      token,
      body: [],
      args: [DeclArg(Token.synthesized('path'))],
      idParts: [RawExpr(token)],
    );

    defGlobal(LuaObject.func('require', defRequire, exec)).doc = LuaDoc(
      category: catRuntime,
      html: '''
      The runtime resolves the lua script identified by <code>path</code>, executes,
      and returns any values. This enables passing lua objects
      between files.
<pre>
<code class="language-lua">local f = require('fibonacci.lua')
print(f(7)) -- prints 13
</code>
</pre>
      ''',
    );
  }

  void initStdIPairs() {
    ipairs() {
      final t = findVar('table');

      if (t?.skipSemanitcs ?? false) {
        return t;
      }

      if (!(t?.isTable ?? false)) {
        final type = t?.typeinfo;
        throw 'Expected table input for ipairs(...). Was $type.';
      }

      t as LuaObject;
      final name = t.id;
      // t.isTable was true.
      final fields = t.fields!;
      final Map<String, LuaObject> newFields = {};

      int i = 0;
      while (i < fields.length) {
        final String key = '${i + 1}';
        if (fields.containsKey(key)) {
          newFields[key] = fields[key]!;
          i++;
        } else {
          break;
        }
      }

      return LuaObject.table('ipairs_$name', newFields);
    }

    final token = Token.synthesized('ipairs');
    final defIPairs = FuncExpr.named(
      token,
      body: [],
      args: [DeclArg(Token.synthesized('table'))],
      idParts: [RawExpr(token)],
    );

    defGlobal(LuaObject.func('ipairs', defIPairs, ipairs)).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Enumerates over a lua table and returns a <code>{index, value}</code>
      pair. Used in for-loops where integer index is expected.
      ''',
    );
  }

  void initStdPairs() {
    pairs() {
      final t = findVar('table');
      if (t?.skipSemanitcs ?? false) {
        return t;
      }

      if (!(t?.isTable ?? false)) {
        final type = t?.typeinfo;
        throw 'Expected table input for pairs(...). Was $type.';
      }

      t as LuaObject;
      final name = t.id;

      // t.isTable was true.
      final fields = t.fields!;

      // Null fields are marked as deleted in lua.
      // I don't remove them in this implementation,
      // but we do exclude them from all operations that
      // expose keys.
      final newFields = fields.entries
          .where((e) => e.value?.isNil == false)
          .map((e) => MapEntry(e.key, e.value!));

      return LuaObject.table(
        'ipairs_$name',
        Map<String, LuaObject>.fromEntries(newFields),
      );
    }

    final token = Token.synthesized('pairs');
    final defPairs = FuncExpr.named(
      token,
      body: [],
      args: [DeclArg(Token.synthesized('table'))],
      idParts: [RawExpr(token)],
    );

    defGlobal(LuaObject.func('pairs', defPairs, pairs)).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Enumerates over a lua table and returns a <code>{key, value}</code>
      pair. Used in common for-loops.
      ''',
    );
  }

  void initStdTable() {
    defGlobal(
      LuaObject.table('table', {
        'insert':
            LuaFuncBuilder.create('insert')
                .arg('t')
                .arg('position')
                .arg('value', optional: true)
                .exec(
                  call: () {
                    LuaObject? tableData = findVar('t');

                    if ((tableData?.isNil ?? true) || tableData!.isNotTable) {
                      throw 'Expected table argument "t" for function.';
                    }

                    LuaObject? value = findVar('value');
                    int? position;

                    if (value?.isNil ?? true) {
                      value = findVar('position');

                      // Insert a nil value is a noop
                      if (value == null) {
                        return LuaObject.nil('ret');
                      }
                    } else {
                      final pos = findVar('position');
                      position = pos?.valueAsInt();

                      if ((pos?.isNil ?? true) || position == null) {
                        throw 'Expected integer "position" for function.';
                      }
                    }

                    final int sz = tableData.tableSize;
                    final int next = (position ?? sz) + 1;
                    if (tableData.tableInsert(next, value!) == null) {
                      throw 'Index out of bounds: $next with bounds of $sz.';
                    }
                  },
                )
              ..doc = LuaDoc(
                category: catRuntime,
                html: '''
                Inserts <code>value</code> into table <code>t</code> at <code>position</code>.<br/>
                <br/>
                If only two arguments are given, then the second argument becomes <code>value</code>
                and the <code>position</code> is determined to be the front of the table <code>t</code>.<br/>
                This is convenient to write stacks in lua.
<pre><code class="language-lua">local t = {}
table.insert(t, 1, "foo")
-- is the same as
table.insert(t, "foo")
</code></pre>
                ''',
              ),
        'remove': LuaFuncBuilder.create('remove')
            .arg('tableData')
            .arg('position')
            .exec(
              call: () {
                LuaObject? tableData = findVar('tableData');

                if ((tableData?.isNil ?? true) || tableData!.isNotTable) {
                  throw 'Expected table argument "tableData" for function.';
                }

                int? position = findVar('value')?.valueAsInt();

                if (position == null) {
                  throw 'Expected integer "position" for function.';
                }

                return tableData.tableRemove(position);
              },
            ),
      }),
    ).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Tables are to lua what classes are to other modern programming languages.<br/>
      They can also be used as lists.
      ''',
    );
  }

  void initStdPrint({StdPrintCallback? impl}) {
    final token = Token.synthesized('print');
    final defPrint = FuncExpr.named(
      token,
      body: [],
      args: [DeclArg(Token.synthesized('...', type: TokenType.kSpread))],
      idParts: [RawExpr(token)],
    );

    exec() {
      tostring(LuaObject e) {
        final mm = e.readMetatable('__tostring')?.as<LuaObject>();
        if (mm == null) {
          return e.toString();
        }
        return callLuaFunction(mm, args: [e]).unpack();
      }

      impl?.call(findVarArgs()?.map(tostring).join(' ') ?? '');
    }

    defGlobal(LuaObject.func('print', defPrint, exec)).doc = LuaDoc(
      category: catRuntime,
      html: '''
          Converts a lua object to a string and then
          displays to console. See <a href="#tostring">tostring</a>.
          ''',
    );
  }

  void initStdMath() {
    math.Random rand = math.Random();

    final defMath =
        LuaObject.table('math', {
            'abs':
                LuaFuncBuilder.create('abs')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return x.abs();
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the absolute value of <code>x</code>.',
                  ),
            'acos':
                LuaFuncBuilder.create('acos')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return math.acos(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        'Returns the arc cosine of <code>x</code> (in radians).',
                  ),
            'asin':
                LuaFuncBuilder.create('asin')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return math.asin(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        'Returns the arc sine of <code>x</code> (in radians).',
                  ),
            'atan':
                LuaFuncBuilder.create('atan')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return math.atan(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        'Returns the arc tangent of <code>x</code> (in radians).',
                  ),
            'atan2':
                LuaFuncBuilder.create('atan2')
                    .arg('y')
                    .arg('x')
                    .exec(
                      call: () {
                        final y = findVar('y')?.valueAs<num>();
                        if (y == null) {
                          throw 'Expected number argument for "y".';
                        }

                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }

                        return math.atan2(y, x);
                      },
                    )
                  ..doc = LuaDoc(
                    html: '''
                        Returns the arc tangent of <code>y/x</code> (in radians), but 
                        uses the signs of both parameters to find the quadrant of the result. 
                        It also handles correctly the case of <code>x=0</code>.''',
                  ),
            'ceil':
                LuaFuncBuilder.create('ceil')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return x.ceil();
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        'Returns the smallest integer larger than or equal to <code>x</code>.',
                  ),
            'cos':
                LuaFuncBuilder.create('cos')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return math.cos(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the cosine of <code>x</code> (in radians).',
                  ),
            'sin':
                LuaFuncBuilder.create('sin')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return math.sin(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the sine of <code>x</code> (in radians).',
                  ),
            'tan':
                LuaFuncBuilder.create('tan')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return math.tan(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the tangent of <code>x</code> (in radians).',
                  ),
            'cosh':
                LuaFuncBuilder.create('cosh')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return (math.exp(x) + math.exp(-x)) * 0.5;
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the hyperbolic cosine of <code>x</code>.',
                  ),
            'sinh':
                LuaFuncBuilder.create('sinh')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return (math.exp(x) - math.exp(-x)) * 0.5;
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the hyperbolic sine of <code>x</code>.',
                  ),
            'tanh':
                LuaFuncBuilder.create('tanh')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        final expPos = math.exp(x);
                        final expNeg = math.exp(-x);
                        return (expPos - expNeg) / (expPos + expNeg);
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the hyperbolic tangent of <code>x</code>.',
                  ),
            'deg':
                LuaFuncBuilder.create('deg')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return x * 180.0 / math.pi;
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        'Returns the angle <code>x</code> from radians into degrees.',
                  ),
            'rad':
                LuaFuncBuilder.create('rad')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return x * math.pi / 180.0;
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        'Returns the angle <code>x</code> from degrees into radians.',
                  ),
            'exp':
                LuaFuncBuilder.create('exp')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return math.exp(x);
                      },
                    )
                  ..doc = LuaDoc(html: 'Returns the value <code>e^x</code>.'),
            'floor':
                LuaFuncBuilder.create('floor')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        return x.floor();
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        'Returns the largest integer smaller than or equal to <code>x</code>.',
                  ),
            'fmod':
                LuaFuncBuilder.create('fmod')
                    .arg('x')
                    .arg('y')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        final y = findVar('y')?.valueAs<num>();
                        if (y == null) {
                          throw 'Expected number argument for "y".';
                        }
                        if (y == 0) {
                          throw 'Division by zero in fmod.';
                        }

                        return x - (x / y).truncateToDouble() * y;
                      },
                    )
                  ..doc = LuaDoc(
                    html: '''Returns the remainder of the division of 
                        <code>x</code> by <code>y</code> that rounds the quotient towards zero.''',
                  ),
            'ldexp':
                LuaFuncBuilder.create('ldexp')
                    .arg('m')
                    .arg('n')
                    .exec(
                      call: () {
                        final m = findVar('m')?.valueAs<num>();
                        final n = findVar('n')?.valueAs<num>();

                        if (m == null || n == null) {
                          throw 'Expected "m" and "n" to be numbers.';
                        }

                        return m * math.pow(2, n);
                      },
                    )
                  ..doc = LuaDoc(html: 'Returns <code>m*2e</code>.'),
            'frexp':
                LuaFuncBuilder.create('frexp')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }

                        if (x == 0.0 || x.isNaN || x.isInfinite) {
                          return [x, 0];
                        }

                        final bool isNegative = x < 0;
                        num absX = isNegative ? -x : x;
                        int exponent = 0;

                        if (absX >= 1.0) {
                          while (absX >= 1.0) {
                            absX /= 2.0;
                            exponent++;
                          }
                        } else if (absX < 0.5) {
                          while (absX < 0.5) {
                            absX *= 2.0;
                            exponent--;
                          }
                        }

                        return [isNegative ? -absX : absX, exponent];
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        '''Returns <code>m</code> and <code>e</code> such that <code>x = m*2e</code>, 
                        <code>e</code> is an integer and the absolute value of <code>m</code> is in the range 
                        <code>[0.5, 1)</code> or zero when <code>x</code> is zero.''',
                  ),
            'log':
                LuaFuncBuilder.create('log')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        if (x <= 0) return double.nan;
                        return math.log(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the natural logarithm of <code>x</code>.',
                  ),
            'log10':
                LuaFuncBuilder.create('log10')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        if (x <= 0) return double.nan;
                        return math.log(x) / math.ln10;
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the base-10 logarithm of <code>x</code>.',
                  ),
            'pow':
                LuaFuncBuilder.create('pow')
                    .arg('x')
                    .arg('y')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }

                        final y = findVar('y')?.valueAs<num>();
                        if (y == null) {
                          throw 'Expected number argument for "y".';
                        }

                        return math.pow(x, y);
                      },
                    )
                  ..doc = LuaDoc(html: 'Returns <code>x^y</code>.'),
            'sqrt':
                LuaFuncBuilder.create('sqrt')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number arguments only.';
                        }
                        return math.sqrt(x);
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the square root of <code>x</code>.',
                  ),
            'max':
                LuaFuncBuilder.create('max')
                    .arg('x')
                    .varargs()
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number arguments only.';
                        }

                        final varargs = findVarArgs()
                            ?.map(
                              (e) => switch (e.valueAs<num>()) {
                                final num n => n,
                                _ => throw 'Expected number arguments only.',
                              },
                            )
                            .toList();

                        if ((varargs ?? []).isEmpty) return x;

                        return varargs!.fold(x, (v, n) => math.max(v, n));
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the maximum value among its arguments.',
                  ),
            'min':
                LuaFuncBuilder.create('min')
                    .arg('x')
                    .varargs()
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number arguments only.';
                        }

                        final varargs = findVarArgs()
                            ?.map(
                              (e) => switch (e.valueAs<num>()) {
                                final num n => n,
                                _ => throw 'Expected number arguments only.',
                              },
                            )
                            .toList();

                        if ((varargs ?? []).isEmpty) return x;

                        return varargs!.fold(x, (v, n) => math.min(v, n));
                      },
                    )
                  ..doc = LuaDoc(
                    html: 'Returns the minimum value among its arguments.',
                  ),
            'randomseed':
                LuaFuncBuilder.create('randomseed')
                    .arg('x')
                    .exec(
                      call: () {
                        final x = findVar('x')?.valueAs<num>();
                        if (x == null) {
                          throw 'Expected number argument for "x".';
                        }
                        rand = math.Random(x.toInt());
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        '''Sets <code>x</code> as the seed for the pseudo-random generator.
                        Identical seeds produce identical sequences of numbers.''',
                  ),
            'random':
                LuaFuncBuilder.create('random')
                    .arg('m')
                    .arg('n')
                    .exec(
                      call: () {
                        final m = findVar('m')?.valueAs<num>()?.toInt();
                        final n = findVar('n')?.valueAs<num>()?.toInt();

                        if (m != null) {
                          if (n != null) {
                            final m0 = math.min(m, n);
                            final n0 = math.max(m, n);
                            return rand.nextInt(n0 - m0) + m0 + 1;
                          } else {
                            return rand.nextInt(m) + 1;
                          }
                        }

                        return rand.nextDouble();
                      },
                    )
                  ..doc = LuaDoc(
                    html:
                        '''When called without arguments, returns a uniform pseudo-random 
                        real number in the range <code>[0,1)</code>.
                        </br>
                        When called with an integer number <code>m</code>, random returns a 
                        uniform pseudo-random integer in the range <code>[1, m]</code>.
                        </br>
                        When called with two integer numbers <code>m</code> and <code>n</code>,
                        returns a uniform pseudo-random integer in the range <code>[m, n]</code>.''',
                  ),
          })
          ..doc = LuaDoc(
            category: catModules,
            html: '''
            The lua runtime math library.
            ''',
          );

    defMath.writeFieldFrom(
      LuaObject.variable('huge', double.maxFinite.toInt())
        ..doc = LuaDoc(
          html:
              'The value <code>HUGE_VAL</code>, a value larger than or equal to any other numerical value.',
        ),
    );

    defMath.writeFieldFrom(
      LuaObject.variable('pi', math.pi)..doc = LuaDoc(html: 'The value of π.'),
    );

    defGlobal(defMath);
  }

  void initStdCoroutines({required CoroutineCallbacks impl}) {
    coroutineImpls = impl;
    final defCoroutine = LuaObject.tableFrom('coroutine', [
      LuaFuncBuilder.create('create')
          .arg('fn')
          .exec(
            call: () {
              final fn = findVar('fn');
              if (fn is LuaObject && fn.isFunc) {
                final int addr = impl.onCoroutineCreate.call(fn);
                return LuaThread(addr).toLua('co');
              }

              final t = switch (fn) {
                null => 'nil',
                final LuaObject o => o.luaTypeInfo,
              };

              throw 'Expected function for coroutine. Found $t.';
            },
          )
        ..doc = LuaDoc(
          html: '''
          Creates a new coroutine with a function <code>fn</code> and returns an object 
          of type <code>thread</code>.
          ''',
        ),
      LuaFuncBuilder.create('resume')
          .arg('co')
          .varargs()
          .exec(
            call: () {
              final co = findVar('co');
              final vs = findVarArgs();
              if (co?.isThread ?? false) {
                final thread = co!.value as LuaThread;
                return impl.onCoroutineResume.call(thread.addr, vs ?? []);
              }

              throw 'Expected coroutine for "resume".';
            },
          )
        ..doc = LuaDoc(
          html: '''
          Resumes the coroutine <code>co</code> and passes the parameters if any. 
          It returns the status of operation and optional other return values.
          ''',
        ),
      LuaFuncBuilder.create('yield').varargs().exec(
          call: () {
            final vs = findVarArgs();
            return impl.onCoroutineYield.call(vs ?? []);
          },
        )
        ..doc = LuaDoc(
          html: '''
          Suspends the running coroutine. The optional parameters passed to this 
          method acts as additional return values to the resume function.
          ''',
        ),
      LuaFuncBuilder.create('status')
          .arg('co')
          .exec(
            call: () {
              final co = findVar('co');
              if (co?.isThread ?? false) {
                final thread = co!.value as LuaThread;
                return impl.onCoroutineStatus.call(thread.addr).toLuaRet();
              }

              throw 'Expected coroutine for "status".';
            },
          )
        ..doc = LuaDoc(
          html: '''
          Returns one of the values: <code>running</code>, <code>normal</code>, 
          <code>suspended</code>, or <code>dead</code> based on the state of the coroutine.
          ''',
        ),
    ]);

    defGlobal(defCoroutine).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Lua offers asymmetric coroutines as a way to reason about statefulness without
      resorting to bloated abstractions to keep track of state and execution.
      ''',
    );
  }

  // I don't have a better name for this group.
  void initMiscRuntime() {
    pcall() {
      final fn = findVar('fn')?.toLuaRet();
      if (fn == null || fn.isNotFunc) {
        throw 'pcall expects a function argument!';
      }

      String err = '';
      except(e) {
        err = e.toString();
      }

      final results = callLuaFunction(fn, onException: except);

      if (err.isNotEmpty) {
        return [false.toLuaRet(), err.toLuaRet()];
      }

      // OK
      return [true.toLuaRet(), ...results];
    }

    defGlobal(
      LuaFuncBuilder.create('pcall').arg('fn').exec(call: pcall),
    ).doc = LuaDoc(
      category: catRuntime,
      html: '''
        The <code>pcall</code> function calls its first argument in protected mode,
        so that it catches any errors while the function is running. If there are no errors,
        <code>pcall</code> returns <code>true</code> plus any values returned by the call.
        Otherwise, it returns <code>false</code> plus the error message.'
        ''',
    );

    defGlobal(
      LuaFuncBuilder.create('xpcall').arg('fn').exec(call: pcall),
    ).doc = LuaDoc(
      category: catRuntime,
      html: '''
      This lua runtime does not support the debug library nor stack traces at runtime.
      Therefore the function <code>xpcall</code> is another name for <code>pcall</code>.
      They do the same thing.
      ''',
    );
  }
}
