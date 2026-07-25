import 'dart:math' as math;
import 'package:puredartlua/lua/visitors/runtime/luaobject.dart';
import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/visitors/runtime/base.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

const catRuntime = 'Runtime';

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
  }

  void initStdMetatables() {
    final defSetMetatable = LuaFuncBuilder.create('setmetatable')
        .arg('t')
        .arg('mt')
        .exec(
          call: () {
            final t = findVar('t');
            final mt = findVar('mt');

            if(t == null || t.isNotTable) {
              throw 'Expected lua table as first argument.';
            }

            if(mt == null || mt.isNotTable) {
              throw 'Expected lua table as second argument.';
            }

            t.setMetatable(mt);
          },
        );

    defGlobal(defSetMetatable).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Given lua object <code>t</code> and a table of functions <code>mt</code>,
      sets <code>t</code>'s metatable to <code>mt</code>.
      ''',
    );

    final defGetMetatable = LuaFuncBuilder.create('getmetatable')
        .arg('t')
        .exec(
          call: () {
            final t = findVar('t');

            if(t == null) {
              throw 'Expected lua object as first argument.';
            }

            return t.getMetatable();
          },
        );

    defGlobal(defGetMetatable).doc = LuaDoc(
      category: catRuntime,
      html: '''
      Given lua object <code>t</code> returns the metatable used
      by <code>t</code> or <code>nil</code> if no metatable is set.
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
      final Map<String, LuaObject> newFields = {};

      int i = 0;
      while(i < fields.length) {
        final String key = '${i+1}';
        if(fields.containsKey(key)) {
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
        throw 'Expected table input for pairs(...), found $type.';
      }

      t as LuaObject;
      final name = t.id;

      // t.isTable was true.
      final fields = t.fields!;

      // Null fields are marked as deleted in lua.
      // I don't remove them in this implementation,
      // but we do exclude them from all operations that
      // expose keys.
      final newFields =
        fields
          .entries
          .where((e) => e.value?.isNil == false)
          .map((e) => MapEntry(e.key, e.value!));

      return LuaObject.table('ipairs_$name',
        Map<String, LuaObject>.fromEntries(newFields)
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
      tostring(LuaObject e) {
        final mm = e.readMetatable('__tostring')?.as<LuaObject>();
        if(mm == null) return e;
        return callLuaFunction(mm, args: [e]).unpack();
      }

      impl?.call(findVarArgs()?.map(tostring).join(' ') ?? '');
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
                    return (math.exp(x) + math.exp(-x)) * 0.5;
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
                    return (math.exp(x) - math.exp(-x)) * 0.5;
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
                    final expPos = math.exp(x);
                    final expNeg = math.exp(-x);
                    return (expPos - expNeg) / (expPos + expNeg);
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
                    if (y == 0) {
                      throw 'Division by zero in fmod.';
                    }

                    return x - (x / y).truncateToDouble() * y;
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
                return impl.onCoroutineResume
                    .call(thread.addr, vs ?? []);
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
      Lua offsers asymmetric coroutines as a way to reason about statefulness without
      resorting to bloated abstractions to keep track of state and execution.
      ''',
    );
  }
}
