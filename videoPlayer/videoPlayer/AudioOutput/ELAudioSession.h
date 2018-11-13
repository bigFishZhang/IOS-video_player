//
//  ELAudioSession.h
//  videoPlayer
//
//  Created by bigfish on 2018/11/9.
//  Copyright © 2018 bigfish. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

extern const NSTimeInterval AUSAudioSessionLatency_Background;
extern const NSTimeInterval AUSAudioSessionLatency_Default;
extern const NSTimeInterval AUSAudioSessionLatency_LowLatency;

@interface ELAudioSession : NSObject

+ (ELAudioSession *)sharedInstance;

@property(nonatomic, strong) AVAudioSession *audioSession; // Underlying system audio session
@property(nonatomic, assign) Float64 preferredSampleRate;
@property(nonatomic, assign, readonly) Float64 currentSampleRate;
@property(nonatomic, assign) NSTimeInterval preferredLatency;
@property(nonatomic, assign) BOOL active;
@property(nonatomic, strong) NSString *category;

- (void)addRouteChangeListener;
@end
