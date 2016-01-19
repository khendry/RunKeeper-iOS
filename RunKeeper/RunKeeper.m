//
//  RunKeeper.m
//  RunKeeper-iOS
//
//  Created by Reid van Melle on 11-09-14.
//  Copyright 2011 Brierwood Design Co-operative. All rights reserved.
//

#import <AFNetworking/AFNetworking.h>
#import <AFNetworking/AFNetworkActivityIndicatorManager.h>
#import "NSDate+JSON.h"
#import "RunKeeper.h"
#import "RunKeeperPathPoint.h"
#import "RunKeeperProfile.h"


#define kRunKeeperAuthorizationURL @"https://runkeeper.com/apps/authorize"
#define kRunKeeperAccessTokenURL @"https://runkeeper.com/apps/token"

#define kRunKeeperBasePath @"https://api.runkeeper.com"
#define kRunKeeperBaseURL @"/user/"

#define SecondsPerDay (24 * 60 * 60)
#define kNotConnectedErrorCode         100
#define kPaginatorStillActiveErrorCode 101

#define kRKBackgroundActivitiesKey        @"background_activities"
#define kRKDiabetesKey                    @"diabetes"
#define kRKFitnessActivitiesKey           @"fitness_activities"
#define kRKGeneralMeasurementsKey         @"general_measurements"
#define kRKNutritionKey                   @"nutrition"
#define kRKProfileKey                     @"profile"
#define kRKRecordsKey                     @"records"
#define kRKSettingsKey                    @"settings"
#define kRKSleepKey                       @"sleep"
#define kRKStrengthTrainingActivitiesKey  @"strength_training_activities"
#define kRKTeamKey                        @"team"
#define kRKUserIDKey                      @"userID"
#define kRKWeightKey                      @"weight"

NSString *const kRunKeeperErrorDomain = @"RunKeeperErrorDomain";
NSString *const kRunKeeperStatusTextKey = @"RunKeeperStatusText";
NSString *const kRunKeeperNewPointNotification = @"RunKeeperNewPointNotification";


@interface RunKeeper()
{
    BOOL _isLoading;
    NSUInteger _pageSize;
    NSUInteger _currentPage;
    NSUInteger _totalPages;
    NSMutableArray* _allItems;
}

- (NSString*)localizedStatusText:(NSString*)bitlyStatusTxt;

- (NSError*)errorWithCode:(NSInteger)code status:(NSString*)status;

- (void)newPathPoint:(NSNotification*)note;

- (void)getBasePathsWithSuccess:(RIBasicCompletionBlock)success
                         failed:(RIBasicFailedBlock)failed;

@property (nonatomic, strong) NSDictionary *paths;
@property (nonatomic, strong) NSNumber *userID;

@property (nonatomic, readwrite) BOOL connected;

// OAuth stuff
@property (nonatomic, strong) NSString *clientID, *clientSecret;
@property (nonatomic, strong) NXOAuth2Client *oauthClient;
@property (nonatomic, strong) AFHTTPRequestOperationManager *httpRequestManager;

@end


@implementation RunKeeper


- (id)initWithClientID:(NSString*)clientID clientSecret:(NSString*)secret
{
    self = [super init];
    if (self) {
        self.clientID = clientID;
        self.clientSecret = secret;
        
        //Replacement for AFHTTPClient:
        self.httpRequestManager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:[NSURL URLWithString:kRunKeeperBasePath]];
        
        NXOAuth2AccessToken *tokenObject = self.oauthClient.accessToken;
        NSString *tokenString = tokenObject.accessToken;
        
        [self.httpRequestManager setRequestSerializer:[AFJSONRequestSerializer serializer]];
        
        [self.httpRequestManager.requestSerializer setValue:[NSString stringWithFormat:@"Bearer %@", tokenString]
                         forHTTPHeaderField:@"Authorization"];
        
        [self.httpRequestManager.requestSerializer setValue:@"application/vnd.com.runkeeper.user+json"
                         forHTTPHeaderField:@"Content-Type"];
        
        self.httpRequestManager.responseSerializer = [AFJSONResponseSerializer serializer];
        
        AFNetworkActivityIndicatorManager *manager = [AFNetworkActivityIndicatorManager sharedManager];
        manager.enabled = YES;

        //AFNetworking 1.0
//        self.httpClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:kRunKeeperBasePath]];
//        self.httpClient.parameterEncoding = AFJSONParameterEncoding;
//        [self.httpClient registerHTTPOperationClass:[AFJSONRequestOperation class]];
        
//        [AFJSONRequestOperation addAcceptableContentTypes:[NSSet setWithObjects:@"application/vnd.com.runkeeper.user+json",
//                                                           @"application/vnd.com.runkeeper.fitnessactivityfeed+json",
//                                                           @"application/vnd.com.runkeeper.fitnessactivitysummary+json",
//                                                           @"application/vnd.com.runkeeper.fitnessactivity+json",
//                                                           @"application/vnd.com.runkeeper.profile+json",
//                                                           nil]];

        self.connected = self.oauthClient.accessToken != nil;
        
        self.currentPath = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(newPathPoint:)
                                                     name:kRunKeeperNewPointNotification object:nil];
    }
    return self;
}


