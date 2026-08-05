#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#if __has_include(<NaturalLanguage/NaturalLanguage.h>)
#import <NaturalLanguage/NaturalLanguage.h>
#endif
#if __has_include(<Vision/Vision.h>)
#import <Vision/Vision.h>
#endif

static NSString * const kTOSourceLanguageKey = @"to_source_language";
static NSString * const kTOTargetLanguageKey = @"to_target_language";
static NSString * const kTOButtonCenterXKey = @"to_button_center_x";
static NSString * const kTOButtonCenterYKey = @"to_button_center_y";
static NSString * const kTOTranslationCacheKey = @"to_translation_cache";

static NSString * const kTOOCRTextScaleKey = @"to_ocr_text_scale";
static NSString * const kTOOCRTextAutoColorEnabledKey = @"to_ocr_text_auto_color_enabled";
static NSString * const kTOOCRBackgroundAutoColorEnabledKey = @"to_ocr_background_auto_color_enabled";
static NSString * const kTOOCRCenterTextEnabledKey = @"to_ocr_center_text_enabled";
static NSString * const kTOOCREditAfterTranslateEnabledKey = @"to_ocr_edit_after_translate_enabled";
static NSString * const kTOMangaTranslationModeEnabledKey = @"to_manga_translation_mode_enabled";
static NSString * const kTOTranslationTapModeKey = @"to_translation_tap_mode";
static NSString * const kTOOCRManualHueKey = @"to_ocr_manual_hue";
static NSString * const kTOOCRManualSaturationKey = @"to_ocr_manual_saturation";
static NSString * const kTOOCRManualBrightnessKey = @"to_ocr_manual_brightness";
static NSString * const kTOOCRBackgroundAlphaKey = @"to_ocr_background_alpha";
static NSString * const kTOOCRBackgroundHueKey = @"to_ocr_background_hue";
static NSString * const kTOOCRBackgroundSaturationKey = @"to_ocr_background_saturation";
static NSString * const kTOOCRBackgroundBrightnessKey = @"to_ocr_background_brightness";
static NSString * const kTOLiveTouchResumeDelayKey = @"to_live_touch_resume_delay";

@class TOTranslationManager;

static BOOL TOShouldTranslateText(NSString *text) {
    if (text.length == 0) return NO;
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trim.length > 0 && trim.length <= 2500;
}

typedef NS_ENUM(NSInteger, TOTranslationTapMode) {
    TOTranslationTapModeNormal = 0,
    TOTranslationTapModeManga = 1,
    TOTranslationTapModeLive = 2
};

static volatile NSInteger gTOTranslationTapModeSnapshot = TOTranslationTapModeNormal;
static volatile BOOL gTOLiveTranslateEnabledSnapshot = NO;

static void TOUpdateTranslationModeSnapshot(NSInteger mode, BOOL liveEnabled) {
    gTOTranslationTapModeSnapshot = mode;
    gTOLiveTranslateEnabledSnapshot = liveEnabled;
}

static BOOL TOIsLiveModeSessionActiveFast(void) {
    return (gTOTranslationTapModeSnapshot == TOTranslationTapModeLive) && gTOLiveTranslateEnabledSnapshot;
}

static NSString *TOPrepareOCRMultilineText(NSString *inputText) {
    if (inputText.length == 0) return @"";

    NSString *normalized = [[inputText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *paragraphs = [normalized componentsSeparatedByString:@"\n\n"];
    NSMutableArray<NSString *> *cleanParagraphs = [NSMutableArray arrayWithCapacity:paragraphs.count];

    for (NSString *paragraph in paragraphs) {
        NSString *lineMerged = [[paragraph stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (lineMerged.length > 0) [cleanParagraphs addObject:lineMerged];
    }

    if (cleanParagraphs.count == 0) {
        return [inputText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return [cleanParagraphs componentsJoinedByString:@"\n\n"];
}

static NSString *TOCollapseWhitespace(NSString *text) {
    if (text.length == 0) return @"";
    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *words = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString *part in parts) {
        if (part.length > 0) [words addObject:part];
    }
    return [words componentsJoinedByString:@" "];
}

static NSString *TOPrepareLiveOCRSourceText(NSString *text) {
    if (text.length == 0) return @"";

    NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                            stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"-\n" withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"…" withString:@"..."];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"“" withString:@"\""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"”" withString:@"\""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"’" withString:@"'"];
    normalized = TOCollapseWhitespace(normalized);
    normalized = [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    while ([normalized containsString:@" ,"]) normalized = [normalized stringByReplacingOccurrencesOfString:@" ," withString:@","];
    while ([normalized containsString:@" ."]) normalized = [normalized stringByReplacingOccurrencesOfString:@" ." withString:@"."];
    while ([normalized containsString:@" !"]) normalized = [normalized stringByReplacingOccurrencesOfString:@" !" withString:@"!"];
    while ([normalized containsString:@" ?"]) normalized = [normalized stringByReplacingOccurrencesOfString:@" ?" withString:@"?"];

    return normalized;
}

static NSString *TONormalizedLocaleIdentifier(NSString *languageCode) {
    if (languageCode.length == 0) return @"en";
    NSString *code = [languageCode stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([code caseInsensitiveCompare:@"zh-CN"] == NSOrderedSame) return @"zh-Hans";
    if ([code caseInsensitiveCompare:@"zh-TW"] == NSOrderedSame) return @"zh-Hant";
    return code;
}

static const void *kTOTranslateGuardKey = &kTOTranslateGuardKey;
static const void *kTOTranslateLastTextKey = &kTOTranslateLastTextKey;
static const void *kTOTranslateLastTargetKey = &kTOTranslateLastTargetKey;
static const void *kTOTranslateLastAttemptTimeKey = &kTOTranslateLastAttemptTimeKey;
static IMP kTOUIListSetTextOriginalIMP = NULL;
static IMP kTOUIListSetSecondaryTextOriginalIMP = NULL;
static IMP kTOUIListSetAttributedTextOriginalIMP = NULL;
static IMP kTOUIListSetAttributedSecondaryTextOriginalIMP = NULL;

static BOOL TOIsUITranslationPipelineEnabled(void) {
    // Keep hook-based UI translation exclusive to normal mode.
    // Live mode uses OCR overlay path to avoid scroll jank from frequent label mutations.
    return (gTOTranslationTapModeSnapshot == TOTranslationTapModeNormal);
}

static NSAttributedString *TORebuildAttributedString(NSAttributedString *source, NSString *translated) {
    if (translated.length == 0) return source;
    NSDictionary *attrs = nil;
    if (source.length > 0) attrs = [source attributesAtIndex:0 effectiveRange:NULL];
    return [[NSAttributedString alloc] initWithString:translated attributes:attrs];
}

static void TOTranslateAndApplyTextToObject(id object, NSString *text, void (^applyBlock)(NSString *translated)) {
    if (!object || !applyBlock || !TOShouldTranslateText(text)) return;
    if (!TOIsUITranslationPipelineEnabled()) return;

    Class managerClass = NSClassFromString(@"TOTranslationManager");
    if (!managerClass || ![managerClass respondsToSelector:@selector(shared)]) return;
    id m = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(shared));
    NSString *target = @"ar";
    if ([m respondsToSelector:@selector(targetLanguage)]) {
        NSString *dynamicTarget = ((id (*)(id, SEL))objc_msgSend)(m, @selector(targetLanguage));
        if ([dynamicTarget isKindOfClass:[NSString class]] && dynamicTarget.length > 0) {
            target = dynamicTarget;
        }
    }
    NSString *lastText = objc_getAssociatedObject(object, kTOTranslateLastTextKey);
    NSString *lastTarget = objc_getAssociatedObject(object, kTOTranslateLastTargetKey);
    NSNumber *lastTime = objc_getAssociatedObject(object, kTOTranslateLastAttemptTimeKey);
    NSTimeInterval now = CACurrentMediaTime();
    if ([lastText isEqualToString:text] && [lastTarget isEqualToString:target]) {
        NSTimeInterval elapsed = lastTime ? (now - lastTime.doubleValue) : DBL_MAX;
        if (elapsed < 1.25) return;
    }

    objc_setAssociatedObject(object, kTOTranslateLastTextKey, text, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(object, kTOTranslateLastTargetKey, target, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(object, kTOTranslateLastAttemptTimeKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak id weakObject = object;
    if (![m respondsToSelector:@selector(translateText:completion:)]) return;
    ((void (*)(id, SEL, NSString *, id))objc_msgSend)(m, @selector(translateText:completion:), text, ^(NSString *translated) {
        id strongObject = weakObject;
        if (!strongObject || translated.length == 0) return;
        // Ignore fallback/no-op responses that equal the original source text to avoid visual toggling.
        if ([translated isEqualToString:text]) return;
        objc_setAssociatedObject(strongObject, kTOTranslateGuardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        applyBlock(translated);
        objc_setAssociatedObject(strongObject, kTOTranslateGuardKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static void TOTranslateAndApplyAttributedTextToObject(id object, NSAttributedString *attributedText, void (^applyBlock)(NSAttributedString *translated)) {
    if (!object || !applyBlock || attributedText.length == 0) return;
    if (!TOIsUITranslationPipelineEnabled()) return;
    NSString *raw = attributedText.string ?: @"";
    if (!TOShouldTranslateText(raw)) return;

    TOTranslateAndApplyTextToObject(object, raw, ^(NSString *translated) {
        NSAttributedString *rebuilt = TORebuildAttributedString(attributedText, translated);
        if (rebuilt.length > 0) applyBlock(rebuilt);
    });
}

static void TO_UIListContentConfiguration_setText(id self, SEL _cmd, NSString *text) {
    if (!kTOUIListSetTextOriginalIMP) return;

    ((void (*)(id, SEL, NSString *))kTOUIListSetTextOriginalIMP)(self, _cmd, text);

    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) return;
    TOTranslateAndApplyTextToObject(self, text, ^(NSString *translated) {
        ((void (*)(id, SEL, NSString *))kTOUIListSetTextOriginalIMP)(self, @selector(setText:), translated);
    });
}

static void TO_UIListContentConfiguration_setSecondaryText(id self, SEL _cmd, NSString *text) {
    if (!kTOUIListSetSecondaryTextOriginalIMP) return;

    ((void (*)(id, SEL, NSString *))kTOUIListSetSecondaryTextOriginalIMP)(self, _cmd, text);

    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) return;
    TOTranslateAndApplyTextToObject(self, text, ^(NSString *translated) {
        ((void (*)(id, SEL, NSString *))kTOUIListSetSecondaryTextOriginalIMP)(self, @selector(setSecondaryText:), translated);
    });
}

static void TO_UIListContentConfiguration_setAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    if (!kTOUIListSetAttributedTextOriginalIMP) return;

    ((void (*)(id, SEL, NSAttributedString *))kTOUIListSetAttributedTextOriginalIMP)(self, _cmd, text);

    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) return;
    TOTranslateAndApplyAttributedTextToObject(self, text, ^(NSAttributedString *translated) {
        ((void (*)(id, SEL, NSAttributedString *))kTOUIListSetAttributedTextOriginalIMP)(self, @selector(setAttributedText:), translated);
    });
}

static void TO_UIListContentConfiguration_setAttributedSecondaryText(id self, SEL _cmd, NSAttributedString *text) {
    if (!kTOUIListSetAttributedSecondaryTextOriginalIMP) return;

    ((void (*)(id, SEL, NSAttributedString *))kTOUIListSetAttributedSecondaryTextOriginalIMP)(self, _cmd, text);

    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) return;
    TOTranslateAndApplyAttributedTextToObject(self, text, ^(NSAttributedString *translated) {
        ((void (*)(id, SEL, NSAttributedString *))kTOUIListSetAttributedSecondaryTextOriginalIMP)(self, @selector(setAttributedSecondaryText:), translated);
    });
}

static void TOInstallUIListContentConfigurationHook(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"UIListContentConfiguration");
        if (!cls) return;
        Method method = class_getInstanceMethod(cls, @selector(setText:));
        if (!method) return;
        kTOUIListSetTextOriginalIMP = method_getImplementation(method);
        method_setImplementation(method, (IMP)TO_UIListContentConfiguration_setText);

        Method secondaryMethod = class_getInstanceMethod(cls, @selector(setSecondaryText:));
        if (secondaryMethod) {
            kTOUIListSetSecondaryTextOriginalIMP = method_getImplementation(secondaryMethod);
            method_setImplementation(secondaryMethod, (IMP)TO_UIListContentConfiguration_setSecondaryText);
        }

        Method attributedMethod = class_getInstanceMethod(cls, @selector(setAttributedText:));
        if (attributedMethod) {
            kTOUIListSetAttributedTextOriginalIMP = method_getImplementation(attributedMethod);
            method_setImplementation(attributedMethod, (IMP)TO_UIListContentConfiguration_setAttributedText);
        }

        Method attributedSecondaryMethod = class_getInstanceMethod(cls, @selector(setAttributedSecondaryText:));
        if (attributedSecondaryMethod) {
            kTOUIListSetAttributedSecondaryTextOriginalIMP = method_getImplementation(attributedSecondaryMethod);
            method_setImplementation(attributedSecondaryMethod, (IMP)TO_UIListContentConfiguration_setAttributedSecondaryText);
        }
    });
}

static NSString *TOBaseLanguageCode(NSString *languageCode) {
    NSString *norm = TONormalizedLocaleIdentifier(languageCode);
    NSArray<NSString *> *parts = [norm componentsSeparatedByString:@"-"];
    return parts.firstObject ?: norm;
}

static NSString *TODisplayLanguageName(NSString *languageCode, NSString *displayLanguageCode, NSString *fallback) {
    if (languageCode.length == 0) return fallback ?: @"";
    if ([languageCode isEqualToString:@"auto"]) return fallback ?: @"auto";

    NSString *displayLocaleID = TONormalizedLocaleIdentifier(displayLanguageCode);
    NSLocale *displayLocale = [NSLocale localeWithLocaleIdentifier:displayLocaleID.length > 0 ? displayLocaleID : @"en"];
    NSString *baseCode = TOBaseLanguageCode(languageCode);
    NSString *name = [displayLocale localizedStringForLanguageCode:baseCode];
    if (name.length == 0) {
        NSLocale *enLocale = [NSLocale localeWithLocaleIdentifier:@"en"];
        name = [enLocale localizedStringForLanguageCode:baseCode];
    }
    return name.length > 0 ? name : (fallback ?: languageCode);
}

static UIWindow *TOActiveWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive && ws.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *w in ws.windows) if (w.isKeyWindow) return w;
            for (UIWindow *w in ws.windows) if (!w.hidden && w.alpha > 0.01) return w;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (app.keyWindow) return app.keyWindow;
#pragma clang diagnostic pop
    return app.windows.firstObject;
}

static NSArray<UIWindow *> *TOVisibleWindows(void) {
    UIApplication *app = UIApplication.sharedApplication;
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive && ws.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *w in ws.windows) {
                if (!w || w.hidden || w.alpha <= 0.01) continue;
                if (![windows containsObject:w]) [windows addObject:w];
            }
        }
    }

    for (UIWindow *w in app.windows) {
        if (!w || w.hidden || w.alpha <= 0.01) continue;
        if (![windows containsObject:w]) [windows addObject:w];
    }

    UIWindow *active = TOActiveWindow();
    if (active && ![windows containsObject:active]) [windows addObject:active];
    return windows;
}

static UIViewController *TOTopViewController(void) {
    UIWindow *window = TOActiveWindow();
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        return nav.visibleViewController ?: nav.topViewController ?: vc;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)vc;
        return tab.selectedViewController ?: vc;
    }
    return vc;
}

static BOOL TOGetRGBComponents(UIColor *color, CGFloat *r, CGFloat *g, CGFloat *b) {
    if (!color) return NO;

    CGFloat rr = 0, gg = 0, bb = 0, aa = 0;
    if ([color getRed:&rr green:&gg blue:&bb alpha:&aa]) {
        if (r) *r = rr;
        if (g) *g = gg;
        if (b) *b = bb;
        return YES;
    }

    CGFloat white = 0;
    if ([color getWhite:&white alpha:&aa]) {
        if (r) *r = white;
        if (g) *g = white;
        if (b) *b = white;
        return YES;
    }

    return NO;
}

static CGFloat TOColorDistance(CGFloat r1, CGFloat g1, CGFloat b1, CGFloat r2, CGFloat g2, CGFloat b2) {
    CGFloat dr = r1 - r2;
    CGFloat dg = g1 - g2;
    CGFloat db = b1 - b2;
    return sqrt((dr * dr) + (dg * dg) + (db * db));
}

@interface TOTranslationManager : NSObject
@property (nonatomic, copy) NSString *sourceLanguage;
@property (nonatomic, copy) NSString *targetLanguage;
@property (nonatomic, strong) NSCache<NSString *, NSString *> *cache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *persistentCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightTranslationKeys;

@property (nonatomic, assign) CGFloat ocrTextScale;
@property (nonatomic, assign) BOOL ocrAutoColorEnabled;
@property (nonatomic, assign) BOOL ocrBackgroundAutoColorEnabled;
@property (nonatomic, assign) BOOL ocrCenterTextEnabled;
@property (nonatomic, assign) BOOL ocrEditAfterTranslateEnabled;
@property (nonatomic, assign) BOOL mangaTranslationModeEnabled;
@property (nonatomic, assign) NSInteger translationTapMode;
@property (nonatomic, assign) CGFloat ocrManualHue;
@property (nonatomic, assign) CGFloat ocrManualSaturation;
@property (nonatomic, assign) CGFloat ocrManualBrightness;
@property (nonatomic, assign) CGFloat ocrBackgroundAlpha;
@property (nonatomic, assign) CGFloat ocrBackgroundHue;
@property (nonatomic, assign) CGFloat ocrBackgroundSaturation;
@property (nonatomic, assign) CGFloat ocrBackgroundBrightness;
@property (nonatomic, assign) NSTimeInterval liveTouchResumeDelay;

+ (instancetype)shared;
- (void)loadSettings;
- (void)saveSettings;
- (UIColor *)ocrManualUIColor;
- (UIColor *)ocrBackgroundUIColor;
- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated))completion;
- (void)translateOCRText:(NSString *)text completion:(void (^)(NSString *translated))completion;
@end

@implementation TOTranslationManager

+ (instancetype)shared {
    static TOTranslationManager *m;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        m = [TOTranslationManager new];
        m.cache = [NSCache new];
        m.persistentCache = [NSMutableDictionary new];
        m.inFlightTranslationKeys = [NSMutableSet new];
        [m loadSettings];
    });
    return m;
}

