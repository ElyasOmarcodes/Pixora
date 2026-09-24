<div align="center">

<img src="assets/branding/icon.png" width="112" alt="Pixora" />

# Pixora

**A layered photo & graphic editor for Android, iOS, Windows, macOS and Linux — built with Flutter/Dart.**

**د ګرځنده او کمپيوټر لپاره د لايرونو لرونکی انځور او ګرافيک ايډيټر — په Flutter/Dart جوړ.**

</div>

---

## پښتو

### دا څه دي؟
پيکسورا يو هر اړخيز فوټو ايډيټر دی چې موخه يې د PixelLab او PicsArt نه ښه UX او د فوټوشاپ په څېر ازادي ده. کوډ يو ځل په Dart کې ليکل کېږي او د Android، iOS، Windows، macOS، Linux او Web لپاره خروجي ورکوي.

### په لومړۍ نسخه کې څه شته
- **سپلش پاڼه** — نرمه متحرکه لوګو.
- **د پروژو پاڼه** — چټک پيل (مربع، سټوري، A4، بندانځور …)، انځور پرانيستل، خپله اندازه، وروستۍ پروژې د بندانځور سره؛ نوم بدلول، دوه‌ګونی او ړنګول.
- **ايډيټر**
  - متن (پښتو/دري/عربي په خپله ښي‌ته‌کيڼ)، انځور او ۷ ډوله شکلونه.
  - لايرونه: ځای بدلول (drag)، پټول، قلف، نوم بدلول، کاپي، ړنګول.
  - په ګوتو يا موږک: خوځول، لويول، څرخول؛ هوښيار لارښوونکي (snap) منځ او غاړو ته.
  - رنګ او ګراډينټ، کرښه (stroke)، سيوری او ځلا، روڼتيا او ۱۶ د ګډون (blend) حالتونه.
  - تنظيمونه: رڼا، کنټراسټ، د رنګ ژوروالی، رنګ بدلون، تودوخه، تتوالی … او ۹ فلټرونه — ټول **غير ويجاړونکي** (non‑destructive).
  - بېرته/بيا کول (Undo/Redo) د هر کار لپاره، په خپله ساتنه (autosave).
  - خروجي PNG/JPG په 0.5× / 1× / 2× — ساتل يا شريکول.
  - د کمپيوټر لپاره کيبورډ شارټکټونه (Ctrl+Z، Ctrl+D، Delete، غشي …).
- **تنظيمات** — ژبه، روښانه/تياره بڼه، اصلي رنګ، autosave، snap، د خروجي بڼه.
- **ژبې:** پښتو، دري/فارسي، عربي، اردو، انګليسي، اسپانيايي، فرانسوي، ترکي.

### UX څنګه له PixelLab ښه دی
- **شرايطي لاندې تول‌بار:** يوازې هغه وسايل ښکاري چې همدا اوس کار ورکوي (متن ټاکل شوی وي نو د متن وسايل، انځور وي نو تنظيم او فلټر).
- د متن زياتول يو ګام دی: «متن» ← وليکه ← بشپړ.
- لايرونه د کانوس پر سر يو نرم پټېدونکی پينل دی؛ په لوی سکرين (ټابليټ/کمپيوټر) کې تل خلاص.
- هر سلايډر ژوندی ښکاري خو د ګوتې تر پورته کولو پورې يو Undo ګام جوړوي.

### جوړول
```bash
flutter pub get
flutter run                 # په وصل شوې وسيله
flutter test                # ازموينې
```

### ريليز
يو ټګ پوش کړئ (لکه `v0.2.0`) يا په GitHub Actions کې **Release** په لاس وچلوئ. ټول پلاتفورمونه جوړېږي، کمپرس کېږي او په Releases کې خپرېږي.

---

## English

### Highlights
- **Immutable document model + snapshot undo/redo.** Every edit is a pure `PixDocument → PixDocument` function, so undo can never get out of sync.
- **One renderer** for the canvas, thumbnails and export — what you see is exactly what you export.
- **Non-destructive effects** (adjustments, filters, shadow/glow) described as data and implemented in a pluggable `EffectRegistry`.
- **Action API** — every editor command is a named, JSON-schema-described `EditorAction`. It is the foundation for macros, scripting and the planned in-app **AI agent** (`lib/ai/agent_bridge.dart`).
- **Pluggable tools** (`EditorTool`) — transform today; brush, eraser, selection and crop plug in without touching the canvas.
- **Platform services** chosen at compile time (conditional imports) and at runtime (`PlatformInfo`): files vs. browser storage, share sheet vs. save dialog.
- **Adaptive UI** — bottom dock + floating layers on phones, tool rail + side panel on tablets/desktops, full RTL support.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and the roadmap.

### Develop
```bash
flutter pub get
flutter analyze && flutter test
flutter run -d windows   # or android, ios, macos, linux, chrome
```

Regenerate app icons after changing the logo:
```bash
flutter test tool/render_icon_test.dart   # renders assets/branding/icon.png
dart run flutter_launcher_icons
```

### Release builds (GitHub Actions)
`.github/workflows/release.yml` runs on a `v*` tag (or manually) and publishes a GitHub Release with:

| Platform | Output | Size tricks |
|---|---|---|
| Android | per-ABI APKs + AAB | R8 minify, resource shrinking, `--split-per-abi`, obfuscation, icon tree-shaking |
| Windows | `.zip` | 7-Zip `-mx=9` Deflate64 |
| macOS | `.dmg` | LZMA (`ULMO`) disk image |
| Linux | `.tar.xz` | `xz -9e` |
| iOS | unsigned `.ipa` | `zip -9` (sign before installing) |
| Web | `.zip` | `zip -9` |

Optional Android signing secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

### License notes
Bundled font: [Vazirmatn](https://github.com/rastikerdar/vazirmatn) (SIL Open Font License, see `assets/fonts/Vazirmatn-OFL.txt`).
