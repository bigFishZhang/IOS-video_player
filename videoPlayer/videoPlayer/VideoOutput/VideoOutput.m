//
//  VideoOutput.m
//  videoPlayer
//
//  Created by bigfish on 2018/11/9.
//  Copyright © 2018 bigfish. All rights reserved.
//

#import "VideoOutput.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES//ES2/glext.h>
#import "YUVFrameCopier.h"
#import "ContrastEnhancerFilter.h"
#import "DirectPassRenderer.h"

/**
 *  Responsibilities of this category:
 *  1:As a subclass of UIView, you must provide layer rendering, which is done here by binding RenderBuffer to our CAEAGLLayer
 *  2:Need to build OpenGL environment, EAGLContext and run Thread
 *  3:Call the third-party Filter and Renderer to process and render YUV420P data to the RenderBuffer
 *  4:Because it involves the operation of the OpenGL, to increase the NotificationCenter listening, in applicationWillResignActive stop drawing
 *
 */
@interface VideoOutput()

@property (atomic) BOOL readyToRender;
@property (nonatomic,assign) BOOL shouldEnableOpenGL;
@property (nonatomic,strong) NSLock *shouldEnableOpenGLLock;
@property (nonatomic,strong) NSOperationQueue *renderOperationQueue;

@end

@implementation VideoOutput
{
    EAGLContext*                            _context;
    GLuint                                  _displayFramebuffer;
    GLuint                                  _renderbuffer;
    GLint                                   _backingWidth;
    GLint                                   _backingHeight;
    
    BOOL                                    _stopping;
    
    YUVFrameCopier*                         _videoFrameCopier;
    
    BaseEffectFilter*                       _filter;
    
    DirectPassRenderer*                     _directPassRenderer;
    
    
}

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame
      textureWidth:(NSInteger)textureWidth
     textureHeight:(NSInteger)textureHeight
{
    return [self initWithFrame:frame textureWidth:textureWidth textureHeight:textureHeight shareGroup:nil];
}

- (id)initWithFrame:(CGRect)frame
       textureWidth:(NSInteger)textureWidth
      textureHeight:(NSInteger)textureHeight
         shareGroup:(EAGLSharegroup *)shareGroup
{
    self = [super initWithFrame:frame];
    if (self) {
        _shouldEnableOpenGLLock = [NSLock new];
        [_shouldEnableOpenGLLock lock];
        _shouldEnableOpenGL = [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
        [_shouldEnableOpenGLLock unlock];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        
        CAEAGLLayer *eaglLayer = (CAEAGLLayer*) self.layer;
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        
        _renderOperationQueue = [[NSOperationQueue alloc] init];
        _renderOperationQueue.maxConcurrentOperationCount = 1;
        _renderOperationQueue.name = @"com.changba.video_player.videoRenderQueue";
        
        __weak VideoOutput *weakSelf = self;
        [_renderOperationQueue addOperationWithBlock:^{
            if (!weakSelf) {
                return;
            }
            
            __strong VideoOutput *strongSelf = weakSelf;
            if (shareGroup) {
                strongSelf->_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 sharegroup:shareGroup];
            } else {
                strongSelf->_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
            }
            
            if (!strongSelf->_context || ![EAGLContext setCurrentContext:strongSelf->_context]) {
                NSLog(@"Setup EAGLContext Failed...");
            }
            if(![strongSelf createDisplayFramebuffer]){
                NSLog(@"create Dispaly Framebuffer failed...");
            }
            
            [strongSelf createCopierInstance];
            if (![strongSelf->_videoFrameCopier prepareRender:textureWidth height:textureHeight]) {
                NSLog(@"_videoFrameFastCopier prepareRender failed...");
            }
            
            strongSelf->_filter = [self createImageProcessFilterInstance];
            if (![strongSelf->_filter prepareRender:textureWidth height:textureHeight]) {
                NSLog(@"_contrastEnhancerFilter prepareRender failed...");
            }
            [strongSelf->_filter setInputTexture:[strongSelf->_videoFrameCopier outputTextureID]];
            
            strongSelf->_directPassRenderer = [[DirectPassRenderer alloc] init];
            if (![strongSelf->_directPassRenderer prepareRender:textureWidth height:textureHeight]) {
                NSLog(@"_directPassRenderer prepareRender failed...");
            }
            [strongSelf->_directPassRenderer setInputTexture:[strongSelf->_filter outputTextureID]];
            strongSelf.readyToRender = YES;
        }];
    }
    return self;
}

- (BaseEffectFilter*)createImageProcessFilterInstance
{
    return [[ContrastEnhancerFilter alloc] init];
}


- (BaseEffectFilter *)getImageProcessFilterInstance
{
    return _filter;
}

- (void)createCopierInstance
{
    _videoFrameCopier = [[YUVFrameCopier alloc] init];
}

