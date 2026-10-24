// ============================================================================
// CarSplitVN - Tweak chia màn hình CarPlay & Bong bóng tốc độ 100% Offline
// Hỗ trợ: iOS 15.0 - 16.x (iPhone 8 A11 arm64 & arm64e Dopamine RootHide)
// Không kết nối máy chủ, không giới hạn thời hạn hay số lượng thiết bị.
// ============================================================================

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>
#import <notify.h>

#define kCSPrefsPath @"/var/mobile/Library/Preferences/vn.carsplit.roothide.plist"
#define kCSPrefsChangedNotification "vn.carsplit.roothide/prefsChanged"
#define kCSOpenCarNotification      "vn.carsplit.roothide/openCar"
#define kCSOpenPhoneNotification    "vn.carsplit.roothide/openPhone"
#define kCSCloseNotification        "vn.carsplit.roothide/close"
#define kCSCalibrateNotification    "vn.carsplit.roothide/calibrate"

// --- Khai báo Private APIs của SpringBoard & FrontBoard (iOS 15 - 16) ---
@interface CADisplay : NSObject
+ (NSArray<CADisplay *> *)displays;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSUInteger displayId;
@property (nonatomic, readonly) CGRect bounds;
@end

@interface FBSDisplayIdentity : NSObject
@end

@interface FBSDisplayConfiguration : NSObject
@property (nonatomic, readonly) FBSDisplayIdentity *identity;
@property (nonatomic, readonly) CGRect bounds;
- (instancetype)initWithCADisplay:(CADisplay *)display isMainDisplay:(BOOL)isMain;
@end

@interface UIRootSceneWindow : UIWindow
- (instancetype)initWithDisplayConfiguration:(FBSDisplayConfiguration *)config;
@end

@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *displayName;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleID;
- (NSArray<SBApplication *> *)allApplications;
@end

@interface SBSceneManager : NSObject
@property (nonatomic, readonly) FBSDisplayIdentity *displayIdentity;
- (id)fetchOrCreateApplicationSceneHandleForRequest:(id)request;
- (id)sceneIdentityForApplication:(SBApplication *)app createPrimaryIfRequired:(BOOL)create;
@end

@interface SBSceneManagerCoordinator : NSObject
+ (instancetype)sharedInstance;
+ (SBSceneManager *)mainDisplaySceneManager;
@end

@interface SBApplicationSceneHandleRequest : NSObject
+ (instancetype)defaultRequestForApplication:(SBApplication *)app
                               sceneIdentity:(id)identity
                             displayIdentity:(FBSDisplayIdentity *)displayIdentity;
@end

@interface SBDeviceApplicationSceneEntity : NSObject
- (instancetype)initWithApplicationSceneHandle:(id)handle;
- (void)clearActivationSettings;
@end

@interface SBAppViewController : UIViewController
- (instancetype)initWithIdentifier:(NSString *)identifier
         andApplicationSceneEntity:(SBDeviceApplicationSceneEntity *)entity;
- (void)setIgnoresOcclusions:(BOOL)ignores;
- (void)_setCurrentMode:(NSInteger)mode;
@end

@interface UIImage (PrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID
                                               format:(int)format
                                                scale:(CGFloat)scale;
@end

// --- Đọc/Ghi cấu hình Offline ---
static NSMutableDictionary *CSLoadPrefs(void) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:kCSPrefsPath];
    if (!dict) dict = [NSMutableDictionary dictionary];
    return dict;
}

static void CSSavePrefs(NSDictionary *dict) {
    [dict writeToFile:kCSPrefsPath atomically:YES];
}

static BOOL CSPrefBool(NSString *key, BOOL fallback) {
    NSDictionary *d = CSLoadPrefs();
    id val = d[key];
    return val ? [val boolValue] : fallback;
}

static NSInteger CSPrefInt(NSString *key, NSInteger fallback) {
    NSDictionary *d = CSLoadPrefs();
    id val = d[key];
    return val ? [val integerValue] : fallback;
}

static CGFloat CSPrefFloat(NSString *key, CGFloat fallback) {
    NSDictionary *d = CSLoadPrefs();
    id val = d[key];
    return val ? [val doubleValue] : fallback;
}

// ============================================================================
// 1. Bong bóng tốc độ HUD (CSSpeedBubbleView) - Dữ liệu GPS + Pin + Ngày giờ
// ============================================================================
@interface CSSpeedBubbleView : UIView <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locManager;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UILabel *limitLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, assign) double currentSpeedKmh;
@property (nonatomic, assign) NSInteger speedLimitKmh;
- (void)applyPreferences;
@end

