# WhatsApp-Location-Spoofer

Spoof WhatsApp Location.

<p><strong>in-WhatsApp settings</strong></p>
<p><strong>spoof your location and live location&nbsp;</strong></p>
<p><strong>تزييف موقعك بتطبيق الواتساب يدعم الموقع العادي ومشاركة الموقع المباشر</strong></p>
<p><strong>اعدادات الاداة بداخل اعدادات تطبيق الواتساب</strong></p>

## Moving Route Simulation

This branch adds a moving-route mode for the location feature.

The new route mode lets the user select a start point and a destination point, then moves the active location along a real MapKit route instead of keeping it fixed on one coordinate.

### Supported movement types

- **Walking**: calculates duration from route distance and walking speed.
- **Driving**: uses MapKit route ETA when available and falls back to an urban driving speed.

### Added files

- `Sources/MovingRoute/EXLRouteSimulationEngine.h`
- `Sources/MovingRoute/EXLRouteSimulationEngine.m`
- `Sources/MovingRoute/EXLRouteSimulationViewController.h`
- `Sources/MovingRoute/EXLRouteSimulationViewController.m`
- `Sources/MovingRoute/EXLRouteIntegrationExample.xm`
- `docs/moving-route-simulation.md`

### Integration summary

1. Add a `Moving Route` action near the existing `Choose Location` flow.
2. Collect two coordinates: start and destination.
3. Open `EXLRouteSimulationViewController` with those coordinates.
4. In the existing location override hook, prefer the active route location when it exists.

```objc
CLLocation *fixedLocation = [self exl_fixedSpoofLocation];
CLLocation *locationToSend = EXLLocationForOutgoingUpdate(fixedLocation);
```

Full integration notes are in [`docs/moving-route-simulation.md`](docs/moving-route-simulation.md).

<p>&nbsp;</p>
<p><strong><img src="https://na9.me/loc1.PNG" alt="" /></strong></p>
<p><strong><img src="https://na9.me/loc2.PNG" alt="" /></strong></p>
<p><strong><img src="https://na9.me/loc3.PNG" alt="" /></strong></p>
