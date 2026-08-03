#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
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
static NSString * const kTOOCRManualHueKey = @"to_ocr_manual_hue";
static NSString * const kTOOCRManualSaturationKey = @"to_ocr_manual_saturation";
static NSString * const kTOOCRBackgroundAlphaKey = @"to_ocr_background_alpha";
static NSString * const kTOOCRBackgroundHueKey = @"to_ocr_background_hue";
static NSString * const kTOOCRBackgroundSaturationKey = @"to_ocr_background_saturation";

static BOOL TOShouldTranslateText(NSString *text) {
    if (text.length == 0) return NO;
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trim.length > 0 && trim.length <= 2500;
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

@interface TOTranslationManager : NSObject
@property (nonatomic, copy) NSString *sourceLanguage;
@property (nonatomic, copy) NSString *targetLanguage;
@property (nonatomic, strong) NSCache<NSString *, NSString *> *cache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *persistentCache;

@property (nonatomic, assign) CGFloat ocrTextScale;
@property (nonatomic, assign) BOOL ocrAutoColorEnabled;
@property (nonatomic, assign) CGFloat ocrManualHue;
@property (nonatomic, assign) CGFloat ocrManualSaturation;
@property (nonatomic, assign) CGFloat ocrBackgroundAlpha;
@property (nonatomic, assign) CGFloat ocrBackgroundHue;
@property (nonatomic, assign) CGFloat ocrBackgroundSaturation;

+ (instancetype)shared;
- (void)loadSettings;
- (void)saveSettings;
- (UIColor *)ocrManualUIColor;
- (UIColor *)ocrBackgroundUIColor;
- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated))completion;
@end

@implementation TOTranslationManager

+ (instancetype)shared {
    static TOTranslationManager *m;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        m = [TOTranslationManager new];
        m.cache = [NSCache new];
        m.persistentCache = [NSMutableDictionary new];
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
        [self.persistentCache removeAllObjects];
        [self.persistentCache addEntriesFromDictionary:stored];
    }

    CGFloat scale = [d doubleForKey:kTOOCRTextScaleKey];
    self.ocrTextScale = (scale >= 0.7 && scale <= 2.0) ? scale : 1.0;

    NSNumber *autoColor = [d objectForKey:kTOOCRTextAutoColorEnabledKey];
    self.ocrAutoColorEnabled = autoColor ? [autoColor boolValue] : YES;

    CGFloat hue = [d doubleForKey:kTOOCRManualHueKey];
    CGFloat sat = [d doubleForKey:kTOOCRManualSaturationKey];
    self.ocrManualHue = (hue >= 0.0 && hue <= 1.0) ? hue : 0.14;
    self.ocrManualSaturation = (sat >= 0.0 && sat <= 1.0) ? sat : 0.75;

    CGFloat bg = [d doubleForKey:kTOOCRBackgroundAlphaKey];
    self.ocrBackgroundAlpha = (bg >= 0.0 && bg <= 1.0) ? bg : 0.65;

    CGFloat bgHue = [d doubleForKey:kTOOCRBackgroundHueKey];
    CGFloat bgSat = [d doubleForKey:kTOOCRBackgroundSaturationKey];
    self.ocrBackgroundHue = (bgHue >= 0.0 && bgHue <= 1.0) ? bgHue : 0.0;
    self.ocrBackgroundSaturation = (bgSat >= 0.0 && bgSat <= 1.0) ? bgSat : 0.0;
}

- (void)saveSettings {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:self.sourceLanguage ?: @"auto" forKey:kTOSourceLanguageKey];
    [d setObject:self.targetLanguage ?: @"ar" forKey:kTOTargetLanguageKey];
    [d setObject:self.persistentCache ?: @{} forKey:kTOTranslationCacheKey];

    [d setDouble:self.ocrTextScale forKey:kTOOCRTextScaleKey];
    [d setBool:self.ocrAutoColorEnabled forKey:kTOOCRTextAutoColorEnabledKey];
    [d setDouble:MIN(MAX(self.ocrManualHue, 0.0), 1.0) forKey:kTOOCRManualHueKey];
    [d setDouble:MIN(MAX(self.ocrManualSaturation, 0.0), 1.0) forKey:kTOOCRManualSaturationKey];
    [d setDouble:MIN(MAX(self.ocrBackgroundAlpha, 0.0), 1.0) forKey:kTOOCRBackgroundAlphaKey];
    [d setDouble:MIN(MAX(self.ocrBackgroundHue, 0.0), 1.0) forKey:kTOOCRBackgroundHueKey];
    [d setDouble:MIN(MAX(self.ocrBackgroundSaturation, 0.0), 1.0) forKey:kTOOCRBackgroundSaturationKey];
    [d synchronize];
}