@implementation CSSpeedBubbleView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(20, 24, 168, 72)])) {
        self.backgroundColor = [[UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.92] colorWithAlphaComponent:0.92];
        self.layer.cornerRadius = 22.0;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        self.clipsToBounds = YES;

        _speedLimitKmh = CSPrefInt(@"speedLimit", 60);

        // Vòng tròn biển báo giới hạn tốc độ
        _limitLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 12, 48, 48)];
        _limitLabel.backgroundColor = [UIColor whiteColor];
        _limitLabel.textColor = [UIColor blackColor];
        _limitLabel.font = [UIFont boldSystemFontOfSize:18];
        _limitLabel.textAlignment = NSTextAlignmentCenter;
        _limitLabel.layer.cornerRadius = 24.0;
        _limitLabel.layer.borderWidth = 4.5;
        _limitLabel.layer.borderColor = [UIColor systemRedColor].CGColor;
        _limitLabel.clipsToBounds = YES;
        _limitLabel.text = [NSString stringWithFormat:@"%ld", (long)_speedLimitKmh];
        [self addSubview:_limitLabel];

        // Chạm biển giới hạn để đổi nhanh mốc 50 / 60 / 80 / 100 / 120 km/h
        _limitLabel.userInteractionEnabled = YES;
        UITapGestureRecognizer *tapLimit = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cycleSpeedLimit)];
        [_limitLabel addGestureRecognizer:tapLimit];

        // Số tốc độ hiện tại
        _speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(66, 8, 62, 36)];
        _speedLabel.textColor = [UIColor whiteColor];
        _speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:30 weight:UIFontWeightBold];
        _speedLabel.textAlignment = NSTextAlignmentRight;
        _speedLabel.text = @"0";
        [self addSubview:_speedLabel];

        _unitLabel = [[UILabel alloc] initWithFrame:CGRectMake(130, 18, 32, 20)];
        _unitLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        _unitLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _unitLabel.text = @"km/h";
        [self addSubview:_unitLabel];

        // Dòng thông tin phụ: Ngày tháng + Phần trăm pin
        _metaLabel = [[UILabel alloc] initWithFrame:CGRectMake(66, 44, 96, 18)];
        _metaLabel.textColor = [UIColor colorWithRed:0.45 green:0.85 blue:1.0 alpha:1.0];
        _metaLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _metaLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_metaLabel];

        // Kéo thả bong bóng tự do trên màn hình
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        _clockTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(updateMetaLine) userInfo:nil repeats:YES];
        [self updateMetaLine];
        [self startGPS];
        [self applyPreferences];
    }
    return self;
}

- (void)startGPS {
    _locManager = [[CLLocationManager alloc] init];
    _locManager.delegate = self;
    _locManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    _locManager.distanceFilter = kCLDistanceFilterNone;
    [_locManager startUpdatingLocation];
}

- (void)cycleSpeedLimit {
    NSArray<NSNumber *> *limits = @[@50, @60, @70, @80, @90, @100, @120];
    NSUInteger idx = [limits indexOfObject:@(_speedLimitKmh)];
    _speedLimitKmh = (idx == NSNotFound || idx + 1 >= limits.count) ? 50 : [limits[idx + 1] integerValue];
    _limitLabel.text = [NSString stringWithFormat:@"%ld", (long)_speedLimitKmh];
    NSMutableDictionary *prefs = CSLoadPrefs();
    prefs[@"speedLimit"] = @(_speedLimitKmh);
    CSSavePrefs(prefs);
}

