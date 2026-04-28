import 'package:puredartlua/lua/passes/lexer.dart';
import 'package:puredartlua/lua/visitors/visitor.dart';

/// Shorthand notation for a [Map] of [String] and [LuaObject]
/// key-pairs. Note that the [LuaObject] can be null as lua
/// represents these as [LuaType.nil].
typedef LuaTable = Map<String, LuaObject?>;

/// Strong type enumerations for all possible lua primitives.
enum LuaType { unresolved, nil, table, ref, func, value }

/// A type to represent if the callstack was unwound b/c of
/// the lua`return` keyword. Stores the [value] of the operation
/// to unpack. See [ReturnStmtCallStackUnwind] and
/// [ReturnStmtDoNotUnwind].
///
/// Not treated as an actual exception or error.
class LuaReturnValueException {
  final LuaObject value;

  LuaReturnValueException(this.value);
}

/// This class provides an API for effortlessly constructing
/// lua function objects.
///
/// Use [LuaFuncBuilder.create] and then chain calls with [arg] to
/// introduce terms to the final function definition. Use [self] if
/// the function should support 'self' as a parameter in-place.
/// Use [exec] to provide a closure definition. This also acts
/// as the terminator to build the [FuncExpr] node and returns
/// the [LuaObject] result.
class LuaFuncBuilder {
  final String id;
  final List<DeclArg> args = [];

  LuaFuncBuilder._(this.id);

  factory LuaFuncBuilder.create(String id) => LuaFuncBuilder._(id);

  /// Create a [DeclArg] node corresponding to the [id].
  /// If [optional] is true, then any generated HTML documentation
  /// will decorate this parameter with '[]' pairs. This named argument
  /// does nothing to the semantics or the lua runtime.
  LuaFuncBuilder arg(String id, {bool optional = false}) =>
      this..args.add(DeclArg(Token.synthesized(id), isOptional: optional));

  LuaFuncBuilder self() =>
      this..args.add(DeclArg(Token.synthesized('self', type: TokenType.kSelf)));

  LuaObject exec({Function? call}) {
    final closure = call ?? () => LuaObject.variable('ret_$id', null);

    final token = Token.synthesized(id);
    final def = FuncExpr.named(
      token,
      body: [],
      args: args,
      idParts: [RawExpr(token)],
    );

    return LuaObject.func(id, def, closure);
  }
}

/// The configuration class for [LuaObject.doc] instances.
/// To add documentation use the [LuaDoc] constructor.
/// Provide a [category] and the generated docs will group it with
/// those objects sharing the same category.
/// To omit the [LuaObject] from the generated docs, use [LuaDoc.skip].
class LuaDoc {
  /// Which category the associated [LuaObject] belongs.
  String? category;

  /// See [html].
  String? _html;

  /// A helper function that maps a table's primitive fields
  /// to their html documentation. This is useful if your
  /// lua object contains fields that are not [LuaObject]s
  /// such as [int] or [bool].
  /// The auto doc will print them as-is without further inspection.
  /// Using this helper will produce additional documentation.
  final String Function(Object value)? keyValueHtml;

  /// A helper function that filters what values or enums
  /// from your table will be present in the generated docs.
  /// This is useful if you must have symbols in your runtime
  /// but wish to exclude those from public documentations.
  final bool Function(Object value)? exclude;

  /// Whether or not the [LuaObject] associated should be
  /// rendered out to html.
  final bool noHtml;

  /// Sets private [_html] to [str].
  set html(String str) => _html = str;

  /// The getter for [_html] which returns empty string if null.
  String get html => _html ?? '';

  /// The positive variant of [noHtml].
  bool get includeHtml => !noHtml;

  /// Configuration sets [noHtml].
  LuaDoc.skip() : noHtml = true, keyValueHtml = null, exclude = null;

  /// Custom configuration associated with some [LuaObject].
  LuaDoc({this.category, String? html, this.keyValueHtml, this.exclude})
    : noHtml = false,
      _html = html;
}

class LuaObject {
  /// The variable name.
  /// Note that if this instance is a value in a table,
  /// then the table may know it by a different name. See [fields].
  final String id;