- (void)loadSettings {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    self.sourceLanguage = [d stringForKey:kTOSourceLanguageKey] ?: @"auto";
    self.targetLanguage = [d stringForKey:kTOTargetLanguageKey] ?: @"ar";

    NSDictionary *stored = [d dictionaryForKey:kTOTranslationCacheKey];
    if ([stored isKindOfClass:[NSDictionary class]]) {
        @synchronized (self) {
            [self.persistentCache removeAllObjects];
            [self.persistentCache addEntriesFromDictionary:stored];
        }
    }

    CGFloat scale = [d doubleForKey:kTOOCRTextScaleKey];
    self.ocrTextScale = (scale >= 0.01 && scale <= 2.0) ? scale : 1.0;

    NSNumber *autoColor = [d objectForKey:kTOOCRTextAutoColorEnabledKey];
    self.ocrAutoColorEnabled = autoColor ? [autoColor boolValue] : YES;

    NSNumber *autoBackgroundColor = [d objectForKey:kTOOCRBackgroundAutoColorEnabledKey];
    self.ocrBackgroundAutoColorEnabled = autoBackgroundColor ? [autoBackgroundColor boolValue] : NO;

    NSNumber *centerText = [d objectForKey:kTOOCRCenterTextEnabledKey];
    self.ocrCenterTextEnabled = centerText ? [centerText boolValue] : YES;

    NSNumber *editAfterTranslate = [d objectForKey:kTOOCREditAfterTranslateEnabledKey];
    self.ocrEditAfterTranslateEnabled = editAfterTranslate ? [editAfterTranslate boolValue] : YES;

    NSNumber *mangaMode = [d objectForKey:kTOMangaTranslationModeEnabledKey];
    self.mangaTranslationModeEnabled = mangaMode ? [mangaMode boolValue] : NO;

    NSInteger tapMode = [d integerForKey:kTOTranslationTapModeKey];
    if (tapMode < TOTranslationTapModeNormal || tapMode > TOTranslationTapModeLive) tapMode = TOTranslationTapModeNormal;
    self.translationTapMode = tapMode;
    TOUpdateTranslationModeSnapshot(self.translationTapMode, NO);

    CGFloat hue = [d doubleForKey:kTOOCRManualHueKey];
    CGFloat sat = [d doubleForKey:kTOOCRManualSaturationKey];
    CGFloat bri = [d doubleForKey:kTOOCRManualBrightnessKey];
    self.ocrManualHue = (hue >= 0.0 && hue <= 1.0) ? hue : 0.14;
    self.ocrManualSaturation = (sat >= 0.0 && sat <= 1.0) ? sat : 0.75;
    self.ocrManualBrightness = (bri >= 0.0 && bri <= 1.0) ? bri : 1.0;

    CGFloat bg = [d doubleForKey:kTOOCRBackgroundAlphaKey];
    self.ocrBackgroundAlpha = (bg >= 0.0 && bg <= 1.0) ? bg : 0.65;

    CGFloat bgHue = [d doubleForKey:kTOOCRBackgroundHueKey];
    CGFloat bgSat = [d doubleForKey:kTOOCRBackgroundSaturationKey];
    CGFloat bgBri = [d doubleForKey:kTOOCRBackgroundBrightnessKey];
    self.ocrBackgroundHue = (bgHue >= 0.0 && bgHue <= 1.0) ? bgHue : 0.0;
    self.ocrBackgroundSaturation = (bgSat >= 0.0 && bgSat <= 1.0) ? bgSat : 0.0;
    self.ocrBackgroundBrightness = (bgBri >= 0.0 && bgBri <= 1.0) ? bgBri : 0.28;

    CGFloat resumeDelay = [d doubleForKey:kTOLiveTouchResumeDelayKey];
    self.liveTouchResumeDelay = (resumeDelay >= 0.0 && resumeDelay <= 1.2) ? resumeDelay : 0.20;
}

- (void)saveSettings {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:self.sourceLanguage ?: @"auto" forKey:kTOSourceLanguageKey];
    [d setObject:self.targetLanguage ?: @"ar" forKey:kTOTargetLanguageKey];
    NSDictionary *cacheSnapshot = nil;
    @synchronized (self) {
        cacheSnapshot = [self.persistentCache copy] ?: @{};
    }
    [d setObject:cacheSnapshot forKey:kTOTranslationCacheKey];

    [d setDouble:self.ocrTextScale forKey:kTOOCRTextScaleKey];
    [d setBool:self.ocrAutoColorEnabled forKey:kTOOCRTextAutoColorEnabledKey];
    [d setBool:self.ocrBackgroundAutoColorEnabled forKey:kTOOCRBackgroundAutoColorEnabledKey];
    [d setBool:self.ocrCenterTextEnabled forKey:kTOOCRCenterTextEnabledKey];
    [d setBool:self.ocrEditAfterTranslateEnabled forKey:kTOOCREditAfterTranslateEnabledKey];
    [d setBool:self.mangaTranslationModeEnabled forKey:kTOMangaTranslationModeEnabledKey];
    [d setInteger:self.translationTapMode forKey:kTOTranslationTapModeKey];
    [d setDouble:MIN(MAX(self.ocrManualHue, 0.0), 1.0) forKey:kTOOCRManualHueKey];
    [d setDouble:MIN(MAX(self.ocrManualSaturation, 0.0), 1.0) forKey:kTOOCRManualSaturationKey];
    [d setDouble:MIN(MAX(self.ocrManualBrightness, 0.0), 1.0) forKey:kTOOCRManualBrightnessKey];
    [d setDouble:MIN(MAX(self.ocrBackgroundAlpha, 0.0), 1.0) forKey:kTOOCRBackgroundAlphaKey];
    [d setDouble:MIN(MAX(self.ocrBackgroundHue, 0.0), 1.0) forKey:kTOOCRBackgroundHueKey];
    [d setDouble:MIN(MAX(self.ocrBackgroundSaturation, 0.0), 1.0) forKey:kTOOCRBackgroundSaturationKey];
    [d setDouble:MIN(MAX(self.ocrBackgroundBrightness, 0.0), 1.0) forKey:kTOOCRBackgroundBrightnessKey];
    [d setDouble:MIN(MAX(self.liveTouchResumeDelay, 0.0), 1.2) forKey:kTOLiveTouchResumeDelayKey];
    [d synchronize];
}

- (UIColor *)ocrManualUIColor {
    CGFloat h = MIN(MAX(self.ocrManualHue, 0.0), 1.0);
    CGFloat s = MIN(MAX(self.ocrManualSaturation, 0.0), 1.0);
    CGFloat b = MIN(MAX(self.ocrManualBrightness, 0.0), 1.0);
    return [UIColor colorWithHue:h saturation:s brightness:b alpha:1.0];
}

- (UIColor *)ocrBackgroundUIColor {
    CGFloat h = MIN(MAX(self.ocrBackgroundHue, 0.0), 1.0);
    CGFloat s = MIN(MAX(self.ocrBackgroundSaturation, 0.0), 1.0);
    CGFloat b = MIN(MAX(self.ocrBackgroundBrightness, 0.0), 1.0);
    return [UIColor colorWithHue:h saturation:s brightness:b alpha:1.0];
}

- (NSString *)detectedLanguage:(NSString *)text {
#if __has_include(<NaturalLanguage/NaturalLanguage.h>)
    if (@available(iOS 12.0, *)) {
        NLLanguageRecognizer *r = [NLLanguageRecognizer new];
        [r processString:text];
        NLLanguage l = r.dominantLanguage;
        if (l) return l;
    }
#endif
    return nil;
}

- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated))completion {
    NSString *inputText = text ?: @"";
    BOOL mangaMultiline = self.mangaTranslationModeEnabled && [inputText containsString:@"\n"];
    NSString *preparedText = inputText;
    if (mangaMultiline) {
        preparedText = TOPrepareOCRMultilineText(inputText);
    }

    if (!TOShouldTranslateText(preparedText)) {
        if (completion) completion(inputText);
        return;
    }

    NSString *source = self.sourceLanguage ?: @"auto";
    NSString *target = self.targetLanguage ?: @"ar";
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@|%@", source, target, preparedText];
    NSString *cached = [self.cache objectForKey:cacheKey];
    if (cached.length == 0) {
        @synchronized (self) {
            cached = self.persistentCache[cacheKey];
        }
    }
    BOOL cachedLooksUntranslated = (cached.length > 0 && [cached isEqualToString:preparedText]);
    if (cachedLooksUntranslated) {
        [self.cache removeObjectForKey:cacheKey];
        @synchronized (self) {
            [self.persistentCache removeObjectForKey:cacheKey];
        }
    }
    if (cached.length > 0 && !cachedLooksUntranslated) {
        if (completion) completion(cached);
        return;
    }

    @synchronized (self) {
        if ([self.inFlightTranslationKeys containsObject:cacheKey]) {
            if (completion) completion(inputText);
            return;
        }
        [self.inFlightTranslationKeys addObject:cacheKey];
    }

    NSString *sl = source;
    if ([sl isEqualToString:@"auto"]) {
        NSString *detected = [self detectedLanguage:preparedText];
        if (detected.length > 0) sl = detected;
    }

    NSString *q = [preparedText stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    NSString *u = [NSString stringWithFormat:@"https://translate.googleapis.com/translate_a/single?client=gtx&sl=%@&tl=%@&dt=t&q=%@", sl, target, q];
    NSURL *url = [NSURL URLWithString:u];
    if (!url) {
        @synchronized (self) {
            [self.inFlightTranslationKeys removeObject:cacheKey];
        }
        if (completion) completion(inputText);
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *result = inputText;
        BOOL didGetValidTranslationPayload = NO;
        if (!error && data.length > 0) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSArray class]]) {
                NSArray *top = (NSArray *)json;
                if (top.count > 0 && [top[0] isKindOfClass:[NSArray class]]) {
                    NSMutableString *combined = [NSMutableString string];
                    for (id seg in (NSArray *)top[0]) {
                        if ([seg isKindOfClass:[NSArray class]]) {
                            NSArray *piece = (NSArray *)seg;
                            if (piece.count > 0 && [piece[0] isKindOfClass:[NSString class]]) {
                                [combined appendString:piece[0]];
                            }
                        }
                    }
                    if (combined.length > 0) {
                        didGetValidTranslationPayload = YES;
                        result = combined;
                    }
                }
            }
        }

        // Cache only validated translation payloads; avoid poisoning cache with original text on network/parse failures.
        if (didGetValidTranslationPayload && result.length > 0) {
            [self.cache setObject:result forKey:cacheKey];
            @synchronized (self) {
                self.persistentCache[cacheKey] = result;
                if (self.persistentCache.count > 500) {
                    NSString *first = self.persistentCache.allKeys.firstObject;
                    if (first) [self.persistentCache removeObjectForKey:first];
                }
            }
            [self saveSettings];
        }

        @synchronized (self) {
            [self.inFlightTranslationKeys removeObject:cacheKey];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result);
        });
    }] resume];
}

- (void)translateOCRText:(NSString *)text completion:(void (^)(NSString *translated))completion {
    NSString *original = text ?: @"";
    NSString *prepared = TOPrepareLiveOCRSourceText(original);
    if (!TOShouldTranslateText(prepared)) {
        if (completion) completion(original);
        return;
    }

    [self translateText:prepared completion:^(NSString *translated) {
        NSString *result = translated.length > 0 ? translated : prepared;

        BOOL unchanged = (result.length > 0 && [result isEqualToString:prepared]);
        BOOL hasMeaningfulRewrite = (prepared.length > 0 && ![prepared isEqualToString:original]);
        if (unchanged && hasMeaningfulRewrite && TOShouldTranslateText(original)) {
            [self translateText:original completion:^(NSString *retryText) {
                NSString *retry = retryText.length > 0 ? retryText : original;
                if (completion) completion(retry);
            }];
            return;
        }

        if (completion) completion(result);
    }];
}

@end

static NSString *TOUIString(NSString *text) {
    if (text.length == 0) return @"";

    TOTranslationManager *m = [TOTranslationManager shared];
    NSString *target = m.targetLanguage ?: @"ar";
    if ([target isEqualToString:@"ar"]) return text;

    NSString *key = [NSString stringWithFormat:@"ar|%@|%@", target, text];
    NSString *cached = [m.cache objectForKey:key];
    if (cached.length == 0) {
        @synchronized (m) {
            cached = m.persistentCache[key];
        }
    }
    if (cached.length > 0) return cached;

    static NSMutableDictionary<NSString *, NSNumber *> *inFlight;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inFlight = [NSMutableDictionary dictionary];
    });

    @synchronized (inFlight) {
        if (inFlight[key]) return text;
        inFlight[key] = @YES;
    }

    NSString *q = [text stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    NSString *u = [NSString stringWithFormat:@"https://translate.googleapis.com/translate_a/single?client=gtx&sl=ar&tl=%@&dt=t&q=%@", target, q];
    NSURL *url = [NSURL URLWithString:u];
    if (!url) {
        @synchronized (inFlight) {
            [inFlight removeObjectForKey:key];
        }
        return text;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, __unused NSURLResponse *response, NSError *error) {
        NSString *translated = text;
        if (!error && data.length > 0) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSArray class]]) {
                NSArray *top = (NSArray *)json;
                if (top.count > 0 && [top[0] isKindOfClass:[NSArray class]]) {
                    NSMutableString *combined = [NSMutableString string];
                    for (id seg in (NSArray *)top[0]) {
                        if ([seg isKindOfClass:[NSArray class]]) {
                            NSArray *piece = (NSArray *)seg;
                            if (piece.count > 0 && [piece[0] isKindOfClass:[NSString class]]) {
                                [combined appendString:piece[0]];
                            }
                        }
                    }
                    if (combined.length > 0) translated = combined;
                }
            }
        }

        if (translated.length > 0) {
            [m.cache setObject:translated forKey:key];
            @synchronized (m) {
                m.persistentCache[key] = translated;
                if (m.persistentCache.count > 800) {
                    NSString *first = m.persistentCache.allKeys.firstObject;
                    if (first) [m.persistentCache removeObjectForKey:first];
                }
            }
            [m saveSettings];
        }

        @synchronized (inFlight) {
            [inFlight removeObjectForKey:key];
        }
    }] resume];

    return text;
}

static void TOWarmupUILocalization(void) {
    TOTranslationManager *m = [TOTranslationManager shared];
    NSString *target = m.targetLanguage ?: @"ar";
    if ([target isEqualToString:@"ar"]) return;

    static NSArray<NSString *> *phrases;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        phrases = @[
            @"إعدادات الترجمة", @"الترجمه من و إلى", @"إعدادات OCR", @"أخرى", @"صفحة المطور",
            @"الترجمه من", @"الترجمة إلى", @"اختيار لغة المصدر", @"اختيار لغة الهدف", @"إعدادات مظهر OCR", @"تغيير حجم نص OCR",
            @"نمط الترجمه", @"ترجمة التطبيق", @"زر نمط ترجمة المانجا", @"زر نمط الترجمه المباشره",
            @"تم تفعيل نمط الترجمه المباشره", @"تم إيقاف نمط الترجمه المباشره", @"تم تفعيل نمط ترجمة المانجا", @"تم تفعيل ترجمة التطبيق",
            @"تنسيق النص: توسيط داخل الموضع", @"تحرير النص بعد ترجمة OCR", @"نمط ترجمة المانجا",
            @"إعدادات لون النص", @"إعدادات لون الخلفية", @"تفعيل اللون التلقائي للنص", @"تعطيل اللون التلقائي للنص",
            @"تفعيل اللون التلقائي لخلفية النص", @"تعطيل اللون التلقائي لخلفية النص",
            @"لون النص: الدرجة اللونية", @"لون النص: التشبع", @"لون الخلفية: الدرجة اللونية",
            @"لون الخلفية: التشبع", @"تعتيم الخلفية", @"تعتيم خلفية النص", @"رجوع", @"إلغاء",
            @"تم", @"إغلاق", @"حفظ", @"تحرير", @"تحرير نص OCR", @"حجم نص OCR", @"نتيجة OCR", @"المصدر", @"الهدف",
            @"جارٍ التقاط الصفحة وتحليلها...", @"تمت محاولة الترجمة",
            @"مهلة استئناف الترجمه المباشره بعد اللمس", @"كلما زادت المهلة، يصبح التمرير أكثر سلاسة", @"تم ضبط مهلة الاستئناف"
        ];
    });

    for (NSString *text in phrases) {
        NSString *key = [NSString stringWithFormat:@"ar|%@|%@", target, text];
        BOOL hasCached = ([m.cache objectForKey:key] != nil);
        if (!hasCached) {
            @synchronized (m) {
                hasCached = (m.persistentCache[key] != nil);
            }
        }
        if (hasCached) continue;
        (void)TOUIString(text);
    }
}

static NSString *TOTranslationModeLabel(TOTranslationTapMode mode) {
    switch (mode) {
        case TOTranslationTapModeManga:
            return TOUIString(@"زر نمط ترجمة المانجا");
        case TOTranslationTapModeLive:
            return TOUIString(@"زر نمط الترجمه المباشره");
        case TOTranslationTapModeNormal:
        default:
            return TOUIString(@"ترجمة التطبيق");
    }
}

