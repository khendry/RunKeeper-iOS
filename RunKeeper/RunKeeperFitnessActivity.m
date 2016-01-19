//
//  RunKeeperFitnessActivity.m
//  RunKeeper-iOS
//
//  Created by Falko Buttler on 5/2/13.
//  Copyright 2013 BlueBamboo.de Apps (www.bluebamboo.de). All rights reserved.
//

#import "RunKeeperFitnessActivity.h"

@implementation RunKeeperFitnessActivity

// For debugging purposes
- (NSString*)description
{
    return [NSString stringWithFormat:@"Date: %@, type: %@, distance: %.2f, duration: %.2f, calories: %@, cal/h: %.0f, uri: %@",
            _startTime,
            [RunKeeperFitnessActivity activityString:_activityType],
            _totalDistanceInMeters.doubleValue / 1000.0,
            _durationInSeconds.doubleValue / 60.0,
            _totalCalories,
            _totalCalories.doubleValue / (_durationInSeconds.doubleValue / 60.0) * 60.0,
            _uri];
}


+ (NSString*)activityString:(RunKeeperActivityType)activity
{
    switch (activity) {
        case kRKRunning:        return @"Running";
        case kRKCycling:        return @"Cycling";
        case kRKMountainBiking: return @"Mountain Biking";
        case kRKWalking:        return @"Walking";
        case kRKHiking:         return @"Hiking";
        case kRKDownhillSkiing: return @"Downhill Skiing";
        case kRKXCountrySkiing: return @"Cross Country Skiing";
        case kRKSnowboarding:   return @"Snowboarding";
        case kRKSkating:        return @"Skating";
        case kRKSwimming:       return @"Swimming";
        case kRKWheelchair:     return @"Wheelchair";
        case kRKRowing:         return @"Rowing";
        case kRKElliptical:     return @"Elliptical";
        case kRKOther:          return @"Other";
    }
    return @"Running";
}

@end
