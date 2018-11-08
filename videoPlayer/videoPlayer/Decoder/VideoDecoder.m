//
//  VideoDecoder.m
//  videoPlayer
//
//  Created by bigfish on 2018/11/5.
//  Copyright © 2018 bigfish. All rights reserved.
//

#import "VideoDecoder.h"
#import <Accelerate/Accelerate.h>

static NSData *copyFrameData(UInt8 *src,
                             int linesize,
                             int width,
                             int height)
{
    width = MIN(linesize, width);
    NSMutableData *md = [NSMutableData dataWithLength: width * height];
    Byte *dst = md.mutableBytes;
    for (NSUInteger i = 0; i < height; ++i) {
        memcpy(dst, src, width);
        dst += width;
        src += linesize;
    }
    return md;
}
    
static void avStreamFPSTimeBase(AVStream *st,
                                CGFloat defaultTimeBase,
                                CGFloat *pFPS,
                                CGFloat *pTimeBase)
{
    CGFloat fps, timebase;
    
    if (st->time_base.den && st->time_base.num)
    {
        timebase = av_q2d(st->time_base);
    }
//    else if(st->codec->time_base.den && st->codec->time_base.num)
//        timebase = av_q2d(st->codec->time_base);
    else{
        timebase = defaultTimeBase;
    }
    
//    if (st->codec->ticks_per_frame != 1) {
//        NSLog(@"WARNING: st.codec.ticks_per_frame=%d", st->codec->ticks_per_frame);
//        //timebase *= st->codec->ticks_per_frame;
//    }
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    if (pFPS)
        *pFPS = fps;
    if (pTimeBase)
        *pTimeBase = timebase;
}

// Get an indexed array of stream data
static NSArray *collectStreams(AVFormatContext *formatCtx, enum AVMediaType codecType)
{
    NSMutableArray *ma = [NSMutableArray array];
    for (NSInteger i = 0; i < formatCtx->nb_streams; ++i)
        if (codecType == formatCtx->streams[i]->codecpar->codec_type)
            [ma addObject: [NSNumber numberWithInteger: i]];
    return [ma copy];
}


@implementation BaseFrame

@end

@implementation AudioFrame

@end

@implementation VideoFrame

@end

@implementation BuriedPoint

@end

@interface VideoDecoder()
{
    AVFrame                     *_videoFrame;
    AVFrame                     *_audioFrame;
    
    CGFloat                     _fps;
    
    CGFloat                     _decodePosition;
    
    BOOL                        _isSubscribe;
    BOOL                        _isEOF;
    
    SwrContext                  *_swrContext;
    void                        *_swrBuffer;
    NSUInteger                  _swrBufferSize;
    
    AVPicture                   _picture;
    BOOL                        _pictureValid;
    struct SwsContext           *_swsContext;
    
    int                         _subscribeTimeOutTimeInSecs;
    int                         _readLastestFrameTime;
    
    BOOL                        _interrupted;
    
    int                         _connectionRetry;
    
}

@end

@implementation VideoDecoder

#pragma mark - INTERRUPT CALLBACK

static int interrupt_callback(void *ctx)
{
    if(!ctx)
    {
        return 0;
    }
    __unsafe_unretained VideoDecoder *p = (__bridge VideoDecoder *)ctx;
    const BOOL r = [p detectInterrupted];
    if(r)
    {
        NSLog(@"DEBUG: INTERRUPT_CALLBACK!");
    }
    return r;
    
}
- (void)interrupt
{
    _subscribeTimeOutTimeInSecs = -1;
    _interrupted =YES;
    _isSubscribe = NO;
}

- (BOOL)detectInterrupted
{
   if([[NSDate date] timeIntervalSince1970] - _readLastestFrameTime > _subscribeTimeOutTimeInSecs)
   {
       return YES;
   }
    return _interrupted;
}


#pragma mark - OPEN FILE

