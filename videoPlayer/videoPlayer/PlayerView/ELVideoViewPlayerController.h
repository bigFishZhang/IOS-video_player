//
//  ELVideoViewPlayerController.h
//  videoPlayer
//
//  Created by bigfish on 2018/11/13.
//  Copyright © 2018 bigfish. All rights reserved.
//

#import <UIKit/UIKit.h>



@interface ELVideoViewPlayerController : UIViewController
+ (id)viewControllerWithContentPath:(NSString *)path
                       contentFrame:(CGRect)frame
                         parameters: (NSDictionary *)parameters;
@end


