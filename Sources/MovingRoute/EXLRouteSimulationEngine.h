#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, EXLRouteTransportMode) {
    EXLRouteTransportModeWalking = 0,
    EXLRouteTransportModeDriving = 1,
};

typedef NS_ENUM(NSInteger, EXLRouteSimulationState) {
    EXLRouteSimulationStateIdle = 0,
    EXLRouteSimulationStateRouting = 1,
    EXLRouteSimulationStateRunning = 2,
    EXLRouteSimulationStatePaused = 3,
    EXLRouteSimulationStateCompleted = 4,
    EXLRouteSimulationStateFailed = 5,
};

@interface EXLRouteSimulationOptions : NSObject <NSCopying>

@property (nonatomic, assign) NSTimeInterval updateInterval;
@property (nonatomic, assign) CLLocationSpeed targetSpeedMetersPerSecond;
@property (nonatomic, assign) CLLocationDistance horizontalAccuracy;
@property (nonatomic, assign) CLLocationDistance verticalAccuracy;
@property (nonatomic, assign) CLLocationDistance altitude;
@property (nonatomic, assign) BOOL usesRouteExpectedTravelTime;

+ (instancetype)defaultOptionsForTransportMode:(EXLRouteTransportMode)transportMode;

@end

@interface EXLRouteSimulationSnapshot : NSObject

@property (nonatomic, assign, readonly) CLLocationDistance totalDistanceMeters;
@property (nonatomic, assign, readonly) CLLocationDistance travelledDistanceMeters;
@property (nonatomic, assign, readonly) NSTimeInterval totalDuration;
@property (nonatomic, assign, readonly) NSTimeInterval elapsedDuration;
@property (nonatomic, assign, readonly) NSTimeInterval remainingDuration;
@property (nonatomic, assign, readonly) double progress;
@property (nonatomic, strong, readonly, nullable) CLLocation *currentLocation;

- (instancetype)initWithTotalDistanceMeters:(CLLocationDistance)totalDistanceMeters
                   travelledDistanceMeters:(CLLocationDistance)travelledDistanceMeters
                              totalDuration:(NSTimeInterval)totalDuration
                            elapsedDuration:(NSTimeInterval)elapsedDuration
                            currentLocation:(nullable CLLocation *)currentLocation NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@class EXLRouteSimulationEngine;

@protocol EXLRouteSimulationEngineDelegate <NSObject>
@optional
- (void)routeSimulationEngine:(EXLRouteSimulationEngine *)engine didChangeState:(EXLRouteSimulationState)state;
- (void)routeSimulationEngine:(EXLRouteSimulationEngine *)engine didUpdateSnapshot:(EXLRouteSimulationSnapshot *)snapshot;
- (void)routeSimulationEngine:(EXLRouteSimulationEngine *)engine didFailWithError:(NSError *)error;
@end

@interface EXLRouteSimulationEngine : NSObject

+ (instancetype)sharedEngine;

@property (nonatomic, weak, nullable) id<EXLRouteSimulationEngineDelegate> delegate;
@property (nonatomic, assign, readonly) EXLRouteSimulationState state;
@property (nonatomic, assign, readonly) EXLRouteTransportMode transportMode;
@property (nonatomic, strong, readonly, nullable) MKRoute *activeRoute;
@property (nonatomic, strong, readonly, nullable) CLLocation *currentLocation;
@property (nonatomic, strong, readonly) EXLRouteSimulationSnapshot *snapshot;

- (void)startRouteFromCoordinate:(CLLocationCoordinate2D)startCoordinate
                    toCoordinate:(CLLocationCoordinate2D)destinationCoordinate
                   transportMode:(EXLRouteTransportMode)transportMode
                         options:(nullable EXLRouteSimulationOptions *)options
                      completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

- (void)startRoute:(MKRoute *)route
     transportMode:(EXLRouteTransportMode)transportMode
           options:(nullable EXLRouteSimulationOptions *)options
        completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

- (void)pause;
- (void)resume;
- (void)stop;

/// Deterministic test hook. Production flow is timer-driven.
- (void)updateWithElapsedDuration:(NSTimeInterval)elapsedDuration;

@end

NS_ASSUME_NONNULL_END
