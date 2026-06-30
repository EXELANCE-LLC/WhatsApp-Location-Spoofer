#import "EXLRouteSimulationEngine.h"

static NSString * const EXLRouteSimulationErrorDomain = @"com.exelance.location.route-simulation";

static CLLocationSpeed EXLFallbackSpeedForMode(EXLRouteTransportMode mode) {
    switch (mode) {
        case EXLRouteTransportModeWalking:
            return 1.35; // ~4.86 km/h
        case EXLRouteTransportModeDriving:
            return 13.89; // ~50 km/h urban fallback
    }
}

static MKDirectionsTransportType EXLMapKitTransportType(EXLRouteTransportMode mode) {
    switch (mode) {
        case EXLRouteTransportModeWalking:
            return MKDirectionsTransportTypeWalking;
        case EXLRouteTransportModeDriving:
            return MKDirectionsTransportTypeAutomobile;
    }
}

static NSString *EXLStateDescription(EXLRouteSimulationState state) {
    switch (state) {
        case EXLRouteSimulationStateIdle: return @"Idle";
        case EXLRouteSimulationStateRouting: return @"Routing";
        case EXLRouteSimulationStateRunning: return @"Running";
        case EXLRouteSimulationStatePaused: return @"Paused";
        case EXLRouteSimulationStateCompleted: return @"Completed";
        case EXLRouteSimulationStateFailed: return @"Failed";
    }
}

static NSValue *EXLValueFromMapPoint(MKMapPoint point) {
    return [NSValue value:&point withObjCType:@encode(MKMapPoint)];
}

static MKMapPoint EXLMapPointFromValue(NSValue *value) {
    MKMapPoint point;
    [value getValue:&point];
    return point;
}

static CLLocationDirection EXLBearing(CLLocationCoordinate2D from, CLLocationCoordinate2D to) {
    double fromLat = from.latitude * M_PI / 180.0;
    double fromLon = from.longitude * M_PI / 180.0;
    double toLat = to.latitude * M_PI / 180.0;
    double toLon = to.longitude * M_PI / 180.0;
    double deltaLon = toLon - fromLon;
    double y = sin(deltaLon) * cos(toLat);
    double x = cos(fromLat) * sin(toLat) - sin(fromLat) * cos(toLat) * cos(deltaLon);
    double bearing = atan2(y, x) * 180.0 / M_PI;
    return fmod(bearing + 360.0, 360.0);
}

@implementation EXLRouteSimulationOptions

+ (instancetype)defaultOptionsForTransportMode:(EXLRouteTransportMode)transportMode {
    EXLRouteSimulationOptions *options = [[self alloc] init];
    options.updateInterval = 1.0;
    options.targetSpeedMetersPerSecond = EXLFallbackSpeedForMode(transportMode);
    options.horizontalAccuracy = transportMode == EXLRouteTransportModeWalking ? 5.0 : 8.0;
    options.verticalAccuracy = 12.0;
    options.altitude = 0.0;
    options.usesRouteExpectedTravelTime = transportMode == EXLRouteTransportModeDriving;
    return options;
}

- (id)copyWithZone:(NSZone *)zone {
    EXLRouteSimulationOptions *copy = [[[self class] allocWithZone:zone] init];
    copy.updateInterval = self.updateInterval;
    copy.targetSpeedMetersPerSecond = self.targetSpeedMetersPerSecond;
    copy.horizontalAccuracy = self.horizontalAccuracy;
    copy.verticalAccuracy = self.verticalAccuracy;
    copy.altitude = self.altitude;
    copy.usesRouteExpectedTravelTime = self.usesRouteExpectedTravelTime;
    return copy;
}

@end

@implementation EXLRouteSimulationSnapshot

- (instancetype)initWithTotalDistanceMeters:(CLLocationDistance)totalDistanceMeters
                   travelledDistanceMeters:(CLLocationDistance)travelledDistanceMeters
                              totalDuration:(NSTimeInterval)totalDuration
                            elapsedDuration:(NSTimeInterval)elapsedDuration
                            currentLocation:(CLLocation *)currentLocation {
    self = [super init];
    if (!self) { return nil; }

    _totalDistanceMeters = MAX(0.0, totalDistanceMeters);
    _travelledDistanceMeters = MIN(MAX(0.0, travelledDistanceMeters), _totalDistanceMeters);
    _totalDuration = MAX(0.0, totalDuration);
    _elapsedDuration = MIN(MAX(0.0, elapsedDuration), _totalDuration);
    _remainingDuration = MAX(0.0, _totalDuration - _elapsedDuration);
    _progress = _totalDistanceMeters <= 0.0 ? 0.0 : MIN(1.0, _travelledDistanceMeters / _totalDistanceMeters);
    _currentLocation = currentLocation;
    return self;
}