- (BOOL)openFile:(NSString *)path
       parameter:(NSDictionary *)parameters
           error:(NSError *__autoreleasing *)openError
{
    BOOL re = YES;
    if (nil == path) {
        NSLog(@"path is nil path:%@",path);
        return NO;
    }
    //Configuration initialization
    _connectionRetry = 0;
    totalVideoFramecount = 0;
    _subscribeTimeOutTimeInSecs = SUBSCRIBE_VIDEO_DATA_TIME_OUT;
    _interrupted = NO;
    _isOpenInputSuccess = NO;
    _isSubscribe = YES;
    //BuriedPoint initialization
    _buriedPoint = [[BuriedPoint alloc] init];
    _buriedPoint.bufferStatusRecords = [[NSMutableArray alloc] init];
    _readLastestFrameTime = [[NSDate date] timeIntervalSince1970];
    // 1. register init
    avformat_network_init();
//    av_register_all();
    _buriedPoint.beginOpen = [[NSDate date] timeIntervalSince1970] * 1000;
    //Open file
    int openInputErrCode = [self openInput:path parameter:parameters];
    if(openInputErrCode > 0) {//open input success
        _buriedPoint.successOpen = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
        _buriedPoint.failOpen = 0.0f;
        _buriedPoint.failOpenType = 1;
        BOOL openVideoStatus = [self openVideoStream];
        BOOL openAudioStatus = [self openAudioStream];
        if(!openVideoStatus || !openAudioStatus){ //open failed
            [self closeFile];//close failed
             NSLog(@"openInput fail");
            re = NO;
        }
    } else {// open input failed
        _buriedPoint.failOpen = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
        _buriedPoint.successOpen = 0.0f;
        _buriedPoint.failOpenType = openInputErrCode;
        NSLog(@"openInput fail");
        re = NO;
    }
    _buriedPoint.retryTimes = _connectionRetry;//Record the retry times
    if(re){//At this point we need to reconnect
        //In the network player it's possible to pull up to a stream that's all 0
        //Pix_fmt of the stream is None
        NSInteger videoWidth = [self frameWidth];
        NSInteger videoHeight = [self frameHeight];
        int retryTimes = 5;//Total retry times
        while(((videoWidth <= 0 || videoHeight <= 0) && retryTimes > 0)){
            NSLog(@"because of videoWidth and videoHeight is Zero We will Retry...");
            usleep(500 * 1000);//sleep 500 ms
            _connectionRetry = 0;//count retry times
            re = [self openFile:path parameter:parameters error:openError];
            if(!re){
                NSLog(@"openFile fail");
                // exit if opening fails
                break;
            }
            retryTimes--;
            videoWidth = [self frameWidth];
            videoHeight = [self frameHeight];
        }
    }
    _isOpenInputSuccess = re;
    return re;
}

- (int)openInput:(NSString *)path parameter:(NSDictionary *)parameters
{
    // 2. initialization AVFormatContext
    AVFormatContext *formatCtx = avformat_alloc_context();
    // 3. register interrupt callback
    AVIOInterruptCB int_cb  = {interrupt_callback, (__bridge void *)(self)};
    formatCtx->interrupt_callback = int_cb;
    //avformat_open_input
    int openInputErrCode = 0;
    if ((openInputErrCode = [self openFormatInput:&formatCtx path:path parameter:parameters]) != 0) {
        NSLog(@"Video decoder open input file failed... videoSourceURL is %@ openInputErr is %s", path, av_err2str(openInputErrCode));
        if (formatCtx)
            avformat_free_context(formatCtx);
        return openInputErrCode;
    }
    // 5. Set the parsing parameter probesize & max_analyze_duration
    [self initAnalyzeDurationAndProbesize:formatCtx parameter:parameters];
    // 6. Get audio and video information
    int findStreamErrCode = 0;
    double startFindStreamTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
    if ((findStreamErrCode = avformat_find_stream_info(formatCtx, NULL)) < 0) {
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        NSLog(@"Video decoder find stream info failed... find stream ErrCode is %s", av_err2str(findStreamErrCode));
        return findStreamErrCode;
    }
    //waste time
    int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startFindStreamTimeMills;
    NSLog(@"Find Stream Info waste TimeMills is %d", wasteTimeMills);
    //check formatCtx
    if (formatCtx->streams[0]->codecpar->codec_id == AV_CODEC_ID_NONE) {
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        NSLog(@"Video decoder First Stream Codec ID Is UnKnown...");
        if([self isNeedRetry]){//retry
            return [self openInput:path parameter:parameters];
        } else {
            return -1;
        }
    }
    _formatCtx = formatCtx;
    return 1;
}


