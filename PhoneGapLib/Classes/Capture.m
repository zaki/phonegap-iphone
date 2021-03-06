/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 * 
 * Copyright (c) 2005-2010, Nitobi Software Inc.
 * Copyright (c) 2011, IBM Corporation
 */

#import "Capture.h"
#import "JSON.h"
#import "PhoneGapDelegate.h"

#define kW3CMediaFormatHeight @"height"
#define kW3CMediaFormatWidth @"width"
#define kW3CMediaFormatCodecs @"codecs"
#define kW3CMediaFormatBitrate @"bitrate"
#define kW3CMediaFormatDuration @"duration"
#define kW3CMediaModeType @"type"

@implementation PGImagePicker

@synthesize quality;
@synthesize callbackId;
@synthesize mimeType;


- (uint64_t) accessibilityTraits
{
	NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
	if (([systemVersion compare:@"4.0" options:NSNumericSearch] != NSOrderedAscending)) { // this means system version is not less than 4.0 
		return UIAccessibilityTraitStartsMediaSession;
	}

	return UIAccessibilityTraitNone;
}

- (void) dealloc
{
	if (callbackId) {
		[callbackId release];
	}
    if (mimeType) {
        [mimeType release];
    }
	
	
	[super dealloc];
}

@end

@implementation Capture
@synthesize inUse;

-(id)initWithWebView:(UIWebView *)theWebView
{
	self = (Capture*)[super initWithWebView:theWebView];
	if(self)
	{
        self.inUse = NO;
    }
    return self;
}
- (void) captureAudio:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
    NSString* callbackId = [arguments objectAtIndex:0];
    NSNumber* duration = [options objectForKey:@"duration"];
    // the default value of duration is 0 so use nil (no duration) if default value
    if (duration) {
        duration = [duration doubleValue] == 0 ? nil : duration;
    }
    PluginResult* result = nil;
    
    if (NSClassFromString(@"AVAudioRecorder") == nil) {
        result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject: CAPTURE_NOT_SUPPORTED];
    }
    else if (self.inUse == YES) {
        result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject: CAPTURE_APPLICATION_BUSY];
    } else {
        // all the work occurs here
        AudioRecorderViewController* audioViewController = [[[AudioRecorderViewController alloc] initWithCommand:  self duration: duration callbackId: callbackId] autorelease];
        
        // Now create a nav controller and display the view...
        UINavigationController *navController = [[[UINavigationController alloc] initWithRootViewController:audioViewController] autorelease];
        self.inUse = YES;
        
        [self.appViewController presentModalViewController:navController animated: YES];
    }
        
    if (result) {
        [self writeJavascript: [result toErrorCallbackString:callbackId]];
    }
}

- (void) captureImage:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
    NSString* callbackId = [arguments objectAtIndex:0];
    NSString* mode = [options objectForKey:@"mode"];
    
	//options could contain limit and mode neither of which are supported at this time
    // taking more than one picture (limit) is only supported if provide own controls via cameraOverlayView property
    // can support mode in OS 
    
	if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
		NSLog(@"Capture.imageCapture: camera not available.");
        PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject:CAPTURE_NOT_SUPPORTED];
        [self writeJavascript:[result toErrorCallbackString:callbackId]];
        
	} else {
	
        if (pickerController == nil) {
            pickerController = [[PGImagePicker alloc] init];
        }
	
        pickerController.delegate = self;
        pickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
        pickerController.allowsEditing = NO;
        if ([pickerController respondsToSelector:@selector(mediaTypes)]) {
            // iOS 3.0
            pickerController.mediaTypes = [NSArray arrayWithObjects: (NSString*) kUTTypeImage, nil];
        }
        /*if ([pickerController respondsToSelector:@selector(cameraCaptureMode)]){
            // iOS 4.0 
            pickerController.cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
            pickerController.cameraDevice = UIImagePickerControllerCameraDeviceRear;
            pickerController.cameraFlashMode = UIImagePickerControllerCameraFlashModeAuto;
        }*/
        // PGImagePicker specific property
        pickerController.callbackId = callbackId;
        pickerController.mimeType = mode;
	
        [[super appViewController] presentModalViewController:pickerController animated:YES];
    }

}
/* Process a still image from the camera.
 * IN: 
 *  UIImage* image - the UIImage data returned from the camera
 *  NSString* callbackId
 * OUT:
 *  NSString* jsString - the error or success JavaScript string to execute
 *  
 */
