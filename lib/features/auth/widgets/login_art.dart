// Artwork from docs/design/screens/Login.dc.html. Colors here belong to the
// illustrations and the Google brand mark, not to the UI theme.

/// tepira village logo (island with house and tree), 64x64 viewBox.
const String kVillageLogoSvg = '''
<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
<path d="M4 34.81 9.35 27.46 23.35 22.92 40.65 22.92 54.65 27.46 60 34.81 60 43.31 54.65 50.66 40.65 55.2 23.35 55.2 9.35 50.66 4 43.31z" fill="#cc922c"/>
<path d="M60 34.81 54.65 42.16 40.65 46.7 23.35 46.7 9.35 42.16 4 34.81 9.35 27.46 23.35 22.92 40.65 22.92 54.65 27.46z" fill="#f8d77f"/>
<path d="M56.64 34.41 51.93 40.88 39.61 44.87 24.39 44.87 12.07 40.88 7.36 34.41 12.07 27.94 24.39 23.95 39.61 23.95 51.93 27.94z" fill="#6cc8ad"/>
<path d="M50 17.81 50 26.71" stroke="#5a4a5e" stroke-width="2.6" stroke-linecap="round"/>
<path d="M50 13.81 56.2 23.81 43.8 23.81z" fill="#37957c"/>
<path d="M50 8.81 54.8 17.81 45.2 17.81z" fill="#4fb396"/>
<path d="M28 41.81 28 29.31 42.5 25.51 42.5 38.01z" fill="#ffd3e4"/>
<path d="M11.5 41.81 11.5 29.31 19.75 19.81 28 29.31 28 41.81z" fill="#fffaf7"/>
<path d="M18.59 20.11 35.6 15.66 43.06 24.24 45.26 24.94 28.25 29.4 26.05 28.7z" fill="#ff7eb3"/>
<path d="M8.93 29.4 11.13 28.7 18.59 20.11" fill="none" stroke="#ff7eb3" stroke-width="2.8" stroke-linecap="round"/>
<path d="M17.25 42.21v-5.3a2.5 2.5 0 0 1 5 0v5.3z" fill="#5a4a5e"/>
</svg>
''';

/// Sample plot scene for the "Contoh kavling" card, 326x120 viewBox.
const String kSamplePlotSvg = '''
<svg viewBox="0 0 326 120" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#d8effa"/><stop offset="1" stop-color="#bfe3f3"/>
</linearGradient></defs>
<rect width="326" height="120" fill="url(#sky)"/>
<ellipse cx="163" cy="96" rx="150" ry="26" fill="#7fcfe6"/>
<ellipse cx="163" cy="88" rx="118" ry="20" fill="#f3c35b"/>
<ellipse cx="163" cy="82" rx="104" ry="16" fill="#6cc8ad"/>
<rect x="70" y="74" width="30" height="6" rx="1" fill="#cdbfc9"/>
<rect x="120" y="58" width="34" height="24" fill="#fffaf7"/>
<rect x="128" y="68" width="8" height="14" fill="#f3c35b"/>
<rect x="180" y="56" width="36" height="26" fill="#fffaf7"/>
<path d="M176 58 L198 38 L220 58 Z" fill="#ff7eb3"/>
<rect x="192" y="68" width="10" height="14" fill="#5a4a5e"/>
<rect x="204" y="62" width="6" height="6" fill="#f3c35b"/>
<rect x="248" y="68" width="4" height="14" fill="#5a4a5e"/>
<path d="M250 42 L262 68 L238 68 Z" fill="#37957c"/>
<path d="M250 50 L260 70 L240 70 Z" fill="#4fb396"/>
<rect x="34" y="70" width="22" height="12" rx="3" fill="#cc922c"/>
<rect x="34" y="66" width="22" height="7" rx="3" fill="#e3a93c"/>
</svg>
''';

/// Google "G" mark, 24x24 viewBox.
const String kGoogleMarkSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
<path fill="#4285F4" d="M21.6 12.2c0-.7-.1-1.4-.2-2H12v3.9h5.4a4.6 4.6 0 0 1-2 3v2.5h3.2c1.9-1.7 3-4.3 3-7.4z"/>
<path fill="#34A853" d="M12 22c2.7 0 5-.9 6.6-2.4l-3.2-2.5c-.9.6-2 1-3.4 1-2.6 0-4.8-1.8-5.6-4.1H3.1v2.6A10 10 0 0 0 12 22z"/>
<path fill="#FBBC05" d="M6.4 14a6 6 0 0 1 0-3.9V7.5H3.1a10 10 0 0 0 0 9z"/>
<path fill="#EA4335" d="M12 6c1.5 0 2.8.5 3.8 1.5l2.8-2.8A10 10 0 0 0 3.1 7.5L6.4 10c.8-2.3 3-4 5.6-4z"/>
</svg>
''';