//avformat_open_input
- (int)openFormatInput:(AVFormatContext **)formatCtx
                   path:(NSString *)path
              parameter:(NSDictionary *)parameters
{
    // 4. Open stream address
    const char* videoSourceURL = [path cStringUsingEncoding:NSUTF8StringEncoding];
    AVDictionary *options = NULL;
    NSString *rtmpTcurl = parameters[RTMP_TCURL_KEY];
    if([rtmpTcurl length] > 0)
    {
        ////TCURL should be related to the CDN of the stream if there is TCURL in the original req, use the original
        const char *rtmp_tcurl = [rtmpTcurl cStringUsingEncoding:NSUTF8StringEncoding];
        av_dict_set(&options, "rtmp_tcurl", rtmp_tcurl, 0);
    }
    // 0 is success
    return avformat_open_input(formatCtx, videoSourceURL, NULL, &options);
}

// start data read delay and cache space (default 5M)
- (void)initAnalyzeDurationAndProbesize:(AVFormatContext *)formatCtx
                              parameter:(NSDictionary *)parameters
{
    float probeSize = [parameters[PROBE_SIZE] floatValue];
    formatCtx->probesize = probeSize ?: 50 * 1024;
    NSArray* durations = parameters[MAX_ANALYZE_DURATION_ARRAY];
    if (durations && durations.count > _connectionRetry) {
        formatCtx->max_analyze_duration = [durations[_connectionRetry] floatValue];
    } else {
        float multiplier = 0.5 + (double)pow(2.0, (double)_connectionRetry) * 0.25;
        formatCtx->max_analyze_duration = multiplier * AV_TIME_BASE;
    }
    // frame rate
    BOOL fpsProbeSizeConfiged = [parameters[FPS_PROBE_SIZE_CONFIGURED] boolValue];
    if(fpsProbeSizeConfiged){
        formatCtx->fps_probe_size = 3;
    }
}


- (BOOL)openVideoStream
{
    _videoStreamIndex = -1;
    // 7. Get an indexed array of stream data
    _videoStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_VIDEO);
    for (NSNumber *n in _videoStreams) {
        // 8. Get the AVCodecContext & AVCodec for each stream through the index of the stream
        const NSUInteger iStream = n.integerValue;
//        AVCodecContext *codecCtx = _formatCtx->streams[iStream]->codec;
        AVCodecParameters *p = _formatCtx->streams[iStream]->codecpar;
        // find soft decoder
        AVCodec *codec = avcodec_find_decoder(p->codec_id);
        if (!codec) {
            NSLog(@"Find Video Decoder Failed codec_id %d CODEC_ID_H264 is %d", p->codec_id, AV_CODEC_ID_H264);
            return NO;
        }
        // 9. open decoder
        AVCodecContext *codecCtx = avcodec_alloc_context3(codec);
        int openCodecErrCode = 0;
        if ((openCodecErrCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
            NSLog(@"open Video Codec Failed openCodecErr is %s", av_err2str(openCodecErrCode));
            return NO;
        }
        // 10. initialize an AVFrame
        _videoFrame = av_frame_alloc();
        if (!_videoFrame) {
            NSLog(@"Alloc Video Frame Failed...");
            avcodec_close(codecCtx);
            return NO;
        }
        _videoStreamIndex = iStream;
        _videoCodecCtx = codecCtx;
        // determine fps
        AVStream *st = _formatCtx->streams[_videoStreamIndex];
        avStreamFPSTimeBase(st, 0.04, &_fps, &_videoTimeBase);
        break;
            
    }
    
    
    return YES;
}


