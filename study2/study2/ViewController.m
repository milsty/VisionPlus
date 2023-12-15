//
//  RecognizingObjViewController.m
//  CoreMLDemo
//
//  Created by kuraki on 2023/12/14.
//  Copyright © 2023 Weibo. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import "YOLOv3.h"
#import <Speech/Speech.h>
#import <AVFAudio/AVSpeechSynthesis.h>

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession * session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer * previewLayer;
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) VNRequest *objectRecognitionRequest;
@property (nonatomic, assign) CGSize bufferSize;
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) NSInteger sensitibity;

@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) SFSpeechRecognizer *speechRecognizer;
@property (nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property (nonatomic, strong) AVSpeechSynthesizer *synthesizer;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupLiveCapture];
    [self setupUI];
    [self setupVisionRequests];
    self.synthesizer = [[AVSpeechSynthesizer alloc] init];
}

- (void)setupUI {
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.layer.bounds;
    [self.view.layer addSublayer:self.previewLayer];
    [self setupButton];
    
    [self.view addSubview:self.textView];
}

- (void)setupButton
{
    UIButton *btn4 = [[UIButton alloc] initWithFrame:CGRectMake(0, 50, 200, 50)];
    [btn4 setTitle:@"开始检测" forState:UIControlStateNormal];
    btn4.backgroundColor = [UIColor colorWithRed:254/255 green:44/255 blue:85/255 alpha:1.0];
    [btn4 addTarget:self action:@selector(configSensitivity:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn4];
    
    UIButton *btn1 = [[UIButton alloc] initWithFrame:CGRectMake(0, 110, 200, 50)];
    [btn1 setTitle:@"实时检测-毫秒级" forState:UIControlStateNormal];
    [btn1 setTitleColor:[UIColor colorWithRed:254/255 green:44/255 blue:85/255 alpha:1.0] forState:UIControlStateNormal];
    btn1.backgroundColor = [UIColor colorWithRed:254/255 green:44/255 blue:85/255 alpha:0.08];
    [btn1 addTarget:self action:@selector(configSensitivity:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn1];
    
    UIButton *btn2 = [[UIButton alloc] initWithFrame:CGRectMake(0, 170, 200, 50)];
    [btn2 setTitle:@"实时检测-秒级" forState:UIControlStateNormal];
    [btn2 setTitleColor:[UIColor colorWithRed:254/255 green:44/255 blue:85/255 alpha:1.0] forState:UIControlStateNormal];
    btn2.backgroundColor = [UIColor colorWithRed:254/255 green:44/255 blue:85/255 alpha:0.08];
    [btn2 addTarget:self action:@selector(configSensitivity:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn2];
    
    UIButton *btn3 = [[UIButton alloc] initWithFrame:CGRectMake(0, 230, 200, 50)];
    [btn3 setTitle:@"实时检测-3秒级" forState:UIControlStateNormal];
    [btn3 setTitleColor:[UIColor colorWithRed:254/255 green:44/255 blue:85/255 alpha:1.0] forState:UIControlStateNormal];
    btn3.backgroundColor = [UIColor colorWithRed:254/255 green:44/255 blue:85/255 alpha:0.08];
    [btn3 addTarget:self action:@selector(configSensitivity:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn3];

    [self.view addSubview:self.recordButton];
}

- (void)configSensitivity:(UIButton *)button
{
    if ([button.titleLabel.text isEqualToString:@"实时检测-毫秒级"]) {
        self.sensitibity = 0;
    } else if ([button.titleLabel.text isEqualToString:@"设置灵敏度为1秒"]) {
        self.sensitibity = 1;
    } else if ([button.titleLabel.text isEqualToString:@"设置灵敏度为3秒"]) {
        self.sensitibity = 3;
    } else if ([button.titleLabel.text isEqualToString:@"开始检测"]) {
        [self starRunningLiveCapture];
    }
}

- (void)setupLiveCapture {
    self.session = [[AVCaptureSession alloc] init];
    
    [self.session beginConfiguration];
    
    self.session.sessionPreset = AVCaptureSessionPreset640x480;
    
    //input
    AVCaptureDevice *videoDevice = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack].devices.firstObject;
    NSError *error = nil;
    AVCaptureInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (error) {
        NSLog(@"Could not create video device input:%@", error);
        return;
    }
    if (![self.session canAddInput:deviceInput]) {
        NSLog(@"Could not add video device input to the session");
        [self.session commitConfiguration];
        return;
    } else {
        [self.session addInput:deviceInput];
    }
    //output
    AVCaptureVideoDataOutput *videoDataOutput = [AVCaptureVideoDataOutput new];
    if ([self.session canAddOutput:videoDataOutput]){
        [self.session addOutput:videoDataOutput];
        // Add a video data output
        videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
        videoDataOutput.videoSettings = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        };
        [videoDataOutput setSampleBufferDelegate:self queue: self.videoDataOutputQueue];
    } else {
        NSLog(@"Could not add video data output to the session");
        [self.session commitConfiguration];
        return;
    }
    //connection
    AVCaptureConnection *captureConnection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    [captureConnection setEnabled:YES];
    [videoDevice lockForConfiguration:nil];
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(videoDevice.activeFormat.formatDescription);
    self.bufferSize = CGSizeMake(dimensions.width, dimensions.height);
    [videoDevice unlockForConfiguration];
    
    [self.session commitConfiguration];
}

- (void)starRunningLiveCapture
{
    self.sensitibity = 0;
    [self.session startRunning];
}

- (void)setupVisionRequests
{
    VNCoreMLModel *visionModel = [VNCoreMLModel modelForMLModel:[YOLOv3 new].model error:NULL];
    self.objectRecognitionRequest = [[VNCoreMLRequest alloc] initWithModel:visionModel completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        if (error) {
            return;// NSLog(@"Failed: %@", error);
        }
        NSArray<VNObservation *> *observations = request.results;
        if (!observations.count) {
            return;// NSLog(@"No Results");
        }
        
        for (VNRecognizedObjectObservation * objectObservation in observations) {
            VNClassificationObservation *topLabelObservation = objectObservation.labels[0];
            CGRect objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox,self.bufferSize.width,self.bufferSize.height);
            
//            self.shapeLayer = [self createRoundedRectLayerWithBounds:objectBounds];
//            CALayer *textLayer = [self createTextSubLayerInBounds:objectBounds identifier:topLabelObservation.identifier confidence:topLabelObservation.confidence];
//           // [self.shapeLayer addSublayer:textLayer];
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [self.shapeLayer addSublayer:textLayer];
//            });
            NSLog(@"%@",topLabelObservation.identifier);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.textView.text = topLabelObservation.identifier;
            });
            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:topLabelObservation.identifier];
            [self.synthesizer speakUtterance:utterance];
        }
    }];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CVImageBufferRef *pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) {
        return;
    }
    if (self.date && ([[NSDate now] timeIntervalSinceDate:self.date] < self.sensitibity)) {
        return;
    }
    self.date = [NSDate now];
    
    CGImagePropertyOrientation *exifOrientation = [self specifyDeviceOrientatin];

    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:exifOrientation options:@{}];
    [imageRequestHandler performRequests:@[self.objectRecognitionRequest] error:NULL];
}


