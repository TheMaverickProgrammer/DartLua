import 'package:puredartlua/lua/visitors/runtime/base.dart';

abstract class Semantics {}

typedef IncludeCallback = Object? Function(String, BaseRuntime);
