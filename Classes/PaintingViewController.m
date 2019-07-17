
#import "PaintingViewController.h"
#import "PaintingView.h"


#define kBrightness             1.0
#define kSaturation             0.45


#define kMinEraseInterval		0.5


@interface PaintingViewController()


@property (weak, nonatomic) IBOutlet UIImageView *imgView;

@property (weak, nonatomic) IBOutlet PaintingView *paintView;

@end

@implementation PaintingViewController

- (void)viewDidLoad {
    [super viewDidLoad];

	[(PaintingView *)self.view setBrushColorWithRed:1 green:0 blue:0];
}


- (IBAction)erase:(id)sender {
    [(PaintingView *)self.view erase];
}


// We do not support auto-rotation in this sample
- (BOOL)shouldAutorotate
{
    return NO;
}


@end
