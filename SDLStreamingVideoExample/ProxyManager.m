//
//  ProxyManager.m
//  SDLStreamingVideoExample
//
//  Created by Nicole on 8/4/17.
//  Copyright © 2017 Livio. All rights reserved.
//

#import "SmartDeviceLink.h"
#import "ProxyManager.h"

NSString *const SDLAppName = @"SDL Example App";
NSString *const SDLAppId = @"9999";
NSString *const SDLIPAddress = @"192.168.1.249";
UInt16 const SDLPort = (UInt16)2776;

BOOL const ShouldRestartOnDisconnect = NO;

typedef NS_ENUM(NSUInteger, SDLHMIFirstState) {
    SDLHMIFirstStateNone,
    SDLHMIFirstStateNonNone,
    SDLHMIFirstStateFull
};

typedef NS_ENUM(NSUInteger, SDLHMIInitialShowState) {
    SDLHMIInitialShowStateNone,
    SDLHMIInitialShowStateDataAvailable,
    SDLHMIInitialShowStateShown
};


NS_ASSUME_NONNULL_BEGIN

@interface ProxyManager () <SDLManagerDelegate>

// Describes the first time the HMI state goes non-none and full.
@property (assign, nonatomic) SDLHMIFirstState firstTimeState;
@property (assign, nonatomic) SDLHMIInitialShowState initialShowState;

@end


@implementation ProxyManager

#pragma mark - Initialization

+ (instancetype)sharedManager {
    static ProxyManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[ProxyManager alloc] init];
    });

    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _state = ProxyStateStopped;
    _firstTimeState = SDLHMIFirstStateNone;
    _initialShowState = SDLHMIInitialShowStateNone;

    return self;
}

- (void)startIAP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];
    // Check for previous instance of sdlManager
    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration defaultConfigurationWithAppName:SDLAppName appId:SDLAppId]];
    SDLConfiguration *config = [SDLConfiguration configurationWithLifecycle:lifecycleConfig lockScreen:[SDLLockScreenConfiguration enabledConfiguration] logging:[SDLLogConfiguration defaultConfiguration]];
    self.sdlManager = [[SDLManager alloc] initWithConfiguration:config delegate:self];

    [self startManager];
}

- (void)startTCP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];
    // Check for previous instance of sdlManager
    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration debugConfigurationWithAppName:SDLAppName appId:SDLAppId ipAddress:SDLIPAddress port:SDLPort]];
    SDLConfiguration *config = [SDLConfiguration configurationWithLifecycle:lifecycleConfig lockScreen:[SDLLockScreenConfiguration enabledConfiguration] logging:[SDLLogConfiguration defaultConfiguration]];
    self.sdlManager = [[SDLManager alloc] initWithConfiguration:config delegate:self];

    [self startManager];
}

- (void)startManager {
    __weak typeof (self) weakSelf = self;
    [self.sdlManager startWithReadyHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            SDLLogE(@"SDL errored starting up: %@", error);
            [weakSelf sdlex_updateProxyState:ProxyStateStopped];
            return;
        }

        [weakSelf sdlex_updateProxyState:ProxyStateConnected];

        [weakSelf sdlex_setupPermissionsCallbacks];

        if ([weakSelf.sdlManager.hmiLevel isEqualToEnum:SDLHMILevelFull]) {
            [weakSelf sdlex_showInitialData];
        }
    }];
}

- (void)reset {
    [self sdlex_updateProxyState:ProxyStateStopped];
    [self.sdlManager stop];
    // Remove reference
    self.sdlManager = nil;
}

#pragma mark - Helpers

- (void)sdlex_showInitialData {
    if ((self.initialShowState != SDLHMIInitialShowStateDataAvailable) || ![self.sdlManager.hmiLevel isEqualToEnum:SDLHMILevelFull]) {
        return;
    }

    SDLSetDisplayLayout *displayLayout = [[SDLSetDisplayLayout alloc] initWithLayout:SDLPredefinedLayoutNonMedia];
    [self.sdlManager sendRequest:displayLayout];

    self.initialShowState = SDLHMIInitialShowStateShown;

    SDLShow* show = [[SDLShow alloc] initWithMainField1:@"SDL" mainField2:@"Test App" alignment:SDLTextAlignmentCenter];

    [self.sdlManager sendRequest:show];
}

