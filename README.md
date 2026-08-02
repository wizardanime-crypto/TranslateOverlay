# TranslateOverlay

تويك iOS (Theos / Logos) يضيف زرًا عائمًا للترجمة داخل التطبيقات مع دعم OCR وعرض النص المترجم فوق لقطة الشاشة.

## الميزات

- ترجمة عناصر الواجهة الحالية (Labels / Buttons / TextFields / TextViews).
- OCR للصفحة الحالية ثم ترجمة كل سطر.
- لون تلقائي للنص المترجم حسب لون النص الأصلي في الصورة (لكل سطر بشكل مستقل).
- لون يدوي عبر شريط منزلق:
	- منزلق الدرجة اللونية Hue.
	- منزلق التشبع Saturation.
	- أيقونة معاينة صغيرة للون المختار.
- منزلق تعتيم خلفية النص المترجم.
- تكبير/تصغير حجم نص OCR.
- تغيير لغة المصدر/الهدف.
- زر عائم قابل للسحب مع Snap للحواف.

## ملفات المشروع

- Tweak.xm: منطق الأداة بالكامل.
- TranslateOverlay.plist: فلتر التحميل.
- Makefile: إعدادات بناء Theos.
- control: بيانات الحزمة.

## البناء

### متطلبات

- Theos متوفر في: /workspaces/theos
- SDK iPhoneOS16.5 موجود داخل Theos

### أوامر البناء

```bash
cd /workspaces/TranslateOverlay
THEOS=/workspaces/theos make clean package
```

### تجهيز ملفات النشر

```bash
cd /workspaces/TranslateOverlay
cp .theos/_/Library/MobileSubstrate/DynamicLibraries/TranslateOverlay.dylib packages/TranslateOverlay.dylib
cp .theos/_/Library/MobileSubstrate/DynamicLibraries/TranslateOverlay.plist packages/TranslateOverlay.plist
cd packages
zip -q -j TranslateOverlay.dylib.zip TranslateOverlay.dylib
zip -q -j TranslateOverlay_injection_bundle.zip TranslateOverlay.dylib TranslateOverlay.plist
```

### المخرجات

- packages/com.wizardanime.translateoverlay_1.0.1_iphoneos-arm64.deb
- packages/TranslateOverlay.dylib
- packages/TranslateOverlay.dylib.zip
- packages/TranslateOverlay_injection_bundle.zip