- (void)newPathPoint:(NSNotification*)note
{
    RunKeeperPathPoint *pt = [note object];
    if (pt.pointType == kRKStartPoint) {
        self.startPointTimestamp = pt.time;
    }
    // If we have not received a start point, then just ignore any of the points
    if (self.startPointTimestamp == nil) return;
    pt.timeStamp = [pt.time timeIntervalSinceDate:self.startPointTimestamp];
    
    [self.currentPath addObject:pt];
}


- (void)tryToConnect:(id <RunKeeperConnectionDelegate>)newDelegate
{
    [self.oauthClient requestAccess];
}

- (void)disconnect
{
    self.oauthClient.accessToken = nil;
    self.connected = NO;
}


- (void)tryToAuthorize
{
    NSString *oauth_path = [NSString stringWithFormat:@"rk%@://oauth2", self.clientID];
    NSURL *authorizationURL = [self.oauthClient authorizationURLWithRedirectURL:[NSURL URLWithString:oauth_path]];
    
    if ([self.delegate respondsToSelector:@selector(needsAuthentication:)]) {
        [self.delegate needsAuthentication:authorizationURL];
    }
    else {
        [[UIApplication sharedApplication] openURL:authorizationURL];
    }
}


- (void)handleOpenURL:(NSURL *)url
{
    [self.oauthClient openRedirectURL:url];
}



- (NSString*)localizedStatusText:(NSString*)bitlyStatusTxt {
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *status = [bundle localizedStringForKey:bitlyStatusTxt value:bitlyStatusTxt table:@"RunKeeperErrors"];
    
	return status;
}


- (NSError*)errorWithCode:(NSInteger)code status:(NSString*)status
{
	NSMutableDictionary *userDict = [NSMutableDictionary dictionary];
	[userDict setObject:status forKey:kRunKeeperStatusTextKey];
	status = [self localizedStatusText:status];
	if(status)
		[userDict setObject:status forKey:NSLocalizedDescriptionKey];
	NSError *bitlyError = [NSError errorWithDomain:kRunKeeperErrorDomain code:code userInfo:userDict];
    
	return bitlyError;
}


- (void)getBasePathsWithSuccess:(RIBasicCompletionBlock)success
                         failed:(RIBasicFailedBlock)failed
{
    NSString *urlString = [NSString stringWithFormat:@"%@%@", kRunKeeperBasePath, kRunKeeperBaseURL];

    [self.httpRequestManager GET:urlString
                      parameters:nil
                         success:^(AFHTTPRequestOperation *operation, id responseObject) {
                             self.paths = responseObject;
                             self.userID = [self.paths objectForKey:kRKUserIDKey];
                             
                             if (success) {
                                 success();
                             }
                         }
                         failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                             NSError *failError = [NSError errorWithDomain:@"RunKeeper Error"
                                                                      code:0
                                                                  userInfo:@{NSLocalizedDescriptionKey:
                                                                                 @"Error while communicating with RunKeeper."}];
                             
                             //AFNetworking 2.0 modification: check for errors here again, as the response string could still be valid in the fail block (weird)...
                             if (operation.responseString == nil) {
                                 self.paths = nil;
                                 self.userID = nil;
                                 self.connected = NO;
                                 
                                 if (failed) {
                                     failed(failError);
                                 }
                             }
                             else {
                                 //Extract the userID out of the responseString...
                                 NSError *jsonError = nil;
                                 NSDictionary *json = [NSJSONSerialization JSONObjectWithData:operation.responseData
                                                                                      options:NSJSONReadingAllowFragments
                                                                                        error:&jsonError];
                                 self.paths = json;
                                 self.userID = [self.paths objectForKey:kRKUserIDKey];
                                 
                                 if (self.userID == nil) {
                                     if (failed) {
                                         failed(failError);
                                     }
                                 }
                                 else {
                                     if (success) {
                                         success();
                                     }
                                 }
                             }
                         }];
}


