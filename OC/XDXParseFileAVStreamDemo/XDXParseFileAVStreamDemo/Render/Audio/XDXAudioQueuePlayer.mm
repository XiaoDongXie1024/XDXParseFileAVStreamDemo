//
//  XDXAudioQueuePlayer.m
//  XDXAudioQueuePlayer
//
//  Created by 小东邪 on 2019/6/27.
//  Copyright © 2019 小东邪. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "XDXAudioQueuePlayer.h"

#define kXDXAudioPCMFramesPerPacket 1
#define kXDXAudioPCMBitsPerChannel  16

static const int kNumberBuffers = 3;

struct XDXAudioInfo {
    AudioStreamBasicDescription  mDataFormat;
    AudioQueueRef                mQueue;
    AudioQueueBufferRef          mBuffers[kNumberBuffers];
    int                          mbufferSize;
};
typedef struct XDXAudioInfo *XDXAudioInfoRef;

static XDXAudioInfoRef m_audioInfo;

@interface XDXAudioQueuePlayer ()

@property (nonatomic, assign, readwrite) BOOL    isRunning;
@property (nonatomic, assign) BOOL               isInitFinish;

@end

@implementation XDXAudioQueuePlayer
SingletonM

#pragma mark - Callback
static void PlayAudioDataCallback(void * aqData,AudioQueueRef inAQ , AudioQueueBufferRef inBuffer) {
    XDXAudioQueuePlayer *instance = (__bridge XDXAudioQueuePlayer *)aqData;
    if(instance == NULL){
        return;
    }
    
    /* Debug
    static Float64 lastTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970]*1000;
    NSLog(@"Test duration - %f",currentTime - lastTime);
    lastTime = currentTime;
    */
    
    [instance receiveAudioDataWithAudioQueueBuffer:inBuffer
                                         audioInfo:m_audioInfo
                                  audioBufferQueue:instance->_audioBufferQueue];
}

static void AudioQueuePlayerPropertyListenerProc  (void *              inUserData,
                                                   AudioQueueRef           inAQ,
                                                   AudioQueuePropertyID    inID) {
    XDXAudioQueuePlayer * instance = (__bridge XDXAudioQueuePlayer *)inUserData;
    UInt32 isRunning = 0;
    UInt32 size = sizeof(isRunning);
    
    if(instance == NULL)
        return ;
    
    OSStatus err = AudioQueueGetProperty (inAQ, kAudioQueueProperty_IsRunning, &isRunning, &size);
    if (err) {
        instance->_isRunning = NO;
    }else {
        instance->_isRunning = isRunning;
    }
    
    NSLog(@"The audio queue work state: %d",instance->_isRunning);
}

#pragma mark - Lifecycle
+ (void)initialize {
    int size = sizeof(XDXAudioInfo);
    m_audioInfo = (XDXAudioInfoRef)malloc(size);
}

- (instancetype)init {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instace                  = [super init];
        self->_isInitFinish       = NO;
        self->_audioBufferQueue   = new XDXCustomQueueProcess();
    });
    return _instace;
}

- (void)dealloc {
    if (_audioBufferQueue) {
        _audioBufferQueue = NULL;
    }
    
    if (m_audioInfo) {
        free(m_audioInfo);
    }
}

#pragma mark - Public
+ (instancetype)getInstance {
    return [[self alloc] init];
}

- (void)configureAudioPlayerWithAudioFormat:(AudioStreamBasicDescription *)audioFormat bufferSize:(int)bufferSize {
    memcpy(&m_audioInfo->mDataFormat, audioFormat, sizeof(XDXAudioInfo));
    m_audioInfo->mbufferSize = bufferSize;    
    BOOL isSuccess = [self configureAudioPlayerWithAudioInfo:m_audioInfo
                                                playCallback:PlayAudioDataCallback
                                            listenerCallback:AudioQueuePlayerPropertyListenerProc];
    
    self.isInitFinish = isSuccess;
}

