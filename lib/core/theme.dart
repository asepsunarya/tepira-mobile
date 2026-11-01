import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette of the tepira village style (docs/design/screens/PanduanGaya.dc.html
/// and Komponen.dc.html). Widgets read colors from here, never from hex literals.
@immutable
class VillageColors extends ThemeExtension<VillageColors> {
  const VillageColors({
    required this.langit,
    required this.langitMuda,
    required this.kertas,
    required this.kartu,
    required this.ink,
    required this.ink2,
    required this.redup,
    required this.garis,
    required this.tileBorder,
    required this.track,
    required this.pink,
    required this.pinkSoft,
    required this.pinkText,
    required this.cta,
    required this.ctaEnd,
    required this.mint,
    required this.mintSoft,
    required this.mintText,
    required this.mintBorder,
    required this.koin,
    required this.koinTua,
    required this.peach,
    required this.merah,
    required this.merahSoft,
    required this.merahBorder,
    required this.biru,
    required this.kuningSoft,
    required this.kuningText,
    required this.catatan,
    required this.disabled,
    required this.putih,
    required this.shadow,
  });

  /// Light village palette; the only palette the app ships.
  static const VillageColors light = VillageColors(
    langit: Color(0xFFCFE9F7),
    langitMuda: Color(0xFFE3F2FB),
    kertas: Color(0xFFFBF1F5),
    kartu: Color(0xFFFFFAF7),
    ink: Color(0xFF5A4A5E),
    ink2: Color(0xFF66566B),
    redup: Color(0xFF74647A),
    garis: Color(0xFFF1E4EA),
    tileBorder: Color(0xFFF6EBF0),
    track: Color(0xFFF3E8EE),
    pink: Color(0xFFFF7EB3),
    pinkSoft: Color(0xFFFFD3E4),
    pinkText: Color(0xFFC2457D),
    cta: Color(0xFFCF3B7B),
    ctaEnd: Color(0xFFBF3571),
    mint: Color(0xFF6CC8AD),
    mintSoft: Color(0xFFDCF5EC),
    mintText: Color(0xFF1F8A63),
    mintBorder: Color(0xFFCDEEE3),
    koin: Color(0xFFF3C35B),
    koinTua: Color(0xFFCC922C),
    peach: Color(0xFFF0A06A),
    merah: Color(0xFFC23B3B),
    merahSoft: Color(0xFFFFE0E0),
    merahBorder: Color(0xFFFFC9C9),
    biru: Color(0xFF5B9AE0),
    kuningSoft: Color(0xFFFFF3D1),
    kuningText: Color(0xFFA87A12),
    catatan: Color(0xFFFFF8DD),
    disabled: Color(0xFFD9CCD5),
    putih: Color(0xFFFFFFFF),
    shadow: Color(0x2E783C64),
  );

  final Color langit;
  final Color langitMuda;
  final Color kertas;
  final Color kartu;
  final Color ink;
  final Color ink2;
  final Color redup;
  final Color garis;
  final Color tileBorder;
  final Color track;
  final Color pink;
  final Color pinkSoft;
  final Color pinkText;
  final Color cta;
  final Color ctaEnd;
  final Color mint;
  final Color mintSoft;
  final Color mintText;
  final Color mintBorder;
  final Color koin;
  final Color koinTua;
  final Color peach;
  final Color merah;
  final Color merahSoft;
  final Color merahBorder;
  final Color biru;
  final Color kuningSoft;
  final Color kuningText;

  /// Yellow note background used by StageNote.
  final Color catatan;
  final Color disabled;

  /// Plain white: card borders, tile fills, text on the CTA gradient.
  final Color putih;

  /// Card shadow, rgba(120,60,100,.18).
  final Color shadow;

  static VillageColors of(BuildContext context) =>
      Theme.of(context).extension<VillageColors>()!;

  @override
  VillageColors copyWith({
    Color? langit,
    Color? langitMuda,
    Color? kertas,
    Color? kartu,
    Color? ink,
    Color? ink2,
    Color? redup,
    Color? garis,
    Color? tileBorder,
    Color? track,
    Color? pink,
    Color? pinkSoft,
    Color? pinkText,
    Color? cta,
    Color? ctaEnd,
    Color? mint,
    Color? mintSoft,
    Color? mintText,
    Color? mintBorder,
    Color? koin,
    Color? koinTua,
    Color? peach,
    Color? merah,
    Color? merahSoft,
    Color? merahBorder,
    Color? biru,
    Color? kuningSoft,
    Color? kuningText,
    Color? catatan,
    Color? disabled,
    Color? putih,
    Color? shadow,
  }) {
    return VillageColors(
      langit: langit ?? this.langit,
      langitMuda: langitMuda ?? this.langitMuda,
      kertas: kertas ?? this.kertas,
      kartu: kartu ?? this.kartu,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      redup: redup ?? this.redup,
      garis: garis ?? this.garis,
      tileBorder: tileBorder ?? this.tileBorder,
      track: track ?? this.track,
      pink: pink ?? this.pink,
      pinkSoft: pinkSoft ?? this.pinkSoft,
      pinkText: pinkText ?? this.pinkText,
      cta: cta ?? this.cta,
      ctaEnd: ctaEnd ?? this.ctaEnd,
      mint: mint ?? this.mint,
      mintSoft: mintSoft ?? this.mintSoft,
      mintText: mintText ?? this.mintText,
      mintBorder: mintBorder ?? this.mintBorder,
      koin: koin ?? this.koin,
      koinTua: koinTua ?? this.koinTua,
      peach: peach ?? this.peach,
      merah: merah ?? this.merah,
      merahSoft: merahSoft ?? this.merahSoft,
      merahBorder: merahBorder ?? this.merahBorder,
      biru: biru ?? this.biru,
      kuningSoft: kuningSoft ?? this.kuningSoft,
      kuningText: kuningText ?? this.kuningText,
      catatan: catatan ?? this.catatan,
      disabled: disabled ?? this.disabled,
      putih: putih ?? this.putih,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  VillageColors lerp(VillageColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return VillageColors(
      langit: mix(langit, other.langit),
      langitMuda: mix(langitMuda, other.langitMuda),
      kertas: mix(kertas, other.kertas),
      kartu: mix(kartu, other.kartu),
      ink: mix(ink, other.ink),
      ink2: mix(ink2, other.ink2),
      redup: mix(redup, other.redup),
      garis: mix(garis, other.garis),
      tileBorder: mix(tileBorder, other.tileBorder),
      track: mix(track, other.track),
      pink: mix(pink, other.pink),
      pinkSoft: mix(pinkSoft, other.pinkSoft),
      pinkText: mix(pinkText, other.pinkText),
      cta: mix(cta, other.cta),
      ctaEnd: mix(ctaEnd, other.ctaEnd),
      mint: mix(mint, other.mint),
      mintSoft: mix(mintSoft, other.mintSoft),
      mintText: mix(mintText, other.mintText),
      mintBorder: mix(mintBorder, other.mintBorder),
      koin: mix(koin, other.koin),
      koinTua: mix(koinTua, other.koinTua),
      peach: mix(peach, other.peach),
      merah: mix(merah, other.merah),
      merahSoft: mix(merahSoft, other.merahSoft),
      merahBorder: mix(merahBorder, other.merahBorder),
      biru: mix(biru, other.biru),
      kuningSoft: mix(kuningSoft, other.kuningSoft),
      kuningText: mix(kuningText, other.kuningText),
      catatan: mix(catatan, other.catatan),
      disabled: mix(disabled, other.disabled),
      putih: mix(putih, other.putih),
      shadow: mix(shadow, other.shadow),
    );
  }
}

/// Corner radii from the style guide.
abstract final class VillageRadius {
  static const double card = 22;
  static const double tile = 14;
  static const double note = 12;
  static const double pill = 999;
}

/// Nunito text style. Only weights 700, 800 and 900 are bundled in
/// assets/fonts, so [fontWeight] must be one of those.
///
/// Always build styles through this function instead of `copyWith` on a
/// theme style: google_fonts registers one family per weight, so changing
/// the weight with `copyWith` would fake-bold the wrong file.
TextStyle villageText({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w800,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  assert(
    fontWeight == FontWeight.w700 ||
        fontWeight == FontWeight.w800 ||
        fontWeight == FontWeight.w900,
    'Only Nunito 700/800/900 are bundled',
  );
  return GoogleFonts.nunito(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextTheme _villageTextTheme(Color ink) {
  // Material's default text theme uses 400/500 weights, which are not bundled;
  // lift every style to at least 700 before applying Nunito.
  final base = Typography.material2021().black;
  TextStyle lift(TextStyle? style) {
    final weight = style?.fontWeight ?? FontWeight.w400;
    return villageText(
      fontSize: style?.fontSize ?? 14,
      fontWeight: weight.value >= 900
          ? FontWeight.w900
          : weight.value >= 600
              ? FontWeight.w800
              : FontWeight.w700,
      color: ink,
      height: style?.height,
      letterSpacing: style?.letterSpacing,
    );
  }

  return TextTheme(
    displayLarge: lift(base.displayLarge),
    displayMedium: lift(base.displayMedium),
    displaySmall: lift(base.displaySmall),
    headlineLarge: lift(base.headlineLarge),
    headlineMedium: lift(base.headlineMedium),
    headlineSmall: lift(base.headlineSmall),
    titleLarge: lift(base.titleLarge),
    titleMedium: lift(base.titleMedium),
    titleSmall: lift(base.titleSmall),
    bodyLarge: lift(base.bodyLarge),
    bodyMedium: lift(base.bodyMedium),
    bodySmall: lift(base.bodySmall),
    labelLarge: lift(base.labelLarge),
    labelMedium: lift(base.labelMedium),
    labelSmall: lift(base.labelSmall),
  );
}

/// Builds the light tepira village theme (pastel, Nunito).
ThemeData buildVillageTheme() {
  const c = VillageColors.light;
  final textTheme = _villageTextTheme(c.ink);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.pink,
      primary: c.cta,
      onPrimary: c.putih,
      secondary: c.mint,
      error: c.merah,
      surface: c.kartu,
      onSurface: c.ink,
    ),
    scaffoldBackgroundColor: c.langit,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: c.langit,
      foregroundColor: c.ink,
      elevation: 0,
      titleTextStyle: villageText(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: c.ink,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.pink,
      linearTrackColor: c.track,
      borderRadius: BorderRadius.circular(VillageRadius.pill),
    ),
    extensions: const [VillageColors.light],
  );
}

final ThemeData tepiraTheme = buildVillageTheme();