- (void)sdlex_setupPermissionsCallbacks {
    // This will tell you whether or not you can use the Show RPC right at this moment
    BOOL isAvailable = [self.sdlManager.permissionManager isRPCAllowed:@"Show"];
    SDLLogD(@"Show is allowed? %@", @(isAvailable));

    // This will set up a block that will tell you whether or not you can use none, all, or some of the RPCs specified, and notifies you when those permissions change
    SDLPermissionObserverIdentifier observerId = [self.sdlManager.permissionManager addObserverForRPCs:@[@"Show", @"Alert"] groupType:SDLPermissionGroupTypeAllAllowed withHandler:^(NSDictionary<SDLPermissionRPCName, NSNumber<SDLBool> *> * _Nonnull change, SDLPermissionGroupStatus status) {
        SDLLogD(@"Show changed permission to status: %@, dict: %@", @(status), change);
    }];
    // The above block will be called immediately, this will then remove the block from being called any more
    [self.sdlManager.permissionManager removeObserverForIdentifier:observerId];

    // This will give us the current status of the group of RPCs, as if we had set up an observer, except these are one-shot calls
    NSArray *rpcGroup =@[@"AddCommand", @"PerformInteraction"];
    SDLPermissionGroupStatus commandPICSStatus = [self.sdlManager.permissionManager groupStatusOfRPCs:rpcGroup];
    NSDictionary *commandPICSStatusDict = [self.sdlManager.permissionManager statusOfRPCs:rpcGroup];
    SDLLogD(@"Command / PICS status: %@, dict: %@", @(commandPICSStatus), commandPICSStatusDict);

    // This will set up a long-term observer for the RPC group and will tell us when the status of any specified RPC changes (due to the `SDLPermissionGroupTypeAny`) option.
    [self.sdlManager.permissionManager addObserverForRPCs:rpcGroup groupType:SDLPermissionGroupTypeAny withHandler:^(NSDictionary<SDLPermissionRPCName, NSNumber<SDLBool> *> * _Nonnull change, SDLPermissionGroupStatus status) {
        SDLLogD(@"Command / PICS changed permission to status: %@, dict: %@", @(status), change);
    }];
}

+ (SDLLifecycleConfiguration *)sdlex_setLifecycleConfigurationPropertiesOnConfiguration:(SDLLifecycleConfiguration *)config {
    SDLArtwork *appIconArt = [SDLArtwork persistentArtworkWithImage:[UIImage imageNamed:@"AppIcon60x60@2x"] name:@"AppIcon" asImageFormat:SDLArtworkImageFormatPNG];

    config.shortAppName = @"SDL Example";
    config.appIcon = appIconArt;
    config.voiceRecognitionCommandNames = @[@"S D L Example"];
    config.ttsName = [SDLTTSChunk textChunksFromString:config.shortAppName];

    return config;
}

+ (SDLLogConfiguration *)sdlex_logConfiguration {
    SDLLogConfiguration *logConfig = [SDLLogConfiguration debugConfiguration];
    SDLLogFileModule *sdlExampleModule = [SDLLogFileModule moduleWithName:@"SDL Example" files:[NSSet setWithArray:@[@"ProxyManager"]]];
    logConfig.modules = [logConfig.modules setByAddingObject:sdlExampleModule];
    logConfig.targets = [logConfig.targets setByAddingObject:[SDLLogTargetFile logger]];
    //    logConfig.filters = [logConfig.filters setByAddingObject:[SDLLogFilter filterByAllowingModules:[NSSet setWithObject:@"Transport"]]];

    return logConfig;
}

- (void)sdlex_updateProxyState:(ProxyState)newState {
    if (self.state != newState) {
        [self willChangeValueForKey:@"state"];
        _state = newState;
        [self didChangeValueForKey:@"state"];
    }
}

#pragma mark - RPC builders

+ (SDLAddCommand *)sdlex_speakNameCommandWithManager:(SDLManager *)manager {
    NSString *commandName = @"Speak App Name";

    SDLMenuParams *commandMenuParams = [[SDLMenuParams alloc] init];
    commandMenuParams.menuName = commandName;

    SDLAddCommand *speakNameCommand = [[SDLAddCommand alloc] init];
    speakNameCommand.vrCommands = @[commandName];
    speakNameCommand.menuParams = commandMenuParams;
    speakNameCommand.cmdID = @0;

    speakNameCommand.handler = ^void(SDLOnCommand *notification) {
        [manager sendRequest:[self.class sdlex_appNameSpeak]];
    };

    return speakNameCommand;
}