static void TOTranslateViewTree(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01) return;

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        [[TOTranslationManager shared] translateText:label.text completion:^(NSString *translated) {
            if (translated.length > 0) label.text = translated;
        }];
        if (label.attributedText.length > 0) {
            TOTranslateAndApplyAttributedTextToObject(label, label.attributedText, ^(NSAttributedString *translated) {
                label.attributedText = translated;
            });
        }
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        [[TOTranslationManager shared] translateText:[button titleForState:UIControlStateNormal] completion:^(NSString *translated) {
            if (translated.length > 0) [button setTitle:translated forState:UIControlStateNormal];
        }];
        NSAttributedString *attrNormal = [button attributedTitleForState:UIControlStateNormal];
        if (attrNormal.length > 0) {
            TOTranslateAndApplyAttributedTextToObject(button, attrNormal, ^(NSAttributedString *translated) {
                [button setAttributedTitle:translated forState:UIControlStateNormal];
            });
        }
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        [[TOTranslationManager shared] translateText:tf.text completion:^(NSString *translated) {
            if (translated.length > 0) tf.text = translated;
        }];
        if (tf.attributedText.length > 0) {
            TOTranslateAndApplyAttributedTextToObject(tf, tf.attributedText, ^(NSAttributedString *translated) {
                tf.attributedText = translated;
            });
        }
        [[TOTranslationManager shared] translateText:tf.placeholder completion:^(NSString *translated) {
            if (translated.length > 0) tf.placeholder = translated;
        }];
        if (tf.attributedPlaceholder.string.length > 0) {
            NSString *raw = tf.attributedPlaceholder.string;
            [[TOTranslationManager shared] translateText:raw completion:^(NSString *translated) {
                if (translated.length > 0) tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:translated attributes:nil];
            }];
        }
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        [[TOTranslationManager shared] translateText:tv.text completion:^(NSString *translated) {
            if (translated.length > 0) tv.text = translated;
        }];
        if (tv.attributedText.length > 0) {
            TOTranslateAndApplyAttributedTextToObject(tv, tv.attributedText, ^(NSAttributedString *translated) {
                tv.attributedText = translated;
            });
        }
    } else if ([view isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *seg = (UISegmentedControl *)view;
        for (NSInteger i = 0; i < (NSInteger)seg.numberOfSegments; i++) {
            NSString *title = [seg titleForSegmentAtIndex:i];
            if (title.length == 0) continue;
            [[TOTranslationManager shared] translateText:title completion:^(NSString *translated) {
                if (translated.length > 0) [seg setTitle:translated forSegmentAtIndex:i];
            }];
        }
    }

    if (view.accessibilityLabel.length > 0) {
        NSString *a11y = view.accessibilityLabel;
        [[TOTranslationManager shared] translateText:a11y completion:^(NSString *translated) {
            if (translated.length > 0) view.accessibilityLabel = translated;
        }];
    }
    if (view.accessibilityValue.length > 0) {
        NSString *a11yValue = view.accessibilityValue;
        [[TOTranslationManager shared] translateText:a11yValue completion:^(NSString *translated) {
            if (translated.length > 0) view.accessibilityValue = translated;
        }];
    }
    if (view.accessibilityHint.length > 0) {
        NSString *a11yHint = view.accessibilityHint;
        [[TOTranslationManager shared] translateText:a11yHint completion:^(NSString *translated) {
            if (translated.length > 0) view.accessibilityHint = translated;
        }];
    }

    for (UIView *sub in view.subviews) TOTranslateViewTree(sub);
}

static void TOTranslateSingleViewNode(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01) return;

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        TOTranslateAndApplyTextToObject(label, label.text, ^(NSString *translated) {
            if (![label.text isEqualToString:translated]) [label setText:translated];
        });
        if (label.attributedText.length > 0) {
            TOTranslateAndApplyAttributedTextToObject(label, label.attributedText, ^(NSAttributedString *translated) {
                if (![[label.attributedText string] isEqualToString:[translated string]]) [label setAttributedText:translated];
            });
        }
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        TOTranslateAndApplyTextToObject(button, [button titleForState:UIControlStateNormal], ^(NSString *translated) {
            NSString *current = [button titleForState:UIControlStateNormal] ?: @"";
            if (![current isEqualToString:translated]) [button setTitle:translated forState:UIControlStateNormal];
        });
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        TOTranslateAndApplyTextToObject(tf, tf.text, ^(NSString *translated) {
            if (![[tf text] isEqualToString:translated]) [tf setText:translated];
        });
        TOTranslateAndApplyTextToObject(tf, tf.placeholder, ^(NSString *translated) {
            if (![[tf placeholder] isEqualToString:translated]) [tf setPlaceholder:translated];
        });
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        TOTranslateAndApplyTextToObject(tv, tv.text, ^(NSString *translated) {
            if (![[tv text] isEqualToString:translated]) [tv setText:translated];
        });
    }
}

static void TOTranslateBarButtonItems(NSArray<UIBarButtonItem *> *items) {
    for (UIBarButtonItem *item in items) {
        if (!item) continue;
        TOTranslateAndApplyTextToObject(item, item.title, ^(NSString *translated) {
            if (![[item title] isEqualToString:translated]) [item setTitle:translated];
        });
    }
}

static void TOTranslateControllerMetadata(UIViewController *controller) {
    if (!controller) return;

    TOTranslateAndApplyTextToObject(controller, controller.title, ^(NSString *translated) {
        if (![[controller title] isEqualToString:translated]) [controller setTitle:translated];
    });

    UINavigationItem *nav = controller.navigationItem;
    if (nav) {
        TOTranslateAndApplyTextToObject(nav, nav.title, ^(NSString *translated) {
            if (![[nav title] isEqualToString:translated]) [nav setTitle:translated];
        });
        TOTranslateAndApplyTextToObject(nav, nav.prompt, ^(NSString *translated) {
            if (![[nav prompt] isEqualToString:translated]) [nav setPrompt:translated];
        });
        TOTranslateBarButtonItems(nav.leftBarButtonItems ?: @[]);
        TOTranslateBarButtonItems(nav.rightBarButtonItems ?: @[]);
        if (nav.backBarButtonItem) TOTranslateBarButtonItems(@[nav.backBarButtonItem]);
    }

    if (controller.tabBarItem) {
        UITabBarItem *tab = controller.tabBarItem;
        TOTranslateAndApplyTextToObject(tab, tab.title, ^(NSString *translated) {
            if (![[tab title] isEqualToString:translated]) [tab setTitle:translated];
        });
    }

    if ([controller isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navVC = (UINavigationController *)controller;
        for (UIViewController *child in navVC.viewControllers) TOTranslateControllerMetadata(child);
    }
    if ([controller isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabVC = (UITabBarController *)controller;
        for (UIViewController *child in tabVC.viewControllers) TOTranslateControllerMetadata(child);
    }
    for (UIViewController *child in controller.childViewControllers) TOTranslateControllerMetadata(child);
    if (controller.presentedViewController) TOTranslateControllerMetadata(controller.presentedViewController);

    if ([controller isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)controller;
        for (UIAlertAction *action in alert.actions) {
            NSString *title = action.title;
            if (title.length == 0) continue;
            [[TOTranslationManager shared] translateText:title completion:^(NSString *translated) {
                if (translated.length == 0) return;
                @try {
                    [action setValue:translated forKey:@"title"];
                } @catch (__unused NSException *e) {
                }
            }];
        }
    }
}

static void TOTranslateControllerTree(UIViewController *controller) {
    if (!controller) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!controller.view) return;
        TOTranslateViewTree(controller.view);
        TOTranslateControllerMetadata(controller);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (controller.view.window) {
                TOTranslateViewTree(controller.view);
                TOTranslateControllerMetadata(controller);
            }
        });
    });
}

static void TOForceImmediateUILocalizationRefresh(void) {
    static NSTimeInterval lastRefreshTime = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if ((now - lastRefreshTime) < 0.25) return;
    lastRefreshTime = now;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<UIWindow *> *windows = TOVisibleWindows();
        if (windows.count == 0) return;

        for (UIWindow *w in windows) {
            TOTranslateViewTree(w);
            if (w.rootViewController) TOTranslateControllerTree(w.rootViewController);
        }

        // Run a second pass right after action-sheet dismissal completes.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSArray<UIWindow *> *windows2 = TOVisibleWindows();
            for (UIWindow *w2 in windows2) {
                TOTranslateViewTree(w2);
                if (w2.rootViewController) TOTranslateControllerTree(w2.rootViewController);
            }
        });
    });
}

static BOOL TOIsLikelyTextBearingView(UIView *view) {
    return [view isKindOfClass:[UILabel class]] ||
           [view isKindOfClass:[UIButton class]] ||
           [view isKindOfClass:[UITextField class]] ||
           [view isKindOfClass:[UITextView class]] ||
           [view isKindOfClass:[UISegmentedControl class]] ||
           [view isKindOfClass:[UISearchBar class]];
}

static CGFloat TOFittedFontSizeForText(NSString *text, CGRect rect, CGFloat minSize, CGFloat maxSize) {
    NSString *sample = text.length > 0 ? text : @"Aa";
    CGRect drawRect = CGRectInset(rect, 1.0, 0.0);
    if (CGRectIsEmpty(drawRect) || drawRect.size.width < 2.0 || drawRect.size.height < 2.0) return minSize;

    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentNatural;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;

    CGFloat size = MIN(MAX(maxSize, minSize), 44.0);
    for (NSInteger i = 0; i < 30; i++) {
        UIFont *font = [UIFont boldSystemFontOfSize:size];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSParagraphStyleAttributeName: paragraph
        };
        CGSize measured = [sample boundingRectWithSize:drawRect.size
                                               options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                            attributes:attrs
                                               context:nil].size;
        if (measured.height <= drawRect.size.height + 0.5 && measured.width <= drawRect.size.width + 0.5) {
            break;
        }
        size -= 1.0;
        if (size <= minSize) {
            size = minSize;
            break;
        }
    }
    return MAX(minSize, size);
}

static UIImage *TORenderTranslatedTextOnImage(UIImage *image, NSArray<NSDictionary *> *items) {
    if (!image || items.count == 0) return image;

    TOTranslationManager *m = [TOTranslationManager shared];
    CGSize size = image.size;
    UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];

    for (NSDictionary *item in items) {
        NSString *text = item[@"translated"];
        NSValue *rectValue = item[@"rect"];
        if (text.length == 0 || !rectValue) continue;

        CGRect rect = [rectValue CGRectValue];
        if (CGRectIsEmpty(rect) || rect.size.width < 2 || rect.size.height < 2) continue;

        CGFloat scale = m.ocrTextScale > 0.01 ? m.ocrTextScale : 1.0;
        NSString *sourceText = item[@"source"] ?: text;
        CGFloat originalFit = TOFittedFontSizeForText(sourceText, rect, 8.0, 34.0);
        CGFloat fontSize = MAX(1.0, MIN(40.0, originalFit * scale));
        UIColor *fg = nil;
        if (m.ocrAutoColorEnabled) fg = item[@"detectedColor"];
        if (!fg) fg = [m ocrManualUIColor];

        CGRect bgRect = CGRectInset(rect, -2.0, -1.0);
        UIColor *bgBase = nil;
        if (m.ocrBackgroundAutoColorEnabled) bgBase = item[@"detectedBackgroundColor"];
        if (!bgBase) bgBase = [m ocrBackgroundUIColor];
        UIColor *bgColor = [bgBase colorWithAlphaComponent:MIN(MAX(m.ocrBackgroundAlpha, 0.0), 1.0)];
        [bgColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:bgRect cornerRadius:3.0] fill];

        CGRect textRect = CGRectInset(rect, 1.0, 0.0);
        NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
        paragraph.alignment = m.ocrCenterTextEnabled ? NSTextAlignmentCenter : NSTextAlignmentNatural;
        paragraph.lineBreakMode = NSLineBreakByWordWrapping;

        NSDictionary *attrs = nil;
        CGSize measured = CGSizeZero;
        for (NSInteger i = 0; i < 12; i++) {
            UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
            attrs = @{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: fg,
                NSParagraphStyleAttributeName: paragraph
            };
            measured = [text boundingRectWithSize:textRect.size
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:attrs
                                         context:nil].size;
            if (measured.height <= textRect.size.height + 0.5) break;
            fontSize = MAX(1.0, fontSize - 1.0);
        }

        CGRect drawRect = textRect;
        if (m.ocrCenterTextEnabled) {
            CGFloat textHeight = MIN(ceil(measured.height), textRect.size.height);
            drawRect.origin.y = textRect.origin.y + MAX(0.0, (textRect.size.height - textHeight) * 0.5);
            drawRect.size.height = textHeight;
        }

        [text drawWithRect:drawRect
                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
               attributes:attrs
                  context:nil];
    }

    UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rendered ?: image;
}

@interface TOOCRTextEditorViewController : UIViewController
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) void (^onSave)(NSString *editedText);
@property (nonatomic, strong) UITextView *textView;
@end

@implementation TOOCRTextEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, self.view.bounds.size.width - 160, 28)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = TOUIString(@"تحرير نص OCR");
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:title];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(self.view.bounds.size.width - 168, 40, 74, 36);
    cancel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [cancel setTitle:TOUIString(@"إلغاء") forState:UIControlStateNormal];
    [cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    cancel.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    cancel.layer.cornerRadius = 10;
    [cancel addTarget:self action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cancel];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.frame = CGRectMake(self.view.bounds.size.width - 86, 40, 74, 36);
    save.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [save setTitle:TOUIString(@"حفظ") forState:UIControlStateNormal];
    [save setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    save.backgroundColor = [[UIColor colorWithRed:0.18 green:0.64 blue:0.95 alpha:1.0] colorWithAlphaComponent:0.85];
    save.layer.cornerRadius = 10;
    [save addTarget:self action:@selector(savePressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:save];

    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(12, 92, self.view.bounds.size.width - 24, self.view.bounds.size.height - 104)];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    tv.textColor = UIColor.whiteColor;
    tv.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    tv.layer.cornerRadius = 12;
    tv.text = self.initialText ?: @"";
    self.textView = tv;
    [self.view addSubview:tv];
}

- (void)cancelPressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)savePressed {
    if (self.onSave) self.onSave(self.textView.text ?: @"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface TOOCRResultsViewController : UIViewController
@property (nonatomic, strong) UIImage *screenshot;
@property (nonatomic, strong) UIImage *baseImage;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *items;
@property (nonatomic, strong) UIImageView *imageView;
@end

@implementation TOOCRResultsViewController

- (NSString *)editorPayload {
    if (self.items.count == 0) return @"";
    NSMutableArray<NSString *> *blocks = [NSMutableArray arrayWithCapacity:self.items.count];
    for (NSDictionary *item in self.items) {
        [blocks addObject:(item[@"translated"] ?: @"")];
    }
    return [blocks componentsJoinedByString:@"\n\n#####\n\n"];
}

- (void)applyEditedPayload:(NSString *)payload {
    NSArray<NSString *> *parts = [payload componentsSeparatedByString:@"\n\n#####\n\n"];
    NSInteger count = MIN((NSInteger)parts.count, (NSInteger)self.items.count);
    for (NSInteger i = 0; i < count; i++) {
        NSString *edited = [parts[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (edited.length > 0) self.items[i][@"translated"] = edited;
    }
}

- (void)refreshRenderedImage {
    UIImage *base = self.baseImage ?: self.screenshot;
    if (!base) return;
    if (self.items.count == 0) {
        self.imageView.image = self.screenshot;
        return;
    }
    self.imageView.image = TORenderTranslatedTextOnImage(base, self.items);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, self.view.bounds.size.width - 120, 28)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"نتيجة OCR";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(self.view.bounds.size.width - 92, 40, 72, 36);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"إغلاق" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    close.layer.cornerRadius = 10;
    [close addTarget:self action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    if ([TOTranslationManager shared].ocrEditAfterTranslateEnabled) {
        UIButton *edit = [UIButton buttonWithType:UIButtonTypeSystem];
        edit.frame = CGRectMake(self.view.bounds.size.width - 170, 40, 72, 36);
        edit.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [edit setTitle:TOUIString(@"تحرير") forState:UIControlStateNormal];
        [edit setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        edit.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
        edit.layer.cornerRadius = 10;
        [edit addTarget:self action:@selector(editPressed) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:edit];
    }

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(12, 88, self.view.bounds.size.width - 24, self.view.bounds.size.height - 104)];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.image = self.screenshot;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.layer.cornerRadius = 12;
    imageView.clipsToBounds = YES;
    imageView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.04];
    self.imageView = imageView;
    [self.view addSubview:imageView];

    [self refreshRenderedImage];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    TOTranslateControllerTree(self);
}

- (void)closePressed { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)editPressed {
    TOOCRTextEditorViewController *editor = [TOOCRTextEditorViewController new];
    editor.modalPresentationStyle = UIModalPresentationFullScreen;
    editor.initialText = [self editorPayload];
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(NSString *editedText) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self applyEditedPayload:editedText ?: @""];
        [self refreshRenderedImage];
    };
    [self presentViewController:editor animated:YES completion:nil];
}

@end

@interface TOPageOCRController : NSObject
+ (instancetype)shared;
- (void)presentOCRForWindow:(UIWindow *)window completion:(void (^)(void))completion;
- (void)buildLiveTranslatedOverlayForWindow:(UIWindow *)window excludingViews:(NSArray<UIView *> *)excludedViews completion:(void (^)(UIImage *resultImage))completion;
@end

@implementation TOPageOCRController

+ (instancetype)shared {
    static TOPageOCRController *c;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ c = [TOPageOCRController new]; });
    return c;
}

- (UIImage *)captureScreenshot:(UIWindow *)window {
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, UIScreen.mainScreen.scale);
    [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (UIImage *)captureScreenshot:(UIWindow *)window excludingViews:(NSArray<UIView *> *)excludedViews {
    NSMutableArray<UIView *> *toggled = [NSMutableArray array];
    for (UIView *v in excludedViews) {
        if (!v || v.window != window || v.hidden) continue;
        [toggled addObject:v];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.hidden = YES;
        [CATransaction commit];
    }

    UIImage *image = [self captureScreenshot:window];

    for (UIView *v in toggled) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.hidden = NO;
        [CATransaction commit];
    }

    return image;
}

- (CGRect)imageRectForNormalizedVisionRect:(CGRect)normalizedRect imageSize:(CGSize)size {
    CGFloat x = normalizedRect.origin.x * size.width;
    CGFloat width = normalizedRect.size.width * size.width;
    CGFloat height = normalizedRect.size.height * size.height;
    CGFloat y = (1.0 - normalizedRect.origin.y - normalizedRect.size.height) * size.height;
    return CGRectIntegral(CGRectMake(x, y, width, height));
}

- (UIColor *)detectedTextColorInImage:(UIImage *)image rect:(CGRect)rect {
    if (!image.CGImage || CGRectIsEmpty(rect)) return nil;

    CGRect safe = CGRectIntersection(rect, CGRectMake(0, 0, image.size.width, image.size.height));
    if (CGRectIsEmpty(safe) || safe.size.width < 2 || safe.size.height < 2) return nil;

    CGFloat scaleX = (CGFloat)CGImageGetWidth(image.CGImage) / image.size.width;
    CGFloat scaleY = (CGFloat)CGImageGetHeight(image.CGImage) / image.size.height;
    CGRect pxRect = CGRectIntegral(CGRectMake(safe.origin.x * scaleX, safe.origin.y * scaleY, safe.size.width * scaleX, safe.size.height * scaleY));
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pxRect);
    if (!cropped) return nil;

    const size_t w = 24;
    const size_t h = 24;
    const size_t bpp = 4;
    const size_t bpr = w * bpp;

    uint8_t *buf = (uint8_t *)calloc(h * bpr, sizeof(uint8_t));
    if (!buf) {
        CGImageRelease(cropped);
        return nil;
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, bpr, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        free(buf);
        CGImageRelease(cropped);
        return nil;
    }

    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cropped);

    CGFloat sumR = 0;
    CGFloat sumG = 0;
    CGFloat sumB = 0;
    CGFloat sumW = 0;

    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            size_t idx = y * bpr + x * bpp;
            CGFloat r = buf[idx] / 255.0;
            CGFloat g = buf[idx + 1] / 255.0;
            CGFloat b = buf[idx + 2] / 255.0;
            CGFloat a = buf[idx + 3] / 255.0;
            if (a < 0.2) continue;

            CGFloat maxC = MAX(r, MAX(g, b));
            CGFloat minC = MIN(r, MIN(g, b));
            CGFloat sat = (maxC <= 0.0001) ? 0.0 : ((maxC - minC) / maxC);
            CGFloat val = maxC;
            if (sat < 0.12 || val < 0.16) continue;

            CGFloat weight = a * (0.4 + 0.6 * sat);
            sumR += r * weight;
            sumG += g * weight;
            sumB += b * weight;
            sumW += weight;
        }
    }

    CGContextRelease(ctx);
    free(buf);
    CGImageRelease(cropped);

    if (sumW < 0.01) return nil;
    return [UIColor colorWithRed:(sumR / sumW) green:(sumG / sumW) blue:(sumB / sumW) alpha:1.0];
}

