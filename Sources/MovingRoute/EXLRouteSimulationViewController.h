#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXLRouteSimulationViewController : UIViewController

- (instancetype)initWithStartCoordinate:(CLLocationCoordinate2D)startCoordinate
                      endCoordinate:(CLLocationCoordinate2D)endCoordinate;

@end

NS_ASSUME_NONNULL_END
