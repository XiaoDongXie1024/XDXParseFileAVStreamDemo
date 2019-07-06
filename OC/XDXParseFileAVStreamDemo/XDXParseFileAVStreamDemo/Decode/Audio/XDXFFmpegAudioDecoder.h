//
//  XDXFFmpegAudioDecoder.h
//  XDXVideoDecoder
//
//  Created by 小东邪 on 2019/6/6.
//  Copyright © 2019 小东邪. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

// FFmpeg Header File
#ifdef __cplusplus
extern "C" {
#endif
    
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"
    
#ifdef __cplusplus
};
#endif

NS_ASSUME_NONNULL_BEGIN

@protocol XDXFFmpegAudioDecoderDelegate <NSObject>

@optional
- (void)getDecodeAudioDataByFFmpeg:(void *)data size:(int)size pts:(int64_t)pts isFirstFrame:(BOOL)isFirstFrame;

@end

@interface XDXFFmpegAudioDecoder : NSObject

@property (weak, nonatomic) id<XDXFFmpegAudioDecoderDelegate> delegate;

- (instancetype)initWithFormatContext:(AVFormatContext *)formatContext audioStreamIndex:(int)audioStreamIndex;
- (void)startDecodeAudioDataWithAVPacket:(AVPacket)packet;
- (void)stopDecoder;

@end

NS_ASSUME_NONNULL_END
