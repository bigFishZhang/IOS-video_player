//
//  VideoDecoder.h
//  videoPlayer
//
//  Created by bigfish on 2018/11/5.
//  Copyright © 2018 bigfish. All rights reserved.
//





#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CVImageBuffer.h>
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"

typedef enum {
    AudioFrameType,
    VideoFrameType,
} FrameType;

@interface BuriedPoint : NSObject

//Absolute time of try to open a live stream
@property (nonatomic,readwrite) long long beginOpen;
//Successfully opening the stream takes time
@property (nonatomic,readwrite) float successOpen;
//first Screen Time Mills
@property (nonatomic,readwrite) float firstScreenTimeMills;
//Failed opening the stream takes time
@property (nonatomic,readwrite) float failOpen;
//Fail open type
@property (nonatomic,readwrite) float failOpenType;
//Retry times
@property (nonatomic,readwrite) int retryTimes;
//Time of pull stream
@property (nonatomic,readwrite) float  duration;
//Status of pull stream
@property (nonatomic,readwrite) NSMutableArray  *bufferStatusRecords;

@end


@interface BaseFrame : NSObject
//FrameType
@property (nonatomic,readwrite) FrameType *type;
//position
@property (nonatomic,readwrite) CGFloat *position;
//duration
@property (nonatomic,readwrite) CGFloat *duration;

@end

@interface AudioFrame : BaseFrame

//samples
@property (nonatomic,readwrite,strong) NSData *samples;

@end

@interface VideoFrame : BaseFrame

//position
@property (nonatomic,readwrite) NSUInteger width;
//height
@property (nonatomic,readwrite) NSUInteger height;
//linesize
@property (nonatomic,readwrite) NSUInteger linesize;
//luma
@property (nonatomic,readwrite,strong) NSData *luma;
//position
@property (nonatomic,readwrite,strong) NSData *chromaB;
//position
@property (nonatomic,readwrite,strong) NSData *chromaR;
//position
@property (nonatomic,readwrite,strong) id imageBuffer;

@end

#ifndef SUBSCRIBE_VIDEO_DATA_TIME_OUT
#define SUBSCRIBE_VIDEO_DATA_TIME_OUT               20
#endif

#ifndef NET_WORK_STREAM_RETRY_TIME
#define NET_WORK_STREAM_RETRY_TIME                  3
#endif


#ifndef RTMP_TCURL_KEY
#define RTMP_TCURL_KEY                              @"RTMP_TCURL_KEY"
#endif

#ifndef FPS_PROBE_SIZE_CONFIGURED
#define FPS_PROBE_SIZE_CONFIGURED                   @"FPS_PROBE_SIZE_CONFIGURED"
#endif

#ifndef PROBE_SIZE
#define PROBE_SIZE                                  @"PROBE_SIZE"
#endif

#ifndef MAX_ANALYZE_DURATION_ARRAY
#define MAX_ANALYZE_DURATION_ARRAY                  @"MAX_ANALYZE_DURATION_ARRAY"
#endif

@interface VideoDecoder : NSObject
{
    AVFormatContext             *_formatCtx;
    BOOL                        _isOpenInputSuccess;
    
    BuriedPoint                 *_buriedPoint;
    
    int                         totalVideoFramecount;
    long long                   decodeVideoFrameWasteTimeMills;
    
    NSArray                     *_videoStreams;
    NSArray                     *_audioStreams;
    NSInteger                   _videoStreamIndex;
    NSInteger                   _audioStreamIndex;
    AVCodecContext              *_videoCodecCtx;
    AVCodecContext              *_audioCodecCtx;
    CGFloat                     _videoTimeBase;
    CGFloat                     _audioTimeBase;
 
}

- (BOOL)openFile:(NSString *)path
        parameter:(NSDictionary*)parameters
            error:(NSError **)openError;

- (NSArray *)decodeFrames:(CGFloat)minDuration
     decodeVideoErrorState:(int *)decodeVideoErrorState;

//Subclass overrides both methods
- (BOOL)openVideoStream;
- (void)closeVideoStream;

- (VideoFrame *)decodeVideo:(AVPacket)packet
                 packetSize:(int)pktSize
      decodeVideoErrorState:(int *)decodeVideoErrorState;

- (void)closeFile;

- (void)interrupt;

- (BOOL)isOpenInputSuccess;

- (void)triggerFirstScreen;
- (void)addBufferStatusRecord:(NSString *)statusFlag;

- (BuriedPoint *)getBuriedPoint;

- (BOOL)detectInterrupted;
- (BOOL)isEOF;
- (BOOL)isSubscribed;
- (NSUInteger)frameWidth;
- (NSUInteger)frameHeight;
- (CGFloat)sampleRate;
- (NSUInteger)channels;
- (BOOL)validVideo;
- (BOOL)validAudio;
- (CGFloat)getVideoFPS;
- (CGFloat)getDuration;

@end