- (UIColor *)detectedBackgroundColorInImage:(UIImage *)image rect:(CGRect)rect textColor:(UIColor *)textColor {
    if (!image.CGImage || CGRectIsEmpty(rect)) return nil;

    CGRect expanded = CGRectInset(rect, -10.0, -6.0);
    CGRect safe = CGRectIntersection(expanded, CGRectMake(0, 0, image.size.width, image.size.height));
    if (CGRectIsEmpty(safe) || safe.size.width < 2 || safe.size.height < 2) return nil;

    CGFloat scaleX = (CGFloat)CGImageGetWidth(image.CGImage) / image.size.width;
    CGFloat scaleY = (CGFloat)CGImageGetHeight(image.CGImage) / image.size.height;
    CGRect pxRect = CGRectIntegral(CGRectMake(safe.origin.x * scaleX, safe.origin.y * scaleY, safe.size.width * scaleX, safe.size.height * scaleY));
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pxRect);
    if (!cropped) return nil;

    const size_t w = 40;
    const size_t h = 40;
    const size_t bpp = 4;
    const size_t bpr = w * bpp;

    uint8_t *buf = (uint8_t *)calloc(h * bpr, sizeof(uint8_t));
    if (!buf) {
        CGImageRelease(cropped);
        return nil;
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, bpr, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        free(buf);
        CGImageRelease(cropped);
        return nil;
    }

    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cropped);

    CGFloat tr = 0, tg = 0, tb = 0;
    BOOL hasTextColor = TOGetRGBComponents(textColor, &tr, &tg, &tb);

    CGFloat safeW = MAX(CGRectGetWidth(safe), 1.0);
    CGFloat safeH = MAX(CGRectGetHeight(safe), 1.0);
    NSInteger innerMinX = (NSInteger)floor(((CGRectGetMinX(rect) - CGRectGetMinX(safe)) / safeW) * (CGFloat)w);
    NSInteger innerMaxX = (NSInteger)ceil(((CGRectGetMaxX(rect) - CGRectGetMinX(safe)) / safeW) * (CGFloat)w);
    NSInteger innerMinY = (NSInteger)floor(((CGRectGetMinY(rect) - CGRectGetMinY(safe)) / safeH) * (CGFloat)h);
    NSInteger innerMaxY = (NSInteger)ceil(((CGRectGetMaxY(rect) - CGRectGetMinY(safe)) / safeH) * (CGFloat)h);
    innerMinX = MAX(0, MIN((NSInteger)w - 1, innerMinX));
    innerMaxX = MAX(0, MIN((NSInteger)w, innerMaxX));
    innerMinY = MAX(0, MIN((NSInteger)h - 1, innerMinY));
    innerMaxY = MAX(0, MIN((NSInteger)h, innerMaxY));

    static const NSInteger kBinsPerChannel = 16;
    static const NSInteger kTotalBins = kBinsPerChannel * kBinsPerChannel * kBinsPerChannel;
    CGFloat binWeight[kTotalBins];
    CGFloat binRingWeight[kTotalBins];
    CGFloat binSumR[kTotalBins];
    CGFloat binSumG[kTotalBins];
    CGFloat binSumB[kTotalBins];
    memset(binWeight, 0, sizeof(binWeight));
    memset(binRingWeight, 0, sizeof(binRingWeight));
    memset(binSumR, 0, sizeof(binSumR));
    memset(binSumG, 0, sizeof(binSumG));
    memset(binSumB, 0, sizeof(binSumB));

    CGFloat fallbackR = 0;
    CGFloat fallbackG = 0;
    CGFloat fallbackB = 0;
    CGFloat fallbackW = 0;

    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            size_t idx = y * bpr + x * bpp;
            CGFloat r = buf[idx] / 255.0;
            CGFloat g = buf[idx + 1] / 255.0;
            CGFloat b = buf[idx + 2] / 255.0;
            CGFloat a = buf[idx + 3] / 255.0;
            if (a < 0.15) continue;

            BOOL insideTextRect = ((NSInteger)x >= innerMinX && (NSInteger)x < innerMaxX && (NSInteger)y >= innerMinY && (NSInteger)y < innerMaxY);
            CGFloat maxC = MAX(r, MAX(g, b));
            CGFloat minC = MIN(r, MIN(g, b));
            CGFloat sat = (maxC <= 0.0001) ? 0.0 : ((maxC - minC) / maxC);
            CGFloat brightness = maxC;

            if (hasTextColor) {
                CGFloat dist = TOColorDistance(r, g, b, tr, tg, tb);
                if (insideTextRect && dist < 0.22) continue;
                if (!insideTextRect && dist < 0.08 && sat > 0.22) continue;
            }

            if (brightness < 0.02) continue;

            CGFloat baseWeight = insideTextRect ? 0.42 : 1.35;
            CGFloat neutralBoost = 1.0 + (1.0 - MIN(sat, 1.0)) * 0.55;
            CGFloat weight = a * baseWeight * neutralBoost;
            if (weight <= 0.01) continue;

            NSInteger ri = (NSInteger)lround(r * (kBinsPerChannel - 1));
            NSInteger gi = (NSInteger)lround(g * (kBinsPerChannel - 1));
            NSInteger bi = (NSInteger)lround(b * (kBinsPerChannel - 1));
            ri = MAX(0, MIN(kBinsPerChannel - 1, ri));
            gi = MAX(0, MIN(kBinsPerChannel - 1, gi));
            bi = MAX(0, MIN(kBinsPerChannel - 1, bi));
            NSInteger bin = (ri << 8) | (gi << 4) | bi;

            binWeight[bin] += weight;
            if (!insideTextRect) binRingWeight[bin] += weight;
            binSumR[bin] += r * weight;
            binSumG[bin] += g * weight;
            binSumB[bin] += b * weight;

            fallbackR += r * weight;
            fallbackG += g * weight;
            fallbackB += b * weight;
            fallbackW += weight;
        }
    }

    NSInteger bestBin = -1;
    NSInteger secondBin = -1;
    CGFloat bestScore = 0;
    CGFloat secondScore = 0;

    for (NSInteger i = 0; i < kTotalBins; i++) {
        CGFloat score = binWeight[i] + (binRingWeight[i] * 0.65);
        if (score > bestScore) {
            secondScore = bestScore;
            secondBin = bestBin;
            bestScore = score;
            bestBin = i;
        } else if (score > secondScore) {
            secondScore = score;
            secondBin = i;
        }
    }

    NSInteger chosenBin = bestBin;
    if (hasTextColor && bestBin >= 0 && secondBin >= 0) {
        CGFloat bestW = MAX(binWeight[bestBin], 0.0001);
        CGFloat bestR = binSumR[bestBin] / bestW;
        CGFloat bestG = binSumG[bestBin] / bestW;
        CGFloat bestB = binSumB[bestBin] / bestW;
        CGFloat textDist = TOColorDistance(bestR, bestG, bestB, tr, tg, tb);
        if (textDist < 0.18 && secondScore > (bestScore * 0.42)) {
            chosenBin = secondBin;
        }
    }

    CGContextRelease(ctx);
    free(buf);
    CGImageRelease(cropped);

    if (chosenBin >= 0 && binWeight[chosenBin] > 0.01) {
        CGFloat wSum = binWeight[chosenBin];
        return [UIColor colorWithRed:(binSumR[chosenBin] / wSum)
                               green:(binSumG[chosenBin] / wSum)
                                blue:(binSumB[chosenBin] / wSum)
                               alpha:1.0];
    }

    if (fallbackW < 0.01) return nil;
    return [UIColor colorWithRed:(fallbackR / fallbackW)
                           green:(fallbackG / fallbackW)
                            blue:(fallbackB / fallbackW)
                           alpha:1.0];
}

static NSArray<NSDictionary<NSString *, NSString *> *> *TOSupportedLanguages(void) {
    static NSArray<NSDictionary<NSString *, NSString *> *> *langs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        langs = @[
            @{@"code": @"auto", @"name": @"اكتشاف تلقائي"},
            @{@"code": @"af", @"name": @"Afrikaans"},
            @{@"code": @"sq", @"name": @"Albanian"},
            @{@"code": @"am", @"name": @"Amharic"},
            @{@"code": @"ar", @"name": @"العربية"},
            @{@"code": @"hy", @"name": @"Armenian"},
            @{@"code": @"az", @"name": @"Azerbaijani"},
            @{@"code": @"eu", @"name": @"Basque"},
            @{@"code": @"be", @"name": @"Belarusian"},
            @{@"code": @"bn", @"name": @"Bengali"},
            @{@"code": @"bs", @"name": @"Bosnian"},
            @{@"code": @"bg", @"name": @"Bulgarian"},
            @{@"code": @"ca", @"name": @"Catalan"},
            @{@"code": @"ceb", @"name": @"Cebuano"},
            @{@"code": @"ny", @"name": @"Chichewa"},
            @{@"code": @"zh-CN", @"name": @"Chinese (Simplified)"},
            @{@"code": @"zh-TW", @"name": @"Chinese (Traditional)"},
            @{@"code": @"co", @"name": @"Corsican"},
            @{@"code": @"hr", @"name": @"Croatian"},
            @{@"code": @"cs", @"name": @"Czech"},
            @{@"code": @"da", @"name": @"Danish"},
            @{@"code": @"nl", @"name": @"Dutch"},
            @{@"code": @"en", @"name": @"English"},
            @{@"code": @"eo", @"name": @"Esperanto"},
            @{@"code": @"et", @"name": @"Estonian"},
            @{@"code": @"tl", @"name": @"Filipino"},
            @{@"code": @"fi", @"name": @"Finnish"},
            @{@"code": @"fr", @"name": @"French"},
            @{@"code": @"fy", @"name": @"Frisian"},
            @{@"code": @"gl", @"name": @"Galician"},
            @{@"code": @"ka", @"name": @"Georgian"},
            @{@"code": @"de", @"name": @"German"},
            @{@"code": @"el", @"name": @"Greek"},
            @{@"code": @"gu", @"name": @"Gujarati"},
            @{@"code": @"ht", @"name": @"Haitian Creole"},
            @{@"code": @"ha", @"name": @"Hausa"},
            @{@"code": @"haw", @"name": @"Hawaiian"},
            @{@"code": @"he", @"name": @"Hebrew"},
            @{@"code": @"hi", @"name": @"Hindi"},
            @{@"code": @"hmn", @"name": @"Hmong"},
            @{@"code": @"hu", @"name": @"Hungarian"},
            @{@"code": @"is", @"name": @"Icelandic"},
            @{@"code": @"ig", @"name": @"Igbo"},
            @{@"code": @"id", @"name": @"Indonesian"},
            @{@"code": @"ga", @"name": @"Irish"},
            @{@"code": @"it", @"name": @"Italian"},
            @{@"code": @"ja", @"name": @"Japanese"},
            @{@"code": @"jw", @"name": @"Javanese"},
            @{@"code": @"kn", @"name": @"Kannada"},
            @{@"code": @"kk", @"name": @"Kazakh"},
            @{@"code": @"km", @"name": @"Khmer"},
            @{@"code": @"rw", @"name": @"Kinyarwanda"},
            @{@"code": @"ko", @"name": @"Korean"},
            @{@"code": @"ku", @"name": @"Kurdish (Kurmanji)"},
            @{@"code": @"ky", @"name": @"Kyrgyz"},
            @{@"code": @"lo", @"name": @"Lao"},
            @{@"code": @"la", @"name": @"Latin"},
            @{@"code": @"lv", @"name": @"Latvian"},
            @{@"code": @"lt", @"name": @"Lithuanian"},
            @{@"code": @"lb", @"name": @"Luxembourgish"},
            @{@"code": @"mk", @"name": @"Macedonian"},
            @{@"code": @"mg", @"name": @"Malagasy"},
            @{@"code": @"ms", @"name": @"Malay"},
            @{@"code": @"ml", @"name": @"Malayalam"},
            @{@"code": @"mt", @"name": @"Maltese"},
            @{@"code": @"mi", @"name": @"Maori"},
            @{@"code": @"mr", @"name": @"Marathi"},
            @{@"code": @"mn", @"name": @"Mongolian"},
            @{@"code": @"my", @"name": @"Myanmar (Burmese)"},
            @{@"code": @"ne", @"name": @"Nepali"},
            @{@"code": @"no", @"name": @"Norwegian"},
            @{@"code": @"or", @"name": @"Odia"},
            @{@"code": @"ps", @"name": @"Pashto"},
            @{@"code": @"fa", @"name": @"Persian"},
            @{@"code": @"pl", @"name": @"Polish"},
            @{@"code": @"pt", @"name": @"Portuguese"},
            @{@"code": @"pa", @"name": @"Punjabi"},
            @{@"code": @"ro", @"name": @"Romanian"},
            @{@"code": @"ru", @"name": @"الروسية"},
            @{@"code": @"sm", @"name": @"Samoan"},
            @{@"code": @"gd", @"name": @"Scots Gaelic"},
            @{@"code": @"sr", @"name": @"Serbian"},
            @{@"code": @"st", @"name": @"Sesotho"},
            @{@"code": @"sn", @"name": @"Shona"},
            @{@"code": @"sd", @"name": @"Sindhi"},
            @{@"code": @"si", @"name": @"Sinhala"},
            @{@"code": @"sk", @"name": @"Slovak"},
            @{@"code": @"sl", @"name": @"Slovenian"},
            @{@"code": @"so", @"name": @"Somali"},
            @{@"code": @"es", @"name": @"Spanish"},
            @{@"code": @"su", @"name": @"Sundanese"},
            @{@"code": @"sw", @"name": @"Swahili"},
            @{@"code": @"sv", @"name": @"Swedish"},
            @{@"code": @"tg", @"name": @"Tajik"},
            @{@"code": @"ta", @"name": @"Tamil"},
            @{@"code": @"tt", @"name": @"Tatar"},
            @{@"code": @"te", @"name": @"Telugu"},
            @{@"code": @"th", @"name": @"Thai"},
            @{@"code": @"tr", @"name": @"التركية"},
            @{@"code": @"tk", @"name": @"Turkmen"},
            @{@"code": @"uk", @"name": @"Ukrainian"},
            @{@"code": @"ur", @"name": @"Urdu"},
            @{@"code": @"ug", @"name": @"Uyghur"},
            @{@"code": @"uz", @"name": @"Uzbek"},
            @{@"code": @"vi", @"name": @"Vietnamese"},
            @{@"code": @"cy", @"name": @"Welsh"},
            @{@"code": @"xh", @"name": @"Xhosa"},
            @{@"code": @"yi", @"name": @"Yiddish"},
            @{@"code": @"yo", @"name": @"Yoruba"},
            @{@"code": @"zu", @"name": @"Zulu"}
        ];
    });
    return langs;
}

- (NSArray<NSDictionary *> *)mergedMangaBlocksFromItems:(NSArray<NSDictionary *> *)items {
    if (items.count <= 1) return items;

    NSMutableArray<NSDictionary *> *sorted = [items mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        CGRect ra = [a[@"rect"] CGRectValue];
        CGRect rb = [b[@"rect"] CGRectValue];
        CGFloat dy = CGRectGetMinY(ra) - CGRectGetMinY(rb);
        if (fabs(dy) > 6.0) return (dy < 0) ? NSOrderedAscending : NSOrderedDescending;
        CGFloat dx = CGRectGetMinX(ra) - CGRectGetMinX(rb);
        return (dx < 0) ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSMutableDictionary *> *blocks = [NSMutableArray array];
    for (NSDictionary *raw in sorted) {
        NSMutableDictionary *current = [raw mutableCopy];
        if (blocks.count == 0) {
            [blocks addObject:current];
            continue;
        }

        NSMutableDictionary *last = blocks.lastObject;
        CGRect lr = [last[@"rect"] CGRectValue];
        CGRect cr = [current[@"rect"] CGRectValue];

        CGFloat verticalGap = CGRectGetMinY(cr) - CGRectGetMaxY(lr);
        CGFloat overlap = MAX(0.0, MIN(CGRectGetMaxX(lr), CGRectGetMaxX(cr)) - MAX(CGRectGetMinX(lr), CGRectGetMinX(cr)));
        CGFloat minWidth = MAX(1.0, MIN(CGRectGetWidth(lr), CGRectGetWidth(cr)));
        CGFloat overlapRatio = overlap / minWidth;
        CGFloat centerDistance = fabs(CGRectGetMidX(lr) - CGRectGetMidX(cr));

        BOOL nearVertically = verticalGap <= MAX(12.0, CGRectGetHeight(lr) * 0.75);
        BOOL aligned = (overlapRatio >= 0.20) || (centerDistance <= MAX(24.0, CGRectGetWidth(lr) * 0.45));

        if (nearVertically && aligned) {
            NSString *prev = last[@"source"] ?: @"";
            NSString *next = current[@"source"] ?: @"";
            if (next.length > 0) {
                last[@"source"] = (prev.length > 0) ? [NSString stringWithFormat:@"%@\n%@", prev, next] : next;
            }
            last[@"rect"] = [NSValue valueWithCGRect:CGRectUnion(lr, cr)];
            if (!last[@"detectedColor"] && current[@"detectedColor"]) last[@"detectedColor"] = current[@"detectedColor"];
            if (!last[@"detectedBackgroundColor"] && current[@"detectedBackgroundColor"]) last[@"detectedBackgroundColor"] = current[@"detectedBackgroundColor"];
        } else {
            [blocks addObject:current];
        }
    }

    return blocks;
}

- (UIImage *)renderTranslatedTextOnImage:(UIImage *)image items:(NSArray<NSDictionary *> *)items {
    return TORenderTranslatedTextOnImage(image, items);
}

- (void)buildLiveTranslatedOverlayForWindow:(UIWindow *)window excludingViews:(NSArray<UIView *> *)excludedViews completion:(void (^)(UIImage *resultImage))completion {
    UIImage *image = [self captureScreenshot:window excludingViews:excludedViews ?: @[]];
    if (!image || !image.CGImage) {
        if (completion) completion(nil);
        return;
    }

    if (@available(iOS 13.0, *)) {
        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
            NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
            if (!error) {
                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                    if (top.string.length == 0) continue;
                    CGRect rect = [self imageRectForNormalizedVisionRect:obs.boundingBox imageSize:image.size];
                    UIColor *autoColor = [self detectedTextColorInImage:image rect:rect];
                    UIColor *autoBackgroundColor = [self detectedBackgroundColorInImage:image rect:rect textColor:autoColor];
                    [items addObject:@{
                        @"source": top.string,
                        @"rect": [NSValue valueWithCGRect:rect],
                        @"detectedColor": autoColor ?: UIColor.whiteColor,
                        @"detectedBackgroundColor": autoBackgroundColor ?: [UIColor colorWithWhite:0.0 alpha:1.0]
                    }];
                }
            }

            TOTranslationManager *settings = [TOTranslationManager shared];
            if (settings.mangaTranslationModeEnabled && items.count > 1) {
                items = [[self mergedMangaBlocksFromItems:items] mutableCopy];
            }

            if (items.count == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil);
                });
                return;
            }

            dispatch_group_t g = dispatch_group_create();
            NSMutableArray<NSMutableDictionary *> *translated = [NSMutableArray arrayWithCapacity:items.count];
            for (NSDictionary *raw in items) [translated addObject:[raw mutableCopy]];

            for (NSMutableDictionary *item in translated) {
                NSString *line = item[@"source"];
                dispatch_group_enter(g);
                [[TOTranslationManager shared] translateOCRText:line completion:^(NSString *text) {
                    item[@"translated"] = text.length > 0 ? text : line;
                    dispatch_group_leave(g);
                }];
            }

            dispatch_group_notify(g, dispatch_get_main_queue(), ^{
                UIImage *rendered = [self renderTranslatedTextOnImage:image items:translated];
                if (completion) completion(rendered);
            });
        }];

        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;
        request.minimumTextHeight = 0.012;

        TOTranslationManager *settings = [TOTranslationManager shared];
        NSString *sourceCode = settings.sourceLanguage ?: @"auto";
        if (![sourceCode isEqualToString:@"auto"]) {
            NSString *recognizedLanguage = TONormalizedLocaleIdentifier(sourceCode);
            if (recognizedLanguage.length > 0) {
                request.recognitionLanguages = @[recognizedLanguage];
            }
        }

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *err = nil;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
            [handler performRequests:@[request] error:&err];
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil);
                });
            }
        });
    } else {
        if (completion) completion(nil);
    }
}

