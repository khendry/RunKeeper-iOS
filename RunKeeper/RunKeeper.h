//
//  RunKeeper.h
//  RunKeeper-iOS
//
//  Created by Reid van Melle on 11-09-14.
//  Copyright 2011 Brierwood Design Co-operative. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <NXOAuth2Client/NXOAuth2Client.h>
#import <NXOAuth2Client/NXOAuth2AccessToken.h>
#import "RunKeeperFitnessActivity.h"


@class RunKeeperProfile;

// Some typedefs to make the ugly code slightly less ugly
typedef void(^RIBasicCompletionBlock)(void);
typedef void(^RIJSONCompletionBlock)(id json);
typedef void(^RIFitnessActivityCompletionBlock)(RunKeeperFitnessActivity* activity);
typedef void(^RIBasicFailedBlock)(NSError *err);
typedef void(^RIPaginatorCompletionBlock)(NSArray* items, NSUInteger page, NSUInteger totalPages);



// Here is your protocol if you want to dance with the oauth prom queen
@protocol RunKeeperConnectionDelegate <NSObject>

@optional
// Connected is called when an existing auth token is found
- (void)connected;

// Called when the request to connect to runkeeper failed
- (void)connectionFailed:(NSError*)err;

// Called when authentication is needed to connect to RunKeeper --- normally, the client app will call
// tryToAuthorize at this point
- (void)needsAuthentication;

// Call to let the delegate handle processing the NSURL, instead of this class.
- (void)needsAuthentication:(NSURL *)authorizationURL;

@end




/** Use this to post notifications of new path points to be auto-recorded by the RunKeeper API and stored
 in currentPath --- see the sample app for more details and sample usage. */
extern NSString *const kRunKeeperNewPointNotification;

@interface RunKeeper : NSObject <NXOAuth2ClientDelegate> {
}

@property (nonatomic, assign) id <RunKeeperConnectionDelegate> delegate;

// The timestamp for the starting point --- used to calculate relative times
@property (nonatomic, strong) NSDate *startPointTimestamp;


/** TRUE if RunKeeper API thinks we have a valid connection -- NOTE, we could be wrong.  The API
 will check for an authorization token at startup and assume it is valid if found.  Otherwise, the connected
 status will get updated during actual oauth connections or manual disconnects.
*/
@property (nonatomic, readonly) BOOL connected;


/** The currentPath of GPS points which the RunKeeper API has recorded via notifications (if you 
 decide to use this feature).  You can safely pass this into the postActivity call.
 */
@property (nonatomic, strong) NSMutableArray *currentPath;

/** Create a new client with your shiny credentials and secretz pleeze
 */
- (id)initWithClientID:(NSString*)clientID clientSecret:(NSString*)secret;

/** Callback from RunKeeper oauth */
- (void)handleOpenURL:(NSURL *)url;

/** Try to connect to the RunKeeper API via auth. The delegate will receive callbacks about the status
 and state of things.  NOTE: this will not actually trigger the authorization flow --- just checks for 
 existing authorization. */
- (void)tryToConnect:(id <RunKeeperConnectionDelegate>)newDelegate;

/** This actually initiates the authorization process --- it is not triggered authomatically since it
 may not be appropriate for your application. */
- (void)tryToAuthorize;

/** Disconnect from the RunKeeper API --- all this does is *forget* the authorization token; there
 are not actual network calls being made */
- (void)disconnect;

/** Returns the profile of the connected user */
- (void)getProfileOnSuccess:(void (^)(RunKeeperProfile *profile))success
                     failed:(RIBasicFailedBlock)failed;

/** Returns the activity type for the string retrieved in the "type" field from the API */
+ (RunKeeperActivityType)activityType:(NSString*)type;

/** Post an activity to RunKeeper --- will fail unless you are already connected.  Almost all of
 the parameters are optional -- the only requirements are those of the RunKeeper web API itself which
 is to provide a start time, activity type, and either the distance or path points. */
- (void)postActivity:(RunKeeperActivityType)activity
               start:(NSDate*)start
            distance:(NSNumber*)distance
            duration:(NSNumber*)duration
            calories:(NSNumber*)calories
        avgHeartRate:(NSNumber*)avgHeartRate
               notes:(NSString*)notes
                path:(NSArray*)path
     heartRatePoints:(NSArray*)heartRatePoints
             success:(RIBasicCompletionBlock)success
              failed:(RIBasicFailedBlock)failed;

/** Retrieves the complete fitness activity feed from Runkeeper. Since RunKeeper returns the feed in pages, the method will
 recursively retrieve all pages and will call the success block with all retrieved objects upon completion. The progress
 block will be called after every loaded page and contains objects retrieved for that page. The retrieved object lists 
 contain instances of RunKeeperFitnessActivityItem. */
- (void)getFitnessActivityFeedNoEarlierThan:(NSDate*)noEarlierThan
                                noLaterThan:(NSDate*)noLaterThan
                      modifiedNoEarlierThan:(NSDate*)modifiedNoEarlierThan
                        modifiedNoLaterThan:(NSDate*)modifiedNoLaterThan
                                   progress:(RIPaginatorCompletionBlock)progress
                                    success:(RIPaginatorCompletionBlock)success
                                     failed:(RIBasicFailedBlock)failed;

/** Retrieves the summary information for a single fitness activity URI and returns the populated activity object in
the success block */
- (void)getFitnessActivitySummary:(NSString*)uri
                          success:(RIFitnessActivityCompletionBlock)success
                           failed:(RIBasicFailedBlock)failed;

@end

// Nothing to see here
extern NSString *const kRunKeeperErrorDomain;
extern NSString *const kRunKeeperStatusTextKey;