- (void)startAudioPlayer {
    if (self.isRunning) {
        NSLog(@"Audio Player: the player is running !");
        return;
    }
    
    if (self.isInitFinish) {
        [self startAudioPlayerWithAudioInfo:m_audioInfo];
    }else {
        NSLog(@"Audio Player: start audio player failed, not init !");
    }
}

- (void)pauseAudioPlayer {
    if (!self.isRunning) {
        NSLog(@"Audio Player: audio player is not running !");
        return;
    }
    
    BOOL isSuccess = [self pauseAudioPlayerWithAudioInfo:m_audioInfo];
    
    if (isSuccess) {
        self.isRunning = NO;
    }
}

- (void)stopAudioPlayer {
    if (self.isRunning == NO) {
        NSLog(@"Audio Player: Stop recorder repeat \n");
        return;
    }
    
    [self stopAudioQueueRecorderWithAudioInfo:m_audioInfo];
}

- (void)resumeAudioPlayer {
    if (self.isRunning) {
        NSLog(@"Audio Player: audio player is running !");
        return;
    }
    
    [self resumeAudioPlayerWithAudioInfo:m_audioInfo];
}

- (void)freeAudioPlayer {
    if (self.isRunning) {
        [self stopAudioQueueRecorderWithAudioInfo:m_audioInfo];
    }
    
    [self freeAudioQueueRecorderWithAudioInfo:m_audioInfo];
}

+ (int)audioBufferSize {
    return m_audioInfo->mbufferSize;
}

#pragma mark - Private
- (BOOL)configureAudioPlayerWithAudioInfo:(XDXAudioInfoRef)audioInfo playCallback:(AudioQueueOutputCallback)playCallback listenerCallback:(AudioQueuePropertyListenerProc)listenerCallback {
//    [self printASBD:*audioFormat];
    
    // Create audio queue
    OSStatus status = AudioQueueNewOutput(&audioInfo->mDataFormat,
                                         playCallback,
                                         (__bridge void *)(self),
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0,
                                         &audioInfo->mQueue);
    
    if (status != noErr) {
        NSLog(@"Audio Player: audio queue new output failed status:%d \n",(int)status);
        return NO;
    }
    
    // Listen the queue is whether working
    AudioQueueAddPropertyListener (audioInfo->mQueue,
                                   kAudioQueueProperty_IsRunning,
                                   listenerCallback,
                                   (__bridge void *)(self));
    
    // Get audio ASBD
    UInt32 size = sizeof(audioInfo->mDataFormat);
    status = AudioQueueGetProperty(audioInfo->mQueue,
                                   kAudioQueueProperty_StreamDescription,
                                   &audioInfo->mDataFormat,
                                   &size);
    if (status != noErr) {
        NSLog(@"Audio Player: get ASBD status:%d",(int)status);
        return NO;
    }
    
    // Set volume
    status = AudioQueueSetParameter(audioInfo->mQueue, kAudioQueueParam_Volume, 1.0);
    if (status != noErr) {
        NSLog(@"Audio Player: set volume failed:%d",(int)status);
        return NO;
    }
    
    // Allocate buffer for audio queue buffer
    for (int i = 0; i != kNumberBuffers; i++) {
        status = AudioQueueAllocateBuffer(audioInfo->mQueue,
                                          audioInfo->mbufferSize,
                                          &audioInfo->mBuffers[i]);
        if (status != noErr) {
            NSLog(@"Audio Player: Allocate buffer status:%d",(int)status);
        }
    }
    
    return YES;
}