- (UIColor *)ocrManualUIColor {
    CGFloat h = MIN(MAX(self.ocrManualHue, 0.0), 1.0);
    CGFloat s = MIN(MAX(self.ocrManualSaturation, 0.0), 1.0);
    return [UIColor colorWithHue:h saturation:s brightness:1.0 alpha:1.0];
}

- (UIColor *)ocrBackgroundUIColor {
    CGFloat h = MIN(MAX(self.ocrBackgroundHue, 0.0), 1.0);
    CGFloat s = MIN(MAX(self.ocrBackgroundSaturation, 0.0), 1.0);
    return [UIColor colorWithHue:h saturation:s brightness:0.28 alpha:1.0];
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
    if (!TOShouldTranslateText(text)) {
        if (completion) completion(text ?: @"");
        return;
    }

    NSString *source = self.sourceLanguage ?: @"auto";
    NSString *target = self.targetLanguage ?: @"ar";
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@|%@", source, target, text];
    NSString *cached = [self.cache objectForKey:cacheKey] ?: self.persistentCache[cacheKey];
    if (cached.length > 0) {
        if (completion) completion(cached);
        return;
    }

    NSString *sl = source;
    if ([sl isEqualToString:@"auto"]) {
        NSString *detected = [self detectedLanguage:text];
        if (detected.length > 0) sl = detected;
    }

    NSString *q = [text stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    NSString *u = [NSString stringWithFormat:@"https://translate.googleapis.com/translate_a/single?client=gtx&sl=%@&tl=%@&dt=t&q=%@", sl, target, q];
    NSURL *url = [NSURL URLWithString:u];
    if (!url) {
        if (completion) completion(text);
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *result = text;
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
                    if (combined.length > 0) result = combined;
                }
            }
        }

        [self.cache setObject:result forKey:cacheKey];
        if (result.length > 0) {
            self.persistentCache[cacheKey] = result;
            if (self.persistentCache.count > 500) {
                NSString *first = self.persistentCache.allKeys.firstObject;
                if (first) [self.persistentCache removeObjectForKey:first];
            }
            [self saveSettings];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result);
        });
    }] resume];
}

@end

static void TOTranslateViewTree(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01) return;

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        [[TOTranslationManager shared] translateText:label.text completion:^(NSString *translated) {
            if (translated.length > 0) label.text = translated;
        }];
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        [[TOTranslationManager shared] translateText:[button titleForState:UIControlStateNormal] completion:^(NSString *translated) {
            if (translated.length > 0) [button setTitle:translated forState:UIControlStateNormal];
        }];
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        [[TOTranslationManager shared] translateText:tf.text completion:^(NSString *translated) {
            if (translated.length > 0) tf.text = translated;
        }];
        [[TOTranslationManager shared] translateText:tf.placeholder completion:^(NSString *translated) {
            if (translated.length > 0) tf.placeholder = translated;
        }];
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        [[TOTranslationManager shared] translateText:tv.text completion:^(NSString *translated) {
            if (translated.length > 0) tv.text = translated;
        }];
    }

    if (view.accessibilityLabel.length > 0) {
        NSString *a11y = view.accessibilityLabel;
        [[TOTranslationManager shared] translateText:a11y completion:^(NSString *translated) {
            if (translated.length > 0) view.accessibilityLabel = translated;
        }];
    }

    for (UIView *sub in view.subviews) TOTranslateViewTree(sub);
}

@interface TOOCRResultsViewController : UIViewController
@property (nonatomic, strong) UIImage *screenshot;
@end

@implementation TOOCRResultsViewController
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

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(12, 88, self.view.bounds.size.width - 24, self.view.bounds.size.height - 104)];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.image = self.screenshot;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.layer.cornerRadius = 12;
    imageView.clipsToBounds = YES;
    imageView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.04];
    [self.view addSubview:imageView];
}