#pragma mark RunKeeperAPI Calls

- (void)getProfileOnSuccess:(void (^)(RunKeeperProfile *profile))success
                     failed:(RIBasicFailedBlock)failed
{
    if (!self.connected) {
        NSError *err = [self errorWithCode:kNotConnectedErrorCode status:@"You are not connected to RunKeeper"];
        if (failed) failed(err);
        return;
    }
    
    NSURL *baseURL = [NSURL URLWithString:[self.paths objectForKey:kRKProfileKey]];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/GET" relativeToURL:baseURL]];
    
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc]
                                         initWithRequest:request];
    operation.responseSerializer = [AFJSONResponseSerializer serializer];
    
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
     {
         RunKeeperProfile* profile = [[RunKeeperProfile alloc] init];
         NSDictionary *json = (NSDictionary *)responseObject;
         
         profile.name = [json objectForKey:@"name"];
         profile.location = [json objectForKey:@"location"];
         profile.athleteType = [json objectForKey:@"athlete_type"];
         profile.gender = [json objectForKey:@"gender"];
         profile.birthday = [json objectForKey:@"birthday"];
         profile.elite = [[json objectForKey:@"elite"] boolValue];
         profile.profile = [json objectForKey:@"profile"];
         profile.smallPicture = [json objectForKey:@"small_picture"];
         profile.normalPicture = [json objectForKey:@"normal_picture"];
         profile.mediumPicture = [json objectForKey:@"medium_picture"];
         profile.largePicture = [json objectForKey:@"large_picture"];
         
         if (success) {
             success(profile);
         }
     }
                                     failure:^(AFHTTPRequestOperation *operation, NSError *error)
     {
         if ( failed ) {
             failed(error);
         }
     }];
    
    [self.httpRequestManager.operationQueue addOperation:operation];
}


+ (RunKeeperActivityType)activityType:(NSString*)type
{
    if ( [type isEqualToString:@"Running"] ) {
        return kRKRunning;
    }
    else if ( [type isEqualToString:@"Cycling"] ) {
        return kRKCycling;
    }
    else if ( [type isEqualToString:@"Mountain Biking"] ) {
        return kRKMountainBiking;
    }
    else if ( [type isEqualToString:@"Walking"] ) {
        return kRKWalking;
    }
    else if ( [type isEqualToString:@"Hiking"] ) {
        return kRKHiking;
    }
    else if ( [type isEqualToString:@"Downhill Skiing"] ) {
        return kRKDownhillSkiing;
    }
    else if ( [type isEqualToString:@"Cross Country Skiing"] ) {
        return kRKXCountrySkiing;
    }
    else if ( [type isEqualToString:@"Snowboarding"] ) {
        return kRKSnowboarding;
    }
    else if ( [type isEqualToString:@"Skating"] ) {
        return kRKSkating;
    }
    else if ( [type isEqualToString:@"Swimming"] ) {
        return kRKSwimming;
    }
    else if ( [type isEqualToString:@"Wheelchair"] ) {
        return kRKWheelchair;
    }
    else if ( [type isEqualToString:@"Rowing"] ) {
        return kRKRowing;
    }
    else if ( [type isEqualToString:@"Elliptical"] ) {
        return kRKElliptical;
    }
    return kRKOther;
}