//The maximum number of frames allowed in the current operationQueue is theoretically no more than one frame on a good model, and the less advanced models (like the iPod touch) are slower to render

//There may be multiple frames in the queue. In this case, if there are more than three frames, remove the previous frames except the last three (corresponding operation cancel).
static int count = 0;
static const NSInteger kMaxOperationQueueCount = 3;

- (void)presentVideoFrame:(VideoFrame *)frame
{
    if(_stopping){
        NSLog(@"Prevent A InValid Renderer >>>>>>>>>>>>>>>>>");
        return;
    }
    
    @synchronized (self.renderOperationQueue) {
        NSInteger operationCount = _renderOperationQueue.operationCount;
        if (operationCount > kMaxOperationQueueCount) {
            [_renderOperationQueue.operations enumerateObjectsUsingBlock:^(__kindof NSOperation * _Nonnull operation, NSUInteger idx, BOOL * _Nonnull stop) {
                if (idx < operationCount - kMaxOperationQueueCount) {
                    [operation cancel];
                } else {
                    //totalDroppedFrames += (idx - 1);
                    //NSLog(@"===========================❌ Dropped frames: %@, total: %@", @(idx - 1), @(totalDroppedFrames));
                    *stop = YES;
                }
            }];
        }
        
        __weak VideoOutput *weakSelf = self;
        [_renderOperationQueue addOperationWithBlock:^{
            if (!weakSelf) {
                return;
            }
            
            __strong VideoOutput *strongSelf = weakSelf;
            
            [strongSelf.shouldEnableOpenGLLock lock];
            if (!strongSelf.readyToRender || !strongSelf.shouldEnableOpenGL) {
                glFinish();
                [strongSelf.shouldEnableOpenGLLock unlock];
                return;
            }
            [strongSelf.shouldEnableOpenGLLock unlock];
            count++;
            int frameWidth = (int)[frame width];
            int frameHeight = (int)[frame height];
            [EAGLContext setCurrentContext:strongSelf->_context];
            [strongSelf->_videoFrameCopier renderWithTexId:frame];
            [strongSelf->_filter renderWithWidth:frameWidth height:frameHeight position:*(frame.position)];
            
            glBindFramebuffer(GL_FRAMEBUFFER, strongSelf->_displayFramebuffer);
            [strongSelf->_directPassRenderer renderWithWidth:strongSelf->_backingWidth height:strongSelf->_backingHeight position:*(frame.position)];
            glBindRenderbuffer(GL_RENDERBUFFER, strongSelf->_renderbuffer);
            [strongSelf->_context presentRenderbuffer:GL_RENDERBUFFER];
        }];
    }
}

- (BOOL)createDisplayFramebuffer
{
    BOOL re = TRUE;
    glGenFramebuffers(1, &_displayFramebuffer);
    glGenRenderbuffers(1, &_renderbuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _displayFramebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbuffer);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"failed to make complete framebuffer object %x", status);
        return FALSE;
    }
    GLenum glError = glGetError();
    if (GL_NO_ERROR != glError) {
        NSLog(@"failed to setup GL %x", glError);
        return FALSE;
    }
    return re;
}

- (void)destroy
{
    _stopping = true;
    
    __weak VideoOutput *weakSelf = self;
    [self.renderOperationQueue addOperationWithBlock:^{
        if (!weakSelf) {
            return;
        }
        __strong VideoOutput *strongSelf = weakSelf;
        if(strongSelf->_videoFrameCopier) {
            [strongSelf->_videoFrameCopier releaseRender];
        }
        if(strongSelf->_filter) {
            [strongSelf->_filter releaseRender];
        }
        if(strongSelf->_directPassRenderer) {
            [strongSelf->_directPassRenderer releaseRender];
        }
        if (strongSelf->_displayFramebuffer) {
            glDeleteFramebuffers(1, &strongSelf->_displayFramebuffer);
            strongSelf->_displayFramebuffer = 0;
        }
        if (strongSelf->_renderbuffer) {
            glDeleteRenderbuffers(1, &strongSelf->_renderbuffer);
            strongSelf->_renderbuffer = 0;
        }
        if ([EAGLContext currentContext] == strongSelf->_context) {
            [EAGLContext setCurrentContext:nil];
        }
    }];
    
    
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_renderOperationQueue) {
        [_renderOperationQueue cancelAllOperations];
        _renderOperationQueue = nil;
    }
    
    _videoFrameCopier = nil;
    _filter = nil;
    _directPassRenderer = nil;
    
    _context = nil;
    NSLog(@"Render Frame Count is %d", count);
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    [self.shouldEnableOpenGLLock lock];
    self.shouldEnableOpenGL = NO;
    [self.shouldEnableOpenGLLock unlock];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self.shouldEnableOpenGLLock lock];
    self.shouldEnableOpenGL = YES;
    [self.shouldEnableOpenGLLock unlock];
}

@end