- (void)closePressed { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface TOPageOCRController : NSObject
+ (instancetype)shared;
- (void)presentOCRForWindow:(UIWindow *)window completion:(void (^)(void))completion;
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

- (UIImage *)renderTranslatedTextOnImage:(UIImage *)image items:(NSArray<NSDictionary *> *)items {
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
        CGFloat fontSize = MAX(10.0, MIN(34.0, rect.size.height * 0.72 * scale));
        UIFont *font = [UIFont boldSystemFontOfSize:fontSize];

        UIColor *fg = nil;
        if (m.ocrAutoColorEnabled) fg = item[@"detectedColor"];
        if (!fg) fg = [m ocrManualUIColor];

        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: fg
        };

        CGRect bgRect = CGRectInset(rect, -2.0, -1.0);
        UIColor *bgColor = [[m ocrBackgroundUIColor] colorWithAlphaComponent:MIN(MAX(m.ocrBackgroundAlpha, 0.0), 1.0)];
        [bgColor setFill];
        UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:bgRect cornerRadius:3.0];
        [bg fill];

        [text drawWithRect:CGRectInset(rect, 1.0, 0.0)
                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
               attributes:attrs
                  context:nil];
    }

    UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rendered ?: image;
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
                        [items addObject:@{
                            @"source": top.string,
                            @"rect": [NSValue valueWithCGRect:rect],
                            @"detectedColor": autoColor ?: UIColor.whiteColor
                        }];
                    }
                }
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
                [[TOTranslationManager shared] translateText:line completion:^(NSString *text) {
                    item[@"translated"] = text.length > 0 ? text : line;
                    dispatch_group_leave(g);
                }];
            }

            dispatch_group_notify(g, dispatch_get_main_queue(), ^{
                UIImage *rendered = [self renderTranslatedTextOnImage:image items:translated];
                TOOCRResultsViewController *vc = [TOOCRResultsViewController new];
                vc.modalPresentationStyle = UIModalPresentationFullScreen;
                vc.screenshot = rendered;
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
+ (instancetype)shared;
- (void)installIfPossible;
- (void)showToast:(NSString *)message;
- (void)startOCR;
- (void)showOCRAppearanceSettings;
- (void)showOCRTextSizePicker;
- (void)showLanguagePicker:(BOOL)isSource;
- (void)openDeveloperPage;
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

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(14, 426, card.bounds.size.width - 28, 32)];
    hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hint.numberOfLines = 1;
    hint.text = @"يمكنك ضبط لون الخلفية وشفافيتها بدون التأثير على بقية الوظائف.";
    hint.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.84];
    hint.font = [UIFont systemFontOfSize:12];
    [card addSubview:hint];

    [self refreshUI];
}

