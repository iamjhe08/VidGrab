#import "VGSavedPlaylistsViewController.h"
#import "VGPlaylistStore.h"
#import "VGTheme.h"

NSString *const VGOpenSavedPlaylist = @"VGOpenSavedPlaylist";

@implementation VGSavedPlaylistsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Saved Playlists";
    self.view.backgroundColor = VGBackground;
    self.tableView.backgroundColor = VGBackground;
    self.tableView.separatorColor = VGStroke;
    [NSNotificationCenter.defaultCenter addObserver:self.tableView selector:@selector(reloadData) name:VGSavedPlaylistsChanged object:nil];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    NSInteger n = [VGPlaylistStore all].count;
    if (n == 0) {
        UILabel *l = [UILabel new];
        l.text = @"No saved playlists yet.\n\nPaste a playlist link on Home, then tap Save playlist.";
        l.numberOfLines = 0;
        l.textAlignment = NSTextAlignmentCenter;
        l.textColor = VGSecondary;
        l.font = VGFont(15, UIFontWeightMedium);
        tv.backgroundView = l;
    } else tv.backgroundView = nil;
    return n;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"p"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"p"];
    VGSavedPlaylist *p = [VGPlaylistStore all][ip.row];
    c.backgroundColor = VGSurface;
    c.textLabel.text = p.title;
    c.textLabel.textColor = VGText;
    c.textLabel.font = VGFont(16, UIFontWeightSemibold);
    NSString *by = p.uploader.length ? [p.uploader stringByAppendingString:@" · "] : @"";
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@%lu videos", by, (unsigned long)p.entries.count];
    c.detailTextLabel.textColor = VGSecondary;
    c.imageView.image = [UIImage systemImageNamed:@"music.note.list"];
    c.imageView.tintColor = VGAccent;
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    VGSavedPlaylist *p = [VGPlaylistStore all][ip.row];
    [NSNotificationCenter.defaultCenter postNotificationName:VGOpenSavedPlaylist object:nil userInfo:@{@"id": p.identifier}];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    VGSavedPlaylist *p = [VGPlaylistStore all][ip.row];
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [VGPlaylistStore remove:p];
        done(YES);
    }];
    UIContextualAction *ren = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        UIAlertController *al = [UIAlertController alertControllerWithTitle:@"Rename playlist" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [al addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = p.title; }];
        [al addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [al addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [VGPlaylistStore rename:p to:al.textFields.firstObject.text]; }]];
        [ws presentViewController:al animated:YES completion:nil];
        done(YES);
    }];
    ren.backgroundColor = VGAccent;
    return [UISwipeActionsConfiguration configurationWithActions:@[del, ren]];
}

@end