- (CGImagePropertyOrientation)specifyDeviceOrientatin
{
    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    CGImagePropertyOrientation exifOrientation;
    switch (curDeviceOrientation) {
        case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = kCGImagePropertyOrientationLeft;
            break;
        case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = kCGImagePropertyOrientationUpMirrored;
            break;
        case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = kCGImagePropertyOrientationDown;
            break;
        case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = kCGImagePropertyOrientationUp;
            break;
        default:
            exifOrientation = kCGImagePropertyOrientationUp;
            break;
    }
    return exifOrientation;
}

- (CALayer *)createRoundedRectLayerWithBounds:(CGRect)bounds
{
    CALayer *shapeLayer = [CALayer new];
    shapeLayer.bounds = bounds;
    shapeLayer.position =  CGPointMake(bounds.origin.x, bounds.origin.y);
    shapeLayer.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.1].CGColor;
    return shapeLayer;
}

- (CATextLayer *)createTextSubLayerInBounds:(CGRect)bounds identifier:(NSString *)identifier confidence:(VNConfidence)confidence
{
    CATextLayer *textLayer = [CATextLayer new];
    textLayer.string = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\nConfidence:  %.2f",identifier,confidence] attributes:@{
        NSForegroundColorAttributeName:[UIColor systemPinkColor]
    }];
    textLayer.bounds = CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.height - 10,bounds.size.width - 10);
    textLayer.position = CGPointMake(bounds.origin.x, bounds.origin.y);
    NSLog(@"%@",identifier);
    return textLayer;
}