- (void)presentOCRForWindow:(UIWindow *)window completion:(void (^)(void))completion {
    UIImage *image = [self captureScreenshot:window];
    if (!image || !image.CGImage) {
        if (completion) completion();
        return;
    }

    if (@available(iOS 13.0, *)) {
        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
            NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
            if (!error) {
                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                    if (top.string.length > 0) {
                        CGRect rect = [self imageRectForNormalizedVisionRect:obs.boundingBox imageSize:image.size];
                        UIColor *autoColor = [self detectedTextColorInImage:image rect:rect];
                        UIColor *autoBackgroundColor = [self detectedBackgroundColorInImage:image rect:rect textColor:autoColor];
                        [items addObject:@{
                            @"source": top.string,
                            @"rect": [NSValue valueWithCGRect:rect],
                            @"detectedColor": autoColor ?: UIColor.whiteColor,
                            @"detectedBackgroundColor": autoBackgroundColor ?: [UIColor colorWithWhite:0.0 alpha:1.0]
                        }];
                    }
                }
            }

            TOTranslationManager *settings = [TOTranslationManager shared];
            if (settings.mangaTranslationModeEnabled && items.count > 1) {
                items = [[self mergedMangaBlocksFromItems:items] mutableCopy];
            }

            if (items.count == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"OCR" message:@"لم يتم العثور على نص في لقطة الشاشة." preferredStyle:UIAlertControllerStyleAlert];
                    [a addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
                    [TOTopViewController() presentViewController:a animated:YES completion:completion];
                });
                return;
            }

            dispatch_group_t g = dispatch_group_create();
            NSMutableArray<NSMutableDictionary *> *translated = [NSMutableArray arrayWithCapacity:items.count];
            for (NSDictionary *raw in items) [translated addObject:[raw mutableCopy]];

            for (NSMutableDictionary *item in translated) {
                NSString *line = item[@"source"];
                dispatch_group_enter(g);
                [[TOTranslationManager shared] translateOCRText:line completion:^(NSString *text) {
                    item[@"translated"] = text.length > 0 ? text : line;
                    dispatch_group_leave(g);
                }];
            }

            dispatch_group_notify(g, dispatch_get_main_queue(), ^{
                UIImage *rendered = [self renderTranslatedTextOnImage:image items:translated];
                TOOCRResultsViewController *vc = [TOOCRResultsViewController new];
                vc.modalPresentationStyle = UIModalPresentationFullScreen;
                vc.screenshot = rendered;
                vc.baseImage = image;
                vc.items = translated;
                [TOTopViewController() presentViewController:vc animated:YES completion:completion];
            });
        }];

        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *err = nil;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
            [handler performRequests:@[request] error:&err];
            if (err && completion) dispatch_async(dispatch_get_main_queue(), completion);
        });
    } else {
        if (completion) completion();
    }
}

@end

@class TOFloatingOverlayController;

@interface TOOCRAppearanceViewController : UIViewController
@property (nonatomic, weak) TOFloatingOverlayController *overlayController;
@property (nonatomic, strong) UISwitch *autoColorSwitch;
@property (nonatomic, strong) UISwitch *autoBackgroundColorSwitch;
@property (nonatomic, strong) UISlider *hueSlider;
@property (nonatomic, strong) UISlider *saturationSlider;
@property (nonatomic, strong) UISlider *bgHueSlider;
@property (nonatomic, strong) UISlider *bgSaturationSlider;
@property (nonatomic, strong) UISlider *bgAlphaSlider;
@property (nonatomic, strong) UIView *colorPreview;
@property (nonatomic, strong) UIView *bgColorPreview;
@property (nonatomic, strong) UILabel *hueValue;
@property (nonatomic, strong) UILabel *satValue;
@property (nonatomic, strong) UILabel *bgHueValue;
@property (nonatomic, strong) UILabel *bgSatValue;
@property (nonatomic, strong) UILabel *bgValue;
@end

@interface TOTranslationSettingsViewController : UIViewController
@property (nonatomic, weak) TOFloatingOverlayController *overlayController;
@end

@interface TOFloatingOverlayController : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, weak) UIWindow *attachedWindow;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPress;
@property (nonatomic, strong) UITapGestureRecognizer *tripleTap;
@property (nonatomic, assign) BOOL hiddenByDoubleTap;
@property (nonatomic, assign) NSInteger activeSliderMode;
@property (nonatomic, weak) UILabel *activeSliderValueLabel;
@property (nonatomic, weak) UIView *activeColorPreviewView;
@property (nonatomic, weak) UILabel *activeSizePreviewLabel;
@property (nonatomic, assign) BOOL liveTranslateEnabled;
@property (nonatomic, strong) NSTimer *liveTranslateTimer;
@property (nonatomic, assign) NSUInteger liveTranslateBurstGeneration;
@property (nonatomic, strong) UIImageView *liveOverlayView;
@property (nonatomic, assign) BOOL liveOCRInFlight;
@property (nonatomic, assign) BOOL liveOCRNeedsRefresh;
@property (nonatomic, assign) NSUInteger liveOCRGeneration;
@property (nonatomic, assign) NSTimeInterval liveScrollInteractionUntil;
@property (nonatomic, assign) NSTimeInterval liveLastUIRefreshTime;
@property (nonatomic, assign) NSTimeInterval liveLastOCRRefreshTime;
@property (nonatomic, strong) NSTimer *liveScrollSettleTimer;
@property (nonatomic, assign) BOOL liveScrollPendingRefresh;
@property (nonatomic, assign) BOOL liveScrollActive;
@property (nonatomic, assign) NSTimeInterval liveLastScrollSignalTime;
@property (nonatomic, assign) BOOL liveTouchActive;
@property (nonatomic, assign) NSUInteger liveTouchResumeGeneration;
@property (nonatomic, strong) NSTimer *appTranslateTimer;
@property (nonatomic, assign) NSUInteger appTranslateBurstGeneration;
+ (instancetype)shared;
- (void)installIfPossible;
- (void)showToast:(NSString *)message;
- (void)startOCR;
- (void)startOCRForMangaMode:(BOOL)useMangaMode;
- (void)translateCurrentPage;
- (void)translateCurrentPageWithToast:(BOOL)showToast;
- (void)showTranslationModeSettings;
- (void)handleScrollActivity;
- (void)beginLiveScrollInteraction;
- (void)beginLiveTouchInteraction;
- (void)endLiveTouchInteractionIfNeeded;
- (void)showLiveTouchResumeDelaySettings;
- (void)syncLiveTranslationLoopState;
- (void)liveTranslationTimerFired;
- (void)scheduleLiveTranslationBurst;
- (void)scheduleLiveRefreshAfterScrollSettled;
- (void)liveScrollSettledTimerFired;
- (void)requestLiveOCROverlayRefresh;
- (void)removeLiveOverlayIfNeeded;
- (void)syncAppTranslationLoopState;
- (void)appTranslationTimerFired;
- (void)scheduleAppTranslationBurst;
- (void)showOCRAppearanceSettings;
- (void)showOCRTextSizePicker;
- (void)showLanguagePicker:(BOOL)isSource;
- (void)openDeveloperPage;
- (NSArray<NSDictionary *> *)colorStops;
- (NSDictionary *)colorStopForNormalized:(CGFloat)normalized;
- (CGFloat)normalizedValueForHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b;
@end

@implementation TOOCRAppearanceViewController

- (UILabel *)label:(NSString *)text y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y, self.view.bounds.size.width - 28, 20)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    return l;
}

- (UILabel *)valueLabelAtY:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 84, y, 68, 20)];
    l.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    l.textAlignment = NSTextAlignmentRight;
    l.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
    l.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    return l;
}

- (UISlider *)sliderAtY:(CGFloat)y action:(SEL)action {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(14, y, self.view.bounds.size.width - 110, 30)];
    s.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];

    TOTranslationManager *m = [TOTranslationManager shared];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, self.view.bounds.size.width - 120, 28)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"إعدادات مظهر OCR";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(self.view.bounds.size.width - 90, 40, 74, 36);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"تم" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14];
    close.layer.cornerRadius = 10;
    [close addTarget:self action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, 92, self.view.bounds.size.width - 24, 468)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    card.layer.cornerRadius = 12;
    [self.view addSubview:card];

    UILabel *autoLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 14, card.bounds.size.width - 130, 22)];
    autoLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    autoLabel.text = @"اللون التلقائي حسب النص الأصلي";
    autoLabel.textColor = UIColor.whiteColor;
    autoLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card addSubview:autoLabel];

    self.autoColorSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(card.bounds.size.width - 66, 9, 52, 32)];
    self.autoColorSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.autoColorSwitch.on = m.ocrAutoColorEnabled;
    self.autoColorSwitch.onTintColor = [UIColor colorWithRed:0.18 green:0.64 blue:0.95 alpha:1.0];
    [self.autoColorSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:self.autoColorSwitch];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12, 50, card.bounds.size.width - 24, 1)];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    line.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14];
    [card addSubview:line];

    [card addSubview:[self label:@"لون النص اليدوي: الدرجة اللونية" y:62]];
    self.hueSlider = [self sliderAtY:84 action:@selector(sliderChanged:)];
    self.hueSlider.minimumValue = 0;
    self.hueSlider.maximumValue = 1;
    self.hueSlider.value = m.ocrManualHue;
    [card addSubview:self.hueSlider];
    self.hueValue = [self valueLabelAtY:88];
    [card addSubview:self.hueValue];

    [card addSubview:[self label:@"لون النص اليدوي: التشبع" y:122]];
    self.saturationSlider = [self sliderAtY:144 action:@selector(sliderChanged:)];
    self.saturationSlider.minimumValue = 0;
    self.saturationSlider.maximumValue = 1;
    self.saturationSlider.value = m.ocrManualSaturation;
    [card addSubview:self.saturationSlider];
    self.satValue = [self valueLabelAtY:148];
    [card addSubview:self.satValue];

    [card addSubview:[self label:@"لون خلفية النص: الدرجة اللونية" y:182]];
    self.bgHueSlider = [self sliderAtY:204 action:@selector(sliderChanged:)];
    self.bgHueSlider.minimumValue = 0;
    self.bgHueSlider.maximumValue = 1;
    self.bgHueSlider.value = m.ocrBackgroundHue;
    [card addSubview:self.bgHueSlider];
    self.bgHueValue = [self valueLabelAtY:208];
    [card addSubview:self.bgHueValue];

    [card addSubview:[self label:@"لون خلفية النص: التشبع" y:242]];
    self.bgSaturationSlider = [self sliderAtY:264 action:@selector(sliderChanged:)];
    self.bgSaturationSlider.minimumValue = 0;
    self.bgSaturationSlider.maximumValue = 1;
    self.bgSaturationSlider.value = m.ocrBackgroundSaturation;
    [card addSubview:self.bgSaturationSlider];
    self.bgSatValue = [self valueLabelAtY:268];
    [card addSubview:self.bgSatValue];

    [card addSubview:[self label:@"تعتيم خلفية النص" y:302]];
    self.bgAlphaSlider = [self sliderAtY:324 action:@selector(sliderChanged:)];
    self.bgAlphaSlider.minimumValue = 0;
    self.bgAlphaSlider.maximumValue = 1;
    self.bgAlphaSlider.value = m.ocrBackgroundAlpha;
    [card addSubview:self.bgAlphaSlider];
    self.bgValue = [self valueLabelAtY:328];
    [card addSubview:self.bgValue];

    [card addSubview:[self label:@"أيقونة معاينة لون النص" y:364]];
    self.colorPreview = [[UIView alloc] initWithFrame:CGRectMake(card.bounds.size.width - 56, 362, 28, 28)];
    self.colorPreview.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.colorPreview.layer.cornerRadius = 14;
    self.colorPreview.layer.borderWidth = 1;
    self.colorPreview.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.35].CGColor;
    [card addSubview:self.colorPreview];

    [card addSubview:[self label:@"أيقونة معاينة لون الخلفية" y:396]];
    self.bgColorPreview = [[UIView alloc] initWithFrame:CGRectMake(card.bounds.size.width - 56, 394, 28, 28)];
    self.bgColorPreview.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.bgColorPreview.layer.cornerRadius = 14;
    self.bgColorPreview.layer.borderWidth = 1;
    self.bgColorPreview.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.35].CGColor;
    [card addSubview:self.bgColorPreview];

    UILabel *autoBgLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 426, card.bounds.size.width - 130, 22)];
    autoBgLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    autoBgLabel.text = @"اللون التلقائي لخلفية النص";
    autoBgLabel.textColor = UIColor.whiteColor;
    autoBgLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [card addSubview:autoBgLabel];

    self.autoBackgroundColorSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(card.bounds.size.width - 66, 421, 52, 32)];
    self.autoBackgroundColorSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.autoBackgroundColorSwitch.on = m.ocrBackgroundAutoColorEnabled;
    self.autoBackgroundColorSwitch.onTintColor = [UIColor colorWithRed:0.18 green:0.64 blue:0.95 alpha:1.0];
    [self.autoBackgroundColorSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:self.autoBackgroundColorSwitch];

    [self refreshUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    TOTranslateControllerTree(self);
}

- (void)refreshUI {
    TOTranslationManager *m = [TOTranslationManager shared];
    m.ocrAutoColorEnabled = self.autoColorSwitch.on;
    m.ocrBackgroundAutoColorEnabled = self.autoBackgroundColorSwitch.on;
    m.ocrManualHue = self.hueSlider.value;
    m.ocrManualSaturation = self.saturationSlider.value;
    m.ocrBackgroundHue = self.bgHueSlider.value;
    m.ocrBackgroundSaturation = self.bgSaturationSlider.value;
    m.ocrBackgroundAlpha = self.bgAlphaSlider.value;

    self.colorPreview.backgroundColor = [m ocrManualUIColor];
    self.bgColorPreview.backgroundColor = [m ocrBackgroundUIColor];

    self.hueValue.text = [NSString stringWithFormat:@"%.0f%%", self.hueSlider.value * 100.0];
    self.satValue.text = [NSString stringWithFormat:@"%.0f%%", self.saturationSlider.value * 100.0];
    self.bgHueValue.text = [NSString stringWithFormat:@"%.0f%%", self.bgHueSlider.value * 100.0];
    self.bgSatValue.text = [NSString stringWithFormat:@"%.0f%%", self.bgSaturationSlider.value * 100.0];
    self.bgValue.text = [NSString stringWithFormat:@"%.0f%%", self.bgAlphaSlider.value * 100.0];

    BOOL manualEnabled = !self.autoColorSwitch.on;
    self.hueSlider.enabled = manualEnabled;
    self.saturationSlider.enabled = manualEnabled;
    self.hueSlider.alpha = manualEnabled ? 1.0 : 0.5;
    self.saturationSlider.alpha = manualEnabled ? 1.0 : 0.5;

    BOOL backgroundManualEnabled = !self.autoBackgroundColorSwitch.on;
    self.bgHueSlider.enabled = backgroundManualEnabled;
    self.bgSaturationSlider.enabled = backgroundManualEnabled;
    self.bgHueSlider.alpha = backgroundManualEnabled ? 1.0 : 0.5;
    self.bgSaturationSlider.alpha = backgroundManualEnabled ? 1.0 : 0.5;
}

- (void)persist {
    [[TOTranslationManager shared] saveSettings];
}

- (void)switchChanged:(UISwitch *)sender {
    (void)sender;
    [self refreshUI];
    [self persist];
}

- (void)sliderChanged:(UISlider *)sender {
    (void)sender;
    [self refreshUI];
    [self persist];
}

- (void)closePressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation TOTranslationSettingsViewController

