//
//  ViewController.m
//  XDXParseFileAVStreamDemo
//
//  Created by 小东邪 on 2019/7/1.
//  Copyright © 2019 小东邪. All rights reserved.
//

#import "ViewController.h"
#import "XDXAVParseHandler.h"
#import "XDXVideoDecoder.h"
#import "XDXFFmpegVideoDecoder.h"
#import "XDXPreviewView.h"
#import "XDXAudioQueuePlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "XDXQueueProcess.h"
#import "XDXFFmpegAudioDecoder.h"
#import "XDXAduioDecoder.h"
#import "XDXSortFrameHandler.h"

int kXDXBufferSize = 4096;

@interface ViewController ()<XDXVideoDecoderDelegate,XDXFFmpegVideoDecoderDelegate,XDXFFmpegAudioDecoderDelegate, XDXSortFrameHandlerDelegate>

@property (weak, nonatomic) IBOutlet UIButton *startWorkBtn;

@property (strong, nonatomic) XDXPreviewView *previewView;

@property (nonatomic, assign) BOOL isUseFFmpeg;
@property (nonatomic, assign) BOOL hasBFrame;

@property (strong, nonatomic) XDXSortFrameHandler *sortHandler;

@end

@implementation ViewController

#pragma mark - Lifecycle
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    // Set it to select decode method
    self.isUseFFmpeg = YES;
    
    [self setupUI];
    [self configureAudioPlayer];
    [self configureSortManagerForBFrameFile];
}

#pragma mark - Button Action
- (IBAction)startWorkBtnDidClicked:(id)sender {
    self.startWorkBtn.hidden = YES;
    
    NSString *fileName = @"testH264";
    if ([fileName isEqualToString:@"testH265"]) {
        self.hasBFrame = YES;
    }else {
        self.hasBFrame = NO;
    }
    
    if (self.isUseFFmpeg) {
        // testH265 need to modify ASBD -> 44100
        [self startRenderAVByFFmpegWithFileName:fileName];
    }else {
        if ([fileName isEqualToString:@"testH265"]) {
            NSLog(@"Not support");
            return;
        }
        
        [self startRenderAVByOriginWithFileName:fileName];
    }
}

#pragma mark - Main Function
- (void)setupUI {
    self.previewView = [[XDXPreviewView alloc] initWithFrame:self.view.frame];
    [self.view addSubview:self.previewView];
    [self.view bringSubviewToFront:self.startWorkBtn];
}

- (void)configureSortManagerForBFrameFile {
    self.sortHandler = [[XDXSortFrameHandler alloc] init];
    self.sortHandler.delegate = self;
}

- (void)configureAudioPlayer {
    // Final Audio Player format : This is only for the FFmpeg to decode.
    AudioStreamBasicDescription ffmpegAudioFormat = {
        .mSampleRate         = 48000,
        .mFormatID           = kAudioFormatLinearPCM,
        .mChannelsPerFrame   = 2,
        .mFormatFlags        = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBitsPerChannel     = 16,
        .mBytesPerPacket     = 4,
        .mBytesPerFrame      = 4,
        .mFramesPerPacket    = 1,
    };
    
    // Final Audio Player format : This is only for audio converter format.
    AudioStreamBasicDescription systemAudioFormat = {
        .mSampleRate         = 48000,
        .mFormatID           = kAudioFormatLinearPCM,
        .mChannelsPerFrame   = 1,
        .mFormatFlags        = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBitsPerChannel     = 16,
        .mBytesPerPacket     = 2,
        .mBytesPerFrame      = 2,
        .mFramesPerPacket    = 1,
    };
    
    // Configure Audio Queue Player
    [[XDXAudioQueuePlayer getInstance] configureAudioPlayerWithAudioFormat:self.isUseFFmpeg ? &ffmpegAudioFormat : &systemAudioFormat bufferSize:kXDXBufferSize];
    [[XDXAudioQueuePlayer getInstance] startAudioPlayer];
}

- (void)startRenderAVByFFmpegWithFileName:(NSString *)fileName {
    NSString *path = [[NSBundle mainBundle] pathForResource:fileName ofType:@"MOV"];
    
    XDXAVParseHandler *parseHandler = [[XDXAVParseHandler alloc] initWithPath:path];
    
    XDXFFmpegVideoDecoder *videoDecoder = [[XDXFFmpegVideoDecoder alloc] initWithFormatContext:[parseHandler getFormatContext] videoStreamIndex:[parseHandler getVideoStreamIndex]];
    videoDecoder.delegate = self;
    
    XDXFFmpegAudioDecoder *audioDecoder = [[XDXFFmpegAudioDecoder alloc] initWithFormatContext:[parseHandler getFormatContext] audioStreamIndex:[parseHandler getAudioStreamIndex]];
    audioDecoder.delegate = self;
    
    static BOOL isFindIDR = NO;
    
    [parseHandler startParseGetAVPackeWithCompletionHandler:^(BOOL isVideoFrame, BOOL isFinish, AVPacket packet) {
        if (isFinish) {
            isFindIDR = NO;
            [videoDecoder stopDecoder];
            [audioDecoder stopDecoder];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.startWorkBtn.hidden = NO;
            });
            return;
        }
        
        if (isVideoFrame) { // Video
            if (packet.flags == 1 && isFindIDR == NO) {
                isFindIDR = YES;
            }
            
            if (!isFindIDR) {
                return;
            }
            
            [videoDecoder startDecodeVideoDataWithAVPacket:packet];
        }else {             // Audio
            [audioDecoder startDecodeAudioDataWithAVPacket:packet];
        }
    }];
}

