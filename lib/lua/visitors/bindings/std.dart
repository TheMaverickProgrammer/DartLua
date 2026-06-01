import 'dart:math' as math;
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

const catRuntime = 'Runtime';

typedef StdPrintCallback = void Function(String);

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

  /// This is called by the closure defined in [initStdCoroutines].
  /// The callback expects a [LuaObject] argument which will have
  /// satisfied [LuaObject.isFunc]. The implementation expected
  /// to return an [int] address value of the designated coroutine.
  int Function(LuaObject)? onCoroutineCreate;

  /// Given a coroutine [int] address, return the status of the
  /// coroutine as a [String].
  String Function(int)? onCoroutineStatus;

  /// Given a coroutine [int] address, resume that coroutine and
  /// return a value. Multiple values will be unpacked by the runtime.
  LuaObject Function(int)? onCoroutineResume;

  /// Given a list of lua value [args], perform the coroutine
  /// yield behavior.
  void Function(List<LuaObject> args)? onCoroutineYield;

  void initStdRuntime() {
    initStdStrings();
    initStdRequire();
    initStdIPairs();
    initStdPairs();
    initStdTable();
    initStdPrint();
    initStdMath();
    initStdCoroutines();
  }

  void initStdCoroutines() {
    final defCoroutine = LuaObject.tableFrom('coroutine', [
      LuaFuncBuilder.create('create')
        .arg('fn')
        .exec(call: () {
          final fn = findVar('fn');
          if(fn is LuaObject && fn.isFunc) {
            final int? addr = onCreateCoRoutine?.call(fn);
            if(addr == null) return LuaObject.nil('co');
            return LuaThread(addr).toLua('co');
          }

          final t = switch(fn) {
            null => 'nil',
            final LuaObject o => o.luaTypeInfo,
            final Object o => o.runtimeType,
          };

          throw 'Expected function for coroutine. Found $t.';
        }),
      LuaFuncBuilder.create('resume')
        .arg('co')
        .exec(call: () {
          final co = findVar('co');
          if(co?.isThread ?? false) {
            return onCoroutineResume?.call(co!.value.addr).toLuaRet();
          }

          throw 'Expected coroutine for "resume".';
        }),
      LuaFuncBuilder.create('yield')
        .vararg()
        .exec(call: () {
          final vs = findVarArgs();
          onCoroutineYield?.call(vs);
        })
      LuafuncBuilder.create('status')
        .arg('co')
        .exec(call: () {
          final co = findVar('co');
          if(co?.isThread ?? false) {
            return onCoroutineStatus?.call(co!.value.addr)?.toLuaRet();
          }
          
          throw 'Expected coroutine for "status".';
        });
    ]);

    defGlobal(defCoroutine).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Lua offsers asymmetric coroutines as a way to reason about statefulness without
      resorting to bloated abstractions to keep track of state and execution.
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
      final modname = findVar('modname');
      final v = modname?.valueAs<String>();
      if (v == null) {
        final type = v.runtimeType;
        throw 'Expected string for modname in `require(modname)`. Found $type.';
      }

      Object? result;
      try {
        pushScope();
        result = onRequireImpl?.call(v, this);
      } catch (e) {
        addError(e.toString());
      } finally {
        popScope();
      }

      onRequireImplComplete?.call(v);

      return result?.makeLuaRef()?.unpack() ?? LuaObject.nil(v);
    }

    final token = Token.synthesized('require');
    final defRequire = FuncExpr.named(
      token,
      body: [],
      args: [DeclArg(Token.synthesized('modname'))],
      idParts: [RawExpr(token)],
    );

    defGlobal(LuaObject.func('require', defRequire, exec)).doc = LuaDoc(
      category: catRuntime,
      html: '''
      The runtime resolves the lua script identified by <code>modname</code>, executes,
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
        throw 'Expected table input for ipairs(...), found $type.';
      }

      t as LuaObject;
      final name = t.id;
      // t.isTable was true.
      final fields = t.fields!;
      return LuaObject.table('ipairs_$name', {
        for (int i = 0; i < fields.entries.length; i++)
          (i + 1).toString(): fields.entries.elementAtOrNull(i)?.value,
      });
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
        throw 'Expected table input for pairs(...), found $type.';
      }

      t as LuaObject;
      final name = t.id;

      // t.isTable was true.
      final fields = t.fields!;

      final newFields = fields.map<String, LuaObject>((k, v) {
        final value = switch (v) {
          null => LuaObject.nil('value'),
          final LuaObject obj => obj,
        };

        final id = value.id;
        return MapEntry<String, LuaObject>(id, value);
      });

      return LuaObject.table('ipairs_$name', newFields);
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
                      throw 'Expected table argument "t" for "${context!.id}".';
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
                        throw 'Expected integer "position" for "${context!.id}".';
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
                category: 'Runtime',
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
                  throw 'Expected table argument "tableData" for "${context!.id}".';
                }

                int? position = findVar('value')?.valueAsInt();

                if (position == null) {
                  throw 'Expected integer "position" for "${context!.id}".';
                }

                return tableData.tableRemove(position);
              },
            ),
      }),
    ).doc = LuaDoc(
      category: 'Runtime',
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
      impl?.call(findVarArgs()?.join(' ') ?? 'nil');
    }

    defGlobal(LuaObject.func('print', defPrint, exec)).doc = LuaDoc(
      category: 'Runtime',
      html: '''
          Converts a lua object to a string and then
          displays to console. See <a href="#tostring">tostring</a>.
          ''',
    );
  }

  void initStdMath() {
    final defMath =
        LuaObject.table('math', {
            'abs': LuaFuncBuilder.create('abs')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x.abs();
                  },
                ),
            'acos': LuaFuncBuilder.create('acos')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.acos(x);
                  },
                ),
            'asin': LuaFuncBuilder.create('asin')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.asin(x);
                  },
                ),
            'atan': LuaFuncBuilder.create('atan')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.atan(x);
                  },
                ),
            'atan2': LuaFuncBuilder.create('atan2')
                .arg('y')
                .arg('x')
                .exec(
                  call: () {
                    final y = findVar('y')?.valueAs<num>();
                    if (y == null) {
                      throw 'Expected num argument "y" for "${context!.id}".';
                    }

                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }

                    return math.atan2(y, x);
                  },
                ),
            'ceil': LuaFuncBuilder.create('ceil')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x.ceil();
                  },
                ),
            'cos': LuaFuncBuilder.create('cos')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.cos(x);
                  },
                ),
            'sin': LuaFuncBuilder.create('sin')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.sin(x);
                  },
                ),
            'tan': LuaFuncBuilder.create('tan')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.tan(x);
                  },
                ),
            'cosh': LuaFuncBuilder.create('cosh')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x; // TODO
                  },
                ),
            'sinh': LuaFuncBuilder.create('sinh')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x; // TODO
                  },
                ),
            'tanh': LuaFuncBuilder.create('tanh')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x; // TODO
                  },
                ),
            'deg': LuaFuncBuilder.create('deg')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x * 180.0 / math.pi;
                  },
                ),
            'rad': LuaFuncBuilder.create('rad')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x * math.pi / 180.0;
                  },
                ),
            'exp': LuaFuncBuilder.create('exp')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.exp(x);
                  },
                ),
            'floor': LuaFuncBuilder.create('floor')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x.floor();
                  },
                ),
            'fmod': LuaFuncBuilder.create('fmod')
                .arg('x')
                .arg('y')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    final y = findVar('y')?.valueAs<num>();
                    if (y == null) {
                      throw 'Expected num argument "y" for "${context!.id}".';
                    }
                    return x; // TODO: math.fmod(x / y);
                  },
                ),
            'frexp': LuaFuncBuilder.create('frexp')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x; // TODO
                  },
                ),
            // TODO: math.huge
            'log': LuaFuncBuilder.create('log')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.log(x);
                  },
                ),
            'log10': LuaFuncBuilder.create('log10')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return x; // TODO
                  },
                ),
            'pow': LuaFuncBuilder.create('pow')
                .arg('x')
                .arg('y')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }

                    final y = findVar('y')?.valueAs<num>();
                    if (y == null) {
                      throw 'Expected num argument "y" for "${context!.id}".';
                    }

                    return math.pow(x, y);
                  },
                ),
            'sqrt': LuaFuncBuilder.create('sqrt')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return math.sqrt(x);
                  },
                ),
            'max': LuaFuncBuilder.create('max')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }

                    final varargs = findVarArgs()
                        ?.map(
                          (e) => switch (e.valueAs<num>()) {
                            final num n => n,
                            _ =>
                              throw 'Expected number arguments for "${context!.id}".',
                          },
                        )
                        .toList();

                    if ((varargs ?? []).isEmpty) return x;

                    return varargs!.fold(x, (v, n) => math.max(v, n));
                  },
                ),
            'min': LuaFuncBuilder.create('min')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }

                    final varargs = findVarArgs()
                        ?.map(
                          (e) => switch (e.valueAs<num>()) {
                            final num n => n,
                            _ =>
                              throw 'Expected number arguments for "${context!.id}".',
                          },
                        )
                        .toList();

                    if ((varargs ?? []).isEmpty) return x;

                    return varargs!.fold(x, (v, n) => math.min(v, n));
                  },
                ),
            // Does nothing atm.
            'randomseed': LuaFuncBuilder.create('randomseed')
                .arg('x')
                .exec(
                  call: () {
                    final x = findVar('x')?.valueAs<num>();
                    if (x == null) {
                      throw 'Expected num argument "x" for "${context!.id}".';
                    }
                    return null;
                  },
                ),
            'random': LuaFuncBuilder.create('random')
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
                        return math.Random().nextInt(n0 - m0) + m0 + 1;
                      } else {
                        return math.Random().nextInt(m) + 1;
                      }
                    }

                    return math.Random().nextDouble();
                  },
                ),
          })
          ..doc = LuaDoc(
            category: 'Runtime',
            html: '''
            The lua runtime math library.
            ''',
          );

    defGlobal(defMath);
  }
}