- (AVCaptureVideoPreviewLayer *)previewLayer
{
    if (!_previewLayer) {
        _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    }
    return _previewLayer;
}

- (AVCaptureSession *)session
{
    if (!_session) {
        _session = [[AVCaptureSession alloc] init];
    }
    return _session;
}

- (dispatch_queue_t)videoDataOutputQueue
{
    if (!_videoDataOutputQueue) {
        _videoDataOutputQueue = dispatch_queue_create("recoginizing.object.queue", DISPATCH_QUEUE_SERIAL);
    }
    return _videoDataOutputQueue;
}

#pragma mark - audio

- (void)requestPermission
{
    // 请求权限
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        NSLog(@"status %@", status == SFSpeechRecognizerAuthorizationStatusAuthorized ? @"授权成功" : @"授权失败");
    }];
}

- (void)initEngine {
    if (!self.speechRecognizer) {
        // 设置语言
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"zh-CN"];
        self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    }
    if (!self.audioEngine) {
        self.audioEngine = [[AVAudioEngine alloc] init];
    }
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryRecord mode:AVAudioSessionModeMeasurement options:AVAudioSessionCategoryOptionDuckOthers error:nil];
    [audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    
    if (self.recognitionRequest) {
        [self.recognitionRequest endAudio];
        self.recognitionRequest = nil;
    }
    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    self.recognitionRequest.shouldReportPartialResults = YES; // 实时翻译
    
    [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        NSLog(@"is final: %d  result: %@", result.isFinal, result.bestTranscription.formattedString);
        if (result.isFinal) {
            self.textView.text = [NSString stringWithFormat:@"%@%@", self.textView.text, result.bestTranscription.formattedString];
        }
    }];
}

- (void)releaseEngine {
    [[self.audioEngine inputNode] removeTapOnBus:0];
    [self.audioEngine stop];
    
    [self.recognitionRequest endAudio];
    self.recognitionRequest = nil;
}

- (void)startRecording:(UIButton *)recordButton {
    [self requestPermission];
    [self initEngine];
    
    AVAudioFormat *recordingFormat = [[self.audioEngine inputNode] outputFormatForBus:0];
    [[self.audioEngine inputNode] installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [self.recognitionRequest appendAudioPCMBuffer:buffer];
    }];
    [self.audioEngine prepare];
    [self.audioEngine startAndReturnError:nil];
    
    [recordButton setTitle:@"录音ing" forState:UIControlStateNormal];
}

- (void)stopRecording:(UIButton *)recordButton {
    [self releaseEngine];
    
    [recordButton setTitle:@"长按录音" forState:UIControlStateNormal];
}

- (UITextView *)textView
{
    if (!_textView) {
        _textView = [[UITextView alloc] initWithFrame:CGRectMake(240, 150, 150, 50)];
        _textView.backgroundColor = [UIColor lightGrayColor];
    }
    return _textView;
}

- (UIButton *)recordButton
{
    if (!_recordButton) {
        _recordButton = [[UIButton alloc] initWithFrame:CGRectMake(240, 50, 150, 50)];
        _recordButton.backgroundColor = [UIColor blackColor];
        [_recordButton setTitle:@"长按录音" forState:UIControlStateNormal];
        [_recordButton addTarget:self action:@selector(startRecording:) forControlEvents:UIControlEventTouchDown];
        [_recordButton addTarget:self action:@selector(stopRecording:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    }
    return _recordButton;
}

@end