- (void)receiveAudioDataWithAudioQueueBuffer:(AudioQueueBufferRef)inBuffer audioInfo:(XDXAudioInfoRef)audioInfo audioBufferQueue:(XDXCustomQueueProcess *)audioBufferQueue {
    XDXCustomQueueNode *node = audioBufferQueue->DeQueue(audioBufferQueue->m_work_queue);
    
    if (node != NULL) {
        if (node->size > 0) {
            UInt32 size = (UInt32)node->size;
            inBuffer->mAudioDataByteSize = size;
            memcpy(inBuffer->mAudioData, node->data, size);
            AudioStreamPacketDescription *packetDesc = (AudioStreamPacketDescription *)node->userData;
            AudioQueueEnqueueBuffer (
                                     audioInfo->mQueue,
                                     inBuffer,
                                     (packetDesc ? size : 0),
                                     packetDesc);

        }
        
        node->size = 0;
        audioBufferQueue->EnQueue(audioBufferQueue->m_free_queue, node);
    }else {
        inBuffer->mAudioDataByteSize = audioInfo->mbufferSize;
        memset(inBuffer->mAudioData, 0, audioInfo->mbufferSize);
        AudioQueueEnqueueBuffer (audioInfo->mQueue, inBuffer, 0, NULL);
    }
}

- (BOOL)startAudioPlayerWithAudioInfo:(XDXAudioInfoRef)audioInfo {
    for (int i = 0; i != kNumberBuffers; i++) {
        memset(audioInfo->mBuffers[i]->mAudioData, 0, audioInfo->mbufferSize);
        audioInfo->mBuffers[i]->mAudioDataByteSize = audioInfo->mbufferSize;
        AudioQueueEnqueueBuffer (audioInfo->mQueue, audioInfo->mBuffers[i], 0, NULL);
    }
    
    OSStatus status;
    status = AudioQueueStart(m_audioInfo->mQueue, NULL);
    if (status != noErr) {
        NSLog(@"Audio Player: Audio Queue Start failed status:%d \n",(int)status);
        return NO;
    }else {
        NSLog(@"Audio Player: Audio Queue Start successful");
        return YES;
    }
}

- (BOOL)pauseAudioPlayerWithAudioInfo:(XDXAudioInfoRef)audioInfo {
    OSStatus status = AudioQueuePause(audioInfo->mQueue);
    if (status != noErr) {
        NSLog(@"Audio Player: Audio Queue pause failed status:%d \n",(int)status);
        return NO;
    }else {
        NSLog(@"Audio Player: Audio Queue pause successful");
        return YES;
    }
}

- (BOOL)resumeAudioPlayerWithAudioInfo:(XDXAudioInfoRef)audioInfo {
    OSStatus status = AudioQueueStart(audioInfo->mQueue, NULL);
    if (status != noErr) {
        NSLog(@"Audio Player: Audio Queue resume failed status:%d \n",(int)status);
        return NO;
    }else {
        NSLog(@"Audio Player: Audio Queue resume successful");
        return YES;
    }
}

-(BOOL)stopAudioQueueRecorderWithAudioInfo:(XDXAudioInfoRef)audioInfo {
    if (audioInfo->mQueue) {
        OSStatus stopRes = AudioQueueStop(audioInfo->mQueue, true);
        
        if (stopRes == noErr){
            NSLog(@"Audio Player: stop Audio Queue success.");
            return YES;
        }else{
            NSLog(@"Audio Player: stop Audio Queue failed.");
            return NO;
        }
    }else {
        NSLog(@"Audio Player: stop Audio Queue failed, the queue is nil.");
        return NO;
    }
}

-(BOOL)freeAudioQueueRecorderWithAudioInfo:(XDXAudioInfoRef)audioInfo {
    if (audioInfo->mQueue) {
        for (int i = 0; i < kNumberBuffers; i++) {
            AudioQueueFreeBuffer(audioInfo->mQueue, audioInfo->mBuffers[i]);
        }
        
        OSStatus status = AudioQueueDispose(audioInfo->mQueue, true);
        if (status != noErr) {
            NSLog(@"Audio Player: Dispose failed: %d",status);
        }else {
            audioInfo->mQueue = NULL;
            NSLog(@"Audio Player: free AudioQueue successful.");
            return YES;
        }
    }else {
        NSLog(@"Audio Player: free Audio Queue failed, the queue is nil.");
    }
    
    return NO;
}