- (void)startRenderAVByOriginWithFileName:(NSString *)fileName {
    NSString *path = [[NSBundle mainBundle] pathForResource:fileName ofType:@"MOV"];
    XDXAVParseHandler *parseHandler = [[XDXAVParseHandler alloc] initWithPath:path];
    
    XDXVideoDecoder *videoDecoder = [[XDXVideoDecoder alloc] init];
    videoDecoder.delegate = self;

    // Origin file aac format
    AudioStreamBasicDescription audioFormat = {
        .mSampleRate         = 48000,
        .mFormatID           = kAudioFormatMPEG4AAC,
        .mChannelsPerFrame   = 2,
        .mFramesPerPacket    = 1024,
    };
    
    XDXAduioDecoder *audioDecoder = [[XDXAduioDecoder alloc] initWithSourceFormat:audioFormat
                                                                     destFormatID:kAudioFormatLinearPCM
                                                                       sampleRate:48000
                                                              isUseHardwareDecode:YES];
    
    [parseHandler startParseWithCompletionHandler:^(BOOL isVideoFrame, BOOL isFinish, struct XDXParseVideoDataInfo *videoInfo, struct XDXParseAudioDataInfo *audioInfo) {
        if (isFinish) {
            [videoDecoder stopDecoder];
            [audioDecoder freeDecoder];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.startWorkBtn.hidden = NO;
            });
            return;
        }
        
        if (isVideoFrame) {
            [videoDecoder startDecodeVideoData:videoInfo];
        }else {
            [audioDecoder decodeAudioWithSourceBuffer:audioInfo->data
                                     sourceBufferSize:audioInfo->dataSize
                                      completeHandler:^(AudioBufferList * _Nonnull destBufferList, UInt32 outputPackets, AudioStreamPacketDescription * _Nonnull outputPacketDescriptions) {
                                          // Put audio data from audio file into audio data queue
                                          [self addBufferToWorkQueueWithAudioData:destBufferList->mBuffers->mData size:destBufferList->mBuffers->mDataByteSize pts:audioInfo->pts];

                                          // control rate
                                          usleep(16.8*1000);
                                      }];
        }
    }];
}

#pragma mark - Decode Callback
- (void)getVideoDecodeDataCallback:(CMSampleBufferRef)sampleBuffer isFirstFrame:(BOOL)isFirstFrame {
    if (self.hasBFrame) {
        // Note : the first frame not need to sort.
        if (isFirstFrame) {
            CVPixelBufferRef pix = CMSampleBufferGetImageBuffer(sampleBuffer);
            [self.previewView displayPixelBuffer:pix];
            return;
        }
        
        [self.sortHandler addDataToLinkList:sampleBuffer];
    }else {
        CVPixelBufferRef pix = CMSampleBufferGetImageBuffer(sampleBuffer);
        [self.previewView displayPixelBuffer:pix];
    }
}

-(void)getDecodeVideoDataByFFmpeg:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pix = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self.previewView displayPixelBuffer:pix];
}


#pragma mark - Decode Callback
- (void)getDecodeAudioDataByFFmpeg:(void *)data size:(int)size pts:(int64_t)pts isFirstFrame:(BOOL)isFirstFrame {
//    NSLog(@"demon test - %d",size);
    // Put audio data from audio file into audio data queue
    [self addBufferToWorkQueueWithAudioData:data size:size pts:pts];

    // control rate
    usleep(14.5*1000);
}

- (void)addBufferToWorkQueueWithAudioData:(void *)data  size:(int)size pts:(int64_t)pts {
    XDXCustomQueueProcess *audioBufferQueue =  [XDXAudioQueuePlayer getInstance]->_audioBufferQueue;
    
    XDXCustomQueueNode *node = audioBufferQueue->DeQueue(audioBufferQueue->m_free_queue);
    if (node == NULL) {
//        NSLog(@"XDXCustomQueueProcess addBufferToWorkQueueWithSampleBuffer : Data in , the node is NULL !");
        return;
    }
    
    node->pts  = pts;
    node->size = size;
    memcpy(node->data, data, size);
    audioBufferQueue->EnQueue(audioBufferQueue->m_work_queue, node);
    
    NSLog(@"Test Data in ,  work size = %d, free size = %d !",audioBufferQueue->m_work_queue->size, audioBufferQueue->m_free_queue->size);
}

#pragma mark - Other
- (Float64)getCurrentTimestamp {
    CMClockRef hostClockRef = CMClockGetHostTimeClock();
    CMTime hostTime = CMClockGetTime(hostClockRef);
    return CMTimeGetSeconds(hostTime)*1000;
}

#pragma mark - Sort Callback
- (void)getSortedVideoNode:(CMSampleBufferRef)sampleBuffer {
    int64_t pts = (int64_t)(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000);
    static int64_t lastpts = 0;
//    NSLog(@"Test marigin - %lld",pts - lastpts);
    lastpts = pts;
    
    [self.previewView displayPixelBuffer:CMSampleBufferGetImageBuffer(sampleBuffer)];
}

@end
