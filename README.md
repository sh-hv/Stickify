# Stickify

تطبيق iOS لصنع حزم ستيكرات واتساب (ثابتة ومتحركة) بشكل محلي بالكامل، بدون حساب وبدون إنترنت.

An iOS app for creating WhatsApp sticker packs (static and animated), fully local, no account, no internet.

## المزايا | Features

- حزم صور وحزم متحركة من فيديو أو GIF | Image packs and animated packs from video or GIF
- قص (مربع، 4:3، 3:4، 16:9، 9:16، أو مخصص) وتكبير وتحريك وإضافة نص | Crop (square, 4:3, 3:4, 16:9, 9:16, or freehand), zoom, move and add text
- حذف تلقائي للخلفية | Auto background removal
- معاينة حية للفيديو وشريط تحديد المقطع (حتى 10 ثواني) بدقة فريم | Live video preview and a trim bar (up to 10 s) with frame-level precision
- ضغط تلقائي ليناسب حدود واتساب (512×512، 15 فريم/ث، 100KB ثابت، 500KB متحرك) | Automatic compression to fit WhatsApp limits (512×512, 15 fps, 100 KB static, 500 KB animated)
- إيموجي واحد لكل ستيكر | One emoji per sticker
- نسخة احتياطية واسترجاع لكل الحزم بملف ZIP | Backup and restore all packs as a ZIP file
- عربي وإنجليزي، ومظهر فاتح وداكن وألوان | Arabic and English, light and dark themes, accent colors

## البناء | Build

لا يحتاج Xcode محلياً. البناء يتم على GitHub Actions.

No local Xcode needed. The build runs on GitHub Actions.

1. ارفع المشروع على فرع `main` | Push the project to the `main` branch
2. افتح **Actions** وانتظر انتهاء **Build IPA** | Open **Actions** and wait for **Build IPA** to finish
3. نزّل `Stickify.ipa` من **Releases** | Download `Stickify.ipa` from **Releases**
4. ثبّته عبر AltStore أو SideStore | Install it with AltStore or SideStore

الملف غير موقّع، والتوقيع يتم وقت التثبيت.

The IPA is unsigned; signing happens at install time.

## التخصيص | Customization

- `icon.png` في جذر المشروع: أيقونة التطبيق (1024×1024، بدون شفافية) | in the repo root: the app icon (1024×1024, opaque)
- `x-logo.png` و`github-logo.png` في جذر المشروع: لوغوات قسم الروابط (PNG شفاف بلون واحد) | in the repo root: logos for the links section (single-color transparent PNG)

## البنية | Structure

```
.github/workflows/build.yml   خطوات البناء | build steps
project.yml                   إعدادات المشروع | project config
Sources/                      كود التطبيق | app source
tools/icon.swift              مولّد الأيقونة الافتراضية | default icon generator
```

## المتطلبات | Requirements

iOS 16 أو أحدث | iOS 16 or later. واتساب مثبت لإضافة الحزم | WhatsApp installed to add packs.