-(NSString*) processImage: (UIImage*) image type: (NSString*) mimeType forCallbackId: (NSString*)callbackId 
{
    PluginResult* result = nil;
    NSString* jsString = nil;
    // save the image to photo album
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    
    NSData* data = nil;
    if (mimeType && [mimeType isEqualToString:@"image/png"]) {
        data = UIImagePNGRepresentation(image);
    } else {
       data = UIImageJPEGRepresentation(image, 0.5);
    }
    
    // write to temp directory and reutrn URI
    NSString* docsPath = [NSTemporaryDirectory() stringByStandardizingPath];  // use file system temporary directory
    NSError* err = nil;
    NSFileManager* fileMgr = [[NSFileManager alloc] init]; 
    
    // generate unique file name
    NSString* filePath;
    int i=1;
    do {
        filePath = [NSString stringWithFormat:@"%@/photo_%03d.jpg", docsPath, i++];
    } while([fileMgr fileExistsAtPath: filePath]);
    
    if (![data writeToFile: filePath options: NSAtomicWrite error: &err]){
        result = [PluginResult resultWithStatus: PGCommandStatus_OK messageToErrorObject: CAPTURE_INTERNAL_ERR ];
        jsString = [result toErrorCallbackString: callbackId];
        if (err) {
            NSLog(@"Error saving image: %@", [err localizedDescription]);
        }
        
    }else{
        // create MediaFile object
        
        NSDictionary* fileDict = [self getMediaDictionaryFromPath:filePath ofType: mimeType];
        NSArray* fileArray = [NSArray arrayWithObject:[fileDict JSONRepresentation]];
        
        result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsArray: fileArray cast:@"navigator.device.capture._castMediaFile"];
        jsString = [result toSuccessCallbackString:callbackId];
        
    }
    [fileMgr release];
    
    return jsString;
}
- (void) captureVideo:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
    NSString* callbackId = [arguments objectAtIndex:0];
	//options could contain limit, duration and mode, only duration is supported (but is not due to apple bug)
    // taking more than one video (limit) is only supported if provide own controls via cameraOverlayView property
    //NSNumber* duration = [options objectForKey:@"duration"];
    NSString* mediaType = nil;
    
	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        // there is a camera, it is available, make sure it can do movies
        if (pickerController != nil) {
            [pickerController release]; // create a new one for each instance to initialize all variables
        }
        pickerController = [[PGImagePicker alloc] init];

        NSArray* types = nil;
        if ([UIImagePickerController respondsToSelector: @selector(availableMediaTypesForSourceType:)]){
             types = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
            //NSLog(@"MediaTypes: %@", [types description]); 
        
            if ([types containsObject:(NSString*)kUTTypeMovie]){
                mediaType = (NSString*)kUTTypeMovie;
            } else if ([types containsObject:(NSString*)kUTTypeVideo]){
                mediaType = (NSString*)kUTTypeVideo;
            }
        }
    }
    if (!mediaType) {
        // don't have video camera return error
		NSLog(@"Capture.captureVideo: video mode not available.");
        PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject:CAPTURE_NOT_SUPPORTED];
        [self writeJavascript:[result toErrorCallbackString:callbackId]];
    } else { 
        
        pickerController.delegate = self;
        pickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
        pickerController.allowsEditing = NO;
        // iOS 3.0
        pickerController.mediaTypes = [NSArray arrayWithObjects: mediaType, nil];
        /*if ([mediaType isEqualToString:(NSString*)kUTTypeMovie]){
            if (duration) {
                pickerController.videoMaximumDuration = [duration doubleValue];
            }
            //NSLog(@"pickerController.videoMaximumDuration = %f", pickerController.videoMaximumDuration);
        }*/
             
        
        // iOS 4.0 
        if ([UIImagePickerController respondsToSelector:@selector(cameraCaptureMode)]) {
            pickerController.cameraCaptureMode = UIImagePickerControllerCameraCaptureModeVideo;
            //pickerController.cameraDevice = UIImagePickerControllerCameraDeviceRear;
            //pickerController.cameraFlashMode = UIImagePickerControllerCameraFlashModeAuto;
        }
        // PGImagePicker specific property
        pickerController.callbackId = callbackId;
        
        [[super appViewController] presentModalViewController:pickerController animated:YES];
    }
    
}
-(NSString*) processVideo: (NSString*) moviePath forCallbackId: (NSString*) callbackId
{
    PluginResult* result = nil;
    NSString* jsString = nil;
    
    // save the movie to photo album (only avail as of iOS 3.1)
    /* don't need, it should automatically get saved
     NSLog(@"can save %@: %d ?", moviePath, UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(moviePath));
    if (&UIVideoAtPathIsCompatibleWithSavedPhotosAlbum != NULL && UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(moviePath) == YES) { 
        NSLog(@"try to save movie");
        UISaveVideoAtPathToSavedPhotosAlbum(moviePath, nil, nil, nil);
        NSLog(@"finished saving movie");
    }*/
    // create MediaFile object
    NSDictionary* fileDict = [self getMediaDictionaryFromPath:moviePath ofType:nil];
    NSArray* fileArray = [NSArray arrayWithObject:[fileDict JSONRepresentation]];
    
    result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsArray: fileArray cast:@"navigator.device.capture._castMediaFile"];
    jsString = [result toSuccessCallbackString:callbackId];
    
    // 
    return jsString;
    
}
- (void) getMediaModes: (NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
   // NSString* callbackId = [arguments objectAtIndex:0];
    //NSMutableDictionary* imageModes = nil;
    NSArray* imageArray = nil;
    NSArray* movieArray = nil;
    NSArray* audioArray = nil;
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        // there is a camera, find the modes
        // can get image/jpeg or image/png from camera
        /* can't find a way to get the default height and width and other info 
         * for images/movies taken with UIImagePickerController
         */
        NSDictionary* jpg = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithInt:0],kW3CMediaFormatHeight, 
                             [NSNumber numberWithInt: 0], kW3CMediaFormatWidth,
                             @"image/jpeg", kW3CMediaModeType,
                             nil];
        NSDictionary* png = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithInt:0],kW3CMediaFormatHeight, 
                             [NSNumber numberWithInt: 0], kW3CMediaFormatWidth,
                             @"image/png", kW3CMediaModeType,
                             nil];
        imageArray = [NSArray arrayWithObjects:jpg, png, nil];
        
        if ([UIImagePickerController respondsToSelector: @selector(availableMediaTypesForSourceType:)]) {
            NSArray* types = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];

            if ([types containsObject:(NSString*)kUTTypeMovie]){
                NSDictionary* mov = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithInt:0],kW3CMediaFormatHeight, 
                                     [NSNumber numberWithInt: 0],kW3CMediaFormatWidth,
                                     @"video/quicktime", kW3CMediaModeType,
                                     nil];
                movieArray = [NSArray arrayWithObject:mov];
            }
        }
        
    }
    NSDictionary* modes = [NSDictionary dictionaryWithObjectsAndKeys:
                          imageArray ? (NSObject*)imageArray : [NSNull null], @"image",
                          movieArray ? (NSObject*)movieArray : [NSNull null], @"video",
                          audioArray ? (NSObject*)audioArray : [NSNull null], @"audio",
                          nil];
    NSString* jsString = [NSString stringWithFormat:@"navigator.device.capture.setSupportedModes(%@);", [modes JSONRepresentation]];
    [self writeJavascript:jsString];
    
    
}
- (void) getFormatData: (NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
    NSString* callbackId = [arguments objectAtIndex:0];
    // existence of fullPath checked on JS side
    NSString* fullPath = [arguments objectAtIndex:1];
    // mimeType could be empty/null
    NSString* mimeType = nil;
    if ([arguments count] > 2) {
        mimeType = [arguments objectAtIndex:2];
    }
    BOOL bError = NO;
    CaptureError errorCode = CAPTURE_INTERNAL_ERR;
    PluginResult* result = nil;
    NSString* jsString = nil;
    
    if (!mimeType){
        // try to determine mime type if not provided
        File* pgFile = [[self appDelegate] getCommandInstance: @"File"];
        mimeType = [pgFile getMimeTypeFromPath:fullPath];
        if (!mimeType) {
            // can't do much without mimeType, return error
            bError = YES;
            errorCode = CAPTURE_INVALID_ARGUMENT;
        }
    }
    if (!bError) {
        // create and initialize return dictionary
        NSMutableDictionary* formatData = [NSMutableDictionary dictionaryWithCapacity:5];
        [formatData setObject:[NSNull null] forKey: kW3CMediaFormatCodecs];
        [formatData setObject:[NSNumber numberWithInt:0] forKey: kW3CMediaFormatBitrate];
        [formatData setObject:[NSNumber numberWithInt:0] forKey: kW3CMediaFormatHeight];
        [formatData setObject:[NSNumber numberWithInt:0] forKey: kW3CMediaFormatWidth];
        [formatData setObject:[NSNumber numberWithInt:0] forKey: kW3CMediaFormatDuration];

        if ([mimeType rangeOfString:@"image/"].location != NSNotFound){
            UIImage* image = [UIImage imageWithContentsOfFile:fullPath];
            if (image) {
                CGSize imgSize = [image size];
                [formatData setObject:[NSNumber numberWithInteger: imgSize.width] forKey: kW3CMediaFormatWidth];
                [formatData setObject:[NSNumber numberWithInteger: imgSize.height] forKey: kW3CMediaFormatHeight];
            }
        } else if ([mimeType rangeOfString: @"video/"].location != NSNotFound && NSClassFromString(@"AVURLAsset") != nil) {
            NSURL* movieURL = [NSURL fileURLWithPath: fullPath];
            AVURLAsset* movieAsset = [[AVURLAsset alloc] initWithURL:movieURL options:nil];
            CMTime duration = [movieAsset duration];
            [formatData setObject:[NSNumber numberWithFloat:CMTimeGetSeconds(duration)]  forKey: kW3CMediaFormatDuration];
            CGSize size = [movieAsset naturalSize];
            [formatData setObject:[NSNumber numberWithFloat: size.height] forKey: kW3CMediaFormatHeight];
            [formatData setObject:[NSNumber numberWithFloat: size.width] forKey:kW3CMediaFormatWidth];
            // not sure how to get codecs or bitrate???
            //AVMetadataItem
            //AudioFile
            [movieAsset release];
            
        } else if ([mimeType rangeOfString: @"audio/"].location != NSNotFound) {
            if (NSClassFromString(@"AVAudioPlayer") != nil) {
                NSURL* fileURL = [NSURL fileURLWithPath: fullPath];
                NSError* err = nil;
                
                AVAudioPlayer* avPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&err];
                if (!err) {
                    // get the data 
                    [formatData setObject: [NSNumber numberWithDouble: [avPlayer duration]] forKey:kW3CMediaFormatDuration];
                    if ([avPlayer respondsToSelector: @selector(settings)]){
                        NSDictionary* info = [avPlayer settings];
                        NSNumber* bitRate = [info objectForKey:AVEncoderBitRateKey];
                        if (bitRate) {
                            [formatData setObject: bitRate forKey:kW3CMediaFormatBitrate];
                        }
                    }
                } // else leave data init'ed to 0
                if (avPlayer) {
                    [avPlayer release];
                }
            }
            
            
        }
        result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsDictionary:formatData];
        jsString = [result toSuccessCallbackString:callbackId];
        //NSLog(@"getFormatData: %@", [formatData description]);
    }
    if (bError) {
        result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject:errorCode];
        jsString = [result toErrorCallbackString:callbackId];
    }
    if (jsString) {
        [self writeJavascript:jsString];
    }
    
    
}
-(NSDictionary*) getMediaDictionaryFromPath: (NSString*) fullPath ofType: (NSString*) type
{
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSMutableDictionary* fileDict = [NSMutableDictionary dictionaryWithCapacity:5];
    [fileDict setObject: [fullPath lastPathComponent] forKey: @"name"];
    [fileDict setObject: fullPath forKey:@"fullPath"];
    // determine type
    if(!type) {
    File* pgFile = [[self appDelegate] getCommandInstance: @"File"];
    NSString* mimeType = [pgFile getMimeTypeFromPath:fullPath];
    [fileDict setObject: (mimeType != nil ? (NSObject*)mimeType : [NSNull null]) forKey:@"type"];
    }
        NSDictionary* fileAttrs = [fileMgr attributesOfItemAtPath:fullPath error:nil];
    [fileDict setObject: [NSNumber numberWithUnsignedLongLong:[fileAttrs fileSize]] forKey:@"size"];
    NSDate* modDate = [fileAttrs fileModificationDate];
    NSNumber* msDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970]*1000];
    [fileDict setObject:msDate forKey:@"lastModifiedDate"];
    
    [fileMgr release];
    return fileDict;
}
- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingImage:(UIImage*)image editingInfo:(NSDictionary*)editingInfo
{
    // older api calls new one
	[self imagePickerController:picker didFinishPickingMediaWithInfo: editingInfo];
    
}
/* Called when image/movie is finished recording.
 * Calls success or error code as appropriate
 * if successful, result  contains an array (with just one entry since can only get one image unless build own camera UI) of MediaFile object representating the image 
 *      name
 *      fullPath
 *      type
 *      lastModifiedDate
 *      size
 */
- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary*)info
{
    PGImagePicker* cameraPicker = (PGImagePicker*)picker;
	NSString* callbackId = cameraPicker.callbackId;
	
	[picker dismissModalViewControllerAnimated:YES];
	
    NSString* jsString = nil;
    PluginResult* result = nil;
	
    UIImage* image = nil;
	NSString* mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if (!mediaType || [mediaType isEqualToString:(NSString*)kUTTypeImage]){
        // mediaType is nil then only option is UIImagePickerControllerOriginalImage
		if ([UIImagePickerController respondsToSelector: @selector(allowsEditing)] &&
            (cameraPicker.allowsEditing && [info objectForKey:UIImagePickerControllerEditedImage])){
                image = [info objectForKey:UIImagePickerControllerEditedImage];
        } else {
			image = [info objectForKey:UIImagePickerControllerOriginalImage];
		}
    }
    if (image != nil) {
        // mediaType was image
        jsString = [self processImage: image type: cameraPicker.mimeType forCallbackId: callbackId];
    } else if ([mediaType isEqualToString:(NSString*)kUTTypeMovie]){
        // process video
        NSString *moviePath = [[info objectForKey: UIImagePickerControllerMediaURL] path];
        if (moviePath) {
            jsString = [self processVideo: moviePath forCallbackId: callbackId];
        }
    }                     
    if (!jsString) { 
        result = [PluginResult resultWithStatus: PGCommandStatus_OK messageToErrorObject:CAPTURE_INTERNAL_ERR];
        jsString = [result toErrorCallbackString: callbackId];
    } 
    
    [self writeJavascript :jsString];
		
	

    
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker
{
    PGImagePicker* cameraPicker = (PGImagePicker*)picker;
	NSString* callbackId = cameraPicker.callbackId;
	
	[picker dismissModalViewControllerAnimated:YES];
	
    NSString* jsString = nil;
    PluginResult* result = nil;
    result = [PluginResult resultWithStatus: PGCommandStatus_OK messageToErrorObject:CAPTURE_NO_MEDIA_FILES];
    jsString = [result toErrorCallbackString: callbackId];


    [self writeJavascript :jsString];
 
}

- (void) dealloc
{
    if (pickerController) {
        [pickerController release];
    }
    [super dealloc];
}

@end

@implementation AudioRecorderViewController
@synthesize errorCode, callbackId, duration, captureCommand, doneButton, recordingView, recordButton, recordImage, stopRecordImage, timerLabel, avRecorder, avSession, resultString, timer;

- (BOOL) isIPad 
{
#ifdef UI_USER_INTERFACE_IDIOM
    return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
#else
    return NO;
#endif
}

- (NSString*) resolveImageResource:(NSString*)resource
{
	NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
	BOOL isLessThaniOS4 = ([systemVersion compare:@"4.0" options:NSNumericSearch] == NSOrderedAscending);
	
	// the iPad image (nor retina) differentiation code was not in 3.x, and we have to explicitly set the path
	if (isLessThaniOS4)
	{
		if ([self isIPad]) {
			return [NSString stringWithFormat:@"%@~ipad.png", resource];
		} else {
			return [NSString stringWithFormat:@"%@.png", resource];
		}
	}
	
	return resource;
}

- (id) initWithCommand:  (Capture*) theCommand duration: (NSNumber*) theDuration callbackId: (NSString*) theCallbackId 
{
    if ((self = [super init])) {
        
        self.captureCommand = theCommand;
        self.duration = theDuration;
        self.callbackId = theCallbackId;
        self.errorCode = CAPTURE_NO_MEDIA_FILES;
        
		return self;
	}
	
	return nil;
}
- (void)loadView
{
    // create view and display
    CGRect viewRect = [[UIScreen mainScreen] applicationFrame];
	UIView *tmp = [[UIView alloc] initWithFrame:viewRect];
    [tmp setIsAccessibilityElement:NO];

    /*tmp.autoresizesSubviews = YES;
    int reSizeMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    tmp.autoresizingMask = reSizeMask;*/
    

    // make backgrounds
    
    UIImage* microphone = [UIImage imageNamed:[self resolveImageResource:@"Capture.bundle/microphone"]];
    UIView* microphoneView = [[[UIView alloc] initWithFrame: CGRectMake(0,0,viewRect.size.width, microphone.size.height)] autorelease];
    [microphoneView setBackgroundColor:[UIColor colorWithPatternImage:microphone]];
    [microphoneView setIsAccessibilityElement:NO];
    [tmp addSubview:microphoneView];

    // add bottom bar view
    UIImage* grayBkg = [UIImage imageNamed: [self resolveImageResource:@"Capture.bundle/controls_bg"]];
    UIView* controls = [[[UIView alloc] initWithFrame:CGRectMake(0, microphone.size.height, viewRect.size.width,grayBkg.size.height )] autorelease];
    [controls setBackgroundColor:[UIColor colorWithPatternImage: grayBkg]];
    [controls setIsAccessibilityElement:NO];
    [tmp addSubview:controls];
   
    /*recordButton = [[UIButton alloc  ] initWithFrame: CGRectMake(viewRect.size.width/4, viewRect.size.height/4, viewRect.size.width/2,viewRect.size.height/2)];
    recordButton.autoresizingMask = reSizeMask;
    //UIButton* recordButton = [UIButton buttonWithType: UIButtonTypeRoundedRect];
    //recordButton.frame = CGRectMake(viewRect.size.width/4, viewRect.size.height/4, viewRect.size.width/2,viewRect.size.height/2);
    */
    // make red recording background view
    UIImage* recordingBkg = [UIImage imageNamed: [self resolveImageResource:@"Capture.bundle/recording_bg"]];
    UIColor *background = [UIColor colorWithPatternImage:recordingBkg];
    self.recordingView = [[UIView alloc] initWithFrame: CGRectMake(0, 0, viewRect.size.width, recordingBkg.size.height)];
    [self.recordingView setBackgroundColor:background];
    [self.recordingView setHidden:YES];
    [self.recordingView setIsAccessibilityElement:NO];
    [tmp addSubview:self.recordingView];
    
    // add label
    self.timerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, viewRect.size.width,recordingBkg.size.height)];
    //timerLabel.autoresizingMask = reSizeMask;
    [self.timerLabel setBackgroundColor:[UIColor clearColor]];
    [self.timerLabel setTextColor:[UIColor whiteColor]];
    [self.timerLabel setTextAlignment: UITextAlignmentCenter];
    [self.timerLabel setText:@"0:00"];
    [self.timerLabel setIsAccessibilityElement:YES];
    self.timerLabel.accessibilityTraits |=  UIAccessibilityTraitUpdatesFrequently;
    self.timerLabel.accessibilityTraits &= ~UIAccessibilityTraitStaticText;
    [tmp addSubview:self.timerLabel];
    
    

    
    
    // Add record button
    
    self.recordImage = [UIImage imageNamed: [self resolveImageResource:@"Capture.bundle/record_button"]];
    self.stopRecordImage = [UIImage imageNamed: [self resolveImageResource:@"Capture.bundle/stop_button"]];
	self.recordButton.accessibilityTraits |= [self accessibilityTraits];
    self.recordButton = [[UIButton alloc  ] initWithFrame: CGRectMake((viewRect.size.width - recordImage.size.width)/2 , (microphone.size.height + (grayBkg.size.height - recordImage.size.height)/2), recordImage.size.width, recordImage.size.height)];
    [self.recordButton setIsAccessibilityElement:YES];
    [self.recordButton setAccessibilityLabel:  @"toggle recording start"];
    [self.recordButton setImage: recordImage forState:UIControlStateNormal];
    [self.recordButton addTarget: self action:@selector(processButton:) forControlEvents:UIControlEventTouchUpInside];
    [tmp addSubview:recordButton];
    
    // make and add done button to navigation bar
    self.doneButton = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissAudioView:)];
	[self.doneButton setStyle:UIBarButtonSystemItemDone];
    [self.doneButton setIsAccessibilityElement:YES];
	self.navigationItem.rightBarButtonItem = self.doneButton;
    
	[self setView:tmp];
    [tmp release];
	
}
- (void)viewDidLoad 
{	
    
    [super viewDidLoad];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
    NSError* error = nil;
    // create audio session
    self.avSession = [AVAudioSession sharedInstance];
    [self.avSession setCategory:AVAudioSessionCategoryRecord error:&error];
    if (error) {
        // return error if can't create recording audio session
        NSLog(@"error creating audio session: %@", [[error userInfo] description]);
        self.errorCode = CAPTURE_INTERNAL_ERR;
        [self dismissAudioView: nil];
    }
    
    // create file to record to in temporary dir
    
    NSString* docsPath = [NSTemporaryDirectory() stringByStandardizingPath];  // use file system temporary directory
    NSError* err = nil;
    NSFileManager* fileMgr = [[NSFileManager alloc] init]; 
    
    // generate unique file name
    NSString* filePath;
    int i=1;
    do {
        filePath = [NSString stringWithFormat:@"%@/audio_%03d.wav", docsPath, i++];
    } while([fileMgr fileExistsAtPath: filePath]);
    
    NSURL* fileURL = [NSURL fileURLWithPath:filePath isDirectory:NO];
    [fileMgr release];
    
    // create AVAudioPlayer
    self.avRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:nil error:&err];
    if (err) {
		NSLog(@"Failed to initialize AVAudioRecorder: %@\n", [err localizedDescription]);
		self.avRecorder = nil;
        // return error
        self.errorCode = CAPTURE_INTERNAL_ERR;
        [self dismissAudioView: nil];

	} else {
		self.avRecorder.delegate = self;
        [self.avRecorder prepareToRecord];
        self.recordButton.enabled = YES;
        self.doneButton.enabled = YES;
	}
    
}