  /// If this object has html content, it may
  /// show up in the autodoc generation.
  LuaDoc? doc;

  /// For non-table lua objects, this stores the value.
  Object? _value;

  /// For table lua objects, this stores all keys and values.
  LuaTable? _fields;

  /// If this lua object is a function, it will have [FuncExpr]
  /// node with information about its arguments.
  FuncExpr? funcDef;

  /// Whenever this lua object is accessed to read its [value]
  /// or [fields], then a callback can be provided with the name
  /// of the field which was accessed.
  Function(String)? _onRead;

  /// Whenever this lua object has its [value]
  /// or [fields] changed (written), then a callback can be provided
  /// with the name of the field which was written.
  Function(String, Object?)? _onWrite;

  /// How often this object was read or written during evaluation.
  /// Can be used for optimization and reporting unused variables.
  int uses = 0;

  /// A reference object to a [LuaObjectNoSemantics] type
  /// should be treated transitively as a [LuaObjectNoSemantics] type.
  bool get skipSemanitcs =>
      this is LuaObjectNoSemantics ||
      switch (isRef) {
        true => deref().skipSemanitcs,
        false => false,
      };

  /// A lua object is nil if both its [value] and [fields]
  /// are nil.
  ///
  /// A reference to a nil lua object is treaded
  /// transitively as a nil lua object.
  bool get isNil => switch (isRef) {
    true => deref().isNil,
    false => _value == null && _fields == null,
  };

  /// A lua object is a table if its fields are non null.
  ///
  /// A reference to a nil lua object is treaded
  /// transitively as a nil lua object.
  bool get isTable => switch (isRef) {
    true => deref().isTable,
    false => _fields != null,
  };

  /// Query the negation of [isTable].
  bool get isNotTable => !isTable;

  /// Query if the stored [value] is of type [LuaObject].
  bool get isRef => _value is LuaObject;

  /// Query if the stored value is not a reference and the [value] is not null.
  bool get isValue => !isRef && _value != null;

  /// Query if this lua object is a table and has a field named '__call'.
  bool get isFunc => isTable && readField('__call') != null;

  /// Query the negation of [isFunc].
  bool get isNotFunc => !isFunc;

  /// Query if std "print" can print the [value].
  /// This is short for asking if the lua object is a table
  /// or a function, which would return the address in the VM
  /// at runtime for this lua obejct.
  bool get isPrintable => switch (isRef) {
    true => deref().isPrintable,
    false => !isTable && !isFunc,
  };

  /// In lua, all values have a truthyness which
  /// means they can be used in conditional statements.
  /// If [value] is null or false, then the result is false.
  /// All other values and the result is true.
  /// If this lua object is a table, then the result is true.
  bool get isTruthy => switch (isRef) {
    true => deref().isTruthy,
    false => switch (isTable) {
      false => switch (_value) {
        null || false => false,
        _ => true,
      },
      true => true,
    },
  };

  /// Query the negation of [isTruthy].
  bool get isFalsey => !isTruthy;

  /// Convenience util to project this lua object
  /// into a map entry keyed by its own [id].
  MapEntry<String, LuaObject> get asMapEntry =>
      MapEntry<String, LuaObject>(id, this);

  /// Query the [LuaType] based on if the following
  /// properties hold:
  /// - [isNil]
  /// - [isTable]
  /// - [isRef]
  /// - [isValue]
  ///
  /// Otherwise the result is [LuaType.unresolved].
  LuaType get type {
    if (isNil) return LuaType.nil;
    if (isTable) return LuaType.table;
    if (isRef) return LuaType.ref;
    if (isValue) return LuaType.value;
    return LuaType.unresolved;
  }

  /// Returns the lua runtime type information.
  /// Unlike vanilla lua, this runtime comes with
  /// additional runtime semantics.
  ///
  /// **CAUTION**
  /// Note that this is not a substitution for the
  /// std function "typeof". This is for debugging
  /// the runtime if needed.
  String get typeinfo {
    final String meta = switch (skipSemanitcs) {
      true => '<noSemantics> ',
      false => '',
    };

    final out = switch (type) {
      LuaType.unresolved => '<unresolved>',
      LuaType.value => '${value.runtimeType}',
      LuaType.ref => 'ref ${deref().typeinfo}',
      LuaType.nil => 'nil',
      LuaType.table => 'table',
      LuaType.func => 'func',
    };

    return '$meta$out';
  }