- (UIButton *)sectionButtonWithTitle:(NSString *)title y:(CGFloat)y action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(14, y, self.view.bounds.size.width - 52, 40);
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    b.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    b.layer.cornerRadius = 10;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)sectionCardWithTitle:(NSString *)title y:(CGFloat)y height:(CGFloat)h {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, y, self.view.bounds.size.width - 24, h)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    card.layer.cornerRadius = 12;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, card.bounds.size.width - 28, 22)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = title;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:15];
    [card addSubview:label];
    return card;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, self.view.bounds.size.width - 120, 28)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"إعدادات الترجمة";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(self.view.bounds.size.width - 90, 40, 74, 36);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"إغلاق" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14];
    close.layer.cornerRadius = 10;
    [close addTarget:self action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    UIView *translationCard = [self sectionCardWithTitle:@"إعدادات الترجمة" y:92 height:138];
    [translationCard addSubview:[self sectionButtonWithTitle:@"الترجمه من" y:44 action:@selector(sourcePressed)]];
    [translationCard addSubview:[self sectionButtonWithTitle:@"الترجمة إلى" y:88 action:@selector(targetPressed)]];
    [self.view addSubview:translationCard];

    UIView *ocrCard = [self sectionCardWithTitle:@"إعدادات OCR" y:242 height:182];
    [ocrCard addSubview:[self sectionButtonWithTitle:@"ترجمة الصفحة OCR" y:44 action:@selector(startOCRPressed)]];
    [ocrCard addSubview:[self sectionButtonWithTitle:@"إعدادات مظهر OCR" y:88 action:@selector(appearancePressed)]];
    [ocrCard addSubview:[self sectionButtonWithTitle:@"تغيير حجم نص OCR" y:132 action:@selector(sizePressed)]];
    [self.view addSubview:ocrCard];

    UIView *otherCard = [self sectionCardWithTitle:@"أخرى" y:436 height:94];
    [otherCard addSubview:[self sectionButtonWithTitle:@"صفحة المطور" y:44 action:@selector(developerPressed)]];
    [self.view addSubview:otherCard];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    TOTranslateControllerTree(self);
}

- (void)closePressed { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)sourcePressed { [self.overlayController showLanguagePicker:YES]; }
- (void)targetPressed { [self.overlayController showLanguagePicker:NO]; }
- (void)startOCRPressed { [self.overlayController startOCR]; }
- (void)appearancePressed { [self.overlayController showOCRAppearanceSettings]; }
- (void)sizePressed { [self.overlayController showOCRTextSizePicker]; }
- (void)developerPressed { [self.overlayController openDeveloperPage]; }

@end

@implementation TOFloatingOverlayController

typedef NS_ENUM(NSInteger, TOOverlaySliderMode) {
    TOOverlaySliderModeNone = 0,
    TOOverlaySliderModeTextHue,
    TOOverlaySliderModeTextSaturation,
    TOOverlaySliderModeBackgroundHue,
    TOOverlaySliderModeBackgroundSaturation,
    TOOverlaySliderModeBackgroundAlpha,
    TOOverlaySliderModeTextSize
};

+ (instancetype)shared {
    static TOFloatingOverlayController *c;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ c = [TOFloatingOverlayController new]; });
    return c;
}

- (void)showToast:(NSString *)message {
    UIWindow *w = self.attachedWindow ?: TOActiveWindow();
    if (!w || message.length == 0) return;
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectZero];
    toast.text = message;
    toast.textColor = UIColor.whiteColor;
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.numberOfLines = 2;
    toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;

    CGFloat width = MIN(w.bounds.size.width - 30, 300);
    CGSize size = [toast sizeThatFits:CGSizeMake(width - 20, CGFLOAT_MAX)];
    toast.frame = CGRectMake((w.bounds.size.width - width) / 2.0, w.bounds.size.height - size.height - 120, width, size.height + 16);
    toast.alpha = 0;
    [w addSubview:toast];
    [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; } completion:^(__unused BOOL f) {
        [UIView animateWithDuration:0.25 delay:1.2 options:UIViewAnimationOptionCurveEaseInOut animations:^{ toast.alpha = 0; } completion:^(__unused BOOL ff) { [toast removeFromSuperview]; }];
    }];
}

- (CGPoint)clampedCenter:(CGPoint)c inWindow:(UIWindow *)window {
    UIEdgeInsets s = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) s = window.safeAreaInsets;
    CGFloat hw = CGRectGetWidth(self.floatingButton.bounds) / 2.0;
    CGFloat hh = CGRectGetHeight(self.floatingButton.bounds) / 2.0;
    CGFloat minX = s.left + hw + 6;
    CGFloat maxX = CGRectGetWidth(window.bounds) - s.right - hw - 6;
    CGFloat minY = s.top + hh + 6;
    CGFloat maxY = CGRectGetHeight(window.bounds) - s.bottom - hh - 6;
    c.x = MIN(MAX(c.x, minX), maxX);
    c.y = MIN(MAX(c.y, minY), maxY);
    return c;
}

- (void)applySavedPosition {
    UIWindow *w = self.attachedWindow;
    if (!w) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSNumber *x = [d objectForKey:kTOButtonCenterXKey];
    NSNumber *y = [d objectForKey:kTOButtonCenterYKey];
    CGPoint c = (x && y) ? CGPointMake(x.doubleValue, y.doubleValue) : CGPointMake(CGRectGetMidX(w.bounds), 140);
    self.floatingButton.center = [self clampedCenter:c inWindow:w];
}

- (void)savePosition {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:@(self.floatingButton.center.x) forKey:kTOButtonCenterXKey];
    [d setObject:@(self.floatingButton.center.y) forKey:kTOButtonCenterYKey];
    [d synchronize];
}

- (CGPoint)snapCenterToNearestEdge:(CGPoint)c inWindow:(UIWindow *)window {
    UIEdgeInsets s = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) s = window.safeAreaInsets;

    CGFloat hw = CGRectGetWidth(self.floatingButton.bounds) / 2.0;
    CGFloat hh = CGRectGetHeight(self.floatingButton.bounds) / 2.0;
    CGFloat minX = s.left + hw + 6;
    CGFloat maxX = CGRectGetWidth(window.bounds) - s.right - hw - 6;
    CGFloat minY = s.top + hh + 6;
    CGFloat maxY = CGRectGetHeight(window.bounds) - s.bottom - hh - 6;

    CGPoint clamped = [self clampedCenter:c inWindow:window];
    CGFloat dLeft = fabs(clamped.x - minX);
    CGFloat dRight = fabs(maxX - clamped.x);
    CGFloat dTop = fabs(clamped.y - minY);
    CGFloat dBottom = fabs(maxY - clamped.y);

    CGFloat best = dLeft;
    CGPoint snapped = CGPointMake(minX, clamped.y);
    if (dRight < best) { best = dRight; snapped = CGPointMake(maxX, clamped.y); }
    if (dTop < best) { best = dTop; snapped = CGPointMake(clamped.x, minY); }
    if (dBottom < best) { snapped = CGPointMake(clamped.x, maxY); }

    return [self clampedCenter:snapped inWindow:window];
}

- (void)animateSnapToNearestEdgeInWindow:(UIWindow *)window {
    CGPoint snappedCenter = [self snapCenterToNearestEdge:self.floatingButton.center inWindow:window];
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.floatingButton.center = snappedCenter;
    } completion:^(__unused BOOL finished) {
        [self savePosition];
    }];
}

- (void)configurePopover:(UIAlertController *)alert {
    UIPopoverPresentationController *p = alert.popoverPresentationController;
    if (!p) return;
    p.sourceView = self.floatingButton ?: self.attachedWindow;
    p.sourceRect = self.floatingButton ? self.floatingButton.bounds : CGRectMake(0, 0, 1, 1);
    p.permittedArrowDirections = UIPopoverArrowDirectionAny;
}

- (void)presentSliderPopupWithTitle:(NSString *)title
                               mode:(TOOverlaySliderMode)mode
                          minValue:(CGFloat)minValue
                          maxValue:(CGFloat)maxValue
                      currentValue:(CGFloat)currentValue
                      showsPreview:(BOOL)showsPreview
                 showsSizePreview:(BOOL)showsSizePreview {
    UIViewController *top = TOTopViewController();
    if (!top) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"\n\n\n\n\n\n"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(18, 76, 234, 28)];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = currentValue;
    slider.tag = mode;
    [slider addTarget:self action:@selector(handlePopupSliderChanged:) forControlEvents:UIControlEventValueChanged];

    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 102, 234, 20)];
    valueLabel.textAlignment = NSTextAlignmentCenter;
    valueLabel.textColor = [UIColor secondaryLabelColor];
    valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];

    UIView *preview = nil;
    if (showsPreview) {
        preview = [[UIView alloc] initWithFrame:CGRectMake(119, 128, 32, 32)];
        preview.layer.cornerRadius = 16;
        preview.layer.borderWidth = 1;
        preview.layer.borderColor = [[UIColor grayColor] colorWithAlphaComponent:0.4].CGColor;
        [alert.view addSubview:preview];
    }

    UILabel *sizePreview = nil;
    if (showsSizePreview) {
        sizePreview = [[UILabel alloc] initWithFrame:CGRectMake(18, 128, 234, 28)];
        sizePreview.text = @"معاينة حجم النص";
        sizePreview.textAlignment = NSTextAlignmentCenter;
        sizePreview.textColor = [UIColor labelColor];
        [alert.view addSubview:sizePreview];
    }

    [alert.view addSubview:slider];
    [alert.view addSubview:valueLabel];

    self.activeSliderMode = mode;
    self.activeSliderValueLabel = valueLabel;
    self.activeColorPreviewView = preview;
    self.activeSizePreviewLabel = sizePreview;

    [self handlePopupSliderChanged:slider];

    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [[TOTranslationManager shared] saveSettings];
    }]];

    [top presentViewController:alert animated:YES completion:^{
        TOTranslateControllerTree(alert);
    }];
}

- (NSArray<NSDictionary *> *)colorStops {
    static NSArray<NSDictionary *> *stops;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stops = @[
            @{@"name": @"أسود", @"h": @0.0, @"s": @0.0, @"b": @0.0},
            @{@"name": @"أحمر", @"h": @0.0, @"s": @0.85, @"b": @1.0},
            @{@"name": @"برتقالي", @"h": @0.08, @"s": @0.85, @"b": @1.0},
            @{@"name": @"أصفر", @"h": @0.14, @"s": @0.85, @"b": @1.0},
            @{@"name": @"ليموني", @"h": @0.20, @"s": @0.75, @"b": @1.0},
            @{@"name": @"أخضر", @"h": @0.33, @"s": @0.75, @"b": @1.0},
            @{@"name": @"فيروزي", @"h": @0.45, @"s": @0.75, @"b": @1.0},
            @{@"name": @"سماوي", @"h": @0.52, @"s": @0.70, @"b": @1.0},
            @{@"name": @"أزرق", @"h": @0.62, @"s": @0.75, @"b": @1.0},
            @{@"name": @"نيلي", @"h": @0.70, @"s": @0.70, @"b": @1.0},
            @{@"name": @"بنفسجي", @"h": @0.78, @"s": @0.70, @"b": @1.0},
            @{@"name": @"وردي", @"h": @0.90, @"s": @0.55, @"b": @1.0},
            @{@"name": @"رمادي", @"h": @0.0, @"s": @0.0, @"b": @0.55},
            @{@"name": @"أبيض", @"h": @0.0, @"s": @0.0, @"b": @1.0}
        ];
    });
    return stops;
}

- (NSDictionary *)colorStopForNormalized:(CGFloat)normalized {
    NSArray<NSDictionary *> *stops = [self colorStops];
    NSInteger last = (NSInteger)stops.count - 1;
    NSInteger idx = (NSInteger)lround(MIN(MAX(normalized, 0.0), 1.0) * last);
    return stops[idx];
}

- (CGFloat)normalizedValueForHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b {
    NSArray<NSDictionary *> *stops = [self colorStops];
    NSInteger bestIdx = 0;
    CGFloat bestDist = CGFLOAT_MAX;
    for (NSInteger i = 0; i < (NSInteger)stops.count; i++) {
        NSDictionary *item = stops[i];
        CGFloat ih = [item[@"h"] doubleValue];
        CGFloat is = [item[@"s"] doubleValue];
        CGFloat ib = [item[@"b"] doubleValue];
        CGFloat d = fabs(ih - h) + fabs(is - s) + fabs(ib - b);
        if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
        }
    }
    if (stops.count <= 1) return 0;
    return (CGFloat)bestIdx / (CGFloat)(stops.count - 1);
}

- (void)handlePopupSliderChanged:(UISlider *)slider {
    TOTranslationManager *m = [TOTranslationManager shared];
    self.activeSliderMode = slider.tag;

    switch (self.activeSliderMode) {
        case TOOverlaySliderModeTextHue:
        {
            NSArray<NSDictionary *> *stops = [self colorStops];
            NSInteger last = (NSInteger)stops.count - 1;
            NSInteger idx = (NSInteger)lround(MIN(MAX(slider.value, 0.0), 1.0) * last);
            slider.value = (CGFloat)idx / (CGFloat)last;
            NSDictionary *stop = stops[idx];
            m.ocrManualHue = [stop[@"h"] doubleValue];
            m.ocrManualSaturation = [stop[@"s"] doubleValue];
            m.ocrManualBrightness = [stop[@"b"] doubleValue];
            self.activeSliderValueLabel.text = [NSString stringWithFormat:@"%@", stop[@"name"]];
            self.activeColorPreviewView.backgroundColor = [m ocrManualUIColor];
            break;
        }
        case TOOverlaySliderModeTextSaturation:
            m.ocrManualSaturation = slider.value;
            self.activeSliderValueLabel.text = [NSString stringWithFormat:@"Saturation: %.0f%%", slider.value * 100.0];
            self.activeColorPreviewView.backgroundColor = [m ocrManualUIColor];
            break;
        case TOOverlaySliderModeBackgroundHue:
        {
            NSArray<NSDictionary *> *stops = [self colorStops];
            NSInteger last = (NSInteger)stops.count - 1;
            NSInteger idx = (NSInteger)lround(MIN(MAX(slider.value, 0.0), 1.0) * last);
            slider.value = (CGFloat)idx / (CGFloat)last;
            NSDictionary *stop = stops[idx];
            m.ocrBackgroundHue = [stop[@"h"] doubleValue];
            m.ocrBackgroundSaturation = [stop[@"s"] doubleValue];
            CGFloat stopBrightness = [stop[@"b"] doubleValue];
            CGFloat stopSaturation = [stop[@"s"] doubleValue];
            // Preserve pure white/black endpoints, while keeping colored stops dimmed for readability.
            if (stopSaturation <= 0.001 && stopBrightness >= 0.999) {
                m.ocrBackgroundBrightness = 1.0;
            } else if (stopSaturation <= 0.001 && stopBrightness <= 0.001) {
                m.ocrBackgroundBrightness = 0.0;
            } else {
                m.ocrBackgroundBrightness = stopBrightness * 0.45;
            }
            self.activeSliderValueLabel.text = [NSString stringWithFormat:@"%@", stop[@"name"]];
            self.activeColorPreviewView.backgroundColor = [m ocrBackgroundUIColor];
            break;
        }
        case TOOverlaySliderModeBackgroundSaturation:
            m.ocrBackgroundSaturation = slider.value;
            self.activeSliderValueLabel.text = [NSString stringWithFormat:@"Saturation: %.0f%%", slider.value * 100.0];
            self.activeColorPreviewView.backgroundColor = [m ocrBackgroundUIColor];
            break;
        case TOOverlaySliderModeBackgroundAlpha:
            m.ocrBackgroundAlpha = slider.value;
            self.activeSliderValueLabel.text = [NSString stringWithFormat:@"Opacity: %.0f%%", slider.value * 100.0];
            self.activeColorPreviewView.backgroundColor = [[m ocrBackgroundUIColor] colorWithAlphaComponent:m.ocrBackgroundAlpha];
            break;
        case TOOverlaySliderModeTextSize: {
            m.ocrTextScale = slider.value;
            self.activeSliderValueLabel.text = [NSString stringWithFormat:@"%.0f%%", slider.value * 100.0];
            CGFloat size = MAX(1.0, MIN(32.0, 16.0 * slider.value));
            self.activeSizePreviewLabel.font = [UIFont boldSystemFontOfSize:size];
            self.activeSizePreviewLabel.text = [NSString stringWithFormat:@"معاينة %.0f%%", slider.value * 100.0];
            break;
        }
        default:
            break;
    }

    [m saveSettings];
}

- (void)showLanguagePicker:(BOOL)isSource {
    TOWarmupUILocalization();
    UIViewController *top = TOTopViewController();
    if (!top) return;
    TOTranslationManager *m = TOTranslationManager.shared;
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:TOUIString(isSource ? @"اختر لغة المصدر" : @"اختر لغة الهدف") message:TOUIString(@"يمكنك تغيير اللغة في أي وقت") preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary<NSString *, NSString *> *> *langs = TOSupportedLanguages();

    for (NSDictionary *item in langs) {
        NSString *code = item[@"code"];
        NSString *fallbackName = item[@"name"];
        if ([code isEqualToString:@"auto"]) fallbackName = TOUIString(fallbackName);
        NSString *name = TODisplayLanguageName(code, m.targetLanguage, fallbackName);
        if (!isSource && [code isEqualToString:@"auto"]) continue;

        NSString *current = isSource ? m.sourceLanguage : m.targetLanguage;
        NSString *title = [current isEqualToString:code] ? [NSString stringWithFormat:@"%@ ✓", name] : name;
        [picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (isSource) {
                m.sourceLanguage = code;
            } else {
                BOOL changed = ![m.targetLanguage isEqualToString:code];
                m.targetLanguage = code;
                if (changed) {
                    TOWarmupUILocalization();
                    TOForceImmediateUILocalizationRefresh();
                }
            }
            [m saveSettings];
            [self showToast:[NSString stringWithFormat:@"%@: %@", TOUIString(isSource ? @"المصدر" : @"الهدف"), name]];
        }]];
    }

    [picker addAction:[UIAlertAction actionWithTitle:TOUIString(@"إلغاء") style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:picker];
    [top presentViewController:picker animated:YES completion:^{
        TOTranslateControllerTree(picker);
    }];
}

- (void)showOCRTextSizePicker {
    TOWarmupUILocalization();
    TOTranslationManager *m = TOTranslationManager.shared;
    [self presentSliderPopupWithTitle:TOUIString(@"حجم نص OCR")
                                 mode:TOOverlaySliderModeTextSize
                           minValue:0.01
                            maxValue:2.0
                        currentValue:m.ocrTextScale
                        showsPreview:NO
                   showsSizePreview:YES];
}