- (void)updateMetaLine {
    NSMutableArray *parts = [NSMutableArray array];
    if (CSPrefBool(@"hudDate", YES)) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"dd/MM HH:mm";
        [parts addObject:[df stringFromDate:[NSDate date]]];
    }
    if (CSPrefBool(@"hudBattery", YES)) {
        float bat = [UIDevice currentDevice].batteryLevel;
        int pct = (bat < 0) ? 100 : (int)roundf(bat * 100.0f);
        [parts addObject:[NSString stringWithFormat:@"%d%%", pct]];
    }
    _metaLabel.text = [parts componentsJoinedByString:@" · "];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (!loc) return;
    double spd = loc.speed > 0 ? (loc.speed * 3.6) : 0.0;
    _currentSpeedKmh = spd;
    int rounded = (int)round(spd);
    _speedLabel.text = [NSString stringWithFormat:@"%d", rounded];

    if (rounded > _speedLimitKmh) {
        self.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.layer.borderWidth = 2.5;
        _speedLabel.textColor = [UIColor systemRedColor];
        if (CSPrefBool(@"hudOverTone", YES)) {
            AudioServicesPlaySystemSound(1057);
        }
    } else {
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        self.layer.borderWidth = 1.5;
        _speedLabel.textColor = [UIColor whiteColor];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (!self.superview) return;
    CGPoint trans = [pan translationInView:self.superview];
    CGPoint c = CGPointMake(self.center.x + trans.x, self.center.y + trans.y);
    CGRect sb = self.superview.bounds;
    CGFloat hw = self.bounds.size.width * 0.5;
    CGFloat hh = self.bounds.size.height * 0.5;
    c.x = MAX(hw + 6, MIN(sb.size.width - hw - 6, c.x));
    c.y = MAX(hh + 6, MIN(sb.size.height - hh - 6, c.y));
    self.center = c;
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)applyPreferences {
    self.hidden = !CSPrefBool(@"hud", YES);
    CGFloat clarity = CSPrefFloat(@"hudClarity", 92.0) / 100.0;
    CGFloat scale = CSPrefFloat(@"hudScale", 100.0) / 100.0;
    self.alpha = MAX(0.3, MIN(1.0, clarity));
    self.transform = CGAffineTransformMakeScale(scale, scale);
    [self updateMetaLine];
}

@end

// ============================================================================
// 2. Bộ quản lý Không gian Chia Màn Hình CarPlay & Mô phỏng (CSWorkspace)
// ============================================================================
@interface CSWorkspace : NSObject
@property (nonatomic, strong) UIWindow *carWindow;
@property (nonatomic, strong) UIWindow *phoneSimWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) UIView *tabBarView;
@property (nonatomic, strong) CSSpeedBubbleView *speedBubble;
@property (nonatomic, strong) NSMutableArray<UIView *> *paneContainers;
@property (nonatomic, strong) NSMutableArray<SBAppViewController *> *paneControllers;
@property (nonatomic, strong) NSMutableArray<NSString *> *currentApps;
@property (nonatomic, assign) NSInteger splitCount; // 1, 2, 3, 4
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, strong) NSTimer *barHideTimer;
+ (instancetype)shared;
- (void)openOnCarOrPhone:(BOOL)onPhone;
- (void)closeWorkspace;
- (void)reloadPreferences;
- (void)showCalibrationOverlay;
@end

@implementation CSWorkspace

+ (instancetype)shared {
    static CSWorkspace *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[CSWorkspace alloc] init];
    });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _paneContainers = [NSMutableArray array];
        _paneControllers = [NSMutableArray array];
        _currentApps = [NSMutableArray array];
        _splitCount = MAX(1, CSPrefInt(@"lastSplitCount", 2));
        _splitRatio = CSPrefFloat(@"splitRatio", 0.5);

        NSArray *savedApps = CSLoadPrefs()[@"lastApps"];
        if ([savedApps isKindOfClass:[NSArray class]] && savedApps.count > 0) {
            [_currentApps addObjectsFromArray:savedApps];
        } else {
            [_currentApps addObjectsFromArray:@[@"com.google.Maps", @"com.apple.Music"]];
        }
    }
    return self;
}

- (CADisplay *)findCarPlayDisplay {
    for (CADisplay *d in [CADisplay displays]) {
        if (d.displayId != 1 && d.bounds.size.width > 300) {
            return d;
        }
    }
    return nil;
}