  /// Returns the lua equivalent runtime type
  /// information. The result is the same as
  /// what lua `type(x)` would return. This
  /// is useful for quick type checking and
  /// printing helpful error messages.
  String get luaTypeInfo {
    if (isTable) return 'table';
    if (isFunc) return 'function';
    return switch (deref().value) {
      null => 'nil',
      final int _ => 'num',
      final double _ => 'num',
      final bool _ => 'boolean',
      final String _ => 'string',
      final Object _ => 'userdata',
    };
  }

  /// Returns the arity of this object.
  /// For lua table length, see [tableSize];
  int get length {
    uses++;
    return switch (type) {
      LuaType.ref => deref().length,
      LuaType.nil || LuaType.unresolved || LuaType.func => 0,
      LuaType.table => _fields?.length ?? 0,
      LuaType.value => 1,
    };
  }

  /// Begins at field "1" and increments this string
  /// until no field is found with that key. Returns the
  /// largest integer field found minus one.
  /// This mimics lua's table len (#) behavior.
  int get tableSize {
    uses++;
    _onRead?.call('self');

    int i = 1;
    while (hasField(i.toString())) {
      i++;
    }

    return i - 1;
  }

  /// Convenience method to implement std table
  /// methods.
  ///
  /// Returns null if there is a problem
  /// Otherwise returns a lua object.
  LuaObject? tableInsert(int index, LuaObject value) {
    uses++;
    if (isTable) {
      final int sz = tableSize;
      if (index < 1 || index > tableSize + 1) return null;

      final List<Object> vals = [];

      int others = index;
      while (hasField(others.toString())) {
        vals.add(readField(others.toString())!);
        others++;
      }

      writeField(index.toString(), value);

      if (others <= sz) {
        while (others > 0) {
          writeField((others + 1).toString(), vals.removeLast());
          others--;
        }
      }

      return LuaObject.nil('ret');
    }

    return null;
  }

  /// Convenience method to implement std table
  /// methods.
  ///
  /// Returns null if there was a problem.
  /// Otherwise, returns the removed lua object.
  LuaObject? tableRemove(int index) {
    uses++;
    if (isTable) {
      LuaObject? out;
      deref()._fields?.removeWhere((key, value) {
        if (key == index.toString()) {
          out = value;
          return true;
        }

        return false;
      });
      return out;
    }

    return null;
  }

  /// Bumps [uses] by one and
  /// returns the stored [_fields]
  /// if a table or [_value] otherwise.
  Object? get value {
    uses++;
    _onRead?.call('self');

    return switch (isTable) {
      true => deref()._fields,
      false => switch (_value) {
        final LuaObject obj => obj.deref().value,
        _ => _value,
      },
    };
  }

  /// Inspects [this.value]. If the type
  /// is [LuaObject], inspects its [this.value].
  /// If the underlying value type is [T], then
  /// it is returned. If no underlying value type
  /// matches [T], the [null] is returned.
  ///
  /// For tables, see [fieldValueAs].
  T? valueAs<T>() {
    uses++;
    _onRead?.call('self');

    return switch (value) {
      final LuaObject obj => switch (obj.value) {
        final T v => v,
        _ => null,
      },
      final T v => v,
      _ => null,
    };
  }

  /// Tries to cast [this.value] as [num]
  /// and performs a lossy integer division
  /// to obtain the leading part of the double.
  /// If the leading part is equal to the double
  /// representation, the value must be a whole number
  /// and therefore an integer. Otherwise, loss happened
  /// and it must be a real number and therefore a double.
  /// If the underlying type of [this.value] is not [num]
  /// then [null] is returned.
  int? valueAsInt() {
    final num? n = valueAs<num>();
    if (n == null) return null;

    final int i = (n ~/ 1);

    if (i.toDouble() == n.toDouble()) {
      return i;
    }

    return null;
  }

