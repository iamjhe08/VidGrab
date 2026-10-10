#import "VGBrowserHistory.h"
#import "VGTheme.h"

static NSString *const kKey = @"vgBrowserHistory";
static const NSUInteger kMax = 500;

@implementation VGBrowserHistory

+ (NSArray<NSDictionary *> *)entries {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:kKey];
    return [saved isKindOfClass:NSArray.class] ? saved : @[];
}

+ (NSDictionary *)latest { return self.entries.firstObject; }

+ (void)save:(NSArray *)list { [NSUserDefaults.standardUserDefaults setObject:list forKey:kKey]; }

+ (void)noteURL:(NSURL *)url title:(NSString *)title {
    NSString *scheme = url.scheme.lowercaseString;
    if (!url.host.length || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;
    NSString *link = url.absoluteString;
    NSString *name = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *list = [self.entries mutableCopy];
    for (NSUInteger i = 0; i < list.count; i++) {      // the same page again: move it to the top instead of repeating it
        if ([list[i][@"url"] isEqualToString:link]) {
            if (!name.length) name = list[i][@"title"];
            [list removeObjectAtIndex:i];
            break;
        }
    }
    [list insertObject:@{@"url": link, @"title": name ?: @"", @"time": @(NSDate.date.timeIntervalSince1970)} atIndex:0];
    while (list.count > kMax) [list removeLastObject];
    [self save:list];
}

+ (void)removeAtIndex:(NSUInteger)index {
    NSMutableArray *list = [self.entries mutableCopy];
    if (index < list.count) { [list removeObjectAtIndex:index]; [self save:list]; }
}

+ (void)clear { [NSUserDefaults.standardUserDefaults removeObjectForKey:kKey]; }

@end

// MARK: History screen

@interface VGHistoryViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *shown;      // after the search filter
@property (nonatomic, copy) NSString *query;
@end

@implementation VGHistoryViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"History";
    self.view.backgroundColor = VGBackground;
    self.tableView.backgroundColor = VGBackground;
    self.tableView.separatorColor = VGStroke;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear all" style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
    UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
    sc.searchResultsUpdater = self;
    sc.obscuresBackgroundDuringPresentation = NO;
    sc.searchBar.placeholder = @"Search history";
    sc.searchBar.searchTextField.textColor = VGText;
    sc.searchBar.keyboardAppearance = UIKeyboardAppearanceDark;
    self.navigationItem.searchController = sc;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self reload];
}

- (void)reload {
    NSArray *all = VGBrowserHistory.entries;
    NSString *q = self.query.lowercaseString;
    if (q.length) {
        NSMutableArray *f = [NSMutableArray array];
        for (NSDictionary *e in all) {
            if ([[e[@"title"] lowercaseString] containsString:q] || [[e[@"url"] lowercaseString] containsString:q]) [f addObject:e];
        }
        all = f;
    }
    self.shown = all;
    self.navigationItem.rightBarButtonItem.enabled = VGBrowserHistory.entries.count > 0;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.query = sc.searchBar.text;
    [self reload];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)clearAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Clear history?" message:@"This removes every page from the list. Your favorites and sign-ins stay." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear all" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [VGBrowserHistory clear];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.shown.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (self.shown.count) return nil;
    return self.query.length ? @"Nothing matches your search." : @"Pages you open in the browser will show up here.";
}

- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = VGTertiary;
}

+ (NSString *)when:(NSTimeInterval)t {
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:t];
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDateFormatter *f = [NSDateFormatter new];
    if ([cal isDateInToday:d]) { f.dateFormat = @"'Today' h:mm a"; }
    else if ([cal isDateInYesterday:d]) { f.dateFormat = @"'Yesterday' h:mm a"; }
    else { f.dateFormat = @"MMM d, h:mm a"; }
    return [f stringFromDate:d];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"h"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"h"];
    NSDictionary *e = self.shown[ip.row];
    NSURL *u = [NSURL URLWithString:e[@"url"]];
    NSString *host = u.host ?: @"";
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    NSString *title = [e[@"title"] length] ? e[@"title"] : host;
    c.backgroundColor = VGSurface;
    c.textLabel.text = title;
    c.textLabel.textColor = VGText;
    c.textLabel.font = VGFont(15, UIFontWeightSemibold);
    c.textLabel.numberOfLines = 1;
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@", host, [VGHistoryViewController when:[e[@"time"] doubleValue]]];
    c.detailTextLabel.textColor = VGSecondary;
    c.detailTextLabel.font = VGFont(12, UIFontWeightMedium);
    c.imageView.image = [UIImage systemImageNamed:@"clock"];
    c.imageView.tintColor = VGTertiary;
    UIView *sel = [UIView new]; sel.backgroundColor = VGSelectedBg; c.selectedBackgroundView = sel;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSString *url = self.shown[ip.row][@"url"];
    [tv deselectRowAtIndexPath:ip animated:YES];
    void (^open)(NSString *) = self.openURL;
    [self dismissViewControllerAnimated:YES completion:^{ if (open) open(url); }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSString *url = self.shown[ip.row][@"url"];
        NSArray *all = VGBrowserHistory.entries;
        for (NSUInteger i = 0; i < all.count; i++) {
            if ([all[i][@"url"] isEqualToString:url]) { [VGBrowserHistory removeAtIndex:i]; break; }
        }
        [self reload];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end