- (void)openOnCarOrPhone:(BOOL)onPhone {
    if (!CSPrefBool(@"enabled", YES)) return;

    UIWindow *targetWindow = nil;
    if (!onPhone) {
        CADisplay *carDisp = [self findCarPlayDisplay];
        if (carDisp) {
            FBSDisplayConfiguration *cfg = [[FBSDisplayConfiguration alloc] initWithCADisplay:carDisp isMainDisplay:NO];
            if (!_carWindow) {
                _carWindow = [[UIRootSceneWindow alloc] initWithDisplayConfiguration:cfg];
                _carWindow.windowLevel = UIWindowLevelAlert + 50.0;
                _carWindow.backgroundColor = [UIColor blackColor];
            }
            targetWindow = _carWindow;
        }
    }

    if (!targetWindow) {
        if (!_phoneSimWindow) {
            _phoneSimWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            _phoneSimWindow.windowLevel = UIWindowLevelStatusBar + 20.0;
            _phoneSimWindow.backgroundColor = [UIColor blackColor];
        }
        targetWindow = _phoneSimWindow;
    }

    [_canvasView removeFromSuperview];
    _canvasView = [[UIView alloc] initWithFrame:targetWindow.bounds];
    _canvasView.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.08 alpha:1.0];
    [targetWindow addSubview:_canvasView];
    targetWindow.hidden = NO;
    [targetWindow makeKeyAndVisible];

    [self applyZoomAndInsets];
    [self rebuildPanes];
    [self buildFloatingTabBar];

    if (!_speedBubble) {
        _speedBubble = [[CSSpeedBubbleView alloc] initWithFrame:CGRectZero];
    }
    [_canvasView addSubview:_speedBubble];
    [_speedBubble applyPreferences];
}

- (void)applyZoomAndInsets {
    if (!_canvasView || !_canvasView.superview) return;
    CGRect bounds = _canvasView.superview.bounds;
    CGFloat topInset = CSPrefFloat(@"calTop", 0);
    CGFloat bottomInset = CSPrefFloat(@"calBottom", 0);
    CGFloat leftInset = CSPrefFloat(@"calLeft", 0);
    CGFloat rightInset = CSPrefFloat(@"calRight", 0);
    CGRect usable = CGRectMake(leftInset, topInset,
                               MAX(200, bounds.size.width - leftInset - rightInset),
                               MAX(150, bounds.size.height - topInset - bottomInset));
    _canvasView.frame = usable;

    CGFloat zoom = CSPrefFloat(@"carZoom", 100.0) / 100.0;
    zoom = MAX(0.70, MIN(1.30, zoom));
    _canvasView.transform = CGAffineTransformMakeScale(zoom, zoom);
}

- (void)rebuildPanes {
    for (SBAppViewController *vc in _paneControllers) {
        if ((id)vc != [NSNull null]) {
            [vc.view removeFromSuperview];
        }
    }
    for (UIView *v in _paneContainers) {
        [v removeFromSuperview];
    }
    [_paneControllers removeAllObjects];
    [_paneContainers removeAllObjects];

    CGRect b = _canvasView.bounds;
    CGFloat gap = 4.0;
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];

    if (_splitCount == 1) {
        [frames addObject:[NSValue valueWithCGRect:b]];
    } else if (_splitCount == 2) {
        CGFloat w1 = floor((b.size.width - gap) * _splitRatio);
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, w1, b.size.height)]];
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(w1 + gap, 0, b.size.width - w1 - gap, b.size.height)]];
    } else if (_splitCount == 3) {
        CGFloat w1 = floor((b.size.width - gap) * _splitRatio);
        CGFloat h2 = floor((b.size.height - gap) * 0.5);
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, w1, b.size.height)]];
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(w1 + gap, 0, b.size.width - w1 - gap, h2)]];
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(w1 + gap, h2 + gap, b.size.width - w1 - gap, b.size.height - h2 - gap)]];
    } else {
        CGFloat w1 = floor((b.size.width - gap) * 0.5);
        CGFloat h1 = floor((b.size.height - gap) * 0.5);
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, w1, h1)]];
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(w1 + gap, 0, b.size.width - w1 - gap, h1)]];
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(0, h1 + gap, w1, b.size.height - h1 - gap)]];
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(w1 + gap, h1 + gap, b.size.width - w1 - gap, b.size.height - h1 - gap)]];
    }

    for (NSUInteger i = 0; i < frames.count; i++) {
        CGRect f = [frames[i] CGRectValue];
        UIView *container = [[UIView alloc] initWithFrame:f];
        container.backgroundColor = [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1.0];
        container.layer.cornerRadius = 14.0;
        container.clipsToBounds = YES;
        container.tag = (NSInteger)i;
        [_canvasView addSubview:container];
        [_paneContainers addObject:container];

        NSString *bundleID = (i < _currentApps.count) ? _currentApps[i] : nil;
        SBAppViewController *appVC = [self createHostControllerForBundleID:bundleID inContainer:container];
        if (appVC) {
            [_paneControllers addObject:appVC];
        } else {
            [_paneControllers addObject:(id)[NSNull null]];
            [self addAppPickerPlaceholderToPane:container index:i];
        }
    }

    if (CSPrefBool(@"restoreLast", YES)) {
        NSMutableDictionary *prefs = CSLoadPrefs();
        prefs[@"lastSplitCount"] = @(_splitCount);
        prefs[@"lastApps"] = _currentApps;
        CSSavePrefs(prefs);
    }
}