  /// Returns the stored [_fields] value
  /// **CAUTION**: check [isTable] is true before use!
  LuaTable get fields => deref()._fields!;

  /// Bumps [uses] by one and stores
  /// [from] as the new [_value] or [_fields]
  /// depending on the type of [from].
  set value(Object? from) {
    uses++;
    if (from == null) {
      _value = null;
      _fields = null;
    } else if (from is LuaTable) {
      _value = null;
      _fields = from;
    } else if (from is LuaObject) {
      _value = from.deref();
      _fields = null;
    } else {
      _value = from;
      _fields = null;
    }
    _onWrite?.call('self', from);
  }

  /// Creates and returns a [LuaObject.ref] instance
  /// of itself.
  LuaObject toRef() => LuaObject.ref(this);

  /// Attempts to find the metamethod '__call' and if found,
  /// executes its closure.
  /// Otherwise this throws an error.
  Object? call() {
    uses++;
    return switch (skipSemanitcs) {
      true => () {
        return LuaObject.noSemantics('${id}_metamethod__call');
      },
      false => switch (fieldValueAs<Function>('__call')) {
        final Function func => func(),
        _ => throw 'No metamethod "__call" on "$id".',
      },
    };
  }

  /// Internal utility method to determine if this
  /// unpacked lua object is a table and has a field named [key].
  bool hasField(String key) {
    if (isRef) {
      return deref().hasField(key);
    } else if (isTable) {
      return _fields?.containsKey(key) ?? false;
    }
    return false;
  }

  /// If this lua object is a table,
  /// unpacks [_fields] and returns the value.
  /// Otherwise null is returned.
  Object? readField(String key) {
    uses++;
    _onRead?.call(key);

    if (skipSemanitcs) return LuaObjectNoSemantics(key);

    if (isRef) {
      return deref().readField(key);
    } else if (isTable) {
      return switch (_fields?[key]) {
        final LuaObject obj => obj.deref(),
        null => null,
      };
    } else {
      // Not allowed except on tables.
      return null;
    }
  }

  /// Inspects the result of [readField] with [key].
  /// If the result's type is [LuaObject], then
  /// it also inspects its [this.value].
  /// If the underlying value type is [T], then
  /// it is returned. If no underlying value type
  /// matches [T], then [or] is returned.
  ///
  /// For non-table lua objects, see [valueAs].
  ///
  /// ### Implicit Casting
  /// If the underlying value is of type
  /// [double] and the requested [T] type is [int]
  /// then an implicit cast is performed.
  ///
  /// This is because in lua, reals and integers
  /// are stored the same way and the fractional
  /// part of the stored value determines whether
  /// or not some lua value is or isn't an integer.
  T? fieldValueAs<T>(String key, {T? or}) {
    uses++;
    if (skipSemanitcs) return or;

    final v = switch (readField(key)) {
      final LuaObject obj => obj.value,
      final Object? other => other,
    };

    if (v is double && T == int) {
      return v.toInt() as T;
    }

    return switch (v) {
      final T obj => obj,
      _ => or,
    };
  }

  /// If this lua object is a table, then
  /// it writes [value] to [key] and returns the field [key].
  /// Otherwise if the lua object is not a table, then null is returned.
  Object? writeField(String key, Object? value) {
    if (skipSemanitcs) return LuaObject.noSemantics(key);

    Object? result;
    if (isRef) {
      result = deref().writeField(key, value);
    } else if (isTable) {
      result = switch (_fields![key]) {
        final LuaObject obj => obj.value = value,
        null => _fields![key] = LuaObject.variable(key, value),
      };
    }
    _onWrite?.call(key, value);
    return result;
  }

  /// A convenience utility to write all fields from some input [table].
  void writeFields(LuaTable table) {
    final ref = deref();
    for (final f in table.entries) {
      ref.writeField(f.key, f.value);
    }
  }

  /// Unpacks a lua object if it holds a reference to another
  /// lua object during runtime. Otherwise if [isRef] is false,
  /// then it returns itself.
  LuaObject deref() {
    if (!isRef) return this;
    return (_value as LuaObject).deref();
  }

