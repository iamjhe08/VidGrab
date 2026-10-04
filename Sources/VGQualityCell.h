#import <UIKit/UIKit.h>
#import "VGEngine.h"

@interface VGQualityCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *resLabel, *badgeLabel, *sizeLabel, *fmtLabel;
@property (nonatomic, strong) UIImageView *check;
- (void)configure:(VGOption *)o selected:(BOOL)selected;
@end
