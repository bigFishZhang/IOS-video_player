//
//  AVAudioSession+RouteUtils.h
//  videoPlayer
//
//  Created by bigfish on 2018/11/9.
//  Copyright © 2018 bigfish. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>

@interface AVAudioSession (RouteUtils)

- (BOOL)usingBlueTooth;

- (BOOL)usingWiredMicrophone;

- (BOOL)shouldShowEarphoneAlert;

@end

