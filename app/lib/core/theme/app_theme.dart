import 'package:flutter/material.dart';

import '../../domain/entity/score_result.dart';

/// 主色：安全绿
const kPrimary = Color(0xFF00B578);
const kPrimaryDark = Color(0xFF00925F);
const kPrimaryLight = Color(0xFF7CE0BE);

/// 等级色（安全=绿，风险=红）
const kGradeA = Color(0xFF00A870);
const kGradeB = Color(0xFF5CD6A0);
const kGradeBMinus = Color(0xFFFFC53D);
const kGradeC = Color(0xFFFF8F1F);
const kGradeD = Color(0xFFE54545);

const kBg = Color(0xFFF5F7FA);
const kSurface = Color(0xFFFFFFFF);
const kTextPri = Color(0xFF1A1A1A);
const kTextSec = Color(0xFF6B7280);
const kDivider = Color(0xFFEDEFF2);
const kWarnBg = Color(0xFFFFF7E6);
const kDangerBg = Color(0xFFFFF1F0);

const kRadiusS = 8.0;
const kRadiusM = 12.0;
const kRadiusL = 20.0;

Color gradeColor(Grade g) => switch (g) {
      Grade.a => kGradeA,
      Grade.b => kGradeB,
      Grade.bMinus => kGradeBMinus,
      Grade.c => kGradeC,
      Grade.d => kGradeD,
      Grade.unknown => const Color(0xFF9E9E9E),
    };

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.light),
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: kTextPri,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusM)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusS)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusS),
        borderSide: const BorderSide(color: kDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusS),
        borderSide: const BorderSide(color: kDivider),
      ),
    ),
    dividerColor: kDivider,
  );
}