- (SBAppViewController *)createHostControllerForBundleID:(NSString *)bundleID inContainer:(UIView *)container {
    if (!bundleID || bundleID.length == 0) return nil;
    @try {
        SBApplication *app = [[NSClassFromString(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
        if (!app) return nil;
        SBSceneManager *mgr = [NSClassFromString(@"SBSceneManagerCoordinator") mainDisplaySceneManager];
        id sceneID = [mgr sceneIdentityForApplication:app createPrimaryIfRequired:YES];
        id req = [NSClassFromString(@"SBApplicationSceneHandleRequest") defaultRequestForApplication:app sceneIdentity:sceneID displayIdentity:mgr.displayIdentity];
        id handle = [mgr fetchOrCreateApplicationSceneHandleForRequest:req];
        SBDeviceApplicationSceneEntity *entity = [[NSClassFromString(@"SBDeviceApplicationSceneEntity") alloc] initWithApplicationSceneHandle:handle];
        [entity clearActivationSettings];
        SBAppViewController *vc = [[NSClassFromString(@"SBAppViewController") alloc] initWithIdentifier:@"CarSplitVN" andApplicationSceneEntity:entity];
        [vc setIgnoresOcclusions:YES];
        [vc _setCurrentMode:2]; // Live active mode
        vc.view.frame = container.bounds;
        vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:vc.view];
        return vc;
    } @catch (NSException *e) {
        return nil;
    }
}

- (void)addAppPickerPlaceholderToPane:(UIView *)container index:(NSUInteger)index {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = container.bounds;
    btn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [btn setTitle:[NSString stringWithFormat:@"+ Chọn ứng dụng (Ô %lu)", (unsigned long)(index + 1)] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    btn.tag = (NSInteger)index;
    [btn addTarget:self action:@selector(chooseAppForPaneButton:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:btn];
}

- (void)chooseAppForPaneButton:(UIButton *)sender {
    NSUInteger paneIdx = (NSUInteger)sender.tag;
    NSArray<NSString *> *candidates = @[
        @"com.google.Maps",
        @"vn.vietmap.live",
        @"com.waze.iphone",
        @"com.lumi.GOFA",
        @"com.apple.Maps",
        @"com.apple.Music",
        @"com.google.ios.youtube",
        @"com.apple.mobilesafari"
    ];
    NSString *cur = (paneIdx < _currentApps.count) ? _currentApps[paneIdx] : @"";
    NSUInteger nextIdx = ([candidates indexOfObject:cur] + 1) % candidates.count;
    while (_currentApps.count <= paneIdx) {
        [_currentApps addObject:@"com.apple.Maps"];
    }
    _currentApps[paneIdx] = candidates[nextIdx];
    [self rebuildPanes];
    [_canvasView bringSubviewToFront:_tabBarView];
    if (_speedBubble) [_canvasView bringSubviewToFront:_speedBubble];
}

// --- Thanh tab điều khiển tự ẩn ---
- (void)buildFloatingTabBar {
    [_tabBarView removeFromSuperview];
    CGFloat barW = 340.0;
    CGFloat barH = 46.0;
    CGRect cb = _canvasView.bounds;
    _tabBarView = [[UIView alloc] initWithFrame:CGRectMake((cb.size.width - barW) * 0.5, cb.size.height - barH - 12.0, barW, barH)];
    _tabBarView.backgroundColor = [UIColor colorWithRed:0.11 green:0.12 blue:0.16 alpha:0.94];
    _tabBarView.layer.cornerRadius = 23.0;
    _tabBarView.layer.borderWidth = 1.0;
    _tabBarView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;

    NSArray<NSString *> *titles = @[@"1 Ô", @"2 Ô", @"3 Ô", @"4 Ô", @"Đảo", @"Đóng"];
    CGFloat btnW = barW / titles.count;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(i * btnW, 0, btnW, barH);
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(tabBarButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tabBarView addSubview:b];
    }
    [_canvasView addSubview:_tabBarView];
    [self scheduleTabBarAutoHide];
}

- (void)tabBarButtonTapped:(UIButton *)sender {
    _tabBarView.alpha = 1.0;
    if (sender.tag >= 0 && sender.tag <= 3) {
        _splitCount = sender.tag + 1;
        [self rebuildPanes];
        [_canvasView bringSubviewToFront:_tabBarView];
        if (_speedBubble) [_canvasView bringSubviewToFront:_speedBubble];
    } else if (sender.tag == 4 && _currentApps.count >= 2) {
        [_currentApps exchangeObjectAtIndex:0 withObjectAtIndex:1];
        [self rebuildPanes];
        [_canvasView bringSubviewToFront:_tabBarView];
        if (_speedBubble) [_canvasView bringSubviewToFront:_speedBubble];
    } else if (sender.tag == 5) {
        [self closeWorkspace];
        return;
    }
    [self scheduleTabBarAutoHide];
}

- (void)scheduleTabBarAutoHide {
    [_barHideTimer invalidate];
    if (!CSPrefBool(@"autoHideBar", YES)) {
        _tabBarView.alpha = 1.0;
        return;
    }
    NSInteger delay = CSPrefInt(@"barHideDelay", 5);
    _barHideTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(3, delay) repeats:NO block:^(NSTimer * _Nonnull timer) {
        [UIView animateWithDuration:0.35 animations:^{
            self.tabBarView.alpha = 0.12;
        }];
    }];
}

- (void)showCalibrationOverlay {
    if (!_canvasView) [self openOnCarOrPhone:NO];
    UIView *calView = [[UIView alloc] initWithFrame:_canvasView.bounds];
    calView.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.95 alpha:0.25];
    calView.layer.borderColor = [UIColor systemCyanColor].CGColor;
    calView.layer.borderWidth = 4.0;
    calView.layer.cornerRadius = 12.0;

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.frame = CGRectMake((calView.bounds.size.width - 140) * 0.5, (calView.bounds.size.height - 44) * 0.5, 140, 44);
    doneBtn.backgroundColor = [UIColor systemBlueColor];
    doneBtn.layer.cornerRadius = 12.0;
    [doneBtn setTitle:@"Lưu khung xe" forState:UIControlStateNormal];
    [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [doneBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [calView removeFromSuperview];
    }] forControlEvents:UIControlEventTouchUpInside];
    [calView addSubview:doneBtn];
    [_canvasView addSubview:calView];
}

