import 'package:flutter/material.dart';

const appPrimary = Color(0xFF4E6EF2); // 豆包蓝
const appDarkBackground = Color(0xFF1E1E1E);
const appDarkForeground = Color(0xFFD4D4D4);

// 抖音主题色：青 -> 红 渐变
const douyinCyan = Color(0xFF25F4EE);
const douyinRed = Color(0xFFFE2C55);
const appDouyinPrimary = Color(0xFFFE2C55); // 单色（用于控件选中态）

// 豆包主题色：豆包蓝深浅渐变
const doubaoBlueLight = Color(0xFF4E6EF2);
const doubaoBlueDeep = Color(0xFF3157F4);

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color card;
  final Color foreground;
  final Color mutedForeground;
  final Color border;
  final Color muted;

  const AppPalette({
    required this.background,
    required this.card,
    required this.foreground,
    required this.mutedForeground,
    required this.border,
    required this.muted,
  });

  static const light = AppPalette(
    background: Color(0xFFFAFAFA),
    card: Color(0xFFFFFFFF),
    foreground: Color(0xFF1A1A1A),
    mutedForeground: Color(0xFF8C8C8C),
    border: Color(0xFFEBEBEB),
    muted: Color(0xFFF3F3F3),
  );

  static const dark = AppPalette(
    background: appDarkBackground,
    card: Color(0xFF252526),
    foreground: appDarkForeground,
    mutedForeground: Color(0xFF9D9D9D),
    border: Color(0xFF3E3E42),
    muted: Color(0xFF2D2D30),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? card,
    Color? foreground,
    Color? mutedForeground,
    Color? border,
    Color? muted,
  }) {
    return AppPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      border: border ?? this.border,
      muted: muted ?? this.muted,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }

  /// 当前主题的主色（随模式切换：豆包橙 / 抖音红）
  Color get primary {
    final theme = Theme.of(this);
    return theme.colorScheme.primary;
  }
}

ThemeData buildAppTheme(Brightness brightness, {String mode = 'doubao'}) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? AppPalette.dark : AppPalette.light;
  final primary = mode == 'douyin' ? appDouyinPrimary : appPrimary;
  final scheme = dark
      ? ColorScheme.dark(
          primary: primary,
          onPrimary: Colors.white,
          surface: appDarkBackground,
          onSurface: appDarkForeground,
          outline: const Color(0xFF3E3E42),
        )
      : ColorScheme.light(
          primary: primary,
          onPrimary: Colors.white,
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF1A1A1A),
          outline: const Color(0xFFEBEBEB),
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    colorScheme: scheme,
    extensions: [palette],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: 1,
      space: 1,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: palette.card,
      selectedItemColor: primary,
      unselectedItemColor: palette.mutedForeground,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.card,
      hintStyle: TextStyle(color: palette.mutedForeground),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// 抖音模式专属的青红渐变（用于主按钮、模式切换器选中态、解析按钮等）
const douyinGradient = LinearGradient(
  colors: [douyinCyan, douyinRed],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

/// 豆包模式专属的蓝色深浅渐变（用于主按钮、模式切换器选中态、解析按钮等）
const doubaoGradient = LinearGradient(
  colors: [doubaoBlueLight, doubaoBlueDeep],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);