- (void)viewDidUnload
{
	[self setView:nil];
    [self.captureCommand setInUse: NO];
}
- (void) processButton:(id)sender
{
    if (self.avRecorder.recording) {
        // stop recording
        [self stopRecordingCleanup];
        [self.avRecorder stop];
        
    } else {
        // begin recording
        [self.recordButton setImage: stopRecordImage forState:UIControlStateNormal];
        self.recordButton.accessibilityLabel = @"toggle recording";
        self.recordButton.accessibilityTraits &= ~[self accessibilityTraits];
        [self.recordingView setHidden:NO];
        NSError* error = nil;
        [self.avSession  setActive: YES error: &error];
        if(error) {
            // can't continue without active audio session
            self.errorCode = CAPTURE_INTERNAL_ERR;
            [self dismissAudioView: nil];
        } else {
            if(self.duration) {
                [self.avRecorder recordForDuration: [duration doubleValue]];
            } else {
                [self.avRecorder record];
            }
            [self.timerLabel setText:@"0.00"];
            self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5f target: self selector:@selector(updateTime) userInfo:nil repeats:YES ];
            self.doneButton.enabled = NO;
        }
    }
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}
/*
 * helper method to clean up when stop recording
 */
- (void) stopRecordingCleanup
{
    [self.recordButton setImage: recordImage forState:UIControlStateNormal];
    self.recordButton.accessibilityTraits |= [self accessibilityTraits];
    self.recordButton.accessibilityLabel = @"toggle recording";  // labels need to be internationalized!!
    [self.recordingView setHidden:YES];
    self.doneButton.enabled = YES;
}
- (void) dismissAudioView: (id) sender
{
    // called when done button pressed or when error condition to do cleanup and remove view
    [self.captureCommand.appViewController.modalViewController dismissModalViewControllerAnimated:YES];
    if (!self.resultString) {
        // return error
        PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject:self.errorCode];
        self.resultString = [result toErrorCallbackString:callbackId];
    }
    
    [self.avRecorder release];
    self.avRecorder = nil;
    [self.avSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [self.avSession  setActive: NO error: nil];
    [self.captureCommand setInUse:NO];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
    // return result
    [self.captureCommand writeJavascript: resultString ];
}
- (void) updateTime
{
    // update the label with the ellapsed time
    [self.timerLabel setText:[self formatTime: self.avRecorder.currentTime]];
    
}
- (NSString *) formatTime: (int) interval 
{
    // is this format universal?
	int secs = interval % 60;
	int min = interval / 60;
	if (interval < 60){
        return [NSString stringWithFormat:@"0:%02d", interval];
    } else {
        return	[NSString stringWithFormat:@"%d:%02d", min, secs];
    }
}
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder*)recorder successfully:(BOOL)flag
{
    // may be called when timed audio finishes - need to stop time and reset buttons
    [self.timer invalidate];
    [self stopRecordingCleanup];
    // deactivate session so sounds can come through
    [self.avSession  setActive: NO error: nil];
    
    // generate success result
    if (flag) {
        NSString* filePath = [avRecorder.url path];
        //NSLog(@"filePath: %@", filePath);
        NSDictionary* fileDict = [captureCommand getMediaDictionaryFromPath:filePath ofType: @"audio/wav"];
        NSArray* fileArray = [NSArray arrayWithObject:[fileDict JSONRepresentation]];
        
        PluginResult* result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsArray: fileArray cast:@"navigator.device.capture._castMediaFile"];
        self.resultString = [result toSuccessCallbackString:callbackId];
    } else {
        PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject:CAPTURE_INTERNAL_ERR];
        self.resultString = [result toErrorCallbackString:callbackId];
    }
}
- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error
{
    [self.timer invalidate];
    [self stopRecordingCleanup];
    [self.avRecorder stop];
    
    NSLog(@"error recording audio");
    PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageToErrorObject:CAPTURE_INTERNAL_ERR];
    self.resultString = [result toErrorCallbackString:callbackId];
    [self dismissAudioView: nil];
}

- (void) dealloc
{
    self.callbackId = nil;
    self.duration = nil;
    self.captureCommand = nil;
    self.doneButton = nil;
    self.recordingView = nil;
    self.recordButton = nil;
    self.recordImage = nil;
    self.stopRecordImage =nil;
    self.timerLabel = nil;
    self.avRecorder = nil;
    self.avSession = nil;
    self.resultString = nil;
    self.timer = nil;
    
    [super dealloc];
}
@end