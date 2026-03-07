import 'package:flutter/material.dart';

extension ThemeExtensions on BuildContext {
  double get width => MediaQuery.of(this).size.width;
  double get height => MediaQuery.of(this).size.height;
  TextTheme get textTheme => Theme.of(this).textTheme;
}
