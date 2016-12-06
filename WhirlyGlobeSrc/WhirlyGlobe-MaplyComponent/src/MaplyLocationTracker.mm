/*
 *  MaplyBaseViewController.mm
 *  MaplyComponent
 *
 *  Created by Ranen Ghosh on 11/23/16.
 *  Copyright 2012-2016 mousebird consulting
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "MaplyLocationTracker.h"
#import "MaplyBaseViewController.h"
#import "MaplyCoordinate.h"
#import "MaplyShape.h"
#import "WhirlyGlobeViewController.h"
#import "MaplyViewController.h"

#define MAPLYLOCATIONTRACKER_SIMUPDATES true

@implementation MaplyLocationTracker {
    CLLocationManager *_locationManager;
    bool _didRequestWhenInUseAuth;
    MaplyCoordinate _prevLoc;
    __weak MaplyBaseViewController *_theViewC;
    __weak WhirlyGlobeViewController *_globeVC;
    __weak MaplyViewController *_mapVC;
    
    __weak NSObject<MaplyLocationTrackerDelegate> *_delegate;
    
    NSMutableArray *_markerImgs, *_markerImgsDirectional;
    
    MaplyComponentObject *_markerObj;
    MaplyComponentObject *_movingMarkerObj;
    MaplyComponentObject *_shapeCircleObj;
    NSMutableDictionary *_markerDesc, *_movingMarkerDesc, *_shapeCircleDesc;
    
    NSNumber *_latestHeading;
    
    NSTimer *_simUpdateTimer;
    NSArray *_simPositions;
    int _simPositionIndex;
    
    bool _useHeading, _useCourse;
    MaplyLocationLockType _lockType;
    int _forwardTrackOffset;
}

- (nonnull instancetype)initWithViewC:(MaplyBaseViewController *__nullable)viewC Delegate:(NSObject<MaplyLocationTrackerDelegate> *__nullable)delegate useHeading:(bool)useHeading useCourse:(bool)useCourse {
    
    self = [super init];
    if (self) {
        _theViewC = viewC;
        if ([viewC isKindOfClass:[WhirlyGlobeViewController class]])
            _globeVC = (WhirlyGlobeViewController *)viewC;
        else if ([viewC isKindOfClass:[MaplyViewController class]])
            _mapVC = (MaplyViewController *)viewC;
        
        _delegate = delegate;
        _useHeading = useHeading;
        _useCourse = useCourse;
        _lockType = MaplyLocationLockNone;
        _forwardTrackOffset = 0;
        
        [self setupMarkerImages];
        if (!MAPLYLOCATIONTRACKER_SIMUPDATES)
            [self setupLocationManager];
        else {
            [self setSimPositions];
            _simUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(simUpdateTimeout) userInfo:nil repeats:YES];
        }
        
    }
    return self;
}

- (void) teardown {
    if (!MAPLYLOCATIONTRACKER_SIMUPDATES)
        [self teardownLocationManager];
    _delegate = nil;
}

- (void) changeLockType:(MaplyLocationLockType)lockType forwardTrackOffset:(int)forwardTrackOffset {
    _lockType = lockType;
    _forwardTrackOffset = forwardTrackOffset;
}

- (void) setupMarkerImages {
    int size = LOC_TRACKER_POS_MARKER_SIZE*2;
    
    UIColor *color0 = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    UIColor *color1 = [UIColor colorWithRed:0.0 green:0.75 blue:1.0 alpha:1.0];
    
    _markerImgs = [NSMutableArray array];
    _markerImgsDirectional = [NSMutableArray array];
    for (int i=0; i<16; i++) {
        [_markerImgs addObject:[self radialGradientMarkerWithSize:size color0:color0 color1:color1 gradLocation:(0.0 + (float)(8-ABS(8-i))/8.0) radius:(float)(size-32-ABS(8-i))/2.0 directional:false]];
        [_markerImgsDirectional addObject:[self radialGradientMarkerWithSize:size color0:color0 color1:color1 gradLocation:(0.0 + (float)(8-ABS(8-i))/8.0) radius:(float)(size-32-ABS(8-i))/2.0 directional:true]];
    }
    
    _markerDesc = [NSMutableDictionary dictionaryWithDictionary:@{kMaplyMinVis: @(0.0), kMaplyMaxVis: @(1.0), kMaplyFade: @(0.0), kMaplyDrawPriority:@(kMaplyVectorDrawPriorityDefault+1), kMaplyEnableEnd: @(MAXFLOAT)}];
    
    _movingMarkerDesc = [NSMutableDictionary dictionaryWithDictionary:@{kMaplyMinVis: @(0.0), kMaplyMaxVis: @(1.0), kMaplyFade: @(0.0), kMaplyDrawPriority:@(kMaplyVectorDrawPriorityDefault+1), kMaplyEnableStart:@(0.0)}];
    
    _shapeCircleDesc = [NSMutableDictionary dictionaryWithDictionary:@{kMaplyColor : [UIColor colorWithRed:0.06 green:0.06 blue:0.1 alpha:0.2], kMaplyFade: @(0.0), kMaplyDrawPriority: @(kMaplyVectorDrawPriorityDefault), kMaplySampleX: @(100)}];
    
}


- (UIImage *)radialGradientMarkerWithSize:(int)size color0:(UIColor *)color0 color1:(UIColor *)color1 gradLocation:(float)gradLocation radius:(float)radius directional:(bool)directional {
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    
    CGColorSpaceRef baseSpace = CGColorSpaceCreateDeviceRGB();
    
    CGFloat colorComponents[8];
    const CGFloat *components0 = CGColorGetComponents(color0.CGColor);
    const CGFloat *components1 = CGColorGetComponents(color1.CGColor);
    colorComponents[0] = components0[0];
    colorComponents[1] = components0[1];
    colorComponents[2] = components0[2];
    colorComponents[3] = components0[3];
    colorComponents[4] = components1[0];
    colorComponents[5] = components1[1];
    colorComponents[6] = components1[2];
    colorComponents[7] = components1[3];
    
    CGFloat locations[] = {0.0, gradLocation};
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(baseSpace, colorComponents, locations, 2);
    CGColorSpaceRelease(baseSpace);
    
    CGPoint gradCenter = CGPointMake(size/2, size/2);
    
    // Draw translucent outline
    CGRect outlineRect = CGRectMake(0, 0, size, size);
    UIColor *translucentColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    CGContextSetFillColorWithColor(ctx, translucentColor.CGColor);
    CGContextFillEllipseInRect(ctx, outlineRect);
    
    // Draw direction indicator triangle
    if (directional) {
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL,    size/2, size/2-radius-20);
        CGPathAddLineToPoint(path, NULL, size/2-12, size/2-radius);
        CGPathAddLineToPoint(path, NULL, size/2+12, size/2-radius);
        CGPathCloseSubpath(path);
        CGContextSetFillColorWithColor(ctx, color1.CGColor);
        CGContextAddPath(ctx, path);
        CGContextFillPath(ctx);
        CGPathRelease(path);
    }

    // Draw white outline
    outlineRect = CGRectMake(size/2-radius-4, size/2-radius-4, 2*radius+8, 2*radius+8);
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(ctx, outlineRect);
    
    // Draw gradient center
    CGContextDrawRadialGradient(ctx, gradient, gradCenter, 0, gradCenter, radius, kCGGradientDrawsBeforeStartLocation);
    CGGradientRelease(gradient);
    
    CGContextRestoreGState(ctx);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return img;
}


- (void) setupLocationManager {
    if (_locationManager)
        return;
    CLAuthorizationStatus authStatus = [CLLocationManager authorizationStatus];
    if (authStatus == kCLAuthorizationStatusRestricted || authStatus == kCLAuthorizationStatusDenied) {
        return;
    }
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
    _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    
    if ([_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        if (!_didRequestWhenInUseAuth) {
            // Sending a message to avoid compile time error
            [[UIApplication sharedApplication] sendAction:@selector(requestWhenInUseAuthorization)
                                                       to:_locationManager
                                                     from:self
                                                 forEvent:nil];
            _didRequestWhenInUseAuth = true;
        }
    } else {
        [[UIApplication sharedApplication] sendAction:@selector(startUpdatingLocation)
                                                   to:_locationManager
                                                 from:self
                                             forEvent:nil];
        [[UIApplication sharedApplication] sendAction:@selector(startUpdatingHeading)
                                                   to:_locationManager
                                                 from:self
                                             forEvent:nil];
        
        
    }
}

- (void) teardownLocationManager {
    if (!_locationManager)
        return;
    [_locationManager stopUpdatingLocation];
    if (_useHeading)
        [_locationManager stopUpdatingHeading];
    _locationManager.delegate = nil;
    _locationManager = nil;
    _didRequestWhenInUseAuth = false;
}

- (MaplyCoordinate) coordOfPointAtTrueCourse:(double)tcDeg andDistanceMeters:(double)dMeters fromCoord:(MaplyCoordinate)coord;
{
    // http://www.movable-type.co.uk/scripts/latlong.html
    double tcRad = tcDeg * M_PI/180.0;
    double lat1 = coord.y;
    double lon1 = -coord.x;
    
    double dRadians = dMeters / 6.371e6;
    
    double latRad, lonRad;
    
    latRad = asin(sin(lat1)*cos(dRadians)+cos(lat1)*sin(dRadians)*cos(tcRad));
    
    if (cos(latRad) == 0)
        lonRad = lon1;
    else
        lonRad = fmod(lon1-asin(sin(tcRad)*sin(dRadians)/cos(latRad))+M_PI,2.0*M_PI)-M_PI;
    
    
    return MaplyCoordinateMake(-lonRad, latRad);
}


- (MaplyShapeCircle *)shapeCircleForCoord:(MaplyCoordinate)coord AndHorizontalAccuracy:(int)horizontalAccuracy {
    
    MaplyShapeCircle *shapeCircle = [[MaplyShapeCircle alloc] init];
    shapeCircle.center = coord;
    
    MaplyCoordinate coord1 = [self coordOfPointAtTrueCourse:0.0 andDistanceMeters:horizontalAccuracy fromCoord:coord];
    MaplyCoordinate coord2 = [self coordOfPointAtTrueCourse:90.0 andDistanceMeters:horizontalAccuracy fromCoord:coord];
    
    MaplyCoordinate3d dispPt0 = [_theViewC displayPointFromGeo:coord];
    MaplyCoordinate3d dispPt1 = [_theViewC displayPointFromGeo:coord1];
    MaplyCoordinate3d dispPt2 = [_theViewC displayPointFromGeo:coord2];
    
    float d1 = sqrtf(powf(dispPt1.x-dispPt0.x, 2.0) + powf(dispPt1.y-dispPt0.y, 2.0));
    float d2 = sqrtf(powf(dispPt2.x-dispPt0.x, 2.0) + powf(dispPt2.y-dispPt0.y, 2.0));
    shapeCircle.radius = (d1 + d2) / 2.0;
    shapeCircle.height = 0.00001;
    
    return shapeCircle;
}

- (void)updateLocation:(CLLocation *)location {
    __strong MaplyBaseViewController *theViewC = _theViewC;
    if (!theViewC)
        return;
    
    MaplyCoordinate endLoc = MaplyCoordinateMakeWithDegrees(location.coordinate.longitude, location.coordinate.latitude);
    MaplyCoordinate startLoc;
    
    if (_markerObj) {
        startLoc = _prevLoc;
        [_theViewC removeObject:_markerObj];
        [_theViewC removeObject:_movingMarkerObj];
        _markerObj = nil;
        _movingMarkerObj = nil;
    } else
        startLoc = endLoc;
    
    if (_shapeCircleObj) {
        [theViewC removeObject:_shapeCircleObj];
        _shapeCircleObj = nil;
    }
    
    // TODO: should we return before or after removing existing markers?
    if (location.horizontalAccuracy < 0)
        return;
    
    MaplyShapeCircle *shapeCircle = [self shapeCircleForCoord:endLoc AndHorizontalAccuracy:location.horizontalAccuracy];
    if (shapeCircle) {
        _shapeCircleObj = [_theViewC addShapes:@[shapeCircle] desc:_shapeCircleDesc];
    }
    
    NSNumber *orientation;
    if (_useHeading && _latestHeading)
        orientation = _latestHeading;
    else if (_useCourse && location.course >= 0)
        orientation = @(location.course);
        
    NSArray *markerImages;
    if (orientation)
        markerImages = _markerImgsDirectional;
    else
        markerImages = _markerImgs;
    
    MaplyMovingScreenMarker *movingMarker = [[MaplyMovingScreenMarker alloc] init];
    movingMarker.loc = startLoc;
    movingMarker.endLoc = endLoc;
    movingMarker.duration = 0.5;
    
    movingMarker.period = 1.0;
    movingMarker.size = CGSizeMake(LOC_TRACKER_POS_MARKER_SIZE, LOC_TRACKER_POS_MARKER_SIZE);
    if (orientation)
        movingMarker.rotation = -M_PI/180.0 * orientation.doubleValue;
    movingMarker.images = markerImages;
    movingMarker.layoutImportance = MAXFLOAT;
    
    MaplyScreenMarker *marker = [[MaplyScreenMarker alloc] init];
    marker.loc = endLoc;
    
    marker.period = 1.0;
    marker.size = CGSizeMake(LOC_TRACKER_POS_MARKER_SIZE, LOC_TRACKER_POS_MARKER_SIZE);
    if (orientation)
        marker.rotation = -M_PI/180.0 * orientation.doubleValue;
    marker.images = markerImages;
    marker.layoutImportance = MAXFLOAT;
    
    NSTimeInterval ti = [NSDate timeIntervalSinceReferenceDate]+0.5;
    _markerDesc[kMaplyEnableStart] = _movingMarkerDesc[kMaplyEnableEnd] = @(ti);
    
    _movingMarkerObj = [_theViewC addScreenMarkers:@[movingMarker] desc:_movingMarkerDesc];
    _markerObj = [_theViewC addScreenMarkers:@[marker] desc:_markerDesc];
    
    [self lockToLocation:endLoc heading:(orientation ? orientation.floatValue : 0.0)];
    
    _prevLoc = endLoc;
}

- (void) lockToLocation:(MaplyCoordinate)location heading:(float)heading{
    __strong WhirlyGlobeViewController *globeVC = _globeVC;
    __strong MaplyViewController *mapVC = _mapVC;
    if (!globeVC && !mapVC)
        return;
    
    MaplyCoordinateD locationD = MaplyCoordinateDMakeWithMaplyCoordinate(location);
    
    switch (_lockType) {
        case MaplyLocationLockNone:
            break;
        case MaplyLocationLockNorthUp:
            if (globeVC)
                [globeVC animateToPosition:location height:[globeVC getHeight] heading:0.0 time:0.5];
            else if (mapVC)
                [mapVC animateToPosition:location height:[mapVC getHeight] heading:0.0 time:0.5];
            break;
        case MaplyLocationLockHeadingUp:
            if (globeVC)
                [globeVC animateToPosition:location height:[globeVC getHeight] heading:fmod(M_PI/180.0 * heading + 2.0*M_PI, 2.0*M_PI) time:0.5];
            else if (mapVC)
                [mapVC animateToPosition:location height:[mapVC getHeight] heading:fmod(M_PI/180.0 * heading + 2.0*M_PI, 2.0*M_PI) time:0.5];
            break;
        case MaplyLocationLockHeadingUpOffset:
            if (globeVC)
                [globeVC animateToPosition:location onScreen:CGPointMake(0, -_forwardTrackOffset) height:[globeVC getHeight] heading:fmod(M_PI/180.0 * heading + 2.0*M_PI, 2.0*M_PI) time:0.5];
            else if (mapVC)
                [mapVC animateToPosition:location onScreen:CGPointMake(0, -_forwardTrackOffset) height:[mapVC getHeight] heading:fmod(M_PI/180.0 * heading + 2.0*M_PI, 2.0*M_PI) time:0.5];
            break;
        default:
            break;
    }
}

#pragma mark
#pragma mark CLLocationManagerDelegate Methods

- (void) locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    __strong NSObject<MaplyLocationTrackerDelegate> *delegate = _delegate;
    _latestHeading = nil;
    if (delegate)
        [delegate locationManager:manager didFailWithError:error];
}

- (void) locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {

    __strong NSObject<MaplyLocationTrackerDelegate> *delegate = _delegate;
    if (delegate)
        [delegate locationManager:manager didChangeAuthorizationStatus:status];
    
    if (status == kCLAuthorizationStatusNotDetermined) {
        return;
    }
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        [self teardownLocationManager];
    } else if (status == kCLAuthorizationStatusAuthorized || status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        
        [_locationManager startUpdatingLocation];
        if (_useHeading)
            [_locationManager startUpdatingHeading];
    }
}

- (void) locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    CLLocation *location = [locations lastObject];
    
    [self updateLocation:location];
    
}

- (void) locationManager:(CLLocationManager *)manager didUpdateHeading:(nonnull CLHeading *)newHeading {
    
    if (newHeading.headingAccuracy < 0)
        _latestHeading = nil;
    else
        _latestHeading = @(newHeading.trueHeading);
}

- (void) simUpdateTimeout {
    
    NSArray *positions = _simPositions[_simPositionIndex];
    _simPositionIndex = ((_simPositionIndex+1) % _simPositions.count);
    
    NSNumber *lonDeg = positions[0];
    NSNumber *latDeg = positions[1];
    NSNumber *hdgDeg = positions[2];
    
    _latestHeading = hdgDeg;
    CLLocation *location = [[CLLocation alloc] initWithCoordinate:(CLLocationCoordinate2D){latDeg.floatValue, lonDeg.floatValue} altitude:10000.0 horizontalAccuracy:250 verticalAccuracy:15 course:hdgDeg.floatValue speed:0 timestamp:[NSDate date]];
    [self updateLocation:location];
    
}

- (void)setSimPositions {
    _simPositions = @[@[@(16.382910),@(48.211350),@(275.700000)],@[@(16.382870),@(48.211250),@(194.900000)],@[@(16.382830),@(48.211150),@(194.900000)],@[@(16.382797),@(48.211023),@(189.900000)],@[@(16.382763),@(48.210897),@(189.900000)],@[@(16.382730),@(48.210770),@(189.900000)],@[@(16.382705),@(48.210647),@(187.700000)],@[@(16.382680),@(48.210525),@(187.700000)],@[@(16.382655),@(48.210403),@(187.700000)],@[@(16.382630),@(48.210280),@(187.700000)],@[@(16.382600),@(48.210135),@(187.900000)],@[@(16.382570),@(48.209990),@(187.900000)],@[@(16.382520),@(48.209830),@(191.800000)],@[@(16.382484),@(48.209729),@(193.200000)],@[@(16.382449),@(48.209628),@(193.200000)],@[@(16.382413),@(48.209527),@(193.200000)],@[@(16.382378),@(48.209426),@(193.200000)],@[@(16.382342),@(48.209324),@(193.200000)],@[@(16.382307),@(48.209223),@(193.200000)],@[@(16.382271),@(48.209122),@(193.200000)],@[@(16.382236),@(48.209021),@(193.200000)],@[@(16.382200),@(48.208920),@(193.200000)],@[@(16.382115),@(48.208829),@(211.800000)],@[@(16.382030),@(48.208737),@(211.800000)],@[@(16.381945),@(48.208646),@(211.800000)],@[@(16.381860),@(48.208555),@(211.800000)],@[@(16.381775),@(48.208464),@(211.800000)],@[@(16.381690),@(48.208373),@(211.800000)],@[@(16.381605),@(48.208281),@(211.800000)],@[@(16.381520),@(48.208190),@(211.800000)],@[@(16.381437),@(48.208105),@(213.100000)],@[@(16.381354),@(48.208020),@(213.100000)],@[@(16.381271),@(48.207935),@(213.100000)],@[@(16.381188),@(48.207850),@(213.100000)],@[@(16.381105),@(48.207765),@(213.100000)],@[@(16.381022),@(48.207680),@(213.100000)],@[@(16.380939),@(48.207595),@(213.100000)],@[@(16.380856),@(48.207510),@(213.100000)],@[@(16.380773),@(48.207425),@(213.100000)],@[@(16.380690),@(48.207340),@(213.100000)],@[@(16.380565),@(48.207410),@(310.000000)],@[@(16.380440),@(48.207480),@(310.000000)],@[@(16.380320),@(48.207370),@(216.000000)],@[@(16.380170),@(48.207230),@(215.500000)],@[@(16.380320),@(48.207185),@(114.200000)],@[@(16.380470),@(48.207140),@(114.200000)],@[@(16.380383),@(48.207058),@(215.300000)],@[@(16.380297),@(48.206977),@(215.300000)],@[@(16.380210),@(48.206895),@(215.300000)],@[@(16.380123),@(48.206813),@(215.300000)],@[@(16.380037),@(48.206732),@(215.300000)],@[@(16.379950),@(48.206650),@(215.300000)],@[@(16.379860),@(48.206564),@(214.800000)],@[@(16.379770),@(48.206478),@(214.800000)],@[@(16.379680),@(48.206391),@(214.800000)],@[@(16.379590),@(48.206305),@(214.800000)],@[@(16.379500),@(48.206219),@(214.800000)],@[@(16.379410),@(48.206132),@(214.800000)],@[@(16.379320),@(48.206046),@(214.800000)],@[@(16.379230),@(48.205960),@(214.800000)],@[@(16.379127),@(48.205862),@(215.000000)],@[@(16.379025),@(48.205765),@(215.000000)],@[@(16.378923),@(48.205668),@(215.000000)],@[@(16.378820),@(48.205570),@(215.000000)],@[@(16.378730),@(48.205478),@(213.200000)],@[@(16.378640),@(48.205387),@(213.200000)],@[@(16.378550),@(48.205295),@(213.200000)],@[@(16.378460),@(48.205203),@(213.200000)],@[@(16.378370),@(48.205112),@(213.200000)],@[@(16.378280),@(48.205020),@(213.200000)],@[@(16.378185),@(48.204923),@(213.200000)],@[@(16.378090),@(48.204827),@(213.200000)],@[@(16.377995),@(48.204730),@(213.200000)],@[@(16.377900),@(48.204633),@(213.200000)],@[@(16.377805),@(48.204537),@(213.200000)],@[@(16.377710),@(48.204440),@(213.200000)],@[@(16.377620),@(48.204347),@(212.700000)],@[@(16.377530),@(48.204253),@(212.700000)],@[@(16.377440),@(48.204160),@(212.700000)],@[@(16.377350),@(48.204067),@(212.700000)],@[@(16.377260),@(48.203973),@(212.700000)],@[@(16.377170),@(48.203880),@(212.700000)],@[@(16.377050),@(48.203760),@(213.700000)],@[@(16.376930),@(48.203640),@(213.700000)],@[@(16.376823),@(48.203533),@(213.700000)],@[@(16.376717),@(48.203427),@(213.700000)],@[@(16.376610),@(48.203320),@(213.700000)],@[@(16.376570),@(48.203340),@(306.900000)],@[@(16.376350),@(48.203450),@(306.900000)],@[@(16.376258),@(48.203365),@(215.700000)],@[@(16.376167),@(48.203280),@(215.700000)],@[@(16.376075),@(48.203195),@(215.700000)],@[@(16.375983),@(48.203110),@(215.700000)],@[@(16.375892),@(48.203025),@(215.700000)],@[@(16.375800),@(48.202940),@(215.700000)],@[@(16.375706),@(48.202849),@(214.600000)],@[@(16.375611),@(48.202758),@(214.600000)],@[@(16.375517),@(48.202667),@(214.600000)],@[@(16.375422),@(48.202576),@(214.600000)],@[@(16.375328),@(48.202484),@(214.600000)],@[@(16.375233),@(48.202393),@(214.600000)],@[@(16.375139),@(48.202302),@(214.600000)],@[@(16.375044),@(48.202211),@(214.600000)],@[@(16.374950),@(48.202120),@(214.600000)],@[@(16.374810),@(48.202000),@(217.900000)],@[@(16.374680),@(48.201950),@(240.000000)],@[@(16.374550),@(48.201900),@(240.000000)],@[@(16.374387),@(48.201858),@(248.600000)],@[@(16.374225),@(48.201815),@(248.600000)],@[@(16.374063),@(48.201772),@(248.600000)],@[@(16.373900),@(48.201730),@(248.600000)],@[@(16.373890),@(48.201730),@(270.000000)],@[@(16.373695),@(48.201720),@(265.600000)],@[@(16.373500),@(48.201710),@(265.600000)],@[@(16.373353),@(48.201740),@(287.100000)],@[@(16.373207),@(48.201770),@(287.100000)],@[@(16.373060),@(48.201800),@(287.100000)],@[@(16.372917),@(48.201832),@(288.400000)],@[@(16.372774),@(48.201863),@(288.400000)],@[@(16.372631),@(48.201895),@(288.400000)],@[@(16.372488),@(48.201927),@(288.400000)],@[@(16.372345),@(48.201959),@(288.400000)],@[@(16.372202),@(48.201990),@(288.400000)],@[@(16.372059),@(48.202022),@(288.400000)],@[@(16.371916),@(48.202054),@(288.400000)],@[@(16.371773),@(48.202086),@(288.400000)],@[@(16.371630),@(48.202117),@(288.400000)],@[@(16.371487),@(48.202149),@(288.400000)],@[@(16.371343),@(48.202181),@(288.400000)],@[@(16.371200),@(48.202213),@(288.400000)],@[@(16.371057),@(48.202244),@(288.400000)],@[@(16.370914),@(48.202276),@(288.400000)],@[@(16.370771),@(48.202308),@(288.400000)],@[@(16.370628),@(48.202340),@(288.400000)],@[@(16.370485),@(48.202371),@(288.400000)],@[@(16.370342),@(48.202403),@(288.400000)],@[@(16.370199),@(48.202435),@(288.400000)],@[@(16.370056),@(48.202467),@(288.400000)],@[@(16.369913),@(48.202498),@(288.400000)],@[@(16.369770),@(48.202530),@(288.400000)],@[@(16.369610),@(48.202564),@(287.700000)],@[@(16.369450),@(48.202598),@(287.700000)],@[@(16.369290),@(48.202632),@(287.700000)],@[@(16.369130),@(48.202666),@(287.700000)],@[@(16.368970),@(48.202700),@(287.700000)],@[@(16.368822),@(48.202735),@(289.500000)],@[@(16.368673),@(48.202770),@(289.500000)],@[@(16.368525),@(48.202805),@(289.500000)],@[@(16.368377),@(48.202840),@(289.500000)],@[@(16.368228),@(48.202875),@(289.500000)],@[@(16.368080),@(48.202910),@(289.500000)],@[@(16.368020),@(48.202740),@(193.200000)],@[@(16.367872),@(48.202773),@(288.300000)],@[@(16.367724),@(48.202805),@(288.300000)],@[@(16.367576),@(48.202838),@(288.300000)],@[@(16.367428),@(48.202871),@(288.300000)],@[@(16.367280),@(48.202903),@(288.300000)],@[@(16.367132),@(48.202936),@(288.300000)],@[@(16.366984),@(48.202969),@(288.300000)],@[@(16.366836),@(48.203001),@(288.300000)],@[@(16.366688),@(48.203034),@(288.300000)],@[@(16.366540),@(48.203067),@(288.300000)],@[@(16.366392),@(48.203099),@(288.300000)],@[@(16.366244),@(48.203132),@(288.300000)],@[@(16.366096),@(48.203165),@(288.300000)],@[@(16.365948),@(48.203197),@(288.300000)],@[@(16.365800),@(48.203230),@(288.300000)],@[@(16.365657),@(48.203262),@(288.600000)],@[@(16.365513),@(48.203294),@(288.600000)],@[@(16.365370),@(48.203327),@(288.600000)],@[@(16.365227),@(48.203359),@(288.600000)],@[@(16.365083),@(48.203391),@(288.600000)],@[@(16.364940),@(48.203423),@(288.600000)],@[@(16.364797),@(48.203456),@(288.600000)],@[@(16.364653),@(48.203488),@(288.600000)],@[@(16.364510),@(48.203520),@(288.600000)],@[@(16.364350),@(48.203580),@(299.400000)],@[@(16.364226),@(48.203658),@(313.300000)],@[@(16.364102),@(48.203736),@(313.300000)],@[@(16.363978),@(48.203814),@(313.300000)],@[@(16.363854),@(48.203892),@(313.300000)],@[@(16.363730),@(48.203970),@(313.300000)],@[@(16.363628),@(48.204045),@(317.800000)],@[@(16.363525),@(48.204121),@(317.800000)],@[@(16.363423),@(48.204196),@(317.800000)],@[@(16.363321),@(48.204271),@(317.800000)],@[@(16.363218),@(48.204346),@(317.800000)],@[@(16.363116),@(48.204422),@(317.800000)],@[@(16.363014),@(48.204497),@(317.800000)],@[@(16.362911),@(48.204572),@(317.800000)],@[@(16.362809),@(48.204648),@(317.800000)],@[@(16.362706),@(48.204723),@(317.800000)],@[@(16.362604),@(48.204798),@(317.800000)],@[@(16.362502),@(48.204874),@(317.800000)],@[@(16.362399),@(48.204949),@(317.800000)],@[@(16.362297),@(48.205024),@(317.800000)],@[@(16.362195),@(48.205099),@(317.800000)],@[@(16.362092),@(48.205175),@(317.800000)],@[@(16.361990),@(48.205250),@(317.800000)],@[@(16.361889),@(48.205327),@(318.800000)],@[@(16.361788),@(48.205404),@(318.800000)],@[@(16.361686),@(48.205481),@(318.800000)],@[@(16.361585),@(48.205558),@(318.800000)],@[@(16.361484),@(48.205635),@(318.800000)],@[@(16.361383),@(48.205712),@(318.800000)],@[@(16.361282),@(48.205789),@(318.800000)],@[@(16.361181),@(48.205866),@(318.800000)],@[@(16.361079),@(48.205944),@(318.800000)],@[@(16.360978),@(48.206021),@(318.800000)],@[@(16.360877),@(48.206098),@(318.800000)],@[@(16.360776),@(48.206175),@(318.800000)],@[@(16.360675),@(48.206252),@(318.800000)],@[@(16.360574),@(48.206329),@(318.800000)],@[@(16.360472),@(48.206406),@(318.800000)],@[@(16.360371),@(48.206483),@(318.800000)],@[@(16.360270),@(48.206560),@(318.800000)],@[@(16.360162),@(48.206640),@(318.000000)],@[@(16.360054),@(48.206720),@(318.000000)],@[@(16.359946),@(48.206800),@(318.000000)],@[@(16.359838),@(48.206880),@(318.000000)],@[@(16.359730),@(48.206960),@(318.000000)],@[@(16.359680),@(48.207030),@(334.500000)],@[@(16.359685),@(48.207155),@(1.500000)],@[@(16.359690),@(48.207280),@(1.500000)],@[@(16.359727),@(48.207383),@(13.300000)],@[@(16.359763),@(48.207487),@(13.300000)],@[@(16.359800),@(48.207590),@(13.300000)],@[@(16.359837),@(48.207693),@(13.300000)],@[@(16.359873),@(48.207797),@(13.300000)],@[@(16.359910),@(48.207900),@(13.300000)],@[@(16.359944),@(48.207998),@(13.000000)],@[@(16.359977),@(48.208095),@(13.000000)],@[@(16.360011),@(48.208193),@(13.000000)],@[@(16.360045),@(48.208290),@(13.000000)],@[@(16.360079),@(48.208388),@(13.000000)],@[@(16.360112),@(48.208485),@(13.000000)],@[@(16.360146),@(48.208582),@(13.000000)],@[@(16.360180),@(48.208680),@(13.000000)],@[@(16.359950),@(48.208720),@(284.600000)],@[@(16.359796),@(48.208739),@(280.600000)],@[@(16.359641),@(48.208759),@(280.600000)],@[@(16.359487),@(48.208778),@(280.600000)],@[@(16.359333),@(48.208797),@(280.600000)],@[@(16.359179),@(48.208816),@(280.600000)],@[@(16.359024),@(48.208836),@(280.600000)],@[@(16.358870),@(48.208855),@(280.600000)],@[@(16.358716),@(48.208874),@(280.600000)],@[@(16.358561),@(48.208894),@(280.600000)],@[@(16.358407),@(48.208913),@(280.600000)],@[@(16.358253),@(48.208932),@(280.600000)],@[@(16.358099),@(48.208951),@(280.600000)],@[@(16.357944),@(48.208971),@(280.600000)],@[@(16.357790),@(48.208990),@(280.600000)],@[@(16.357755),@(48.208880),@(192.000000)],@[@(16.357720),@(48.208770),@(192.000000)],@[@(16.357685),@(48.208660),@(192.000000)],@[@(16.357650),@(48.208550),@(192.000000)],@[@(16.357610),@(48.208433),@(192.900000)],@[@(16.357570),@(48.208317),@(192.900000)],@[@(16.357530),@(48.208200),@(192.900000)],@[@(16.357370),@(48.208220),@(280.600000)],@[@(16.357210),@(48.208240),@(280.600000)],@[@(16.357050),@(48.208260),@(280.600000)],@[@(16.356890),@(48.208280),@(280.600000)],@[@(16.356730),@(48.208300),@(280.600000)],@[@(16.356570),@(48.208320),@(280.600000)],@[@(16.356410),@(48.208344),@(282.900000)],@[@(16.356250),@(48.208369),@(282.900000)],@[@(16.356090),@(48.208393),@(282.900000)],@[@(16.355930),@(48.208418),@(282.900000)],@[@(16.355770),@(48.208442),@(282.900000)],@[@(16.355610),@(48.208467),@(282.900000)],@[@(16.355450),@(48.208491),@(282.900000)],@[@(16.355290),@(48.208516),@(282.900000)],@[@(16.355130),@(48.208540),@(282.900000)],@[@(16.355115),@(48.208660),@(355.200000)],@[@(16.355100),@(48.208780),@(355.200000)],@[@(16.355122),@(48.208887),@(7.700000)],@[@(16.355143),@(48.208993),@(7.700000)],@[@(16.355165),@(48.209100),@(7.700000)],@[@(16.355187),@(48.209207),@(7.700000)],@[@(16.355208),@(48.209313),@(7.700000)],@[@(16.355230),@(48.209420),@(7.700000)],@[@(16.355255),@(48.209530),@(8.600000)],@[@(16.355280),@(48.209640),@(8.600000)],@[@(16.355305),@(48.209750),@(8.600000)],@[@(16.355330),@(48.209860),@(8.600000)],@[@(16.355355),@(48.209970),@(8.600000)],@[@(16.355380),@(48.210080),@(8.600000)],@[@(16.355405),@(48.210190),@(8.600000)],@[@(16.355430),@(48.210300),@(8.600000)],@[@(16.355456),@(48.210402),@(9.600000)],@[@(16.355482),@(48.210504),@(9.600000)],@[@(16.355508),@(48.210606),@(9.600000)],@[@(16.355534),@(48.210708),@(9.600000)],@[@(16.355560),@(48.210810),@(9.600000)],@[@(16.355585),@(48.210918),@(8.800000)],@[@(16.355610),@(48.211026),@(8.800000)],@[@(16.355635),@(48.211134),@(8.800000)],@[@(16.355660),@(48.211242),@(8.800000)],@[@(16.355685),@(48.211350),@(8.800000)],@[@(16.355710),@(48.211458),@(8.800000)],@[@(16.355735),@(48.211566),@(8.800000)],@[@(16.355760),@(48.211674),@(8.800000)],@[@(16.355785),@(48.211782),@(8.800000)],@[@(16.355810),@(48.211890),@(8.800000)],@[@(16.355836),@(48.211997),@(9.100000)],@[@(16.355861),@(48.212103),@(9.100000)],@[@(16.355887),@(48.212210),@(9.100000)],@[@(16.355912),@(48.212317),@(9.100000)],@[@(16.355938),@(48.212423),@(9.100000)],@[@(16.355963),@(48.212530),@(9.100000)],@[@(16.355989),@(48.212637),@(9.100000)],@[@(16.356014),@(48.212743),@(9.100000)],@[@(16.356040),@(48.212850),@(9.100000)],@[@(16.356064),@(48.212958),@(8.400000)],@[@(16.356088),@(48.213066),@(8.400000)],@[@(16.356112),@(48.213174),@(8.400000)],@[@(16.356136),@(48.213282),@(8.400000)],@[@(16.356160),@(48.213390),@(8.400000)],@[@(16.356187),@(48.213500),@(9.300000)],@[@(16.356214),@(48.213610),@(9.300000)],@[@(16.356241),@(48.213720),@(9.300000)],@[@(16.356269),@(48.213830),@(9.300000)],@[@(16.356296),@(48.213940),@(9.300000)],@[@(16.356323),@(48.214050),@(9.300000)],@[@(16.356350),@(48.214160),@(9.300000)],@[@(16.356397),@(48.214273),@(15.300000)],@[@(16.356443),@(48.214387),@(15.300000)],@[@(16.356490),@(48.214500),@(15.300000)],@[@(16.356280),@(48.214550),@(289.700000)],@[@(16.356310),@(48.214580),@(33.700000)],@[@(16.356467),@(48.214551),@(105.500000)],@[@(16.356624),@(48.214522),@(105.500000)],@[@(16.356781),@(48.214493),@(105.500000)],@[@(16.356938),@(48.214464),@(105.500000)],@[@(16.357095),@(48.214435),@(105.500000)],@[@(16.357252),@(48.214406),@(105.500000)],@[@(16.357409),@(48.214377),@(105.500000)],@[@(16.357566),@(48.214348),@(105.500000)],@[@(16.357723),@(48.214319),@(105.500000)],@[@(16.357880),@(48.214290),@(105.500000)],@[@(16.358033),@(48.214265),@(103.800000)],@[@(16.358185),@(48.214240),@(103.800000)],@[@(16.358338),@(48.214215),@(103.800000)],@[@(16.358490),@(48.214190),@(103.800000)],@[@(16.358643),@(48.214165),@(103.800000)],@[@(16.358795),@(48.214140),@(103.800000)],@[@(16.358948),@(48.214115),@(103.800000)],@[@(16.359100),@(48.214090),@(103.800000)],@[@(16.359252),@(48.214062),@(105.500000)],@[@(16.359404),@(48.214034),@(105.500000)],@[@(16.359556),@(48.214006),@(105.500000)],@[@(16.359708),@(48.213978),@(105.500000)],@[@(16.359860),@(48.213950),@(105.500000)],@[@(16.360029),@(48.213931),@(99.400000)],@[@(16.360197),@(48.213913),@(99.400000)],@[@(16.360366),@(48.213894),@(99.400000)],@[@(16.360534),@(48.213876),@(99.400000)],@[@(16.360703),@(48.213857),@(99.400000)],@[@(16.360871),@(48.213839),@(99.400000)],@[@(16.361040),@(48.213820),@(99.400000)],@[@(16.361270),@(48.213750),@(114.500000)],@[@(16.361440),@(48.213640),@(134.200000)],@[@(16.361605),@(48.213725),@(52.300000)],@[@(16.361770),@(48.213810),@(52.300000)],@[@(16.361912),@(48.213873),@(56.600000)],@[@(16.362055),@(48.213935),@(56.600000)],@[@(16.362198),@(48.213998),@(56.600000)],@[@(16.362340),@(48.214060),@(56.600000)],@[@(16.362590),@(48.214170),@(56.600000)],@[@(16.362620),@(48.214130),@(153.400000)],@[@(16.362750),@(48.214010),@(144.200000)],@[@(16.362880),@(48.213890),@(144.200000)],@[@(16.362660),@(48.213790),@(235.700000)],@[@(16.362590),@(48.213870),@(329.800000)],@[@(16.362530),@(48.213940),@(330.300000)],@[@(16.362670),@(48.214010),@(53.100000)],@[@(16.362804),@(48.214073),@(55.000000)],@[@(16.362938),@(48.214135),@(55.000000)],@[@(16.363071),@(48.214197),@(55.000000)],@[@(16.363205),@(48.214260),@(55.000000)],@[@(16.363339),@(48.214323),@(55.000000)],@[@(16.363473),@(48.214385),@(55.000000)],@[@(16.363606),@(48.214447),@(55.000000)],@[@(16.363740),@(48.214510),@(55.000000)],@[@(16.363871),@(48.214569),@(55.800000)],@[@(16.364002),@(48.214628),@(55.800000)],@[@(16.364133),@(48.214687),@(55.800000)],@[@(16.364263),@(48.214747),@(55.800000)],@[@(16.364394),@(48.214806),@(55.800000)],@[@(16.364525),@(48.214865),@(55.800000)],@[@(16.364656),@(48.214924),@(55.800000)],@[@(16.364787),@(48.214983),@(55.800000)],@[@(16.364918),@(48.215043),@(55.800000)],@[@(16.365048),@(48.215102),@(55.800000)],@[@(16.365179),@(48.215161),@(55.800000)],@[@(16.365310),@(48.215220),@(55.800000)],@[@(16.365446),@(48.215284),@(54.600000)],@[@(16.365581),@(48.215349),@(54.600000)],@[@(16.365717),@(48.215413),@(54.600000)],@[@(16.365853),@(48.215477),@(54.600000)],@[@(16.365989),@(48.215541),@(54.600000)],@[@(16.366124),@(48.215606),@(54.600000)],@[@(16.366260),@(48.215670),@(54.600000)],@[@(16.366391),@(48.215729),@(55.900000)],@[@(16.366522),@(48.215788),@(55.900000)],@[@(16.366653),@(48.215847),@(55.900000)],@[@(16.366784),@(48.215906),@(55.900000)],@[@(16.366915),@(48.215965),@(55.900000)],@[@(16.367046),@(48.216024),@(55.900000)],@[@(16.367177),@(48.216083),@(55.900000)],@[@(16.367308),@(48.216142),@(55.900000)],@[@(16.367439),@(48.216201),@(55.900000)],@[@(16.367570),@(48.216260),@(55.900000)],@[@(16.367698),@(48.216319),@(55.200000)],@[@(16.367827),@(48.216379),@(55.200000)],@[@(16.367956),@(48.216438),@(55.200000)],@[@(16.368084),@(48.216498),@(55.200000)],@[@(16.368212),@(48.216558),@(55.200000)],@[@(16.368341),@(48.216617),@(55.200000)],@[@(16.368469),@(48.216676),@(55.200000)],@[@(16.368598),@(48.216736),@(55.200000)],@[@(16.368727),@(48.216795),@(55.200000)],@[@(16.368855),@(48.216855),@(55.200000)],@[@(16.368983),@(48.216915),@(55.200000)],@[@(16.369112),@(48.216974),@(55.200000)],@[@(16.369241),@(48.217033),@(55.200000)],@[@(16.369369),@(48.217093),@(55.200000)],@[@(16.369498),@(48.217152),@(55.200000)],@[@(16.369626),@(48.217212),@(55.200000)],@[@(16.369754),@(48.217272),@(55.200000)],@[@(16.369883),@(48.217331),@(55.200000)],@[@(16.370012),@(48.217391),@(55.200000)],@[@(16.370140),@(48.217450),@(55.200000)],@[@(16.370310),@(48.217510),@(62.100000)],@[@(16.370540),@(48.217540),@(78.900000)],@[@(16.370705),@(48.217530),@(95.200000)],@[@(16.370870),@(48.217520),@(95.200000)],@[@(16.371100),@(48.217500),@(97.400000)],@[@(16.371250),@(48.217410),@(132.000000)],@[@(16.371400),@(48.217320),@(132.000000)],@[@(16.371580),@(48.217200),@(135.000000)],@[@(16.371675),@(48.217118),@(142.500000)],@[@(16.371770),@(48.217035),@(142.500000)],@[@(16.371865),@(48.216952),@(142.500000)],@[@(16.371960),@(48.216870),@(142.500000)],@[@(16.372055),@(48.216788),@(142.500000)],@[@(16.372150),@(48.216705),@(142.500000)],@[@(16.372245),@(48.216622),@(142.500000)],@[@(16.372340),@(48.216540),@(142.500000)],@[@(16.372417),@(48.216450),@(150.400000)],@[@(16.372493),@(48.216360),@(150.400000)],@[@(16.372570),@(48.216270),@(150.400000)],@[@(16.372647),@(48.216180),@(150.400000)],@[@(16.372723),@(48.216090),@(150.400000)],@[@(16.372800),@(48.216000),@(150.400000)],@[@(16.372877),@(48.215910),@(150.400000)],@[@(16.372953),@(48.215820),@(150.400000)],@[@(16.373030),@(48.215730),@(150.400000)],@[@(16.373100),@(48.215632),@(154.500000)],@[@(16.373170),@(48.215534),@(154.500000)],@[@(16.373240),@(48.215436),@(154.500000)],@[@(16.373310),@(48.215338),@(154.500000)],@[@(16.373380),@(48.215240),@(154.500000)],@[@(16.373455),@(48.215100),@(160.400000)],@[@(16.373530),@(48.214960),@(160.400000)],@[@(16.373592),@(48.214860),@(157.700000)],@[@(16.373653),@(48.214760),@(157.700000)],@[@(16.373715),@(48.214660),@(157.700000)],@[@(16.373777),@(48.214560),@(157.700000)],@[@(16.373838),@(48.214460),@(157.700000)],@[@(16.373900),@(48.214360),@(157.700000)],@[@(16.373970),@(48.214270),@(152.600000)],@[@(16.374040),@(48.214180),@(152.600000)],@[@(16.374110),@(48.214090),@(152.600000)],@[@(16.374185),@(48.213997),@(151.600000)],@[@(16.374260),@(48.213905),@(151.600000)],@[@(16.374335),@(48.213813),@(151.600000)],@[@(16.374410),@(48.213720),@(151.600000)],@[@(16.374507),@(48.213630),@(144.200000)],@[@(16.374605),@(48.213540),@(144.200000)],@[@(16.374703),@(48.213450),@(144.200000)],@[@(16.374800),@(48.213360),@(144.200000)],@[@(16.374909),@(48.213286),@(135.400000)],@[@(16.375018),@(48.213213),@(135.400000)],@[@(16.375127),@(48.213139),@(135.400000)],@[@(16.375236),@(48.213065),@(135.400000)],@[@(16.375345),@(48.212992),@(135.400000)],@[@(16.375455),@(48.212918),@(135.400000)],@[@(16.375564),@(48.212845),@(135.400000)],@[@(16.375673),@(48.212771),@(135.400000)],@[@(16.375782),@(48.212697),@(135.400000)],@[@(16.375891),@(48.212624),@(135.400000)],@[@(16.376000),@(48.212550),@(135.400000)],@[@(16.376133),@(48.212480),@(128.400000)],@[@(16.376265),@(48.212410),@(128.400000)],@[@(16.376397),@(48.212340),@(128.400000)],@[@(16.376530),@(48.212270),@(128.400000)],@[@(16.376690),@(48.212210),@(119.400000)],@[@(16.376850),@(48.212150),@(119.400000)],@[@(16.377003),@(48.212106),@(113.500000)],@[@(16.377156),@(48.212061),@(113.500000)],@[@(16.377309),@(48.212017),@(113.500000)],@[@(16.377461),@(48.211973),@(113.500000)],@[@(16.377614),@(48.211929),@(113.500000)],@[@(16.377767),@(48.211884),@(113.500000)],@[@(16.377920),@(48.211840),@(113.500000)],@[@(16.378082),@(48.211796),@(112.200000)],@[@(16.378244),@(48.211752),@(112.200000)],@[@(16.378406),@(48.211708),@(112.200000)],@[@(16.378568),@(48.211664),@(112.200000)],@[@(16.378730),@(48.211620),@(112.200000)],@[@(16.378910),@(48.211580),@(108.400000)],@[@(16.379090),@(48.211540),@(108.400000)],@[@(16.379240),@(48.211520),@(101.300000)],@[@(16.379390),@(48.211500),@(101.300000)],@[@(16.379542),@(48.211490),@(95.600000)],@[@(16.379695),@(48.211480),@(95.600000)],@[@(16.379848),@(48.211470),@(95.600000)],@[@(16.380000),@(48.211460),@(95.600000)],@[@(16.380153),@(48.211453),@(94.000000)],@[@(16.380306),@(48.211446),@(94.000000)],@[@(16.380459),@(48.211439),@(94.000000)],@[@(16.380611),@(48.211431),@(94.000000)],@[@(16.380764),@(48.211424),@(94.000000)],@[@(16.380917),@(48.211417),@(94.000000)],@[@(16.381070),@(48.211410),@(94.000000)],@[@(16.381233),@(48.211406),@(92.300000)],@[@(16.381397),@(48.211401),@(92.300000)],@[@(16.381560),@(48.211397),@(92.300000)],@[@(16.381723),@(48.211392),@(92.300000)],@[@(16.381887),@(48.211388),@(92.300000)],@[@(16.382050),@(48.211383),@(92.300000)],@[@(16.382213),@(48.211379),@(92.300000)],@[@(16.382377),@(48.211374),@(92.300000)],@[@(16.382540),@(48.211370),@(92.300000)]];
    _simPositionIndex = 0;
}

@end

