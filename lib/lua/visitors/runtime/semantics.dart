import 'package:puredartlua/lua/visitors/runtime/base.dart';

abstract class Semantics {}

typedef LuaRequireCallback = Object? Function(String, BaseRuntime);
