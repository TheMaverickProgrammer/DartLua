import 'package:colorize/colorize.dart';

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