#import <UIKit/UIKit.h>

/// The slot in VGPalette.all that holds the custom theme the person has applied.
/// Built-in presets keep their old numbers; new presets are added after this slot so saved themes never shift.
#define VGCustomThemeSlot 11

NSString *VGHexString(unsigned hex);
BOOL VGParseHex(NSString *text, unsigned *out);
unsigned VGHexOf(UIColor *c);
UIColor *VGMixColors(UIColor *a, UIColor *b, CGFloat t);

/// One custom theme: a built-in preset it starts from, plus the person's own changes.
/// Everything the app and the previews draw comes from this one description.
@interface VGThemeSpec : NSObject <NSCopying>
@property (nonatomic, copy) NSString *identifier, *name;
@property (nonatomic, assign) NSInteger base;                 // preset it started from
@property (nonatomic, assign) unsigned accent, bgColor, grad1, grad2;
@property (nonatomic, copy) NSString *bgMode;                  // color | gradient | photo | texture
@property (nonatomic, assign) NSInteger gradDirection;         // 0 down, 1 diagonal, 2 across, 3 up
@property (nonatomic, copy) NSString *texture;                 // carbon | noise | grid | dots | lines
@property (nonatomic, assign) double dim, blur;                // photo only
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *overrides;   // advanced colors the person changed
/// A starting point that matches a built-in preset exactly.
+ (instancetype)specFromPreset:(NSInteger)preset;
+ (instancetype)specFromDictionary:(NSDictionary *)d;
- (NSDictionary *)dictionary;
- (BOOL)isEqualToSpec:(VGThemeSpec *)other;
/// Where this theme's photo lives (it may not exist).
@property (nonatomic, readonly) NSString *photoPath;
@property (nonatomic, readonly) BOOL hasPhoto;
/// The editor sets this while a picked photo has not been saved yet, so previews treat the theme as having a photo.
@property (nonatomic, assign) BOOL assumePhoto;
/// Changes whenever anything that affects the picture behind the pages changes.
@property (nonatomic, readonly) NSString *cacheKey;
@end

/// Saved custom themes, kept in the app's settings (the photos sit in their own folder).
@interface VGThemeStore : NSObject
+ (NSArray<VGThemeSpec *> *)all;
+ (VGThemeSpec *)specWithID:(NSString *)identifier;
+ (VGThemeSpec *)active;
+ (void)saveSpec:(VGThemeSpec *)spec;                  // adds or replaces by id
+ (void)deleteSpec:(VGThemeSpec *)spec;
+ (NSString *)uniqueNameFor:(NSString *)name excluding:(NSString *)identifier;
+ (NSString *)photoDirectory;
/// Makes the theme the active custom theme and switches the app to it.
+ (void)apply:(VGThemeSpec *)spec;
/// Re-reads everything (after a restore) and refreshes the active palette.
+ (void)reload;
/// Moves a custom theme made with the first version (1.3.6c beta) into the new list.
+ (void)migrateIfNeeded;
/// Theme files for sharing: a versioned JSON, with the photo inside when it is small enough.
+ (NSData *)exportDataForSpec:(VGThemeSpec *)spec;
/// Validates and adds the theme. Returns nil and sets a plain-English reason when the file can't be used.
+ (VGThemeSpec *)importData:(NSData *)data message:(NSString **)message needsPhoto:(BOOL *)needsPhoto;
/// For backups: every custom theme with its photo.
+ (NSDictionary *)backupPayload;
+ (void)restoreFromPayload:(NSDictionary *)payload;
@end

/// Draws the picture behind the pages for a custom theme. Photos should be rendered off the main thread.
UIImage *VGRenderThemeBackground(VGThemeSpec *spec, CGSize size, CGFloat scale, UIImage *photoOverride);
void VGRenderThemeBackgroundAsync(VGThemeSpec *spec, CGSize size, CGFloat scale, UIImage *photoOverride, void (^done)(UIImage *));
/// The built-in texture names, in the order the editor lists them.
NSArray<NSString *> *VGTextureIDs(void);
NSString *VGTextureTitle(NSString *identifier);
