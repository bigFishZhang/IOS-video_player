//
//  AudioOutput.h
//  videoPlayer
//
//  Created by bigfish on 2018/11/9.
//  Copyright © 2018 bigfish. All rights reserved.
//



#import <Foundation/Foundation.h>

@protocol FillDataDelegate <NSObject>

- (NSUInteger)fillAudioData:(SInt16 *)sampleBuffer
                  numFrames:(NSInteger)frameNum
                numChannels:(NSInteger)channels;

@end

@interface AudioOutput : NSObject

@property (nonatomic,assign) Float64 sampleRate;

@property (nonatomic,assign) Float64 channels;


- (id)initWithChannels:(NSInteger)channels
             sampleRate:(NSInteger)sampleRate
         bytesPerSample:(NSInteger)bytePerSample
      fillDataDelegate:(id<FillDataDelegate>)fillAudioDataDelegate;

- (BOOL)play;
- (void)stop;



@end



