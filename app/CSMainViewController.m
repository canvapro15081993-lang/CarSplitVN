// ============================================================================
// Giao diện ứng dụng CarSplitVN (Dark Mode - Giống hệt thiết kế "Trên xe")
// Hoạt động 100% Offline, không kiểm tra máy chủ, không khóa thời hạn.
// ============================================================================

#import "CSMainViewController.h"
#import <notify.h>

#define kCSPrefsPath @"/var/mobile/Library/Preferences/vn.carsplit.roothide.plist"
#define kCSPrefsChangedNotification "vn.carsplit.roothide/prefsChanged"
#define kCSOpenCarNotification      "vn.carsplit.roothide/openCar"
#define kCSOpenPhoneNotification    "vn.carsplit.roothide/openPhone"
#define kCSCloseNotification        "vn.carsplit.roothide/close"
#define kCSCalibrateNotification    "vn.carsplit.roothide/calibrate"

static NSMutableDictionary *CSAppLoadPrefs(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:kCSPrefsPath];
    return d ? d : [NSMutableDictionary dictionary];
}

static void CSAppSetPref(NSString *key, id value) {
    NSMutableDictionary *d = CSAppLoadPrefs();
    if (value) d[key] = value;
    else [d removeObjectForKey:key];
    [d writeToFile:kCSPrefsPath atomically:YES];
    notify_post(kCSPrefsChangedNotification);
}

static BOOL CSAppBool(NSString *key, BOOL def) {
    id v = CSAppLoadPrefs()[key];
    return v ? [v boolValue] : def;
}

static NSInteger CSAppInt(NSString *key, NSInteger def) {
    id v = CSAppLoadPrefs()[key];
    return v ? [v integerValue] : def;
}

// ============================================================================
// Tab 2: "Trên xe" (Giống hệt giao diện trong ảnh chụp của bạn)
// ============================================================================
@implementation CSDriveSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trên xe";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.09 alpha:1.0];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3; // 0: CARPLAY, 1: THANH TAB, 2: Màn hình xe / Bong bóng tốc độ / Mở nhanh / Ứng dụng
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 2;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"CARPLAY";
    if (section == 1) return @"THANH TAB";
    return nil;
}

- (UIView *)badgeIconWithSymbol:(NSString *)symbol bgColor:(UIColor *)bgColor {
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    box.backgroundColor = bgColor;
    box.layer.cornerRadius = 7.0;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    iv.tintColor = [UIColor whiteColor];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(5, 5, 20, 20);
    [box addSubview:iv];
    return box;
}

- (UIGraphicsImageRenderer *)iconRenderer {
    return [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(30, 30)];
}

- (UIImage *)renderedBadge:(NSString *)symbol color:(UIColor *)color {
    return [[self iconRenderer] imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 30, 30) cornerRadius:7.0];
        [color setFill];
        [path fill];
        UIImage *sym = [[UIImage systemImageNamed:symbol] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        [sym drawInRect:CGRectMake(5, 5, 20, 20)];
    }];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];

    if (indexPath.section == 0) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.onTintColor = [UIColor systemGreenColor];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Mở khi kết nối CarPlay";
            cell.imageView.image = [self renderedBadge:@"car.fill" color:[UIColor systemBlueColor]];
            sw.on = CSAppBool(@"autoOpen", YES);
            sw.tag = 100;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Mở lại bố cục lần cuối";
            cell.imageView.image = [self renderedBadge:@"arrow.counterclockwise" color:[UIColor systemIndigoColor]];
            sw.on = CSAppBool(@"restoreLast", YES);
            sw.tag = 101;
        } else {
            cell.textLabel.text = @"Về iPhone khi rút CarPlay";
            cell.imageView.image = [self renderedBadge:@"iphone" color:[UIColor systemGreenColor]];
            sw.on = CSAppBool(@"unplugToPhone", YES);
            sw.tag = 102;
        }
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Thanh tab tự ẩn";
            cell.imageView.image = [self renderedBadge:@"dock.rectangle" color:[UIColor systemGrayColor]];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.onTintColor = [UIColor systemGreenColor];
            sw.on = CSAppBool(@"autoHideBar", YES);
            sw.tag = 200;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Ẩn sau";
            cell.imageView.image = [self renderedBadge:@"clock.fill" color:[UIColor systemGrayColor]];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld giây", (long)CSAppInt(@"barHideDelay", 5)];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Màn hình xe";
            cell.imageView.image = [self renderedBadge:@"rectangle.inset.filled" color:[UIColor systemBlueColor]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Bong bóng tốc độ";
            cell.imageView.image = [self renderedBadge:@"speedometer" color:[UIColor systemOrangeColor]];
            cell.detailTextLabel.text = CSAppBool(@"hud", YES) ? @"Bật" : @"Tắt";
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Mở nhanh";
            cell.imageView.image = [self renderedBadge:@"sparkles" color:[UIColor systemCyanColor]];
        } else {
            cell.textLabel.text = @"Ứng dụng";
            cell.imageView.image = [self renderedBadge:@"square.grid.2x2.fill" color:[UIColor systemPurpleColor]];
            cell.detailTextLabel.text = @"Tất cả";
        }
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag == 100) CSAppSetPref(@"autoOpen", @(sender.isOn));
    else if (sender.tag == 101) CSAppSetPref(@"restoreLast", @(sender.isOn));
    else if (sender.tag == 102) CSAppSetPref(@"unplugToPhone", @(sender.isOn));
    else if (sender.tag == 200) CSAppSetPref(@"autoHideBar", @(sender.isOn));
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 1) {
        NSArray<NSNumber *> *delays = @[@3, @5, @10, @30];
        NSInteger cur = CSAppInt(@"barHideDelay", 5);
        NSUInteger idx = [delays indexOfObject:@(cur)];
        NSInteger next = (idx == NSNotFound || idx + 1 >= delays.count) ? 3 : [delays[idx + 1] integerValue];
        CSAppSetPref(@"barHideDelay", @(next));
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        notify_post(kCSCalibrateNotification);
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        BOOL cur = CSAppBool(@"hud", YES);
        CSAppSetPref(@"hud", @(!cur));
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath.section == 2 && indexPath.row == 2) {
        notify_post(kCSOpenCarNotification);
    }
}