- (void)postActivity:(RunKeeperActivityType)activity start:(NSDate*)start distance:(NSNumber*)distance
            duration:(NSNumber*)duration calories:(NSNumber*)calories avgHeartRate:(NSNumber*)avgHeartRate
               notes:(NSString*)notes path:(NSArray*)path  heartRatePoints:(NSArray*)heartRatePoints
             success:(RIBasicCompletionBlock)success failed:(RIBasicFailedBlock)failed
{
    if (!self.connected) {
        NSError *err = [self errorWithCode:kNotConnectedErrorCode status:@"You are not connected to RunKeeper"];
        if (failed) failed(err);
        return;
    }
    
    NSMutableDictionary *activityDictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                               [RunKeeperFitnessActivity activityString:activity], @"type",
                                               [start proxyForJson], @"start_time",
                                               distance, @"total_distance",
                                               duration, @"duration",
                                               nil];
    
    if (avgHeartRate != nil){
        [activityDictionary setValue:avgHeartRate forKey:@"average_heart_rate"];
    }
    
    if (calories != nil){
        [activityDictionary setValue:calories forKey:@"total_calories"];
    }
    
    if (notes != nil){
        [activityDictionary setValue:notes forKey:@"notes"];
    }
    
    if (path != nil){
        [activityDictionary setValue:[path valueForKeyPath:@"proxyForJson"] forKey:@"path"];
    }
    
    if (heartRatePoints != nil){
        [activityDictionary setValue:[heartRatePoints valueForKeyPath:@"proxyForJson"] forKey:@"heart_rate"];
    }
    
    //Set request serializer...
    [self.httpRequestManager.requestSerializer setValue:@"application/vnd.com.runkeeper.NewFitnessActivity+json"
                                     forHTTPHeaderField:@"Content-Type"];
    
    //Make request...
    NSString *urlString = [NSString stringWithFormat:@"%@%@",
                           kRunKeeperBasePath,
                           [self.paths objectForKey:kRKFitnessActivitiesKey]];
    
    [self.httpRequestManager POST:urlString
                       parameters:activityDictionary
                          success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
                              if (success) {
                                  success();
                              }
                          }
                          failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
                              if (failed) {
                                  failed(error);
                              }
                          }];
}


- (void)getFitnessActivityFeedNoEarlierThan:(NSDate*)noEarlierThan
                                noLaterThan:(NSDate*)noLaterThan
                      modifiedNoEarlierThan:(NSDate*)modifiedNoEarlierThan
                        modifiedNoLaterThan:(NSDate*)modifiedNoLaterThan
                                   progress:(RIPaginatorCompletionBlock)progress
                                    success:(RIPaginatorCompletionBlock)success
                                     failed:(RIBasicFailedBlock)failed
{
    if (!self.connected) {
        NSError *err = [self errorWithCode:kNotConnectedErrorCode status:@"You are not connected to RunKeeper"];
        if (failed) failed(err);
        return;
    }

    if ( _isLoading ) {
        NSError *err = [self errorWithCode:kPaginatorStillActiveErrorCode status:@"The paginator is still active"];
        if (failed) failed(err);
        return;
    }
    
    _isLoading = YES;
    _pageSize = 25;
    _currentPage = 0;
    _totalPages = 1;
    _allItems = [NSMutableArray array];
        
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd";
    
    if ( !noEarlierThan ) {
        noEarlierThan = [NSDate dateWithTimeIntervalSince1970:0];
    }
    if ( !modifiedNoEarlierThan ) {
        modifiedNoEarlierThan = [NSDate dateWithTimeIntervalSince1970:0];
    }
    if ( !noLaterThan ) {
        noLaterThan = [NSDate dateWithTimeIntervalSinceNow:SecondsPerDay * 2]; // this is what RunKeeper does by default
    }
    if ( !modifiedNoLaterThan ) {
        modifiedNoLaterThan = [NSDate dateWithTimeIntervalSinceNow:SecondsPerDay * 2]; // this is what RunKeeper does by default
    }
    
    NSDictionary* dict = @{@"pageSize" : @(_pageSize),
                           @"noEarlierThan" : [dateFormatter stringFromDate:noEarlierThan],
                           @"noLaterThan" : [dateFormatter stringFromDate:noLaterThan],
                           @"modifiedNoEarlierThan" : [dateFormatter stringFromDate:modifiedNoEarlierThan],
                           @"modifiedNoLaterThan" : [dateFormatter stringFromDate:modifiedNoLaterThan]};
    [self loadNextPage:[self.paths objectForKey:kRKFitnessActivitiesKey] parameters:dict progress:progress success:success failed:failed];
}