- (BOOL)openAudioStream
{
    _videoStreamIndex = -1;
    // 7. Get an indexed array of stream data
    _videoStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_AUDIO);
    for (NSNumber *n in _videoStreams) {
        // 8. Get the AVCodecContext & AVCodec for each stream through the index of the stream
        const NSUInteger iStream = n.integerValue;
       // AVCodecContext *codecCtx = _formatCtx->streams[iStream]->codec;
        AVCodecParameters *p = _formatCtx->streams[iStream]->codecpar;
        // find soft decoder
        AVCodec *codec = avcodec_find_decoder(p->codec_id);
        if (!codec) {
            NSLog(@"Find Audio Decoder Failed codec_id %d CODEC_ID_AAC is %d", p->codec_id, AV_CODEC_ID_AAC);
            return NO;
        }
        // 9. open decoder
        int openCodecErrCode = 0;
        AVCodecContext *codecCtx = avcodec_alloc_context3(codec);
        if ((openCodecErrCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
            NSLog(@"open Audio Codec Failed openCodecErr is %s", av_err2str(openCodecErrCode));
            return NO;
        }
        // 10. If the current stream's sampling format is not supported, a resampling is required
        SwrContext *swrContext = NULL;
        if(![self audioCodecIsSupported:codecCtx]){
            NSLog(@"because of audio Codec Is Not Supported so we will init swresampler...");
            
            /**
             * initialize resampler
             * @param s               Swr context, can be NULL
             * @param out_ch_layout   output channel layout (AV_CH_LAYOUT_*)
             * @param out_sample_fmt  output sample format (AV_SAMPLE_FMT_*).
             * @param out_sample_rate output sample rate (frequency in Hz)
             * @param in_ch_layout    input channel layout (AV_CH_LAYOUT_*)
             * @param in_sample_fmt   input sample format (AV_SAMPLE_FMT_*).
             * @param in_sample_rate  input sample rate (frequency in Hz)
             * @param log_offset      logging level offset
             * @param log_ctx         parent logging context, can be NULL
             */
            swrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(codecCtx->channels), AV_SAMPLE_FMT_S16, codecCtx->sample_rate, av_get_default_channel_layout(codecCtx->channels), codecCtx->sample_fmt, codecCtx->sample_rate, 0, NULL);
            if (!swrContext || swr_init(swrContext)) {
                if (swrContext)
                    swr_free(&swrContext);
                avcodec_close(codecCtx);
                NSLog(@"init resampler failed...");
                return NO;
            }
            
            // 11. initialize an AVFrame
            _audioFrame = av_frame_alloc();
            if (!_audioFrame) {
                NSLog(@"Alloc Audio Frame Failed...");
                if (swrContext)
                    swr_free(&swrContext);
                avcodec_close(codecCtx);
                return NO;
            }
            _audioStreamIndex = iStream;
            _audioCodecCtx = codecCtx;
            _swrContext = swrContext;
            // determine fps
            AVStream *st = _formatCtx->streams[_audioStreamIndex];
            avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
            break;
        }
        
    }
    return YES;
}

//check audio codec is supported
- (BOOL)audioCodecIsSupported:(AVCodecContext *)audioCodecCtx
{
    if (audioCodecCtx->sample_fmt == AV_SAMPLE_FMT_S16) {
        return true;
    }
    return false;
}

#pragma mark - DECODE VIDEO
//read frame from formatCtx
- (NSArray *)decodeFrames:(CGFloat)minDuration decodeVideoErrorState:(int *)decodeVideoErrorState
{
    if (_videoStreamIndex == -1 && _audioStreamIndex == -1)
        return nil;
    NSMutableArray *result = [NSMutableArray array];
    //12. Get AVPacket
    AVPacket packet;
    CGFloat decodedDuration = 0;
    BOOL finished = NO;
    while (!finished) {
        if (av_read_frame(_formatCtx, &packet) < 0) {
            _isEOF = YES;
            break;
        }
        int pktSize = packet.size;
        int pktStreamIndex = packet.stream_index;
        ////13. Get AVFrame
        if (pktStreamIndex ==_videoStreamIndex) {
            double startDecodeTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
            VideoFrame* vframe = [self decodeVideo:packet
                                       packetSize:pktSize
                            decodeVideoErrorState:decodeVideoErrorState];
            int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startDecodeTimeMills;
            decodeVideoFrameWasteTimeMills += wasteTimeMills;
            if(vframe){
                totalVideoFramecount++;
                [result addObject:vframe];
                decodedDuration += *(vframe.duration);
                if (decodedDuration > minDuration)
                    finished = YES;
            }
        } else if (pktStreamIndex == _audioStreamIndex) {
            while (pktSize > 0) {
                int gotframe = 0;
                //decode audio avpackt get frame
                int len = avcodec_decode_audio4(_audioCodecCtx, _audioFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    NSLog(@"decode audio error, skip packet");
                    break;
                }
                if (gotframe) {
                    AudioFrame * aframe = [self handleAudioFrame];
                    if (aframe) {
                        [result addObject:aframe];
                        if (_videoStreamIndex == -1) {
                            _decodePosition = *(aframe.position);
                            decodedDuration += *(aframe.duration);
                            if (decodedDuration > minDuration)
                                finished = YES;
                        }
                    }
                }
                if (0 == len)
                    break;
                pktSize -= len;
            }
        } else {
            NSLog(@"We Can Not Process Stream Except Audio And Video Stream...");
        }
        av_packet_unref(&packet);
    }
    //    NSLog(@"decodedDuration is %.3f", decodedDuration);
    _readLastestFrameTime = [[NSDate date] timeIntervalSince1970];
    return result;
}