@end

// ============================================================================
// Tab 1: "Trang chủ" (Bật/tắt nhanh & Trạng thái Offline hoàn toàn)
// ============================================================================
@implementation CSHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"CarSplitVN";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.09 alpha:1.0];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 120, self.view.bounds.size.width - 32, 96)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:1.0];
    card.layer.cornerRadius = 18.0;

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 220, 26)];
    titleLbl.text = @"Kích hoạt CarSplitVN";
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.font = [UIFont boldSystemFontOfSize:19];
    [card addSubview:titleLbl];

    UILabel *subLbl = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, 240, 22)];
    subLbl.text = @"Chế độ Offline vĩnh viễn · Không máy chủ";
    subLbl.textColor = [UIColor systemGreenColor];
    subLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [card addSubview:subLbl];

    UISwitch *enableSw = [[UISwitch alloc] initWithFrame:CGRectMake(card.bounds.size.width - 70, 32, 51, 31)];
    enableSw.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    enableSw.onTintColor = [UIColor systemGreenColor];
    enableSw.on = CSAppBool(@"enabled", YES);
    [enableSw addTarget:self action:@selector(toggleEnabled:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:enableSw];

    [self.view addSubview:card];
}

- (void)toggleEnabled:(UISwitch *)sender {
    CSAppSetPref(@"enabled", @(sender.isOn));
    if (!sender.isOn) notify_post(kCSCloseNotification);
}

@end

// ============================================================================
// Tab 3: "Mô phỏng" (Mở thử giao diện chia màn hình ngay trên iPhone 8)
// ============================================================================
@implementation CSSimulateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Mô phỏng";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.09 alpha:1.0];

    UIButton *simBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    simBtn.frame = CGRectMake(24, 150, self.view.bounds.size.width - 48, 54);
    simBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    simBtn.backgroundColor = [UIColor systemBlueColor];
    simBtn.layer.cornerRadius = 16.0;
    [simBtn setTitle:@"Mở chia màn hình thử trên iPhone" forState:UIControlStateNormal];
    [simBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    simBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [simBtn addTarget:self action:@selector(startSim) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:simBtn];
}

- (void)startSim {
    notify_post(kCSOpenPhoneNotification);
}

@end

// ============================================================================
// TabBar Chính (3 Tab: Trang chủ - Trên xe - Mô phỏng, đã bỏ tab Tài khoản/Server)
// ============================================================================
@implementation CSMainTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:[[CSHomeViewController alloc] init]];
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trang chủ" image:[UIImage systemImageNamed:@"house.fill"] tag:0];

    UINavigationController *driveNav = [[UINavigationController alloc] initWithRootViewController:[[CSDriveSettingsViewController alloc] init]];
    driveNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trên xe" image:[UIImage systemImageNamed:@"car.fill"] tag:1];

    UINavigationController *simNav = [[UINavigationController alloc] initWithRootViewController:[[CSSimulateViewController alloc] init]];
    simNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Mô phỏng" image:[UIImage systemImageNamed:@"play.tv.fill"] tag:2];

    self.viewControllers = @[homeNav, driveNav, simNav];
    self.selectedIndex = 1; // Mở mặc định vào tab "Trên xe"
}

@end
