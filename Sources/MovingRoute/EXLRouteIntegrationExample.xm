#import <CoreLocation/CoreLocation.h>
#import "EXLRouteSimulationEngine.h"

/*
 Integration point for the existing location override flow.

 Keep the project's current fixed-location behavior as the fallback. When route
 movement is active, call EXLCurrentRouteLocation() from the same place where the
 current spoofed CLLocation is returned to WhatsApp live/location sharing.
*/

static CLLocation *EXLCurrentRouteLocation(void) {
    EXLRouteSimulationEngine *engine = [EXLRouteSimulationEngine sharedEngine];
    switch (engine.state) {
        case EXLRouteSimulationStateRunning:
        case EXLRouteSimulationStatePaused:
        case EXLRouteSimulationStateCompleted:
            return engine.currentLocation;
        case EXLRouteSimulationStateIdle:
        case EXLRouteSimulationStateRouting:
        case EXLRouteSimulationStateFailed:
            return nil;
    }
}

static CLLocation *EXLLocationForOutgoingUpdate(CLLocation *fallbackLocation) {
    CLLocation *routeLocation = EXLCurrentRouteLocation();
    return routeLocation ?: fallbackLocation;
}

/*
 Example usage inside the existing tweak hook:

 CLLocation *fixedLocation = [self exl_fixedSpoofLocation];
 CLLocation *locationToSend = EXLLocationForOutgoingUpdate(fixedLocation);

 If the hook works with CLLocation arrays:

 NSArray<CLLocation *> *locations = locationToSend ? @[locationToSend] : originalLocations;

 The engine deliberately exposes a single read-only currentLocation so the rest
 of the project does not need to know whether the source is a fixed point or a
 moving route.
*/