- (void)refreshUI {
    TOTranslationManager *m = [TOTranslationManager shared];
    m.ocrAutoColorEnabled = self.autoColorSwitch.on;
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
    [translationCard addSubview:[self sectionButtonWithTitle:@"اختيار لغة المصدر" y:44 action:@selector(sourcePressed)]];
    [translationCard addSubview:[self sectionButtonWithTitle:@"اختيار لغة الهدف" y:88 action:@selector(targetPressed)]];
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

- (void)closePressed { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)sourcePressed { [self.overlayController showLanguagePicker:YES]; }
- (void)targetPressed { [self.overlayController showLanguagePicker:NO]; }
- (void)startOCRPressed { [self.overlayController startOCR]; }
- (void)appearancePressed { [self.overlayController showOCRAppearanceSettings]; }
- (void)sizePressed { [self.overlayController showOCRTextSizePicker]; }
- (void)developerPressed { [self.overlayController openDeveloperPage]; }

@end

@implementation TOFloatingOverlayController

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

- (void)showLanguagePicker:(BOOL)isSource {
    UIViewController *top = TOTopViewController();
    if (!top) return;
    TOTranslationManager *m = TOTranslationManager.shared;
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:(isSource ? @"اختر لغة المصدر" : @"اختر لغة الهدف") message:@"يمكنك تغيير اللغة في أي وقت" preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary<NSString *, NSString *> *> *langs = @[
        @{@"code": @"auto", @"name": @"اكتشاف تلقائي"},
        @{@"code": @"ar", @"name": @"العربية"},
        @{@"code": @"en", @"name": @"الإنجليزية"},
        @{@"code": @"fr", @"name": @"الفرنسية"},
        @{@"code": @"tr", @"name": @"التركية"},
        @{@"code": @"es", @"name": @"الإسبانية"},
        @{@"code": @"de", @"name": @"الألمانية"},
        @{@"code": @"it", @"name": @"الإيطالية"},
        @{@"code": @"ru", @"name": @"الروسية"}
    ];

    for (NSDictionary *item in langs) {
        NSString *code = item[@"code"];
        NSString *name = item[@"name"];
        if (!isSource && [code isEqualToString:@"auto"]) continue;

        NSString *current = isSource ? m.sourceLanguage : m.targetLanguage;
        NSString *title = [current isEqualToString:code] ? [NSString stringWithFormat:@"%@ ✓", name] : name;
        [picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (isSource) m.sourceLanguage = code; else m.targetLanguage = code;
            [m saveSettings];
            [self showToast:[NSString stringWithFormat:@"%@: %@", isSource ? @"المصدر" : @"الهدف", name]];
        }]];
    }

    [picker addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:picker];
    [top presentViewController:picker animated:YES completion:nil];
}

- (void)showOCRTextSizePicker {
    UIViewController *top = TOTopViewController();
    if (!top) return;
    TOTranslationManager *m = TOTranslationManager.shared;

    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"حجم نص OCR"
                                                                     message:[NSString stringWithFormat:@"الحجم الحالي: %.0f%%", m.ocrTextScale * 100.0]
                                                              preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary *> *sizes = @[
        @{@"name": @"صغير 80%", @"value": @(0.8)},
        @{@"name": @"عادي 100%", @"value": @(1.0)},
        @{@"name": @"متوسط 120%", @"value": @(1.2)},
        @{@"name": @"كبير 140%", @"value": @(1.4)},
        @{@"name": @"كبير جدًا 170%", @"value": @(1.7)}
    ];

    for (NSDictionary *item in sizes) {
        NSString *name = item[@"name"];
        CGFloat value = [item[@"value"] doubleValue];
        NSString *title = fabs(m.ocrTextScale - value) < 0.01 ? [NSString stringWithFormat:@"%@ ✓", name] : name;
        [picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            m.ocrTextScale = value;
            [m saveSettings];
            [self showToast:[NSString stringWithFormat:@"حجم نص OCR: %@", name]];
        }]];
    }

    [picker addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:picker];
    [top presentViewController:picker animated:YES completion:nil];
}

- (void)showOCRAppearanceSettings {
    UIViewController *top = TOTopViewController();
    if (!top) return;
    TOOCRAppearanceViewController *vc = [TOOCRAppearanceViewController new];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.overlayController = self;
    [top presentViewController:vc animated:YES completion:nil];
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

- (void)startOCR {
    UIWindow *w = self.attachedWindow ?: TOActiveWindow();
    if (!w) {
        [self showToast:@"لا توجد نافذة نشطة"];
        return;
    }

    self.floatingButton.hidden = YES;
    [self showToast:@"جارٍ التقاط الصفحة وتحليلها..."];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[TOPageOCRController shared] presentOCRForWindow:w completion:^{
            self.floatingButton.hidden = NO;
        }];
    });
}

- (void)translateCurrentPage {
    UIWindow *w = self.attachedWindow ?: TOActiveWindow();
    if (!w) return;
    TOTranslateViewTree(w);
    if (w.rootViewController) TOTranslateViewTree(w.rootViewController.view);
    [self showToast:@"تمت محاولة الترجمة"];
}

- (void)showSettings {
    UIViewController *top = TOTopViewController();
    if (!top) return;
    TOTranslationSettingsViewController *vc = [TOTranslationSettingsViewController new];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.overlayController = self;
    [top presentViewController:vc animated:YES completion:nil];
}

- (void)singleTap { [self translateCurrentPage]; }

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
}

@end

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[TOTranslationManager shared] loadSettings];
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