  /// Default constructor for some lua object. The variable name
  /// in scope will become [id] and can have either [fields] or
  /// [value] but not both.
  LuaObject(this.id, {LuaTable? fields, Object? value})
    : _value = value,
      _fields = fields,
      assert(
        (value == null || fields == null),
        '''A lua object's storage can either be a value or 
          a set of fields if it should become a table, but it
          cannot have both!
        ''',
      );

  /// Constructs a lua object with [id] for its variable name
  /// in scope with some initial [value].
  LuaObject.variable(this.id, Object? value) : super() {
    if (value is LuaTable) {
      _fields = value;
    } else if (value is LuaObject) {
      this.value = value.deref();
      if (value.isFunc) {
        funcDef = value.funcDef;
      }
    } else {
      this.value = value;
    }
  }

  /// Constructs a lua object with [id] for its variable name
  /// in scope with some set of [fields].
  LuaObject.table(this.id, Map<String, Object?> fields) : super() {
    _fields = fields.map(
      (k, v) => MapEntry(k, v?.toLua(k) ?? LuaObject.nil(k)),
    );
  }

  /// Constructs a lua function with [id] for its function name
  /// in scope with some [closure] to be written to the metamethod
  /// '__call'. A required [def] is needed to determine the input
  /// arguments and other runtime information.
  LuaObject.func(this.id, FuncExpr def, Function closure) : super() {
    _fields = {};
    funcDef = def;
    writeField('__call', closure);
  }

  /// Constructs a lua object with null values and fields.
  LuaObject.nil(this.id);

  /// See [toRef].
  /// Note that the runtime [id] will be prefixed with meta information
  /// to assist debugging call stacks.
  LuaObject.ref(LuaObject src) : id = 'ref_${src.id}', super() {
    _value = src;
    _fields = null;
    funcDef = null;
  }

  /// Constructs a [LuaObjectNoSemantics] instance whose variable name
  /// in scope is [id].
  factory LuaObject.noSemantics(String id) => LuaObjectNoSemantics(id);

  /// Whenever a lua object's fields or value is read, executes [callback].
  void onRead(Function(String)? callback) => _onRead = callback;

  /// Whenever a lua object's fields or value is modified (written),
  /// executes [callback]. If the lua object's storage is [value], then
  /// the first argument of [callback] will be 'self'. Otherwise it is
  /// the string name of the field's key.
  void onWrite(Function(String, Object?)? callback) => _onWrite = callback;

  /// Due to a dart bug, I cannot throw if we're converting a table
  /// or some other unknown data type to a string.
  /// Instead, unhandled types return their variable name wrapped
  /// in angle brackets <>. I'll check for string type conversion
  /// as-needed instead.
  @override
  String toString() {
    if (isValue) {
      return switch (value) {
        // Lua promotes decimal values without fractional parts to int.
        final double d => switch ((d - d.toInt()) == 0.0) {
          true => d.toInt(),
          false => d,
        }.toString(),
        _ => value.toString(),
      };
    } else if (isRef) {
      return deref().toString();
    } else if (isNil) {
      return 'nil';
    }

    return '<$id>';
  }
}

/// Represents a lua object for analyzing irregardless
/// if it is a well-defined variable or value.
/// This permits any visitor to look pass semantic errors
/// and continue marching through the grapheme.
class LuaObjectNoSemantics extends LuaObject {
  LuaObjectNoSemantics(super.id) : super();
}

/// A convenience utility on [Object] to construct
/// [LuaObject] instances in-place.
///
/// See [Object.toLua].
extension Native2Lua on Object {
  /// A new [LuaObject.variable] instance
  /// is returned whose variable name in scope is [id].
  LuaObject toLua(String id) => LuaObject.variable(id, this);

  /// Calls [toLua] with the id of "ret"
  /// which is short for "return".
  /// The helps track return values.
  LuaObject toLuaRet() => toLua('ret');

  /// Attempts to return the underlying [LuaObject]
  /// of [this] to be used as a direct handle or
  /// reference. Otherwise null is returned.
  LuaObject? makeLuaRef() => switch (this) {
    final LuaObject obj => obj,
    _ => null,
  };
}
