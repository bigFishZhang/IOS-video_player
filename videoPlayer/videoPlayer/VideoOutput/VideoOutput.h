//
//  VideoOutput.h
//  videoPlayer
//
//  Created by bigfish on 2018/11/9.
//  Copyright © 2018 bigfish. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "VideoDecoder.h"
#import "BaseEffectFilter.h"

@interface VideoOutput : UIView

- (id)initWithFrame:(CGRect)frame
       textureWidth:(NSInteger)textureWidth
      textureHeight:(NSInteger)textureHeight;

- (id)initWithFrame:(CGRect)frame
       textureWidth:(NSInteger)textureWidth
      textureHeight:(NSInteger)textureHeight
         shareGroup:(EAGLSharegroup *)shareGroup;

- (void)presentVideoFrame:(VideoFrame *)frame;

- (BaseEffectFilter *) createImageProcessFilterInstance;
- (BaseEffectFilter *) getImageProcessFilterInstance;

- (void)destroy;

@end