#pragma mark Other
-(int)computeRecordBufferSizeFrom:(const AudioStreamBasicDescription *)format audioQueue:(AudioQueueRef)audioQueue durationSec:(float)durationSec {
    int packets = 0;
    int frames  = 0;
    int bytes   = 0;
    
    frames = (int)ceil(durationSec * format->mSampleRate);
    
    if (format->mBytesPerFrame > 0)
        bytes = frames * format->mBytesPerFrame;
    else {
        UInt32 maxPacketSize;
        if (format->mBytesPerPacket > 0){   // CBR
            maxPacketSize = format->mBytesPerPacket;    // constant packet size
        }else { // VBR
            // AAC Format get kAudioQueueProperty_MaximumOutputPacketSize return -50. so the method is not effective.
            UInt32 propertySize = sizeof(maxPacketSize);
            OSStatus status     = AudioQueueGetProperty(audioQueue,
                                                        kAudioQueueProperty_MaximumOutputPacketSize,
                                                        &maxPacketSize,
                                                        &propertySize);
            if (status != noErr) {
                NSLog(@"%s: get max output packet size failed:%d",__func__,status);
            }
        }
        
        if (format->mFramesPerPacket > 0)
            packets = frames / format->mFramesPerPacket;
        else
            packets = frames;    // worst-case scenario: 1 frame in a packet
        if (packets == 0)        // sanity check
            packets = 1;
        bytes = packets * maxPacketSize;
    }
    
    return bytes;
}

- (void)printASBD:(AudioStreamBasicDescription)asbd {
    char formatIDString[5];
    UInt32 formatID = CFSwapInt32HostToBig (asbd.mFormatID);
    bcopy (&formatID, formatIDString, 4);
    formatIDString[4] = '\0';
    
    NSLog (@"  Sample Rate:         %10.0f",  asbd.mSampleRate);
    NSLog (@"  Format ID:           %10s",    formatIDString);
    NSLog (@"  Format Flags:        %10X",    asbd.mFormatFlags);
    NSLog (@"  Bytes per Packet:    %10d",    asbd.mBytesPerPacket);
    NSLog (@"  Frames per Packet:   %10d",    asbd.mFramesPerPacket);
    NSLog (@"  Bytes per Frame:     %10d",    asbd.mBytesPerFrame);
    NSLog (@"  Channels per Frame:  %10d",    asbd.mChannelsPerFrame);
    NSLog (@"  Bits per Channel:    %10d",    asbd.mBitsPerChannel);
}

-(AudioStreamBasicDescription)getAudioFormatWithFormatID:(UInt32)formatID sampleRate:(Float64)sampleRate channelCount:(UInt32)channelCount {
    AudioStreamBasicDescription dataFormat = {0};
    
    UInt32 size = sizeof(dataFormat.mSampleRate);
    // Get hardware origin sample rate. (Recommended it)
    Float64 hardwareSampleRate = 0;
    AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate,
                            &size,
                            &hardwareSampleRate);
    // Manual set sample rate
    dataFormat.mSampleRate = sampleRate;
    
    size = sizeof(dataFormat.mChannelsPerFrame);
    // Get hardware origin channels number. (Must refer to it)
    UInt32 hardwareNumberChannels = 0;
    AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareInputNumberChannels,
                            &size,
                            &hardwareNumberChannels);
    dataFormat.mChannelsPerFrame = channelCount;
    
    // Set audio format
    dataFormat.mFormatID = formatID;
    
    // Set detail audio format params
    if (formatID == kAudioFormatLinearPCM) {
        dataFormat.mFormatFlags     = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        
        dataFormat.mBitsPerChannel  = kXDXAudioPCMBitsPerChannel;
        dataFormat.mBytesPerPacket  = dataFormat.mBytesPerFrame = (dataFormat.mBitsPerChannel / 8) * dataFormat.mChannelsPerFrame;
        dataFormat.mFramesPerPacket = kXDXAudioPCMFramesPerPacket;
    }else if (formatID == kAudioFormatMPEG4AAC) {
        dataFormat.mFormatFlags = kMPEG4Object_AAC_Main;
    }
    
    NSLog(@"Audio Player: starup PCM audio encoder:%f,%d",sampleRate,channelCount);
    return dataFormat;
}

@end

