//
//  XDXAudioQueuePlayer.h
//  XDXAudioQueuePlayer
//
//  Created by 小东邪 on 2019/6/27.
//  Copyright © 2019 小东邪. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XDXSingleton.h"
#import "XDXQueueProcess.h"


NS_ASSUME_NONNULL_BEGIN

@interface XDXAudioQueuePlayer : NSObject
{
    @public
    XDXCustomQueueProcess   *_audioBufferQueue;
}

SingletonH

@property (nonatomic, assign, readonly) BOOL isRunning;

+ (instancetype)getInstance;


/**
 configure player

 @param audioFormat audio format by ASBD
 @param bufferSize  audio queue buffer size
 */
- (void)configureAudioPlayerWithAudioFormat:(AudioStreamBasicDescription *)audioFormat
                                 bufferSize:(int)bufferSize;


/**
 * Control player
 */
- (void)startAudioPlayer;
- (void)pauseAudioPlayer;
- (void)resumeAudioPlayer;
- (void)stopAudioPlayer;
- (void)freeAudioPlayer;


/**
 * get audio queue buffer size
 */
+ (int)audioBufferSize;

@end

NS_ASSUME_NONNULL_END
