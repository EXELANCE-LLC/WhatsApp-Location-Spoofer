# Moving Route Simulation

This feature adds route-based movement for the location flow. Instead of staying on a fixed point, the active location can progress from a selected start point to a selected end point along a MapKit route.

## What was added

- `EXLRouteSimulationEngine`
  - Calculates a route between two coordinates with `MKDirections`.
  - Supports walking and driving modes.
  - Uses route distance and duration to advance the location over time.
  - Emits `CLLocation` updates with coordinate, course, speed, accuracy and timestamp.
  - Supports start, pause, resume and stop.

- `EXLRouteSimulationViewController`
  - Lightweight UIKit screen for selecting walking/driving mode and controlling route movement.
  - Shows current coordinate, total distance, elapsed time, remaining time and progress.

- `EXLRouteIntegrationExample.xm`
  - Minimal adapter showing how the existing fixed-location spoof flow can read the active route location.

## Recommended integration flow

1. Keep the existing fixed location feature unchanged.
2. Add a new action beside `Choose Location`: `Moving Route`.
3. Reuse the existing map picker to collect two points:
   - start coordinate
   - destination coordinate
4. Open `EXLRouteSimulationViewController` with these two coordinates.
5. In the existing location override hook, prefer route movement when active:

```objc
CLLocation *fixedLocation = [self exl_fixedSpoofLocation];
CLLocation *locationToSend = EXLLocationForOutgoingUpdate(fixedLocation);
```

## Movement model

### Walking

Default speed: `1.35 m/s` (`~4.86 km/h`).

Duration calculation:

```text
duration = routeDistance / walkingSpeed
```

### Driving

Default behavior uses MapKit route ETA when available.

Fallback speed: `13.89 m/s` (`~50 km/h`).

Duration calculation:

```text
duration = route.expectedTravelTime
fallback duration = routeDistance / drivingFallbackSpeed
```

## Public API

```objc
[[EXLRouteSimulationEngine sharedEngine] startRouteFromCoordinate:start
                                                     toCoordinate:end
                                                    transportMode:EXLRouteTransportModeWalking
                                                          options:nil
                                                       completion:^(BOOL success, NSError *error) {
    // handle result
}];
```

Read the currently active moving location:

```objc
CLLocation *location = [EXLRouteSimulationEngine sharedEngine].currentLocation;
```

Stop movement:

```objc
[[EXLRouteSimulationEngine sharedEngine] stop];
```

Pause/resume movement:

```objc
[[EXLRouteSimulationEngine sharedEngine] pause];
[[EXLRouteSimulationEngine sharedEngine] resume];
```

## Build notes

The new files require:

- `CoreLocation.framework`
- `MapKit.framework`
- `UIKit.framework` for the optional controller

For Theos-style builds, include the new `.m` files in the tweak source list and add MapKit to the linked frameworks.

Example:

```make
TWEAK_NAME = WhatsAppLocationSpoofer
WhatsAppLocationSpoofer_FILES += Sources/MovingRoute/EXLRouteSimulationEngine.m \
                                 Sources/MovingRoute/EXLRouteSimulationViewController.m
WhatsAppLocationSpoofer_FRAMEWORKS += CoreLocation MapKit UIKit
```