+ (SDLAddCommand *)sdlex_interactionSetCommandWithManager:(SDLManager *)manager {
    NSString *commandName = @"Perform Interaction";

    SDLMenuParams *commandMenuParams = [[SDLMenuParams alloc] init];
    commandMenuParams.menuName = commandName;

    SDLAddCommand *performInteractionCommand = [[SDLAddCommand alloc] init];
    performInteractionCommand.vrCommands = @[commandName];
    performInteractionCommand.menuParams = commandMenuParams;
    performInteractionCommand.cmdID = @1;

    // NOTE: You may want to preload your interaction sets, because they can take a while for the remote system to process. We're going to ignore our own advice here.
    __weak typeof(self) weakSelf = self;
    performInteractionCommand.handler = ^void(SDLOnCommand *notification) {
        [weakSelf sdlex_sendPerformOnlyChoiceInteractionWithManager:manager];
    };

    return performInteractionCommand;
}

+ (SDLAddCommand *)sdlex_vehicleDataCommandWithManager:(SDLManager *)manager {
    SDLMenuParams *commandMenuParams = [[SDLMenuParams alloc] init];
    commandMenuParams.menuName = @"Get Vehicle Data";

    SDLAddCommand *getVehicleDataCommand = [[SDLAddCommand alloc] init];
    getVehicleDataCommand.vrCommands = [NSMutableArray arrayWithObject:@"Get Vehicle Data"];
    getVehicleDataCommand.menuParams = commandMenuParams;
    getVehicleDataCommand.cmdID = @2;

    getVehicleDataCommand.handler = ^void(SDLOnCommand *notification) {
        [ProxyManager sdlex_sendGetVehicleDataWithManager:manager];
    };

    return getVehicleDataCommand;
}

+ (SDLSpeak *)sdlex_appNameSpeak {
    SDLSpeak *speak = [[SDLSpeak alloc] init];
    speak.ttsChunks = [SDLTTSChunk textChunksFromString:@"S D L Example App"];

    return speak;
}

+ (SDLSpeak *)sdlex_goodJobSpeak {
    SDLSpeak *speak = [[SDLSpeak alloc] init];
    speak.ttsChunks = [SDLTTSChunk textChunksFromString:@"Good Job"];

    return speak;
}

+ (SDLSpeak *)sdlex_youMissedItSpeak {
    SDLSpeak *speak = [[SDLSpeak alloc] init];
    speak.ttsChunks = [SDLTTSChunk textChunksFromString:@"You missed it"];

    return speak;
}

+ (SDLCreateInteractionChoiceSet *)sdlex_createOnlyChoiceInteractionSet {
    SDLCreateInteractionChoiceSet *createInteractionSet = [[SDLCreateInteractionChoiceSet alloc] init];
    createInteractionSet.interactionChoiceSetID = @0;

    NSString *theOnlyChoiceName = @"The Only Choice";
    SDLChoice *theOnlyChoice = [[SDLChoice alloc] init];
    theOnlyChoice.choiceID = @0;
    theOnlyChoice.menuName = theOnlyChoiceName;
    theOnlyChoice.vrCommands = @[theOnlyChoiceName];

    createInteractionSet.choiceSet = @[theOnlyChoice];

    return createInteractionSet;
}

+ (void)sdlex_sendPerformOnlyChoiceInteractionWithManager:(SDLManager *)manager {
    SDLPerformInteraction *performOnlyChoiceInteraction = [[SDLPerformInteraction alloc] init];
    performOnlyChoiceInteraction.initialText = @"Choose the only one! You have 5 seconds...";
    performOnlyChoiceInteraction.initialPrompt = [SDLTTSChunk textChunksFromString:@"Choose it"];
    performOnlyChoiceInteraction.interactionMode = SDLInteractionModeBoth;
    performOnlyChoiceInteraction.interactionChoiceSetIDList = @[@0];
    performOnlyChoiceInteraction.helpPrompt = [SDLTTSChunk textChunksFromString:@"Do it"];
    performOnlyChoiceInteraction.timeoutPrompt = [SDLTTSChunk textChunksFromString:@"Too late"];
    performOnlyChoiceInteraction.timeout = @5000;
    performOnlyChoiceInteraction.interactionLayout = SDLLayoutModeListOnly;

    [manager sendRequest:performOnlyChoiceInteraction withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLPerformInteractionResponse * _Nullable response, NSError * _Nullable error) {
        SDLLogD(@"Perform Interaction fired");
        if ((response == nil) || (error != nil)) {
            SDLLogE(@"Something went wrong, no perform interaction response: %@", error);
        }

        if ([response.choiceID isEqualToNumber:@0]) {
            [manager sendRequest:[self sdlex_goodJobSpeak]];
        } else {
            [manager sendRequest:[self sdlex_youMissedItSpeak]];
        }
    }];
}


