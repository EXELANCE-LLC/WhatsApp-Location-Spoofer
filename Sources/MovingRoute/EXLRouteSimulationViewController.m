#import "EXLRouteSimulationViewController.h"
#import "EXLRouteSimulationEngine.h"

@interface EXLRouteSimulationViewController () <EXLRouteSimulationEngineDelegate>
@property (nonatomic, assign) CLLocationCoordinate2D startCoordinate;
@property (nonatomic, assign) CLLocationCoordinate2D endCoordinate;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *stopButton;
@end

@implementation EXLRouteSimulationViewController

- (instancetype)initWithStartCoordinate:(CLLocationCoordinate2D)startCoordinate
                          endCoordinate:(CLLocationCoordinate2D)endCoordinate {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) { return nil; }
    _startCoordinate = startCoordinate;
    _endCoordinate = endCoordinate;
    self.title = @"Moving Route";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [EXLRouteSimulationEngine sharedEngine].delegate = self;
    [self buildInterface];
    [self updateSummaryWithSnapshot:[EXLRouteSimulationEngine sharedEngine].snapshot];
}

- (void)buildInterface {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Route movement";
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    titleLabel.numberOfLines = 0;

    UILabel *coordinateLabel = [[UILabel alloc] init];
    coordinateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    coordinateLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    coordinateLabel.numberOfLines = 0;
    coordinateLabel.textColor = UIColor.secondaryLabelColor;
    coordinateLabel.text = [NSString stringWithFormat:@"Start: %.6f, %.6f\nEnd: %.6f, %.6f",
                            self.startCoordinate.latitude,
                            self.startCoordinate.longitude,
                            self.endCoordinate.latitude,
                            self.endCoordinate.longitude];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Walking", @"Driving"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = 0;

    self.summaryLabel = [[UILabel alloc] init];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.textColor = UIColor.secondaryLabelColor;

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;

    self.startButton = [self buttonWithTitle:@"Start" action:@selector(startTapped)];
    self.pauseButton = [self buttonWithTitle:@"Pause" action:@selector(pauseTapped)];
    self.stopButton = [self buttonWithTitle:@"Stop" action:@selector(stopTapped)];

    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.startButton, self.pauseButton, self.stopButton]];
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 10;
    buttonStack.distribution = UIStackViewDistributionFillEqually;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, coordinateLabel, self.modeControl, self.progressView, self.summaryLabel, buttonStack]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    [self.view addSubview:stack];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:24]
    ]];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)startTapped {
    EXLRouteTransportMode mode = self.modeControl.selectedSegmentIndex == 1 ? EXLRouteTransportModeDriving : EXLRouteTransportModeWalking;
    EXLRouteSimulationOptions *options = [EXLRouteSimulationOptions defaultOptionsForTransportMode:mode];

    __weak typeof(self) weakSelf = self;
    [[EXLRouteSimulationEngine sharedEngine] startRouteFromCoordinate:self.startCoordinate
                                                         toCoordinate:self.endCoordinate
                                                        transportMode:mode
                                                              options:options
                                                           completion:^(BOOL success, NSError *error) {
        if (!success && error) {
            [weakSelf showError:error];
        }
    }];
}

- (void)pauseTapped {
    EXLRouteSimulationEngine *engine = [EXLRouteSimulationEngine sharedEngine];
    if (engine.state == EXLRouteSimulationStatePaused) {
        [engine resume];
        [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
    } else {
        [engine pause];
        [self.pauseButton setTitle:@"Resume" forState:UIControlStateNormal];
    }
}

- (void)stopTapped {
    [[EXLRouteSimulationEngine sharedEngine] stop];
    self.progressView.progress = 0.0;
    [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
    [self updateSummaryWithSnapshot:[EXLRouteSimulationEngine sharedEngine].snapshot];
}

- (void)routeSimulationEngine:(EXLRouteSimulationEngine *)engine didUpdateSnapshot:(EXLRouteSimulationSnapshot *)snapshot {
    [self updateSummaryWithSnapshot:snapshot];
}

- (void)routeSimulationEngine:(EXLRouteSimulationEngine *)engine didChangeState:(EXLRouteSimulationState)state {
    if (state == EXLRouteSimulationStateCompleted || state == EXLRouteSimulationStateIdle) {
        [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
    }
}

- (void)routeSimulationEngine:(EXLRouteSimulationEngine *)engine didFailWithError:(NSError *)error {
    [self showError:error];
}

- (void)updateSummaryWithSnapshot:(EXLRouteSimulationSnapshot *)snapshot {
    self.progressView.progress = (float)snapshot.progress;
    CLLocationCoordinate2D coordinate = snapshot.currentLocation.coordinate;
    NSString *coordinateLine = snapshot.currentLocation ? [NSString stringWithFormat:@"Current: %.6f, %.6f", coordinate.latitude, coordinate.longitude] : @"Current: not started";
    self.summaryLabel.text = [NSString stringWithFormat:@"%@\nDistance: %.0f / %.0f m\nElapsed: %.0f s\nRemaining: %.0f s\nProgress: %.0f%%",
                              coordinateLine,
                              snapshot.travelledDistanceMeters,
                              snapshot.totalDistanceMeters,
                              snapshot.elapsedDuration,
                              snapshot.remainingDuration,
                              snapshot.progress * 100.0];
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Route error"
                                                                   message:error.localizedDescription
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