- (void)showOCRAppearanceSettings {
    TOWarmupUILocalization();
    UIViewController *top = TOTopViewController();
    if (!top) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:TOUIString(@"إعدادات مظهر OCR")
                                                                   message:TOUIString(@"تخصيص لون النص والخلفية")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ▸", TOUIString(@"إعدادات لون النص")] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIViewController *menuTop = TOTopViewController();
        if (!menuTop) return;

        TOTranslationManager *innerM = TOTranslationManager.shared;
        NSString *innerAutoColorTitle = TOUIString(innerM.ocrAutoColorEnabled ? @"تعطيل اللون التلقائي للنص" : @"تفعيل اللون التلقائي للنص");
        UIAlertController *textSheet = [UIAlertController alertControllerWithTitle:TOUIString(@"إعدادات لون النص")
                                                                            message:nil
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];

        [textSheet addAction:[UIAlertAction actionWithTitle:innerAutoColorTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            innerM.ocrAutoColorEnabled = !innerM.ocrAutoColorEnabled;
            [innerM saveSettings];
            [self showToast:TOUIString(innerM.ocrAutoColorEnabled ? @"تم تفعيل اللون التلقائي" : @"تم تعطيل اللون التلقائي")];
        }]];

        [textSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"لون النص: الدرجة اللونية") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self presentSliderPopupWithTitle:TOUIString(@"لون النص - الدرجة اللونية")
                                         mode:TOOverlaySliderModeTextHue
                                    minValue:0
                                    maxValue:1
                                currentValue:[self normalizedValueForHue:innerM.ocrManualHue saturation:innerM.ocrManualSaturation brightness:innerM.ocrManualBrightness]
                                showsPreview:YES
                           showsSizePreview:NO];
        }]];

        [textSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"لون النص: التشبع") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self presentSliderPopupWithTitle:TOUIString(@"لون النص - التشبع")
                                         mode:TOOverlaySliderModeTextSaturation
                                    minValue:0
                                    maxValue:1
                                currentValue:innerM.ocrManualSaturation
                                showsPreview:YES
                           showsSizePreview:NO];
        }]];

        [textSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"رجوع") style:UIAlertActionStyleCancel handler:nil]];
        [self configurePopover:textSheet];
        [menuTop presentViewController:textSheet animated:YES completion:^{
            TOTranslateControllerTree(textSheet);
        }];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ▸", TOUIString(@"إعدادات لون الخلفية")] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIViewController *menuTop = TOTopViewController();
        if (!menuTop) return;

        TOTranslationManager *innerM = TOTranslationManager.shared;
        NSString *innerAutoBackgroundTitle = TOUIString(innerM.ocrBackgroundAutoColorEnabled ? @"تعطيل اللون التلقائي لخلفية النص" : @"تفعيل اللون التلقائي لخلفية النص");
        UIAlertController *bgSheet = [UIAlertController alertControllerWithTitle:TOUIString(@"إعدادات لون الخلفية")
                                                                          message:nil
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];

        [bgSheet addAction:[UIAlertAction actionWithTitle:innerAutoBackgroundTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            innerM.ocrBackgroundAutoColorEnabled = !innerM.ocrBackgroundAutoColorEnabled;
            [innerM saveSettings];
            [self showToast:TOUIString(innerM.ocrBackgroundAutoColorEnabled ? @"تم تفعيل اللون التلقائي لخلفية النص" : @"تم تعطيل اللون التلقائي لخلفية النص")];
        }]];

        [bgSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"لون الخلفية: الدرجة اللونية") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self presentSliderPopupWithTitle:TOUIString(@"لون الخلفية - الدرجة اللونية")
                                         mode:TOOverlaySliderModeBackgroundHue
                                    minValue:0
                                    maxValue:1
                                currentValue:[self normalizedValueForHue:innerM.ocrBackgroundHue saturation:innerM.ocrBackgroundSaturation brightness:innerM.ocrBackgroundBrightness]
                                showsPreview:YES
                           showsSizePreview:NO];
        }]];

        [bgSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"لون الخلفية: التشبع") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self presentSliderPopupWithTitle:TOUIString(@"لون الخلفية - التشبع")
                                         mode:TOOverlaySliderModeBackgroundSaturation
                                    minValue:0
                                    maxValue:1
                                currentValue:innerM.ocrBackgroundSaturation
                                showsPreview:YES
                           showsSizePreview:NO];
        }]];

        [bgSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"تعتيم الخلفية") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self presentSliderPopupWithTitle:TOUIString(@"تعتيم خلفية النص")
                                         mode:TOOverlaySliderModeBackgroundAlpha
                                    minValue:0
                                    maxValue:1
                                currentValue:innerM.ocrBackgroundAlpha
                                showsPreview:YES
                           showsSizePreview:NO];
        }]];

        [bgSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"رجوع") style:UIAlertActionStyleCancel handler:nil]];
        [self configurePopover:bgSheet];
        [menuTop presentViewController:bgSheet animated:YES completion:^{
            TOTranslateControllerTree(bgSheet);
        }];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"إلغاء") style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet];
    [top presentViewController:sheet animated:YES completion:^{
        TOTranslateControllerTree(sheet);
    }];
}

- (void)openDeveloperPage {
    NSURL *url = [NSURL URLWithString:@"https://instagram.com/wiz.wizo1/"];
    if (!url) return;
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [app openURL:url];
#pragma clang diagnostic pop
    }
}

- (void)startOCRForMangaMode:(BOOL)useMangaMode {
    UIWindow *w = self.attachedWindow ?: TOActiveWindow();
    if (!w) {
        [self showToast:@"لا توجد نافذة نشطة"];
        return;
    }

    TOTranslationManager *m = [TOTranslationManager shared];
    m.mangaTranslationModeEnabled = useMangaMode;
    [m saveSettings];

    self.floatingButton.hidden = YES;
    [self showToast:@"جارٍ التقاط الصفحة وتحليلها..."];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[TOPageOCRController shared] presentOCRForWindow:w completion:^{
            self.floatingButton.hidden = NO;
        }];
    });
}

- (void)startOCR {
    TOTranslationManager *m = [TOTranslationManager shared];
    [self startOCRForMangaMode:(m.translationTapMode == TOTranslationTapModeManga)];
}

- (void)translateCurrentPageWithToast:(BOOL)showToast {
    TOTranslationManager *m = [TOTranslationManager shared];
    NSTimeInterval now = CACurrentMediaTime();
    if (m.translationTapMode == TOTranslationTapModeLive && self.liveTranslateEnabled) {
        if (now < self.liveScrollInteractionUntil) return;
        if ((now - self.liveLastUIRefreshTime) < 0.85) return;
        self.liveLastUIRefreshTime = now;
    }

    TOForceImmediateUILocalizationRefresh();
    if (showToast) [self showToast:@"تمت محاولة الترجمة"];
}

- (void)translateCurrentPage {
    [self translateCurrentPageWithToast:YES];
}

- (void)removeLiveOverlayIfNeeded {
    if (self.liveOverlayView) {
        self.liveOverlayView.hidden = YES;
        self.liveOverlayView.image = nil;
        [self.liveOverlayView removeFromSuperview];
        self.liveOverlayView = nil;
    }
}

- (void)requestLiveOCROverlayRefresh {
    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) {
        [self removeLiveOverlayIfNeeded];
        return;
    }

    UIWindow *w = self.attachedWindow ?: TOActiveWindow();
    if (!w) return;

    if (self.liveTouchActive || self.liveScrollActive) {
        self.liveOCRNeedsRefresh = YES;
        self.liveScrollPendingRefresh = YES;
        if (self.liveOverlayView) self.liveOverlayView.hidden = YES;
        return;
    }

    NSTimeInterval now = CACurrentMediaTime();
    if (now < self.liveScrollInteractionUntil) {
        self.liveOCRNeedsRefresh = YES;
        return;
    }
    if ((now - self.liveLastOCRRefreshTime) < 1.35) {
        self.liveOCRNeedsRefresh = YES;
        return;
    }
    self.liveLastOCRRefreshTime = now;

    if (self.liveOCRInFlight) {
        self.liveOCRNeedsRefresh = YES;
        return;
    }

    if (!self.liveOverlayView) {
        UIImageView *overlay = [[UIImageView alloc] initWithFrame:w.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.userInteractionEnabled = NO;
        overlay.contentMode = UIViewContentModeScaleToFill;
        overlay.hidden = YES;
        self.liveOverlayView = overlay;
    }

    if (self.liveOverlayView.superview != w) {
        [self.liveOverlayView removeFromSuperview];
        if (self.floatingButton.superview == w) {
            [w insertSubview:self.liveOverlayView belowSubview:self.floatingButton];
        } else {
            [w addSubview:self.liveOverlayView];
        }
    } else if (self.floatingButton.superview == w) {
        [w insertSubview:self.liveOverlayView belowSubview:self.floatingButton];
    }

    self.liveOCRInFlight = YES;
    self.liveOCRNeedsRefresh = NO;
    NSUInteger token = ++self.liveOCRGeneration;

    NSMutableArray<UIView *> *excluded = [NSMutableArray array];
    if (self.liveOverlayView.superview == w) [excluded addObject:self.liveOverlayView];
    if (self.floatingButton.superview == w) [excluded addObject:self.floatingButton];

    [[TOPageOCRController shared] buildLiveTranslatedOverlayForWindow:w excludingViews:excluded completion:^(UIImage *resultImage) {
        self.liveOCRInFlight = NO;
        if (token != self.liveOCRGeneration) return;

        TOTranslationManager *inner = [TOTranslationManager shared];
        BOOL stillLive = (inner.translationTapMode == TOTranslationTapModeLive && self.liveTranslateEnabled);
        if (!stillLive) {
            [self removeLiveOverlayIfNeeded];
            return;
        }

        if (resultImage) {
            self.liveOverlayView.frame = w.bounds;
            self.liveOverlayView.image = resultImage;
            self.liveOverlayView.hidden = NO;
            if (self.floatingButton.superview == w) {
                [w insertSubview:self.liveOverlayView belowSubview:self.floatingButton];
                [w bringSubviewToFront:self.floatingButton];
            }
        }

        if (self.liveOCRNeedsRefresh) {
            self.liveOCRNeedsRefresh = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self requestLiveOCROverlayRefresh];
            });
        }
    }];
}

- (void)handleScrollActivity {
    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) return;

    NSTimeInterval now = CACurrentMediaTime();
    if ((now - self.liveLastScrollSignalTime) < 0.14) return;
    self.liveLastScrollSignalTime = now;

    BOOL wasScrollActive = self.liveScrollActive;
    self.liveScrollActive = YES;
    self.liveScrollInteractionUntil = MAX(self.liveScrollInteractionUntil, now + 0.55);
    self.liveScrollPendingRefresh = YES;
    if (!wasScrollActive && self.liveOverlayView) self.liveOverlayView.hidden = YES;
    [self scheduleLiveRefreshAfterScrollSettled];
}

- (void)beginLiveScrollInteraction {
    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) return;

    NSTimeInterval now = CACurrentMediaTime();
    BOOL wasScrollActive = self.liveScrollActive;
    self.liveScrollActive = YES;
    self.liveScrollInteractionUntil = MAX(self.liveScrollInteractionUntil, now + 0.55);
    self.liveScrollPendingRefresh = YES;
    if (!wasScrollActive && self.liveOverlayView) self.liveOverlayView.hidden = YES;
    [self scheduleLiveRefreshAfterScrollSettled];
}

- (void)beginLiveTouchInteraction {
    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) return;

    self.liveTouchResumeGeneration++;
    self.liveTouchActive = YES;
    self.liveScrollPendingRefresh = YES;
    if (self.liveOverlayView) self.liveOverlayView.hidden = YES;
}

- (void)endLiveTouchInteractionIfNeeded {
    if (!self.liveTouchActive) return;
    self.liveTouchActive = NO;

    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) return;
    if (self.liveScrollActive || self.liveScrollSettleTimer) return;

    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval delay = MIN(MAX(m.liveTouchResumeDelay, 0.0), 1.2);
    self.liveScrollInteractionUntil = MAX(self.liveScrollInteractionUntil, now + delay);
    NSUInteger token = ++self.liveTouchResumeGeneration;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self.liveTouchResumeGeneration) return;
        TOTranslationManager *inner = [TOTranslationManager shared];
        if (inner.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) return;
        if (self.liveTouchActive || self.liveScrollActive || self.liveScrollSettleTimer) return;
        if (CACurrentMediaTime() < self.liveScrollInteractionUntil) return;

        self.liveScrollPendingRefresh = YES;
        [self requestLiveOCROverlayRefresh];
    });
}

- (void)scheduleLiveRefreshAfterScrollSettled {
    NSDate *targetDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
    if (self.liveScrollSettleTimer) {
        self.liveScrollSettleTimer.fireDate = targetDate;
        return;
    }
    self.liveScrollSettleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                   target:self
                                                                 selector:@selector(liveScrollSettledTimerFired)
                                                                 userInfo:nil
                                                                  repeats:NO];
}

- (void)liveScrollSettledTimerFired {
    self.liveScrollSettleTimer = nil;
    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) return;
    if (CACurrentMediaTime() < self.liveScrollInteractionUntil) return;
    self.liveScrollActive = NO;
    if (!self.liveScrollPendingRefresh) return;
    self.liveScrollPendingRefresh = NO;
    [self requestLiveOCROverlayRefresh];
}

- (void)liveTranslationTimerFired {
    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) {
        [self syncLiveTranslationLoopState];
        return;
    }
    if (self.liveTouchActive || self.liveScrollActive) return;
    if (self.liveScrollSettleTimer) return;
    if (CACurrentMediaTime() < self.liveScrollInteractionUntil) return;
    [self requestLiveOCROverlayRefresh];
}

- (void)scheduleLiveTranslationBurst {
    NSUInteger token = ++self.liveTranslateBurstGeneration;
    NSArray<NSNumber *> *steps = @[@0.0, @0.75];
    for (NSNumber *delay in steps) {
        NSTimeInterval t = delay.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TOTranslationManager *m = [TOTranslationManager shared];
            if (token != self.liveTranslateBurstGeneration) return;
            if (m.translationTapMode != TOTranslationTapModeLive || !self.liveTranslateEnabled) return;
            if (CACurrentMediaTime() < self.liveScrollInteractionUntil) return;
            [self requestLiveOCROverlayRefresh];
        });
    }
}

- (void)syncLiveTranslationLoopState {
    TOTranslationManager *m = [TOTranslationManager shared];
    BOOL shouldRun = (m.translationTapMode == TOTranslationTapModeLive && self.liveTranslateEnabled);
    TOUpdateTranslationModeSnapshot(m.translationTapMode, self.liveTranslateEnabled);

    if (shouldRun) {
        BOOL didCreateTimer = NO;
        if (!self.liveTranslateTimer) {
                        self.liveTranslateTimer = [NSTimer scheduledTimerWithTimeInterval:2.1
                                                                        target:self
                                                                      selector:@selector(liveTranslationTimerFired)
                                                                      userInfo:nil
                                                                       repeats:YES];
            didCreateTimer = YES;
        }
        if (didCreateTimer) [self scheduleLiveTranslationBurst];
    } else {
        self.liveTranslateBurstGeneration++;
        self.liveOCRGeneration++;
        self.liveOCRNeedsRefresh = NO;
        self.liveOCRInFlight = NO;
        self.liveScrollPendingRefresh = NO;
        self.liveScrollActive = NO;
        self.liveLastScrollSignalTime = 0;
        self.liveTouchActive = NO;
        if (self.liveScrollSettleTimer) {
            [self.liveScrollSettleTimer invalidate];
            self.liveScrollSettleTimer = nil;
        }
        self.liveScrollInteractionUntil = 0;
        self.liveLastUIRefreshTime = 0;
        self.liveLastOCRRefreshTime = 0;
        [self removeLiveOverlayIfNeeded];
        if (self.liveTranslateTimer) {
            [self.liveTranslateTimer invalidate];
            self.liveTranslateTimer = nil;
        }
    }
}

- (void)showTranslationModeSettings {
    UIViewController *top = TOTopViewController();
    if (!top) return;

    TOTranslationManager *m = [TOTranslationManager shared];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:TOUIString(@"نمط الترجمه")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSNumber *> *modes = @[@(TOTranslationTapModeNormal), @(TOTranslationTapModeManga), @(TOTranslationTapModeLive)];
    for (NSNumber *modeNum in modes) {
        TOTranslationTapMode mode = (TOTranslationTapMode)modeNum.integerValue;
        NSString *label = TOTranslationModeLabel(mode);
        NSString *title = (m.translationTapMode == mode) ? [NSString stringWithFormat:@"%@ ✓", label] : label;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            m.translationTapMode = mode;
            m.mangaTranslationModeEnabled = (mode == TOTranslationTapModeManga);
            if (mode != TOTranslationTapModeLive) self.liveTranslateEnabled = NO;
            TOUpdateTranslationModeSnapshot(m.translationTapMode, self.liveTranslateEnabled);
            [m saveSettings];
            [self syncLiveTranslationLoopState];
            [self syncAppTranslationLoopState];

            if (mode == TOTranslationTapModeManga) {
                [self showToast:TOUIString(@"تم تفعيل نمط ترجمة المانجا")];
            } else if (mode == TOTranslationTapModeLive) {
                [self showToast:TOUIString(@"تم اختيار نمط الترجمه المباشره")];
            } else {
                [self showToast:TOUIString(@"تم تفعيل ترجمة التطبيق")];
            }
        }]];
    }

    NSTimeInterval delayMs = round(MIN(MAX(m.liveTouchResumeDelay, 0.0), 1.2) * 1000.0);
    NSString *delayTitle = [NSString stringWithFormat:@"%@ (%dms) ▸", TOUIString(@"مهلة استئناف الترجمه المباشره بعد اللمس"), (int)delayMs];
    [sheet addAction:[UIAlertAction actionWithTitle:delayTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [self showLiveTouchResumeDelaySettings];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"رجوع") style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet];
    [top presentViewController:sheet animated:YES completion:^{
        TOTranslateControllerTree(sheet);
    }];
}

- (void)showLiveTouchResumeDelaySettings {
    UIViewController *top = TOTopViewController();
    if (!top) return;

    TOTranslationManager *m = [TOTranslationManager shared];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:TOUIString(@"مهلة استئناف الترجمه المباشره بعد اللمس")
                                                                   message:TOUIString(@"كلما زادت المهلة، يصبح التمرير أكثر سلاسة")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSNumber *> *delays = @[@0.10, @0.20, @0.35, @0.50];
    for (NSNumber *value in delays) {
        NSTimeInterval option = value.doubleValue;
        BOOL selected = fabs(m.liveTouchResumeDelay - option) < 0.01;
        NSString *title = [NSString stringWithFormat:@"%dms%@", (int)lround(option * 1000.0), (selected ? @" ✓" : @"")];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            m.liveTouchResumeDelay = option;
            [m saveSettings];
            [self showToast:[NSString stringWithFormat:@"%@: %dms", TOUIString(@"تم ضبط مهلة الاستئناف"), (int)lround(option * 1000.0)]];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"رجوع") style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet];
    [top presentViewController:sheet animated:YES completion:^{
        TOTranslateControllerTree(sheet);
    }];
}