- (void)closeWorkspace {
    [_barHideTimer invalidate];
    for (SBAppViewController *vc in _paneControllers) {
        if ((id)vc != [NSNull null]) {
            [vc _setCurrentMode:0];
            [vc.view removeFromSuperview];
        }
    }
    [_paneControllers removeAllObjects];
    [_paneContainers removeAllObjects];
    [_canvasView removeFromSuperview];
    _canvasView = nil;
    if (_carWindow) _carWindow.hidden = YES;
    if (_phoneSimWindow) _phoneSimWindow.hidden = YES;
}

- (void)reloadPreferences {
    [self applyZoomAndInsets];
    if (_speedBubble) [_speedBubble applyPreferences];
    [self scheduleTabBarAutoHide];
}

@end

// ============================================================================
// 3. Hooks vào SpringBoard (Giữ ứng dụng chạy khi khóa màn hình iPhone)
// ============================================================================
%hook SBSuspendedUnderLockManager

- (BOOL)_shouldBeBackgroundUnderLockForScene:(id)scene withSettings:(id)settings {
    if ([CSWorkspace shared].canvasView != nil) {
        return NO; // Giữ các ứng dụng đang chia màn hình hoạt động mượt khi iPhone khóa màn hình
    }
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
            return;
        }
        %init;

        int t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0;
        notify_register_dispatch(kCSPrefsChangedNotification, &t1, dispatch_get_main_queue(), ^(int token) {
            [[CSWorkspace shared] reloadPreferences];
        });
        notify_register_dispatch(kCSOpenCarNotification, &t2, dispatch_get_main_queue(), ^(int token) {
            [[CSWorkspace shared] openOnCarOrPhone:NO];
        });
        notify_register_dispatch(kCSOpenPhoneNotification, &t3, dispatch_get_main_queue(), ^(int token) {
            [[CSWorkspace shared] openOnCarOrPhone:YES];
        });
        notify_register_dispatch(kCSCloseNotification, &t4, dispatch_get_main_queue(), ^(int token) {
            [[CSWorkspace shared] closeWorkspace];
        });
        notify_register_dispatch(kCSCalibrateNotification, &t5, dispatch_get_main_queue(), ^(int token) {
            [[CSWorkspace shared] showCalibrationOverlay];
        });
    }
}
