//
//  YUVFrameCopier.h
//  videoPlayer
//
//  Created by bigfish on 2018/11/12.
//  Copyright © 2018 bigfish. All rights reserved.
//

#import "BaseEffectFilter.h"
#import "BaseEffectFilter.h"
#import "VideoDecoder.h"

@interface YUVFrameCopier : BaseEffectFilter

- (void)renderWithTexId:(VideoFrame *)videoFrame;

@end