@end

@interface EXLRouteSimulationEngine ()
@property (nonatomic, assign, readwrite) EXLRouteSimulationState state;
@property (nonatomic, assign, readwrite) EXLRouteTransportMode transportMode;
@property (nonatomic, strong, readwrite) MKRoute *activeRoute;
@property (nonatomic, strong, readwrite) CLLocation *currentLocation;
@property (nonatomic, strong, readwrite) EXLRouteSimulationSnapshot *snapshot;
@property (nonatomic, strong) EXLRouteSimulationOptions *options;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, assign) NSTimeInterval elapsedBeforePause;
@property (nonatomic, copy) NSArray<NSValue *> *mapPoints;
@property (nonatomic, copy) NSArray<NSNumber *> *segmentLengths;
@property (nonatomic, assign) CLLocationDistance totalDistanceMeters;
@property (nonatomic, assign) NSTimeInterval totalDuration;
@end

@implementation EXLRouteSimulationEngine

+ (instancetype)sharedEngine {
    static EXLRouteSimulationEngine *engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[EXLRouteSimulationEngine alloc] initPrivate];
    });
    return engine;
}

- (instancetype)init {
    [NSException raise:NSInternalInconsistencyException format:@"Use +sharedEngine instead."];
    return nil;
}

- (instancetype)initPrivate {
    self = [super init];
    if (!self) { return nil; }
    _state = EXLRouteSimulationStateIdle;
    _transportMode = EXLRouteTransportModeWalking;
    _snapshot = [[EXLRouteSimulationSnapshot alloc] initWithTotalDistanceMeters:0 travelledDistanceMeters:0 totalDuration:0 elapsedDuration:0 currentLocation:nil];
    return self;
}

- (void)startRouteFromCoordinate:(CLLocationCoordinate2D)startCoordinate
                    toCoordinate:(CLLocationCoordinate2D)destinationCoordinate
                   transportMode:(EXLRouteTransportMode)transportMode
                         options:(EXLRouteSimulationOptions *)options
                      completion:(void (^)(BOOL success, NSError *error))completion {
    if (!CLLocationCoordinate2DIsValid(startCoordinate) || !CLLocationCoordinate2DIsValid(destinationCoordinate)) {
        NSError *error = [NSError errorWithDomain:EXLRouteSimulationErrorDomain
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid start or destination coordinate."}];
        if (completion) { completion(NO, error); }
        return;
    }

    [self stop];
    [self setSimulationState:EXLRouteSimulationStateRouting];

    MKPlacemark *sourcePlacemark = [[MKPlacemark alloc] initWithCoordinate:startCoordinate addressDictionary:nil];
    MKPlacemark *destinationPlacemark = [[MKPlacemark alloc] initWithCoordinate:destinationCoordinate addressDictionary:nil];

    MKDirectionsRequest *request = [[MKDirectionsRequest alloc] init];
    request.source = [[MKMapItem alloc] initWithPlacemark:sourcePlacemark];
    request.destination = [[MKMapItem alloc] initWithPlacemark:destinationPlacemark];
    request.transportType = EXLMapKitTransportType(transportMode);
    request.requestsAlternateRoutes = NO;

    MKDirections *directions = [[MKDirections alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            MKRoute *route = response.routes.firstObject;
            if (error || !route) {
                NSError *routeError = error ?: [NSError errorWithDomain:EXLRouteSimulationErrorDomain
                                                                    code:1002
                                                                userInfo:@{NSLocalizedDescriptionKey: @"Could not calculate a route for the selected points."}];
                [strongSelf failWithError:routeError];
                if (completion) { completion(NO, routeError); }
                return;
            }

            [strongSelf startRoute:route transportMode:transportMode options:options completion:completion];
        });
    }];
}

