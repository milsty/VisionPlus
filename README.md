# 运行说明：
1. 从苹果网站下载模型YOLOv3:https://developer.apple.com/machine-learning/models/
2. 放入工程里
# 项目简介
VisionPlus是一款专为失明者设计的创新型应用，我们将在通过coreML框架的语音识别和图像识别技术，帮助用户更全面地感知和理解周围的世界。这款应用不仅提供实时场景的语音描述，还能通过图像识别将环境中的物体、人物和文字转化为声音或语音提示，让用户能够更自信、方便地参与社交、工作和生活活动。我们需要实现以下功能：
1. 实时场景描述： VisionPlus利用手机摄像头捕捉环境，并通过语音实时描述用户所“看见”的物品。
2. 物体识别： 应用能够识别并描述用户所面对的物体，例如家具、器物、食物等，通过语音反馈，使用户能够更好地理解周围环境。
3. 用户友好界面： VisionPlus注重用户体验，提供简洁直观的界面，支持语音和手势操作，确保用户能够轻松地使用各种功能。
通过coreML框架的语音识别和图像识别技术，我们可以轻松实现以上功能
## 1 语音识别
 Core ML的Speech框架支持实时语音识别，能够将用户的语音转换为文本。这对于视力障碍者在找物品时非常有用，通过语音就可以直接输入要寻找的物品。VisionPlus进而可以在实时场景中寻找对应的物品。
### 1.1 请求语音识别权限
1. 引入Speech Kit框架，请求录音和语音识别的权限。
[SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
}];
2. 在app的Info.plist中增加NSSpeechRecognitionUsageDescription，写明请求语音识别的作用。如果不写，调用上面的api时，app会直接crash
### 1.2 创建语音识别请求
1. 创建SFSpeechRecognizer，设置语言
2. 创建AVAudioEngine，用于录制音频
3. 创建SFSpeechAudioBufferRecognitionRequest，用于识别录制的语音
```
- (void)setupEngine
{
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"zh-CN"];
    self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    self.audioEngine = [[AVAudioEngine alloc] init];
}
```
### 1.3 执行语音识别请求
将录制的语音buffer传入语音识别请求中
```
    [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        if (result.isFinal) {
            self.textView.text = [NSString stringWithFormat:@"%@%@", self.textView.text, result.bestTranscription.formattedString];
        }
    }];
```
## 2 实时场景捕捉
### 2.1 使用AVFoudnation实时捕捉视频
1. 设置分辨率。
苹果建议：为您的应用选择正确的分辨率非常重要。如果您的应用程序不需要，请不要简单地选择可用的最高分辨率。最好选择较低的分辨率，以便 Vision 可以更有效地处理结果。检查 Xcode 中的模型参数，了解您的应用程序是否需要小于 640 x 480 像素的分辨率。
 self.session.sessionPreset = AVCaptureSessionPreset640x480;
2. 将设备的input输入到session中
```
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
```
4. 将视频输出添加到session中，确保指定像素格式
 为了简化缓冲区管理，在捕获输出中，我们设置alwaysDiscardsLateVideoFrames，使得AVFoundation 在下一帧来临时丢弃上一次未被处理的帧。
```
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
```
5. 处理每一帧，但一次不要保留多个视觉请求。
```
    AVCaptureConnection *captureConnection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    [captureConnection setEnabled:YES];
    [videoDevice lockForConfiguration:nil];
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(videoDevice.activeFormat.formatDescription);
    self.bufferSize = CGSizeMake(dimensions.width, dimensions.height);
    [videoDevice unlockForConfiguration];
    
    [self.session commitConfiguration];
```
7. 启动视频实时捕捉
```
    [self.session startRunning];
```
## 3 物体识别
### 3.1 创建图像识别请求
objectObservation.labels列出了每个分类标识符及其置信度值，从最高置信度到最低置信度排序。
```
- (void)setupVisionRequests
{
    VNCoreMLModel *visionModel = [VNCoreMLModel modelForMLModel:[YOLOv3 new].model error:NULL];
    self.objectRecognitionRequest = [[VNCoreMLRequest alloc] initWithModel:visionModel completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        for (VNRecognizedObjectObservation * objectObservation in observations) {
            VNClassificationObservation *topLabelObservation = objectObservation.labels[0];
        }
    }];
}
```
### 3.2 将实时捕捉的图像输入到图像识别请求中
1. 实现AVCaptureVideoDataOutputSampleBufferDelegate，将sampleBuffer输入到imageRequestHandler中
```
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CVImageBufferRef *pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CGImagePropertyOrientation *exifOrientation = [self specifyDeviceOrientatin];
    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:exifOrientation options:@{}];
    [imageRequestHandler performRequests:@[self.objectRecognitionRequest] error:NULL];
}
```
2. specifyDeviceOrientatin是用于确定相机的方向。本文使用手机的方向UIDeviceOrientation来确定图片的方向CGImagePropertyOrientation。这样做的原因是为了确保图像识别的结果与用户实际看到的场景保持一致。这是因为相机采集到的图像数据通常是与手机的物理方向有关的，而图像识别算法可能需要根据这个方向来正确解释和处理图像。
```
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
```
### 3.3 灵敏度调节
在实时识别图像时，降低灵敏度级别以减少误识别是一个合理的做法，尤其是在移动时。要实现秒级的灵敏度级别比较合适。有三种方法实现：
1. 帧率调整：降低图像处理的帧率是最直接的方法之一。你可以设置相机捕获图像的帧率，然后仅对部分帧进行图像识别。这可以通过设置 AVCaptureDevice 的 activeVideoMinFrameDuration 或 activeVideoMaxFrameDuration 属性来实现。
2. 处理间隔：在实际进行图像处理时，你可以设置一个处理间隔，只对每隔一定时间的图像帧进行识别。这可以通过记录上次处理的时间戳，然后与当前帧的时间戳进行比较来实现。
3. 帧差法。
VisionPlus采用处理间隔来实现灵敏度的条件。
## 4 语音播报
使用AVSpeechUtterance、AVSpeechSynthesizer就可以直接将文字转语音播报出来
```
AVSpeechUtterance *speech = [AVSpeechUtterance speechUtteranceWithString:topLabelObservation.identifier];
AVSpeechSynthesizer *er = [[AVSpeechSynthesizer alloc] init];
[er speakUtterance:speech];
```