//Decode a frame of video data. Input a compressed encoding structure AVPacket,
//output a decoded structure AVFrame.
- (VideoFrame *)decodeVideo:(AVPacket)packet
                 packetSize:(int)pktSize
      decodeVideoErrorState:(int *)decodeVideoErrorState
{
    VideoFrame *frame = nil;
    while (pktSize > 0) {
        int gotframe = 0;
        //decode
        int len = avcodec_decode_video2(_videoCodecCtx, _videoFrame, &gotframe, &packet);
        if (len < 0) {
            NSLog(@"decode video error, skip packet %s", av_err2str(len));
            *decodeVideoErrorState  = 1;
            break;
        }
        if (gotframe) {
            frame = [self handleVideoFrame];
        }
        #pragma mark - TODO
        //int nalu_type = (packet.data[4] & 0x1F);
        if(packet.flags == 1){
            //IDR Frame
            NSLog(@"IDR Frame %f", *(frame.position));
        } else if (packet.flags == 0) {
            //NON-IDR Frame
            NSLog(@"===========NON-IDR Frame=========== %f", *(frame.position));
        }
        if (0 == len)
            break;
        pktSize -= len;
    }
    return frame;
}

- (VideoFrame *)handleVideoFrame
{
    if (!_videoFrame->data[0])
    {
        NSLog(@" _videoFrame data is nil");
        return nil;
    }
    VideoFrame *vframe = [[VideoFrame alloc] init];
    if(_videoCodecCtx->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecCtx->pix_fmt == AV_PIX_FMT_YUVJ420P){
        vframe.luma = copyFrameData(_videoFrame->data[0],
                                   _videoFrame->linesize[0],
                                   _videoCodecCtx->width,
                                   _videoCodecCtx->height);
        
        vframe.chromaB = copyFrameData(_videoFrame->data[1],
                                      _videoFrame->linesize[1],
                                      _videoCodecCtx->width / 2,
                                      _videoCodecCtx->height / 2);
        
        vframe.chromaR = copyFrameData(_videoFrame->data[2],
                                      _videoFrame->linesize[2],
                                      _videoCodecCtx->width / 2,
                                      _videoCodecCtx->height / 2);
    } else{
        if (!_swsContext &&
            ![self setupScaler]) {
            NSLog(@"fail setup video scaler");
            return nil;
        }
        sws_scale(_swsContext,
                  (const uint8_t **)_videoFrame->data,
                  _videoFrame->linesize,
                  0,
                  _videoCodecCtx->height,
                  _picture.data,
                  _picture.linesize);
        vframe.luma = copyFrameData(_picture.data[0],
                                   _picture.linesize[0],
                                   _videoCodecCtx->width,
                                   _videoCodecCtx->height);
        
        vframe.chromaB = copyFrameData(_picture.data[1],
                                      _picture.linesize[1],
                                      _videoCodecCtx->width / 2,
                                      _videoCodecCtx->height / 2);
        
        vframe.chromaR = copyFrameData(_picture.data[2],
                                      _picture.linesize[2],
                                      _videoCodecCtx->width / 2,
                                      _videoCodecCtx->height / 2);
    }
    vframe.width = _videoCodecCtx->width;
    vframe.height = _videoCodecCtx->height;
    vframe.linesize = _videoFrame->linesize[0];
    vframe.type = (FrameType *)VideoFrameType;
    
    int64_t effort = av_frame_get_best_effort_timestamp(_videoFrame) * _videoTimeBase;
    vframe.position = (CGFloat *)&effort;
    
    const int64_t frameDuration = av_frame_get_pkt_duration(_videoFrame);
    if (frameDuration) {
        
        CGFloat d = frameDuration * _videoTimeBase;
        vframe.duration = (CGFloat *)&d;
        
        CGFloat t = _videoFrame->repeat_pict * _videoTimeBase * 0.5;
        *(vframe.duration) += t;
    } else {
        // sometimes, ffmpeg unable to determine a frame duration
        // as example yuvj420p stream from web camera
        CGFloat fps = 1.0 / _fps;
        vframe.duration = (CGFloat *)&(fps);
    }
    //    if(totalVideoFramecount == 30){
    //        //软件解码的第31帧写入文件
    //        NSString* softDecoderFrame30FilePath = [CommonUtil documentsPath:@"soft_decoder_30.yuv"];
    //        NSMutableData* data1 = [[NSMutableData alloc] init];
    //        [data1 appendData:frame.luma];
    //        [data1 appendData:frame.chromaB];
    //        [data1 appendData:frame.chromaR];
    //        [data1 writeToFile:softDecoderFrame30FilePath atomically:YES];
    //    } else if(totalVideoFramecount == 60) {
    //        //软件解码的第61帧写入文件
    //        NSString* softDecoderFrame60FilePath = [CommonUtil documentsPath:@"soft_decoder_60.yuv"];
    //        NSMutableData* data1 = [[NSMutableData alloc] init];
    //        [data1 appendData:frame.luma];
    //        [data1 appendData:frame.chromaB];
    //        [data1 appendData:frame.chromaR];
    //        [data1 writeToFile:softDecoderFrame60FilePath atomically:YES];
    //    }
    //    NSLog(@"Add Video Frame position is %.3f", frame.position);
    return vframe;
}