- (void)fillFitnessActivity:(RunKeeperFitnessActivity*)item fromFeedDict:(NSDictionary*)itemDict
{
    item.activityType = [RunKeeper activityType:[itemDict objectForKey:@"type"]];
    item.startTime = [NSDate dateFromJSONDate:[itemDict objectForKey:@"start_time"]];
    item.totalDistanceInMeters = [itemDict objectForKey:@"total_distance"];
    item.durationInSeconds = [itemDict objectForKey:@"duration"];
    item.source = [itemDict objectForKey:@"source"];
    item.entryMode = [itemDict objectForKey:@"entry_mode"];
    item.hasPath = [[itemDict objectForKey:@"has_path"] boolValue];
    item.uri = [itemDict objectForKey:@"uri"];
}

- (void)fillFitnessActivity:(RunKeeperFitnessActivity*)item fromSummaryDict:(NSDictionary*)itemDict
{
    [self fillFitnessActivity:item fromFeedDict:itemDict];
    item.userID = [itemDict objectForKey:@"userID"];
    item.secondaryType = [itemDict objectForKey:@"secondary_type"];
    item.equipment = [itemDict objectForKey:@"equipment"];
    item.averageHeartRate = [itemDict objectForKey:@"average_heart_rate"];
    item.totalCalories = [itemDict objectForKey:@"total_calories"];
    item.climbInMeters = [itemDict objectForKey:@"climb"];
    item.notes = [itemDict objectForKey:@"notes"];
    item.isLive = [[itemDict objectForKey:@"is_live"] boolValue];
    item.share = [itemDict objectForKey:@"share"];
    item.shareMap = [itemDict objectForKey:@"share_map"];
    item.publicURI = [itemDict objectForKey:@"activity"];
}


- (void)loadNextPage:(NSString*)uri
          parameters:(NSDictionary*)dict
            progress:(RIPaginatorCompletionBlock)progress
             success:(RIPaginatorCompletionBlock)success
              failed:(RIBasicFailedBlock)failed
{
    NSURL *baseURL = [NSURL URLWithString:uri];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/GET" relativeToURL:baseURL]];
    
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc]
                                         initWithRequest:request];
    operation.responseSerializer = [AFJSONResponseSerializer serializer];
    
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
     {
         NSDictionary *json = (NSDictionary *)responseObject;
         NSArray* itemDicts = [json objectForKey:@"items"];
         NSMutableArray* items = [NSMutableArray arrayWithCapacity:itemDicts.count];
         
         for( NSDictionary* itemDict in itemDicts ) {
             RunKeeperFitnessActivity* item = [[RunKeeperFitnessActivity alloc] init];
             [self fillFitnessActivity:item fromFeedDict:itemDict];
             [items addObject:item];
         }
         [_allItems addObjectsFromArray:items];
         
         if ( _currentPage == 0 ) {
             _totalPages = roundf(([[json objectForKey:@"size"] floatValue] / (float)_pageSize) + 0.5);
         }
         
         if ( _totalPages == 1 || _currentPage == _totalPages-1 ) { // We reached the last page
             _isLoading = NO;
             if (progress) {
                 progress(items, _currentPage, _totalPages);
             }
             if (success) {
                 success(_allItems, _currentPage, _totalPages);
             }
             _allItems = nil;
         }
         else { // Load next page recursively
             NSString* nextPageURI = [json objectForKey:@"next"];
             [self loadNextPage:nextPageURI parameters:nil progress:progress success:success failed:failed];
             
             if ( progress ) {
                 progress(items, _currentPage, _totalPages);
             }
             _currentPage++;
         }
     }
                                     failure:^(AFHTTPRequestOperation *operation, NSError *error)
     {
         _isLoading = NO;
         _allItems = nil;
         if (failed) {
             failed(error);
         }
     }];

    [self.httpRequestManager.operationQueue addOperation:operation];
}