- (void)startRoute:(MKRoute *)route
     transportMode:(EXLRouteTransportMode)transportMode
           options:(EXLRouteSimulationOptions *)options
        completion:(void (^)(BOOL success, NSError *error))completion {
    if (!route || route.polyline.pointCount < 2) {
        NSError *error = [NSError errorWithDomain:EXLRouteSimulationErrorDomain
                                             code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Route must contain at least two polyline points."}];
        [self failWithError:error];
        if (completion) { completion(NO, error); }
        return;
    }

    [self stop];

    self.activeRoute = route;
    self.transportMode = transportMode;
    self.options = options ? [options copy] : [EXLRouteSimulationOptions defaultOptionsForTransportMode:transportMode];
    self.options.updateInterval = MAX(0.2, self.options.updateInterval);
    self.mapPoints = [self mapPointValuesFromPolyline:route.polyline];
    self.segmentLengths = [self segmentLengthsForMapPoints:self.mapPoints totalDistance:&_totalDistanceMeters];
    self.totalDuration = [self durationForRoute:route options:self.options transportMode:transportMode];
    self.elapsedBeforePause = 0.0;
    self.startedAt = [NSDate date];

    [self updateWithElapsedDuration:0.0];
    [self setSimulationState:EXLRouteSimulationStateRunning];
    [self startTimer];

    if (completion) { completion(YES, nil); }
}

- (void)pause {
    if (self.state != EXLRouteSimulationStateRunning) { return; }
    self.elapsedBeforePause = self.snapshot.elapsedDuration;
    [self.timer invalidate];
    self.timer = nil;
    [self setSimulationState:EXLRouteSimulationStatePaused];
}

- (void)resume {
    if (self.state != EXLRouteSimulationStatePaused) { return; }
    self.startedAt = [NSDate date];
    [self setSimulationState:EXLRouteSimulationStateRunning];
    [self startTimer];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    self.startedAt = nil;
    self.elapsedBeforePause = 0.0;
    self.activeRoute = nil;
    self.currentLocation = nil;
    self.mapPoints = @[];
    self.segmentLengths = @[];
    self.totalDistanceMeters = 0.0;
    self.totalDuration = 0.0;
    self.snapshot = [[EXLRouteSimulationSnapshot alloc] initWithTotalDistanceMeters:0 travelledDistanceMeters:0 totalDuration:0 elapsedDuration:0 currentLocation:nil];
    [self setSimulationState:EXLRouteSimulationStateIdle];
}

- (void)updateWithElapsedDuration:(NSTimeInterval)elapsedDuration {
    if (!self.activeRoute || self.mapPoints.count < 2 || self.totalDuration <= 0.0) { return; }

    NSTimeInterval boundedElapsed = MIN(MAX(0.0, elapsedDuration), self.totalDuration);
    double progress = self.totalDuration <= 0.0 ? 1.0 : boundedElapsed / self.totalDuration;
    CLLocationDistance targetDistance = self.totalDistanceMeters * progress;
    CLLocation *location = [self locationAtDistance:targetDistance speed:[self currentSpeedMetersPerSecond]];

    self.currentLocation = location;
    self.snapshot = [[EXLRouteSimulationSnapshot alloc] initWithTotalDistanceMeters:self.totalDistanceMeters
                                                           travelledDistanceMeters:targetDistance
                                                                      totalDuration:self.totalDuration
                                                                    elapsedDuration:boundedElapsed
                                                                    currentLocation:location];

    if ([self.delegate respondsToSelector:@selector(routeSimulationEngine:didUpdateSnapshot:)]) {
        [self.delegate routeSimulationEngine:self didUpdateSnapshot:self.snapshot];
    }

    if (boundedElapsed >= self.totalDuration && self.state == EXLRouteSimulationStateRunning) {
        [self.timer invalidate];
        self.timer = nil;
        [self setSimulationState:EXLRouteSimulationStateCompleted];
    }
}

#pragma mark - Private

- (void)startTimer {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.options.updateInterval
                                                  target:self
                                                selector:@selector(timerDidTick:)
                                                userInfo:nil
                                                 repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)timerDidTick:(NSTimer *)timer {
    if (self.state != EXLRouteSimulationStateRunning || !self.startedAt) { return; }
    NSTimeInterval elapsed = self.elapsedBeforePause + [[NSDate date] timeIntervalSinceDate:self.startedAt];
    [self updateWithElapsedDuration:elapsed];
}

- (void)setSimulationState:(EXLRouteSimulationState)state {
    if (_state == state) { return; }
    _state = state;
    NSLog(@"[EXLRouteSimulation] state=%@", EXLStateDescription(state));
    if ([self.delegate respondsToSelector:@selector(routeSimulationEngine:didChangeState:)]) {
        [self.delegate routeSimulationEngine:self didChangeState:state];
    }
}

- (void)failWithError:(NSError *)error {
    [self.timer invalidate];
    self.timer = nil;
    [self setSimulationState:EXLRouteSimulationStateFailed];
    if ([self.delegate respondsToSelector:@selector(routeSimulationEngine:didFailWithError:)]) {
        [self.delegate routeSimulationEngine:self didFailWithError:error];
    }
}

- (NSArray<NSValue *> *)mapPointValuesFromPolyline:(MKPolyline *)polyline {
    NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithCapacity:polyline.pointCount];
    MKMapPoint *rawPoints = polyline.points;
    for (NSUInteger index = 0; index < polyline.pointCount; index++) {
        [points addObject:EXLValueFromMapPoint(rawPoints[index])];
    }
    return points.copy;
}