- (AudioFrame *)handleAudioFrame
{
    if (!_audioFrame->data[0]) {
        NSLog(@" _audioFrame data is nil");
        return nil;
    }
    const NSUInteger numChannels = _audioCodecCtx->channels;
    NSInteger numFrames;
    void *audioData;
    if (_swsContext) {
        const NSUInteger ratio = 2;
        const int bufSize = av_samples_get_buffer_size(NULL, (int)numChannels, (int)(_audioFrame->nb_samples * ratio), AV_SAMPLE_FMT_S16, 1);
        if(!_swrBuffer || _swrBufferSize < bufSize){
            _swrBufferSize = bufSize;
            //reallocate memory space
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        Byte *outbuf[2] = {_swrBuffer,0};
        numFrames = swr_convert(_swrContext, outbuf,
                                (int)(_audioFrame->nb_samples * ratio),
                                (const uint8_t **)_audioFrame->data,
                                _audioFrame->nb_samples);
        if (numFrames < 0) {
            NSLog(@"fail resample audio");
            return nil;
        }
        audioData = _swrBuffer;
    }else{
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSLog(@"Audio format is invalid");
            return nil;
        }
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
        
    }
    const NSUInteger numElements = numFrames * numChannels;
    NSMutableData *pcmData = [NSMutableData dataWithLength:numElements * sizeof(SInt16)];
    memcpy(pcmData.mutableBytes, audioData, numElements * sizeof(SInt16));
    AudioFrame *aframe = [[AudioFrame alloc] init];
    
    int64_t effort = av_frame_get_best_effort_timestamp(_audioFrame) * _videoTimeBase;
    aframe.position = (CGFloat *)&effort;
    CGFloat d = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
    aframe.duration = (CGFloat *)&d;
    aframe.samples = pcmData;
    aframe.type = (FrameType *)AudioFrameType;
    //    NSLog(@"Add Audio Frame position is %.3f", frame.position);
    return aframe;
}
    

#pragma mark - CLOSE FILE

- (void)closeFile
{
    NSLog(@"Enter closeFile...");
    //Calculate opening time
    if (_buriedPoint.failOpenType == 1) {
        _buriedPoint.duration = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
    }
    //set status
    [self interrupt];
    
    //close stream
    [self closeAudioStream];
    [self closeVideoStream];
    
    _videoStreams = nil;
    _audioStreams = nil;
    
    if (_formatCtx) {
        _formatCtx->interrupt_callback.opaque = NULL;
        _formatCtx->interrupt_callback.callback = NULL;
        avformat_close_input(&_formatCtx);
        _formatCtx = NULL;
    }
    float decodeFrameAVGTimeMills = (double)decodeVideoFrameWasteTimeMills / (float)totalVideoFramecount;
    NSLog(@"Decoder decoder totalVideoFramecount is %d decodeFrameAVGTimeMills is %.3f", totalVideoFramecount, decodeFrameAVGTimeMills);
    
}