- (void)appTranslationTimerFired {
    TOTranslationManager *m = [TOTranslationManager shared];
    if (m.translationTapMode != TOTranslationTapModeNormal) {
        [self syncAppTranslationLoopState];
        return;
    }
    TOForceImmediateUILocalizationRefresh();
}

- (void)scheduleAppTranslationBurst {
    NSUInteger token = ++self.appTranslateBurstGeneration;
    NSArray<NSNumber *> *steps = @[@0.0, @0.22, @0.55];
    for (NSNumber *delay in steps) {
        NSTimeInterval t = delay.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TOTranslationManager *m = [TOTranslationManager shared];
            if (token != self.appTranslateBurstGeneration) return;
            if (m.translationTapMode != TOTranslationTapModeNormal) return;
            TOForceImmediateUILocalizationRefresh();
        });
    }
}

- (void)syncAppTranslationLoopState {
    TOTranslationManager *m = [TOTranslationManager shared];
    BOOL shouldRun = (m.translationTapMode == TOTranslationTapModeNormal);

    if (shouldRun) {
        BOOL didCreateTimer = NO;
        if (!self.appTranslateTimer) {
            self.appTranslateTimer = [NSTimer scheduledTimerWithTimeInterval:1.05
                                                                       target:self
                                                                     selector:@selector(appTranslationTimerFired)
                                                                     userInfo:nil
                                                                      repeats:YES];
            didCreateTimer = YES;
        }
        if (didCreateTimer) [self scheduleAppTranslationBurst];
        TOForceImmediateUILocalizationRefresh();
    } else {
        self.appTranslateBurstGeneration++;
        if (self.appTranslateTimer) {
            [self.appTranslateTimer invalidate];
            self.appTranslateTimer = nil;
        }
    }
}

- (void)showSettings {
    TOWarmupUILocalization();
    UIViewController *top = TOTopViewController();
    if (!top) return;
    TOTranslationManager *m = TOTranslationManager.shared;
    NSString *msg = [NSString stringWithFormat:@"%@: %@\n%@: %@", TOUIString(@"المصدر"), m.sourceLanguage, TOUIString(@"الهدف"), m.targetLanguage];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:TOUIString(@"إعدادات الترجمة")
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ▸", TOUIString(@"الترجمه من و إلى")] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIViewController *menuTop = TOTopViewController();
        if (!menuTop) return;
        UIAlertController *langSheet = [UIAlertController alertControllerWithTitle:TOUIString(@"الترجمه من و إلى")
                                                                            message:nil
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
        [langSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"الترجمه من") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self showLanguagePicker:YES]; }]];
        [langSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"الترجمة إلى") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self showLanguagePicker:NO]; }]];
        [langSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"رجوع") style:UIAlertActionStyleCancel handler:nil]];
        [self configurePopover:langSheet];
        [menuTop presentViewController:langSheet animated:YES completion:^{
            TOTranslateControllerTree(langSheet);
        }];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ▸", TOUIString(@"إعدادات الترجمة")] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIViewController *menuTop = TOTopViewController();
        if (!menuTop) return;
        TOTranslationManager *tm = TOTranslationManager.shared;
        UIAlertController *ocrSheet = [UIAlertController alertControllerWithTitle:TOUIString(@"إعدادات الترجمة")
                                                                           message:nil
                                                                    preferredStyle:UIAlertControllerStyleActionSheet];

        NSString *centerTitle = [NSString stringWithFormat:@"%@: %@", TOUIString(@"تنسيق النص: توسيط داخل الموضع"), (tm.ocrCenterTextEnabled ? TOUIString(@"مفعل") : TOUIString(@"معطل"))];
        [ocrSheet addAction:[UIAlertAction actionWithTitle:centerTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            tm.ocrCenterTextEnabled = !tm.ocrCenterTextEnabled;
            [tm saveSettings];
            [self showToast:[NSString stringWithFormat:@"%@: %@", TOUIString(@"تنسيق النص: توسيط داخل الموضع"), (tm.ocrCenterTextEnabled ? TOUIString(@"مفعل") : TOUIString(@"معطل"))]];
        }]];

        NSString *editTitle = [NSString stringWithFormat:@"%@: %@", TOUIString(@"تحرير النص بعد ترجمة OCR"), (tm.ocrEditAfterTranslateEnabled ? TOUIString(@"مفعل") : TOUIString(@"معطل"))];
        [ocrSheet addAction:[UIAlertAction actionWithTitle:editTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            tm.ocrEditAfterTranslateEnabled = !tm.ocrEditAfterTranslateEnabled;
            [tm saveSettings];
            [self showToast:[NSString stringWithFormat:@"%@: %@", TOUIString(@"تحرير النص بعد ترجمة OCR"), (tm.ocrEditAfterTranslateEnabled ? TOUIString(@"مفعل") : TOUIString(@"معطل"))]];
        }]];

        NSString *modeTitle = [NSString stringWithFormat:@"%@: %@", TOUIString(@"نمط الترجمه"), TOTranslationModeLabel((TOTranslationTapMode)tm.translationTapMode)];
        [ocrSheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ▸", modeTitle] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self showTranslationModeSettings];
        }]];

        [ocrSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"إعدادات مظهر OCR") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self showOCRAppearanceSettings]; }]];
        [ocrSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"تغيير حجم نص OCR") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self showOCRTextSizePicker]; }]];
        [ocrSheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"رجوع") style:UIAlertActionStyleCancel handler:nil]];
        [self configurePopover:ocrSheet];
        [menuTop presentViewController:ocrSheet animated:YES completion:^{
            TOTranslateControllerTree(ocrSheet);
        }];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"صفحة المطور") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self openDeveloperPage];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:TOUIString(@"إلغاء") style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet];
    [top presentViewController:sheet animated:YES completion:^{
        TOTranslateControllerTree(sheet);
    }];
}

- (void)singleTap {
    TOTranslationManager *m = [TOTranslationManager shared];
    TOTranslationTapMode mode = (TOTranslationTapMode)m.translationTapMode;
    switch (mode) {
        case TOTranslationTapModeManga:
            [self startOCRForMangaMode:YES];
            break;
        case TOTranslationTapModeLive:
            self.liveTranslateEnabled = !self.liveTranslateEnabled;
            TOUpdateTranslationModeSnapshot(m.translationTapMode, self.liveTranslateEnabled);
            [self syncLiveTranslationLoopState];
            if (self.liveTranslateEnabled) {
                [self requestLiveOCROverlayRefresh];
                [self scheduleLiveTranslationBurst];
                [self showToast:TOUIString(@"تم تفعيل نمط الترجمه المباشره")];
            } else {
                TOUpdateTranslationModeSnapshot(m.translationTapMode, NO);
                [self showToast:TOUIString(@"تم إيقاف نمط الترجمه المباشره")];
            }
            break;
        case TOTranslationTapModeNormal:
        default:
            [self syncAppTranslationLoopState];
            [self translateCurrentPage];
            break;
    }
}

- (void)doubleTap {
    self.hiddenByDoubleTap = YES;
    self.floatingButton.hidden = YES;
    [self showToast:@"تم إخفاء الأداة. انقر 3 مرات لإظهارها"];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) [self showSettings];
}

- (void)handleTripleTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized || !self.hiddenByDoubleTap) return;
    self.hiddenByDoubleTap = NO;
    self.floatingButton.hidden = NO;
    [self showToast:@"ظهرت الأداة"];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    UIWindow *w = self.attachedWindow;
    if (!w) return;

    CGPoint t = [g translationInView:w];
    CGPoint next = CGPointMake(self.floatingButton.center.x + t.x, self.floatingButton.center.y + t.y);
    self.floatingButton.center = [self clampedCenter:next inWindow:w];
    [g setTranslation:CGPointZero inView:w];

    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self animateSnapToNearestEdgeInWindow:w];
    }
}

- (void)installIfPossible {
    UIWindow *w = TOActiveWindow();
    if (!w) return;
    self.attachedWindow = w;

    if (!self.floatingButton) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(18, 140, 56, 56);
        b.layer.cornerRadius = 28;
        b.clipsToBounds = YES;
        b.backgroundColor = [UIColor colorWithRed:0.14 green:0.45 blue:0.95 alpha:1.0];
        [b setTitle:@"ترجم" forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];

        [b addTarget:self action:@selector(singleTap) forControlEvents:UIControlEventTouchUpInside];

        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap)];
        doubleTap.numberOfTapsRequired = 2;
        [b addGestureRecognizer:doubleTap];

        self.longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        self.longPress.minimumPressDuration = 0.45;
        [b addGestureRecognizer:self.longPress];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [b addGestureRecognizer:pan];

        self.floatingButton = b;
    }

    if (self.floatingButton.superview != w) {
        [self.floatingButton removeFromSuperview];
        [w addSubview:self.floatingButton];
    }

    [w bringSubviewToFront:self.floatingButton];
    self.floatingButton.hidden = self.hiddenByDoubleTap;
    [self applySavedPosition];

    if (!self.tripleTap || self.tripleTap.view != w) {
        if (self.tripleTap.view) [self.tripleTap.view removeGestureRecognizer:self.tripleTap];
        self.tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTripleTap:)];
        self.tripleTap.numberOfTapsRequired = 3;
        self.tripleTap.numberOfTouchesRequired = 1;
        self.tripleTap.cancelsTouchesInView = NO;
        [w addGestureRecognizer:self.tripleTap];
    }

    [self syncAppTranslationLoopState];
    [self syncLiveTranslationLoopState];
}

@end

%hook UILabel

- (void)setText:(NSString *)text {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(text);
        return;
    }

    %orig(text);
    TOTranslateAndApplyTextToObject(self, text, ^(NSString *translated) {
        if (![self.text isEqualToString:translated]) {
            [self setText:translated];
        }
    });
}

- (void)setAttributedText:(NSAttributedString *)text {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(text);
        return;
    }

    %orig(text);
    TOTranslateAndApplyAttributedTextToObject(self, text, ^(NSAttributedString *translated) {
        if (![[self.attributedText string] isEqualToString:[translated string]]) {
            [self setAttributedText:translated];
        }
    });
}

%end

%hook UIButton

- (void)setTitle:(NSString *)title forState:(UIControlState)state {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(title, state);
        return;
    }

    %orig(title, state);
    TOTranslateAndApplyTextToObject(self, title, ^(NSString *translated) {
        NSString *current = [self titleForState:state] ?: @"";
        if (![current isEqualToString:translated]) {
            [self setTitle:translated forState:state];
        }
    });
}

- (void)setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(title, state);
        return;
    }

    %orig(title, state);
    TOTranslateAndApplyAttributedTextToObject(self, title, ^(NSAttributedString *translated) {
        NSString *current = [[self attributedTitleForState:state] string] ?: @"";
        if (![current isEqualToString:translated.string ?: @""]) {
            [self setAttributedTitle:translated forState:state];
        }
    });
}

%end

%hook UINavigationItem

- (void)setTitle:(NSString *)title {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(title);
        return;
    }

    %orig(title);
    TOTranslateAndApplyTextToObject(self, title, ^(NSString *translated) {
        if (![[self title] isEqualToString:translated]) {
            [self setTitle:translated];
        }
    });
}

- (void)setPrompt:(NSString *)prompt {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(prompt);
        return;
    }

    %orig(prompt);
    TOTranslateAndApplyTextToObject(self, prompt, ^(NSString *translated) {
        if (![[self prompt] isEqualToString:translated]) {
            [self setPrompt:translated];
        }
    });
}

%end

%hook UITabBarItem

- (void)setTitle:(NSString *)title {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(title);
        return;
    }

    %orig(title);
    TOTranslateAndApplyTextToObject(self, title, ^(NSString *translated) {
        if (![[self title] isEqualToString:translated]) {
            [self setTitle:translated];
        }
    });
}

%end

%hook UIBarButtonItem

- (void)setTitle:(NSString *)title {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(title);
        return;
    }

    %orig(title);
    TOTranslateAndApplyTextToObject(self, title, ^(NSString *translated) {
        if (![[self title] isEqualToString:translated]) {
            [self setTitle:translated];
        }
    });
}

%end

%hook UISearchBar

- (void)setPlaceholder:(NSString *)placeholder {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(placeholder);
        return;
    }

    %orig(placeholder);
    TOTranslateAndApplyTextToObject(self, placeholder, ^(NSString *translated) {
        NSString *current = [self placeholder] ?: @"";
        if (![current isEqualToString:translated]) {
            [self setPlaceholder:translated];
        }
    });
}

- (void)setPrompt:(NSString *)prompt {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(prompt);
        return;
    }

    %orig(prompt);
    TOTranslateAndApplyTextToObject(self, prompt, ^(NSString *translated) {
        NSString *current = [self prompt] ?: @"";
        if (![current isEqualToString:translated]) {
            [self setPrompt:translated];
        }
    });
}

%end

%hook UITextField

- (void)setAttributedText:(NSAttributedString *)text {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(text);
        return;
    }

    %orig(text);
    TOTranslateAndApplyAttributedTextToObject(self, text, ^(NSAttributedString *translated) {
        NSString *current = self.attributedText.string ?: @"";
        if (![current isEqualToString:translated.string ?: @""]) {
            [self setAttributedText:translated];
        }
    });
}

- (void)setAttributedPlaceholder:(NSAttributedString *)placeholder {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(placeholder);
        return;
    }

    %orig(placeholder);
    TOTranslateAndApplyAttributedTextToObject(self, placeholder, ^(NSAttributedString *translated) {
        NSString *current = self.attributedPlaceholder.string ?: @"";
        if (![current isEqualToString:translated.string ?: @""]) {
            [self setAttributedPlaceholder:translated];
        }
    });
}

%end

%hook UITextView

- (void)setAttributedText:(NSAttributedString *)text {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(text);
        return;
    }

    %orig(text);
    TOTranslateAndApplyAttributedTextToObject(self, text, ^(NSAttributedString *translated) {
        NSString *current = self.attributedText.string ?: @"";
        if (![current isEqualToString:translated.string ?: @""]) {
            [self setAttributedText:translated];
        }
    });
}

%end

%hook UITableViewCell

- (UILabel *)textLabel {
    UILabel *label = %orig;
    if (label.text.length > 0) {
        TOTranslateAndApplyTextToObject(label, label.text, ^(NSString *translated) {
            if (![label.text isEqualToString:translated]) {
                [label setText:translated];
            }
        });
    }
    return label;
}

%end

%hook UIAlertController

- (void)setTitle:(NSString *)title {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(title);
        return;
    }

    %orig(title);
    TOTranslateAndApplyTextToObject(self, title, ^(NSString *translated) {
        if (![[self title] isEqualToString:translated]) {
            [self setTitle:translated];
        }
    });
}

- (void)setMessage:(NSString *)message {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(message);
        return;
    }

    %orig(message);
    TOTranslateAndApplyTextToObject(self, message, ^(NSString *translated) {
        if (![[self message] isEqualToString:translated]) {
            [self setMessage:translated];
        }
    });
}

- (void)addAction:(UIAlertAction *)action {
    %orig(action);
    NSString *title = [action title];
    if (title.length == 0) return;

    [[TOTranslationManager shared] translateText:title completion:^(NSString *translated) {
        if (translated.length == 0) return;
        @try {
            [action setValue:translated forKey:@"title"];
            TOForceImmediateUILocalizationRefresh();
        } @catch (__unused NSException *e) {
        }
    }];
}

%end

%hook UIViewController

- (void)setTitle:(NSString *)title {
    if ([objc_getAssociatedObject(self, kTOTranslateGuardKey) boolValue]) {
        %orig(title);
        return;
    }

    %orig(title);
    TOTranslateAndApplyTextToObject(self, title, ^(NSString *translated) {
        if (![[self title] isEqualToString:translated]) {
            [self setTitle:translated];
        }
    });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    TOTranslateControllerTree(self);
    [[TOFloatingOverlayController shared] syncAppTranslationLoopState];
}

%end

%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (self.window && TOIsLikelyTextBearingView(self) && TOIsUITranslationPipelineEnabled()) {
        TOTranslateSingleViewNode(self);
    }
}

%end

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset {
    %orig;
    if (TOIsLiveModeSessionActiveFast()) {
        static NSTimeInterval lastSignalTime = 0;
        NSTimeInterval now = CACurrentMediaTime();
        if ((now - lastSignalTime) >= 0.22) {
            lastSignalTime = now;
            [[TOFloatingOverlayController shared] beginLiveScrollInteraction];
        }
    }
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    %orig;
    if (TOIsLiveModeSessionActiveFast()) {
        static NSTimeInterval lastAnimatedSignalTime = 0;
        NSTimeInterval now = CACurrentMediaTime();
        if ((now - lastAnimatedSignalTime) >= 0.22) {
            lastAnimatedSignalTime = now;
            [[TOFloatingOverlayController shared] beginLiveScrollInteraction];
        }
    }
}

%end

%hook UIWindow

- (void)sendEvent:(UIEvent *)event {
    %orig(event);

    if (!TOIsLiveModeSessionActiveFast()) return;
    if (event.type != UIEventTypeTouches) return;

    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) {
        [[TOFloatingOverlayController shared] endLiveTouchInteractionIfNeeded];
        return;
    }

    BOOL hasActiveTouch = NO;
    for (UITouch *touch in touches) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            hasActiveTouch = YES;
            break;
        }
    }

    TOFloatingOverlayController *overlay = [TOFloatingOverlayController shared];
    if (hasActiveTouch) {
        [overlay beginLiveTouchInteraction];
    } else {
        [overlay endLiveTouchInteractionIfNeeded];
    }
}

%end

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[TOTranslationManager shared] loadSettings];
            TOInstallUIListContentConfigurationHook();
            TOFloatingOverlayController *overlay = [TOFloatingOverlayController shared];

            for (NSInteger i = 0; i < 10; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [overlay installIfPossible];
                });
            }

            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
                [overlay installIfPossible];
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
                [overlay installIfPossible];
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
                [overlay installIfPossible];
            }];
            if (@available(iOS 13.0, *)) {
                [[NSNotificationCenter defaultCenter] addObserverForName:UISceneDidActivateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
                    [overlay installIfPossible];
                }];
            }

            [overlay installIfPossible];
        });
    }
}
