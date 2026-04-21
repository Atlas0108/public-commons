import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_trace.dart';

/// Loads Playfair Display + Lora files used across the app so the first paint
/// does not briefly use the platform fallback (FOUT).
///
/// Each distinct family + [FontWeight] + [FontStyle] may map to a separate font file.
Future<void> preloadAppGoogleFonts() async {
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w400, fontStyle: FontStyle.italic),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w500),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
      GoogleFonts.lora(fontWeight: FontWeight.w600),
    ]).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        commonsTrace('preloadAppGoogleFonts', 'timeout after 10s');
        return <void>[];
      },
    );
    commonsTrace('preloadAppGoogleFonts', 'done');
  } on Object catch (e) {
    commonsTrace('preloadAppGoogleFonts', 'failed (fonts may load later): $e');
  }
}