- (void)closeAudioStream
{
    _audioStreamIndex = -1;
    
    if (_swrBuffer) {
        free(_swrBuffer);
        _swrBuffer = NULL;
        _swrBufferSize = 0;
    }
    
    if (_swrContext) {
        swr_free(&_swrContext);
        _swrContext = NULL;
    }
    
    if (_audioFrame) {
        av_free(_audioFrame);
        _audioFrame = NULL;
    }
    
    if (_audioCodecCtx) {
        avcodec_close(_audioCodecCtx);
        _audioCodecCtx = NULL;
    }
    
}
- (void)closeVideoStream
{
    _videoStreamIndex = -1;
    
    [self closeScaler];
    
    if (_videoFrame) {
        av_free(_videoFrame);
        _videoFrame = NULL;
    }
    
    if (_videoCodecCtx) {
        avcodec_close(_videoCodecCtx);
        _videoCodecCtx = NULL;
    }
}

- (void)closeScaler
{
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
    
    if (_pictureValid) {
        avpicture_free(&_picture);
        _pictureValid = NO;
    }
        
}

#pragma mark - TRIGGER RECORD
- (void)triggerFirstScreen
{
    if (_buriedPoint.failOpenType == 1) {
        _buriedPoint.firstScreenTimeMills = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
    }
    NSLog(@"firstScreenTimeMills %f",_buriedPoint.firstScreenTimeMills);
    
}
-(void)addBufferStatusRecord:(NSString *)statusFlag
{
    if([@"F" isEqualToString:statusFlag] && [[_buriedPoint.bufferStatusRecords lastObject] hasPrefix:@"F_"]){
        return;
    }
    float timeInterval = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
    [_buriedPoint.bufferStatusRecords addObject:[NSString stringWithFormat:@"%@_%.3f",statusFlag,timeInterval]];
    
}

#pragma mark - GET STATUS
- (BOOL)isNeedRetry
{
    _connectionRetry++;
    
    return _connectionRetry <= NET_WORK_STREAM_RETRY_TIME;
}

- (BOOL)isOpenInputSuccess
{
    return _isOpenInputSuccess;
}

- (BOOL) isSubscribed;
{
    return _isSubscribe;
}
- (BOOL)isEOF;
{
    return _isEOF;
}

#pragma mark - GET SET
// set up scaler
- (BOOL)setupScaler
{
    [self closeScaler];
    _pictureValid = avpicture_alloc(&_picture,
                                    AV_PIX_FMT_YUV420P,
                                    _videoCodecCtx->width,
                                    _videoCodecCtx->height) == 0;
    if (!_pictureValid)
        return NO;
    _swsContext = sws_getCachedContext(_swsContext,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       _videoCodecCtx->pix_fmt,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       AV_PIX_FMT_YUV420P,
                                       SWS_FAST_BILINEAR,
                                       NULL, NULL, NULL);
    return _swsContext != NULL;
}


- (CGFloat)getDuration;
{
    if(_formatCtx){
        if(_formatCtx->duration == AV_NOPTS_VALUE){
            return -1;
        }
        return _formatCtx->duration / AV_TIME_BASE;
    }
    return -1;
}
- (BuriedPoint*)getBuriedPoint;
{
    return _buriedPoint;
}

- (CGFloat)getVideoFPS;
{
    return _fps;
}

- (BOOL)validVideo;
{
    return _videoStreamIndex != -1;
}

- (BOOL)validAudio;
{
    return _audioStreamIndex != -1;
}

- (NSUInteger)frameWidth;
{
    return _videoCodecCtx ? _videoCodecCtx->width : 0;
}

- (NSUInteger)frameHeight;
{
    return _videoCodecCtx ? _videoCodecCtx->height : 0;
}

- (CGFloat)sampleRate;
{
    return _audioCodecCtx ? _audioCodecCtx->sample_rate : 0;
}

- (NSUInteger)channels;
{
    return _audioCodecCtx ? _audioCodecCtx->channels : 0;
}


#pragma mark - DEALLOC
- (void) dealloc;
{
    NSLog(@"VideoDecoder Dealloc...");
}

@end