- (NSArray<NSNumber *> *)segmentLengthsForMapPoints:(NSArray<NSValue *> *)points totalDistance:(CLLocationDistance *)totalDistance {
    NSMutableArray<NSNumber *> *lengths = [NSMutableArray arrayWithCapacity:MAX(0, (NSInteger)points.count - 1)];
    CLLocationDistance distance = 0.0;

    for (NSUInteger index = 1; index < points.count; index++) {
        MKMapPoint previous = EXLMapPointFromValue(points[index - 1]);
        MKMapPoint current = EXLMapPointFromValue(points[index]);
        CLLocationDistance segmentLength = MKMetersBetweenMapPoints(previous, current);
        distance += segmentLength;
        [lengths addObject:@(segmentLength)];
    }

    if (totalDistance) { *totalDistance = distance; }
    return lengths.copy;
}

- (NSTimeInterval)durationForRoute:(MKRoute *)route options:(EXLRouteSimulationOptions *)options transportMode:(EXLRouteTransportMode)transportMode {
    if (options.usesRouteExpectedTravelTime && route.expectedTravelTime > 1.0) {
        return route.expectedTravelTime;
    }

    CLLocationSpeed speed = options.targetSpeedMetersPerSecond > 0.1 ? options.targetSpeedMetersPerSecond : EXLFallbackSpeedForMode(transportMode);
    CLLocationDistance distance = self.totalDistanceMeters > 0.0 ? self.totalDistanceMeters : route.distance;
    return MAX(1.0, distance / speed);
}

- (CLLocationSpeed)currentSpeedMetersPerSecond {
    if (self.totalDuration <= 0.0 || self.totalDistanceMeters <= 0.0) {
        return 0.0;
    }
    return self.totalDistanceMeters / self.totalDuration;
}

- (CLLocation *)locationAtDistance:(CLLocationDistance)targetDistance speed:(CLLocationSpeed)speed {
    if (self.mapPoints.count == 0) { return nil; }

    targetDistance = MIN(MAX(0.0, targetDistance), self.totalDistanceMeters);
    CLLocationDistance traversed = 0.0;

    for (NSUInteger index = 0; index < self.segmentLengths.count; index++) {
        CLLocationDistance segmentLength = self.segmentLengths[index].doubleValue;
        BOOL isLastSegment = index == self.segmentLengths.count - 1;

        if (targetDistance <= traversed + segmentLength || isLastSegment) {
            MKMapPoint startPoint = EXLMapPointFromValue(self.mapPoints[index]);
            MKMapPoint endPoint = EXLMapPointFromValue(self.mapPoints[index + 1]);
            double segmentProgress = segmentLength <= 0.0 ? 0.0 : (targetDistance - traversed) / segmentLength;
            segmentProgress = MIN(MAX(0.0, segmentProgress), 1.0);

            MKMapPoint interpolatedPoint = MKMapPointMake(startPoint.x + ((endPoint.x - startPoint.x) * segmentProgress),
                                                          startPoint.y + ((endPoint.y - startPoint.y) * segmentProgress));
            CLLocationCoordinate2D coordinate = MKCoordinateForMapPoint(interpolatedPoint);
            CLLocationCoordinate2D startCoordinate = MKCoordinateForMapPoint(startPoint);
            CLLocationCoordinate2D endCoordinate = MKCoordinateForMapPoint(endPoint);
            CLLocationDirection course = EXLBearing(startCoordinate, endCoordinate);

            return [[CLLocation alloc] initWithCoordinate:coordinate
                                                 altitude:self.options.altitude
                                       horizontalAccuracy:self.options.horizontalAccuracy
                                         verticalAccuracy:self.options.verticalAccuracy
                                                   course:course
                                                    speed:speed
                                                timestamp:[NSDate date]];
        }

        traversed += segmentLength;
    }

    MKMapPoint lastPoint = EXLMapPointFromValue(self.mapPoints.lastObject);
    CLLocationCoordinate2D coordinate = MKCoordinateForMapPoint(lastPoint);
    return [[CLLocation alloc] initWithCoordinate:coordinate
                                         altitude:self.options.altitude
                               horizontalAccuracy:self.options.horizontalAccuracy
                                 verticalAccuracy:self.options.verticalAccuracy
                                           course:0.0
                                            speed:0.0
                                        timestamp:[NSDate date]];
}

@end