- (void)getFitnessActivitySummary:(NSString*)uri
                          success:(RIFitnessActivityCompletionBlock)success
                           failed:(RIBasicFailedBlock)failed
{
    NSURL *baseURL = [NSURL URLWithString:uri];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/GET" relativeToURL:baseURL]];
    
    [request setValue:@"application/vnd.com.runkeeper.FitnessActivitySummary+json" forHTTPHeaderField:@"Accept"];
    
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc]
                                         initWithRequest:request];
    operation.responseSerializer = [AFJSONResponseSerializer serializer];
    
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        RunKeeperFitnessActivity *item = [[RunKeeperFitnessActivity alloc] init];
        [self fillFitnessActivity:item fromSummaryDict:responseObject];
        if (success) {
            success(item);
        }
    }
                                     failure:^(AFHTTPRequestOperation *operation, NSError *error)
    {
        if (failed) {
            failed(error);
        }
    }];
    
    [self.httpRequestManager.operationQueue addOperation:operation];
}


#pragma mark NXOAuth2ClientDelegate
- (void)oauthClientDidGetAccessToken:(NXOAuth2Client *)client
{
    NSLog(@"didGetAccessToken");
    [self.httpRequestManager setRequestSerializer:[AFJSONRequestSerializer serializer]];
    [self.httpRequestManager.requestSerializer setValue:@"application/vnd.com.runkeeper.user+json;charset=ISO-8859-1"
                                     forHTTPHeaderField:@"Content-Type"];
    
    NXOAuth2AccessToken *tokenObject = self.oauthClient.accessToken;
    NSString *tokenString = tokenObject.accessToken;
    
    [self.httpRequestManager.requestSerializer setValue:[NSString stringWithFormat:@"Bearer %@", tokenString]
                                     forHTTPHeaderField:@"Authorization"];
    
    self.connected = YES;

    [self getBasePathsWithSuccess:^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(connected)]) {
            [self.delegate connected];
        }
    }
                           failed:^(NSError *err) {
                               if (self.delegate && [self.delegate respondsToSelector:@selector(connectionFailed:)]) {
                                   [self.delegate connectionFailed:err];
                               }
                           }];


}


- (void)oauthClientDidLoseAccessToken:(NXOAuth2Client *)client
{
    NSLog(@"didLoseAccessToken");
    self.connected = NO;
    if (self.delegate && [self.delegate respondsToSelector:@selector(connectionFailed:)]) {
        [self.delegate connectionFailed:nil];
    }
}
- (void)oauthClient:(NXOAuth2Client *)client didFailToGetAccessTokenWithError:(NSError *)error
{
    NSLog(@"didFailToGetAccessToken");
    self.connected = NO;
    if (self.delegate && [self.delegate respondsToSelector:@selector(connectionFailed:)]) {
        [self.delegate connectionFailed:nil];
    }
}

- (void)oauthClientNeedsAuthentication:(NXOAuth2Client *)client
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(needsAuthentication)]) {
        [self.delegate needsAuthentication];
    }
}

 
- (NXOAuth2Client*)oauthClient
{
    if (_oauthClient == nil)
    {
        assert(self.clientID);
        assert(self.clientSecret);
        _oauthClient = [[NXOAuth2Client alloc] initWithClientID:self.clientID
                                                  clientSecret:self.clientSecret
                                                  authorizeURL:[NSURL URLWithString:kRunKeeperAuthorizationURL]
                                                      tokenURL:[NSURL URLWithString:kRunKeeperAccessTokenURL]
                                                      delegate:self];
        
        NXOAuth2AccessToken *tokenObject = self.oauthClient.accessToken;
        NSString *tokenString = tokenObject.accessToken;
        
        [self.httpRequestManager.requestSerializer setValue:[NSString stringWithFormat:@"Bearer %@", tokenString]
                                         forHTTPHeaderField:@"Authorization"];
    }
    return _oauthClient;
}



#pragma mark -
#pragma mark Memory management

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
 
 
@end