+ (void)sdlex_sendGetVehicleDataWithManager:(SDLManager *)manager {
    SDLGetVehicleData *getVehicleData = [[SDLGetVehicleData alloc] initWithAccelerationPedalPosition:YES airbagStatus:YES beltStatus:YES bodyInformation:YES clusterModeStatus:YES deviceStatus:YES driverBraking:YES eCallInfo:YES emergencyEvent:YES engineTorque:YES externalTemperature:YES fuelLevel:YES fuelLevelState:YES gps:YES headLampStatus:YES instantFuelConsumption:YES myKey:YES odometer:YES prndl:YES rpm:YES speed:YES steeringWheelAngle:YES tirePressure:YES vin:YES wiperStatus:YES];

    [manager sendRequest:getVehicleData withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        NSLog(@"vehicle data response: %@", response);
    }];
}


#pragma mark - Files / Artwork

- (void)sdlex_prepareRemoteSystem {
    [self.sdlManager sendRequest:[self.class sdlex_speakNameCommandWithManager:self.sdlManager]];
    [self.sdlManager sendRequest:[self.class sdlex_interactionSetCommandWithManager:self.sdlManager]];
    [self.sdlManager sendRequest:[self.class sdlex_vehicleDataCommandWithManager:self.sdlManager]];

    dispatch_group_t dataDispatchGroup = dispatch_group_create();
    dispatch_group_enter(dataDispatchGroup);

    dispatch_group_enter(dataDispatchGroup);
//    [self.sdlManager.fileManager uploadFile:[self.class sdlex_mainGraphicArtwork] completionHandler:^(BOOL success, NSUInteger bytesAvailable, NSError * _Nullable error) {
//        dispatch_group_leave(dataDispatchGroup);
//
//        if (success == NO) {
//            SDLLogW(@"Something went wrong, image could not upload: %@", error);
//            return;
//        }
//    }];
//
//    dispatch_group_enter(dataDispatchGroup);
//    [self.sdlManager.fileManager uploadFile:[self.class sdlex_pointingSoftButtonArtwork] completionHandler:^(BOOL success, NSUInteger bytesAvailable, NSError * _Nullable error) {
//        dispatch_group_leave(dataDispatchGroup);
//
//        if (success == NO) {
//            SDLLogW(@"Something went wrong, image could not upload: %@", error);
//            return;
//        }
//    }];

    dispatch_group_enter(dataDispatchGroup);
    [self.sdlManager sendRequest:[self.class sdlex_createOnlyChoiceInteractionSet] withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        // Interaction choice set ready
        dispatch_group_leave(dataDispatchGroup);
    }];

    dispatch_group_leave(dataDispatchGroup);
    dispatch_group_notify(dataDispatchGroup, dispatch_get_main_queue(), ^{
        self.initialShowState = SDLHMIInitialShowStateDataAvailable;
        [self sdlex_showInitialData];
    });
}


#pragma mark - SDLManagerDelegate

- (void)managerDidDisconnect {
    // Reset our state
    self.firstTimeState = SDLHMIFirstStateNone;
    self.initialShowState = SDLHMIInitialShowStateNone;
    [self sdlex_updateProxyState:ProxyStateStopped];
    if (ShouldRestartOnDisconnect) {
        [self startManager];
    }
}

- (void)hmiLevel:(SDLHMILevel)oldLevel didChangeToLevel:(SDLHMILevel)newLevel {
    if (![newLevel isEqualToEnum:SDLHMILevelNone] && (self.firstTimeState == SDLHMIFirstStateNone)) {
        // This is our first time in a non-NONE state
        self.firstTimeState = SDLHMIFirstStateNonNone;

        // Send AddCommands
        [self sdlex_prepareRemoteSystem];
    }

    if ([newLevel isEqualToEnum:SDLHMILevelFull] && (self.firstTimeState != SDLHMIFirstStateFull)) {
        // This is our first time in a FULL state
        self.firstTimeState = SDLHMIFirstStateFull;
    }

    if ([newLevel isEqualToEnum:SDLHMILevelFull]) {
        // We're always going to try to show the initial state, because if we've already shown it, it won't be shown, and we need to guard against some possible weird states
        [self sdlex_showInitialData];
    }
}

@end

NS_ASSUME_NONNULL_END