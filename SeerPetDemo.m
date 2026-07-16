#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

static NSArray<NSString *> *Actions(void) { return @[@"attack", @"sa", @"cp", @"hited"]; }
static NSArray<NSNumber *> *PetSizes(void) { return @[@0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @1.75]; }
static NSDictionary<NSString *, NSString *> *DefaultActionNames(void) {
    return @{@"attack": @"普通攻击", @"sa": @"特殊攻击 (sa)",
             @"cp": @"属性攻击 (cp)", @"hited": @"受击"};
}
static const CGFloat BaseWindowSize = 480.0;
static const CGFloat IdleDisplaySize = 448.0;
static const CGFloat ActionPadding = 8.0;
static const CGFloat CropPadding = 8.0;
static const CGFloat DefaultIdleFPS = 12.0;
static const CGFloat MovementFPS = 25.0;
static const CGFloat MovementSpeed = 60.0;
static const CGFloat RandomAttackInterval = 8.0;
static const CGFloat MaxRasterSide = IdleDisplaySize * 2.0;
static const CGFloat MaxActionRasterSide = 4096.0;
static void SetError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"SeerPet" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}
static NSSize SourcePixelSizeAtURL(NSURL *url) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return NSZeroSize;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return NSMakeSize([properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue],
                      [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue]);
}
static NSRect AppKitRectFromTopOriginRect(NSRect rect, CGFloat imageHeight) {
    return NSMakeRect(rect.origin.x, imageHeight - NSMaxY(rect), rect.size.width, rect.size.height);
}
static BOOL DownsamplePNGAtURL(NSURL *url, CGFloat scale) {
    if (scale >= 1.0) return YES;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return NO;
    NSSize size = SourcePixelSizeAtURL(url);
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(ceil(MAX(size.width, size.height) * scale)),
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES
    });
    CFRelease(source);
    if (!image) return NO;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    if (destination) {
        CGImageDestinationAddImage(destination, image, NULL);
        BOOL finalized = CGImageDestinationFinalize(destination);
        CFRelease(destination);
        CGImageRelease(image);
        return finalized && [data writeToURL:url options:NSDataWritingAtomic error:nil];
    }
    CGImageRelease(image);
    return NO;
}
static BOOL NormalizeFramesAtURL(NSURL *framesURL, NSDictionary<NSString *, NSNumber *> *baseScales,
                                 void (^progress)(double)) {
    NSArray<NSURL *> *directories = [NSFileManager.defaultManager contentsOfDirectoryAtURL:framesURL
        includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableDictionary<NSString *, NSNumber *> *scales = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *work = [NSMutableArray array];
    for (NSURL *directory in directories) {
        NSArray<NSURL *> *pngs = [[NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
                return [url.pathExtension.lowercaseString isEqualToString:@"png"];
            }]];
        if (pngs.count == 0) continue;
        CGFloat maxSide = 0;
        for (NSURL *url in pngs) {
            NSSize size = SourcePixelSizeAtURL(url);
            maxSide = MAX(maxSide, MAX(size.width, size.height));
        }
        CGFloat targetMaxSide = [Actions() containsObject:directory.lastPathComponent] ?
            MaxActionRasterSide : MaxRasterSide;
        CGFloat scale = maxSide > targetMaxSide ? targetMaxSide / maxSide : 1.0;
        scales[directory.lastPathComponent] =
            @([baseScales[directory.lastPathComponent] ?: @1.0 doubleValue] * scale);
        for (NSURL *url in pngs) [work addObject:@{@"url": url, @"scale": @(scale)}];
    }
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = MIN(6, MAX(2, NSProcessInfo.processInfo.activeProcessorCount / 2));
    __block BOOL success = YES;
    __block NSUInteger completed = 0;
    NSLock *lock = [NSLock new];
    for (NSDictionary *item in work) [queue addOperationWithBlock:^{
        BOOL converted = DownsamplePNGAtURL(item[@"url"], [item[@"scale"] doubleValue]);
        [lock lock];
        if (!converted) success = NO;
        completed++;
        double fraction = work.count ? (double)completed / work.count : 1.0;
        [lock unlock];
        if (progress) progress(fraction);
    }];
    [queue waitUntilAllOperationsAreFinished];
    return success && [scales writeToURL:[framesURL URLByAppendingPathComponent:@".raster-scales.plist"]
                              atomically:YES];
}

@interface PetView : NSView <NSMenuDelegate>
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<NSImage *> *> *actionFrames;
@property(nonatomic, strong) NSArray<NSImage *> *idleFrames;
@property(nonatomic, strong) NSArray<NSImage *> *walkLeftFrames;
@property(nonatomic, strong) NSArray<NSImage *> *walkRightFrames;
@property(nonatomic, strong) NSArray<NSImage *> *currentFrames;
@property(nonatomic, strong) NSImage *currentImage;
@property(nonatomic, strong) NSImage *idleImage;
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<NSURL *> *> *actionURLs;
@property(nonatomic, strong) NSDictionary<NSString *, NSValue *> *actionCropBounds;
@property(nonatomic, strong) NSDictionary<NSString *, NSNumber *> *rasterScales;
@property(nonatomic, strong) NSDictionary<NSString *, NSNumber *> *sourceRasterScales;
@property(nonatomic) NSRect currentSourceRect;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSTimer *movementTimer;
@property(nonatomic, strong) NSTimer *randomAttackTimer;
@property(nonatomic, strong) NSDictionary<NSString *, NSValue *> *actionAnchors;
@property(nonatomic, strong) NSDictionary<NSString *, NSValue *> *frameBodySizes;
@property(nonatomic, copy) NSString *petID;
@property(nonatomic, copy) NSString *currentAction;
@property(nonatomic) CGFloat displayScale;
@property(nonatomic) CGFloat currentScale;
@property(nonatomic) CGFloat idleFPS;
@property(nonatomic) CGFloat idleRasterScale;
@property(nonatomic) CGFloat walkScale;
@property(nonatomic) CGFloat sizeMultiplier;
@property(nonatomic) CGFloat movementDirection;
@property(nonatomic) NSPoint restingCenter;
@property(nonatomic) NSRect restingFrame;
@property(nonatomic) NSPoint idleAnchor;
@property(nonatomic) NSPoint actionAnchorScreenPosition;
@property(nonatomic) NSUInteger frameIndex;
@property(nonatomic) NSPoint dragMouseStart;
@property(nonatomic) NSPoint dragLastMouse;
@property(nonatomic) BOOL dragged;
@property(nonatomic) BOOL playingAction;
@property(nonatomic) BOOL mouseHeld;
@property(nonatomic) BOOL freeMovementEnabled;
@property(nonatomic) BOOL randomAttackEnabled;
@property(nonatomic) BOOL movementPaused;
@property(nonatomic) BOOL facingLeft;
- (instancetype)initWithFrame:(NSRect)frame resourceURL:(NSURL *)resourceURL petID:(NSString *)petID;
- (BOOL)loadFramesFromURL:(NSURL *)resourceURL petID:(NSString *)petID;
- (void)play:(NSString *)action;
- (void)startIdlePlayback;
- (void)changeSize:(NSMenuItem *)sender;
- (void)movementTick:(NSTimer *)timer;
- (void)randomAttackTick:(NSTimer *)timer;
- (NSString *)actionNameForKey:(NSString *)action;
- (CGFloat)orientedAnchorX:(CGFloat)x imageWidth:(CGFloat)width;
- (BOOL)writeLayoutMetadataForFramesURL:(NSURL *)framesURL progress:(void (^)(double))progress;
@end

@implementation PetView

- (CGImageRef)newRasterImageAtURL:(NSURL *)url maxSide:(CGFloat)maxSide CF_RETURNS_RETAINED {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CGFloat width = [properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat height = [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    CGImageRef image;
    if (MAX(width, height) > maxSide) {
        image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
            (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxSide),
            (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES
        });
    } else {
        image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    }
    CFRelease(source);
    return image;
}

- (NSSize)pixelSizeAtURL:(NSURL *)url maxSide:(CGFloat)maxSide {
    CGImageRef image = [self newRasterImageAtURL:url maxSide:maxSide];
    if (!image) return NSZeroSize;
    NSSize size = NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image));
    CGImageRelease(image);
    return size;
}

- (NSValue *)visibleBoundsAtURL:(NSURL *)url maxSide:(CGFloat)maxSide {
    CGImageRef image = [self newRasterImageAtURL:url maxSide:maxSide];
    if (!image) return nil;

    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image), rowBytes = width * 4;
    unsigned char *pixels = calloc(height, rowBytes);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, rowBytes, colorSpace,
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) { free(pixels); CGImageRelease(image); return nil; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    size_t minX = width, minY = height, maxX = 0, maxY = 0;
    BOOL visible = NO;
    for (size_t y = 0; y < height; y++) for (size_t x = 0; x < width; x++) {
        if (pixels[y * rowBytes + x * 4 + 3] != 0) {
            visible = YES;
            minX = MIN(minX, x); minY = MIN(minY, y);
            maxX = MAX(maxX, x); maxY = MAX(maxY, y);
        }
    }
    CGContextRelease(context);
    free(pixels);
    CGImageRelease(image);
    if (!visible) return nil;
    return [NSValue valueWithRect:NSMakeRect(minX, minY,
                                              maxX - minX + 1, maxY - minY + 1)];
}

- (NSImage *)imageAtURL:(NSURL *)url croppedTo:(NSRect)bounds maxSide:(CGFloat)maxSide {
    CGImageRef image = [self newRasterImageAtURL:url maxSide:maxSide];
    if (!image) return nil;
    CGRect imageBounds = CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image));
    CGImageRef cropped = CGImageCreateWithImageInRect(image, CGRectIntersection(NSRectToCGRect(bounds), imageBounds));
    CGImageRelease(image);
    if (!cropped) return nil;
    NSImage *result = [[NSImage alloc] initWithCGImage:cropped
                                                 size:NSMakeSize(CGImageGetWidth(cropped), CGImageGetHeight(cropped))];
    result.cacheMode = NSImageCacheNever;
    CGImageRelease(cropped);
    return result;
}

- (instancetype)initWithFrame:(NSRect)frame resourceURL:(NSURL *)resourceURL petID:(NSString *)petID {
    if ((self = [super initWithFrame:frame])) {
        CGFloat savedSize = [NSUserDefaults.standardUserDefaults doubleForKey:@"petSize"];
        self.sizeMultiplier = [PetSizes() containsObject:@(savedSize)] ? savedSize : 1.0;
        self.freeMovementEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"freeMovement"];
        self.randomAttackEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"randomAttack"];
        self.movementDirection = 1.0;
        if (![self loadFramesFromURL:resourceURL petID:petID]) return nil;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        [self updateIdleBob];
        [self startIdlePlayback];
        [self updateMovementTimer];
        [self updateRandomAttackTimer];
    }
    return self;
}

- (BOOL)writeLayoutMetadataForFramesURL:(NSURL *)framesURL progress:(void (^)(double))progress {
    NSMutableArray<NSString *> *allActions = Actions().mutableCopy;
    [allActions addObjectsFromArray:@[@"idle", @"walk-left", @"walk-right"]];
    NSMutableDictionary *layout = [NSMutableDictionary dictionary];
    NSUInteger completed = 0;
    for (NSString *action in allActions) {
        NSURL *directory = [framesURL URLByAppendingPathComponent:action];
        NSArray<NSURL *> *urls = [[NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:nil options:0 error:nil]
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
                return [url.pathExtension.lowercaseString isEqualToString:@"png"];
            }]];
        urls = [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            return [a.lastPathComponent compare:b.lastPathComponent options:NSNumericSearch];
        }];
        if (urls.count == 0) { completed++; continue; }
        NSSize sourceSize = SourcePixelSizeAtURL(urls.firstObject);
        CGFloat loadScale = MAX(sourceSize.width, sourceSize.height) > MaxRasterSide ?
            MaxRasterSide / MAX(sourceSize.width, sourceSize.height) : 1.0;
        NSMutableArray<NSNumber *> *visible = [NSMutableArray arrayWithCapacity:urls.count];
        NSRect unionBounds = NSZeroRect, firstBounds = NSZeroRect;
        BOOL hasVisibleFrame = NO;
        for (NSUInteger i = 0; i < urls.count; i++) @autoreleasepool {
            NSValue *bounds = [self visibleBoundsAtURL:urls[i] maxSide:MaxRasterSide];
            [visible addObject:@(bounds != nil)];
            if (bounds) {
                if (!hasVisibleFrame) firstBounds = bounds.rectValue;
                unionBounds = hasVisibleFrame ? NSUnionRect(unionBounds, bounds.rectValue) : bounds.rectValue;
                hasVisibleFrame = YES;
            }
        }
        if (!hasVisibleFrame) return NO;
        NSSize canvasSize = [self pixelSizeAtURL:urls.firstObject maxSide:MaxRasterSide];
        unionBounds = NSIntersectionRect(NSInsetRect(unionBounds, -CropPadding, -CropPadding),
                                         NSMakeRect(0, 0, canvasSize.width, canvasSize.height));
        NSRect sourceCrop = NSMakeRect(unionBounds.origin.x / loadScale, unionBounds.origin.y / loadScale,
                                      unionBounds.size.width / loadScale, unionBounds.size.height / loadScale);
        NSRect sourceFirst = NSMakeRect(firstBounds.origin.x / loadScale, firstBounds.origin.y / loadScale,
                                       firstBounds.size.width / loadScale, firstBounds.size.height / loadScale);
        NSPoint sourceAnchor = NSMakePoint((NSMidX(firstBounds) - NSMinX(unionBounds)) / loadScale,
                                           (NSMaxY(firstBounds) - NSMinY(unionBounds)) / loadScale);
        layout[action] = @{@"crop": NSStringFromRect(sourceCrop), @"first": NSStringFromRect(sourceFirst),
                           @"anchor": NSStringFromPoint(sourceAnchor), @"visible": visible};
        completed++;
        if (progress) progress((double)completed / allActions.count);
    }
    return [layout writeToURL:[framesURL URLByAppendingPathComponent:@".layout-v1.plist"] atomically:YES];
}

- (BOOL)loadFramesFromURL:(NSURL *)resourceURL petID:(NSString *)petID {
    NSMutableDictionary<NSString *, NSArray<NSImage *> *> *loaded = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSValue *> *anchors = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSArray<NSURL *> *> *actionURLs = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSValue *> *actionCropBounds = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSValue *> *bodySizes = [NSMutableDictionary dictionary];
    NSImage *newIdleImage = nil;
    NSMutableArray<NSString *> *allActions = Actions().mutableCopy;
    [allActions addObjectsFromArray:@[@"idle", @"walk-left", @"walk-right"]];
    NSURL *framesURL = [resourceURL URLByAppendingPathComponent:@"frames"];
    NSDictionary<NSString *, NSNumber *> *rasterScales =
        [NSDictionary dictionaryWithContentsOfURL:[framesURL URLByAppendingPathComponent:@".raster-scales.plist"]] ?: @{};
    NSDictionary *layout = [NSDictionary dictionaryWithContentsOfURL:
        [framesURL URLByAppendingPathComponent:@".layout-v1.plist"]];
    NSMutableDictionary<NSString *, NSNumber *> *effectiveRasterScales = rasterScales.mutableCopy;
    for (NSString *action in allActions) {
        NSURL *directory = [framesURL URLByAppendingPathComponent:action];
        NSArray<NSURL *> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory
                                                              includingPropertiesForKeys:nil options:0 error:nil];
        urls = [[urls filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.pathExtension.lowercaseString isEqualToString:@"png"];
        }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            return [a.lastPathComponent compare:b.lastPathComponent options:NSNumericSearch];
        }];
        if (urls.count == 0) {
            if ([action isEqualToString:@"idle"] || [action hasPrefix:@"walk-"]) continue;
            return NO;
        }
        CGFloat loadMaxSide = MaxRasterSide;
        NSSize sourceSize = SourcePixelSizeAtURL(urls.firstObject);
        CGFloat loadScale = MAX(sourceSize.width, sourceSize.height) > loadMaxSide ?
            loadMaxSide / MAX(sourceSize.width, sourceSize.height) : 1.0;
        effectiveRasterScales[action] = @([rasterScales[action] ?: @1.0 doubleValue] * loadScale);

        NSDictionary *savedLayout = layout[action];
        NSMutableArray *boundsByFrame = [NSMutableArray arrayWithCapacity:urls.count];
        NSRect unionBounds = savedLayout ? NSRectFromString(savedLayout[@"crop"]) : NSZeroRect;
        NSRect firstBounds = savedLayout ? NSRectFromString(savedLayout[@"first"]) : NSZeroRect;
        if (savedLayout) {
            unionBounds = NSMakeRect(unionBounds.origin.x * loadScale, unionBounds.origin.y * loadScale,
                                     unionBounds.size.width * loadScale, unionBounds.size.height * loadScale);
            firstBounds = NSMakeRect(firstBounds.origin.x * loadScale, firstBounds.origin.y * loadScale,
                                     firstBounds.size.width * loadScale, firstBounds.size.height * loadScale);
        }
        BOOL hasVisibleFrame = NO;
        if (savedLayout) {
            NSArray<NSNumber *> *visible = savedLayout[@"visible"];
            for (NSUInteger i = 0; i < urls.count; i++) {
                BOOL frameVisible = i < visible.count ? visible[i].boolValue : YES;
                [boundsByFrame addObject:frameVisible ? [NSValue valueWithRect:firstBounds] : NSNull.null];
            }
            hasVisibleFrame = YES;
        } else {
            // ponytail: one action gets one coordinate system; per-frame cropping causes zooming and drift.
            for (NSURL *url in urls) @autoreleasepool {
                NSValue *bounds = [self visibleBoundsAtURL:url maxSide:loadMaxSide];
                [boundsByFrame addObject:bounds ?: NSNull.null];
                if (bounds) {
                    if (!hasVisibleFrame) firstBounds = bounds.rectValue;
                    unionBounds = hasVisibleFrame ? NSUnionRect(unionBounds, bounds.rectValue) : bounds.rectValue;
                    hasVisibleFrame = YES;
                }
            }
            if (!hasVisibleFrame) return NO;
            NSSize canvasSize = [self pixelSizeAtURL:urls.firstObject maxSide:loadMaxSide];
            unionBounds = NSIntersectionRect(NSInsetRect(unionBounds, -CropPadding, -CropPadding),
                                             NSMakeRect(0, 0, canvasSize.width, canvasSize.height));
        }
        if ([Actions() containsObject:action]) {
            actionURLs[action] = urls;
            NSRect topOriginCrop = savedLayout ? NSRectFromString(savedLayout[@"crop"]) : NSMakeRect(
                    unionBounds.origin.x / loadScale, unionBounds.origin.y / loadScale,
                    unionBounds.size.width / loadScale, unionBounds.size.height / loadScale);
            actionCropBounds[action] = [NSValue valueWithRect:
                AppKitRectFromTopOriginRect(topOriginCrop, sourceSize.height)];
        }
        NSUInteger firstVisible = [boundsByFrame indexOfObjectPassingTest:^BOOL(id value, NSUInteger _, BOOL *__) {
            return value != NSNull.null;
        }];
        NSPoint anchor = savedLayout ? NSPointFromString(savedLayout[@"anchor"]) :
            NSMakePoint(NSMidX(firstBounds) - NSMinX(unionBounds),
                        NSMaxY(firstBounds) - NSMinY(unionBounds));
        if (!savedLayout && [Actions() containsObject:action])
            anchor = NSMakePoint(anchor.x / loadScale, anchor.y / loadScale);
        if (savedLayout && ![Actions() containsObject:action])
            anchor = NSMakePoint(anchor.x * loadScale, anchor.y * loadScale);
        anchors[action] = [NSValue valueWithPoint:anchor];
        bodySizes[action] = [NSValue valueWithSize:firstBounds.size];

        if ([Actions() containsObject:action]) {
            NSImage *placeholder = [[NSImage alloc] initWithSize:unionBounds.size];
            NSMutableArray<NSImage *> *placeholders = [NSMutableArray arrayWithCapacity:urls.count];
            for (NSUInteger i = 0; i < urls.count; i++) [placeholders addObject:placeholder];
            loaded[action] = placeholders;
            if ([action isEqualToString:@"sa"]) {
                newIdleImage = [self imageAtURL:urls[firstVisible] croppedTo:firstBounds maxSide:loadMaxSide];
            }
            continue;
        }
        NSMutableArray<NSImage *> *images = [NSMutableArray array];
        for (NSUInteger i = 0; i < urls.count; i++) @autoreleasepool {
            if (boundsByFrame[i] == NSNull.null) {
                if (images.lastObject) [images addObject:images.lastObject];
                continue;
            }
            NSImage *image = [self imageAtURL:urls[i] croppedTo:unionBounds maxSide:loadMaxSide];
            if (image) [images addObject:image];
        }
        if (images.count == 0) return NO;
        loaded[action] = images;
    }
    [self.timer invalidate];
    self.timer = nil;
    self.currentFrames = nil;
    self.actionFrames = loaded;
    self.actionAnchors = anchors;
    self.frameBodySizes = bodySizes;
    self.actionURLs = actionURLs;
    self.actionCropBounds = actionCropBounds;
    self.rasterScales = effectiveRasterScales;
    self.sourceRasterScales = rasterScales;
    self.petID = petID;
    self.idleFrames = loaded[@"idle"] ?: @[newIdleImage ?: loaded[@"sa"].firstObject];
    self.walkLeftFrames = loaded[@"walk-left"];
    self.walkRightFrames = loaded[@"walk-right"];
    self.idleImage = self.idleFrames.firstObject;
    self.idleRasterScale = [effectiveRasterScales[@"idle"] ?: effectiveRasterScales[@"sa"] ?: @1.0 doubleValue];
    NSURL *idleFPSURL = [[[resourceURL URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@"idle"]
                         URLByAppendingPathComponent:@"idle-fps.txt"];
    CGFloat configuredIdleFPS = [[NSString stringWithContentsOfURL:idleFPSURL encoding:NSUTF8StringEncoding error:nil]
                                 doubleValue];
    self.idleFPS = configuredIdleFPS > 0 ? configuredIdleFPS : DefaultIdleFPS;
    self.idleAnchor = anchors[@"idle"] ? anchors[@"idle"].pointValue :
        NSMakePoint(self.idleImage.size.width / 2.0, self.idleImage.size.height);
    self.displayScale = IdleDisplaySize * self.sizeMultiplier /
        MAX(self.idleImage.size.width, self.idleImage.size.height);
    NSSize idleBody = [bodySizes[@"idle"] ?: bodySizes[@"sa"] sizeValue];
    NSSize walkBody = [bodySizes[@"walk-right"] ?: bodySizes[@"walk-left"] sizeValue];
    self.walkScale = idleBody.height > 0 && walkBody.height > 0 ?
        self.displayScale * idleBody.height / walkBody.height : self.displayScale;
    self.currentScale = self.displayScale;
    self.currentImage = self.idleImage;
    if (self.window) {
        self.restingCenter = NSMakePoint(NSMidX(self.window.frame), NSMidY(self.window.frame));
        CGFloat side = BaseWindowSize * self.sizeMultiplier;
        [self.window setFrame:NSMakeRect(self.restingCenter.x - side / 2.0,
                                         self.restingCenter.y - side / 2.0, side, side) display:YES];
        self.restingFrame = self.window.frame;
        [self updateIdleBob];
        [self startIdlePlayback];
    }
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)updateIdleBob {
    [self.layer removeAnimationForKey:@"idleBob"];
    if (self.idleFrames.count > 1) return;
    CABasicAnimation *bob = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    bob.fromValue = @(-3); bob.toValue = @(3); bob.duration = 1.8;
    bob.autoreverses = YES; bob.repeatCount = HUGE_VALF;
    [self.layer addAnimation:bob forKey:@"idleBob"];
}

- (BOOL)isOpaque { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
    NSRect sourceRect = NSIsEmptyRect(self.currentSourceRect) ?
        NSMakeRect(0, 0, self.currentImage.size.width, self.currentImage.size.height) : self.currentSourceRect;
    NSSize imageSize = sourceRect.size;
    NSSize size = NSMakeSize(imageSize.width * self.currentScale, imageSize.height * self.currentScale);
    NSRect target = NSMakeRect(NSMidX(self.bounds) - size.width / 2.0, NSMidY(self.bounds) - size.height / 2.0,
                               size.width, size.height);
    [NSGraphicsContext saveGraphicsState];
    BOOL nativeWalkFrame = self.currentFrames == self.walkLeftFrames || self.currentFrames == self.walkRightFrames;
    if (self.facingLeft && !nativeWalkFrame) {
        NSAffineTransform *mirror = [NSAffineTransform transform];
        [mirror translateXBy:NSWidth(self.bounds) yBy:0]; [mirror scaleXBy:-1 yBy:1]; [mirror concat];
    }
    [self.currentImage drawInRect:target fromRect:sourceRect operation:NSCompositingOperationSourceOver
                         fraction:1.0 respectFlipped:YES hints:nil];
    [NSGraphicsContext restoreGraphicsState];
}

- (CGFloat)orientedAnchorX:(CGFloat)x imageWidth:(CGFloat)width {
    return self.facingLeft ? width - x : x;
}

- (void)resizeWindowForAction:(NSString *)action {
    NSSize imageSize = self.currentSourceRect.size;
    CGFloat actionRasterScale = [self.sourceRasterScales[action] ?: @1.0 doubleValue];
    self.currentScale = self.displayScale * self.idleRasterScale / actionRasterScale;
    NSSize drawn = NSMakeSize(imageSize.width * self.currentScale, imageSize.height * self.currentScale);
    CGFloat minimumSide = BaseWindowSize * self.sizeMultiplier;
    CGFloat padding = ActionPadding * self.sizeMultiplier;
    NSSize windowSize = NSMakeSize(MAX(minimumSide, ceil(drawn.width + padding * 2.0)),
                                   MAX(minimumSide, ceil(drawn.height + padding * 2.0)));
    NSPoint anchor = self.actionAnchors[action].pointValue;
    CGFloat anchorX = [self orientedAnchorX:anchor.x imageWidth:imageSize.width];
    NSPoint anchorInWindow = NSMakePoint((windowSize.width - drawn.width) / 2.0 + anchorX * self.currentScale,
                                         (windowSize.height - drawn.height) / 2.0 +
                                         (imageSize.height - anchor.y) * self.currentScale);
    NSPoint origin = NSMakePoint(self.restingCenter.x - anchorInWindow.x,
                                 self.restingCenter.y - anchorInWindow.y);
    [self.window setFrame:NSMakeRect(origin.x, origin.y, windowSize.width, windowSize.height) display:YES];
    self.actionAnchorScreenPosition = NSMakePoint(origin.x + anchorInWindow.x, origin.y + anchorInWindow.y);
}

- (void)restoreIdleWindow {
    self.currentScale = self.displayScale;
    [self.window setFrame:self.restingFrame display:YES];
}

- (void)play:(NSString *)action {
    [self.timer invalidate];
    if (!self.playingAction) {
        self.restingFrame = self.window.frame;
        NSSize drawn = NSMakeSize(self.idleImage.size.width * self.displayScale,
                                 self.idleImage.size.height * self.displayScale);
        CGFloat idleAnchorX = [self orientedAnchorX:self.idleAnchor.x imageWidth:self.idleImage.size.width];
        NSPoint anchorInWindow = NSMakePoint((self.restingFrame.size.width - drawn.width) / 2.0 +
                                             idleAnchorX * self.displayScale,
                                             (self.restingFrame.size.height - drawn.height) / 2.0 +
                                             (self.idleImage.size.height - self.idleAnchor.y) * self.displayScale);
        self.restingCenter = NSMakePoint(NSMinX(self.restingFrame) + anchorInWindow.x,
                                         NSMinY(self.restingFrame) + anchorInWindow.y);
    }
    self.playingAction = YES;
    self.currentAction = action;
    self.currentFrames = self.actionFrames[action];
    self.frameIndex = 0;
    NSURL *firstURL = self.actionURLs[action].firstObject;
    NSValue *cropBounds = self.actionCropBounds[action];
    NSImage *firstImage = firstURL ? [[NSImage alloc] initWithContentsOfURL:firstURL] : nil;
    firstImage.cacheMode = NSImageCacheNever;
    self.currentImage = firstImage ?: self.currentFrames.firstObject;
    self.currentSourceRect = firstImage && cropBounds ? cropBounds.rectValue : NSZeroRect;
    [self resizeWindowForAction:action];
    self.timer = [NSTimer timerWithTimeInterval:1.0 / 25.0 target:self selector:@selector(nextFrame:)
                                       userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self.timer fire];
}

- (void)startIdlePlayback {
    [self.timer invalidate];
    self.playingAction = NO;
    self.currentAction = nil;
    self.currentFrames = self.idleFrames;
    self.frameIndex = 0;
    self.currentScale = self.displayScale;
    self.currentImage = self.idleImage;
    self.currentSourceRect = NSZeroRect;
    if (self.idleFrames.count > 1) {
        self.timer = [NSTimer timerWithTimeInterval:1.0 / self.idleFPS target:self selector:@selector(nextFrame:)
                                           userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
        [self.timer fire];
    }
    [self setNeedsDisplay:YES];
}

- (void)nextFrame:(NSTimer *)timer {
    if (!self.playingAction) {
        if (self.idleFrames.count > 0) {
            self.currentImage = self.idleFrames[self.frameIndex % self.idleFrames.count];
            self.frameIndex = (self.frameIndex + 1) % self.idleFrames.count;
        }
        [self setNeedsDisplay:YES];
        return;
    }
    if (self.frameIndex >= self.currentFrames.count) {
        if (self.mouseHeld && [self.currentAction isEqualToString:@"hited"]) {
            self.frameIndex = 0;
        } else {
            [self.timer invalidate]; self.timer = nil;
            [self restoreIdleWindow];
            [self startIdlePlayback];
            [self setNeedsDisplay:YES];
            return;
        }
    }
    NSUInteger index = self.frameIndex++;
    NSArray<NSURL *> *urls = self.actionURLs[self.currentAction];
    NSURL *url = index < urls.count ? urls[index] : nil;
    NSValue *cropBounds = self.actionCropBounds[self.currentAction];
    NSImage *image = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    image.cacheMode = NSImageCacheNever;
    self.currentImage = image ?: self.currentFrames[index];
    self.currentSourceRect = image && cropBounds ? cropBounds.rectValue : NSZeroRect;
    [self setNeedsDisplay:YES];
}

- (void)setFacingLeftIfNeeded:(BOOL)facingLeft {
    if (self.facingLeft == facingLeft) return;
    self.facingLeft = facingLeft; [self setNeedsDisplay:YES];
}

- (void)updateMovementTimer {
    [self.movementTimer invalidate]; self.movementTimer = nil;
    if (!self.freeMovementEnabled) return;
    self.movementTimer = [NSTimer timerWithTimeInterval:1.0 / MovementFPS target:self
                                               selector:@selector(movementTick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.movementTimer forMode:NSRunLoopCommonModes];
}

- (void)movementTick:(NSTimer *)timer {
    if (!self.freeMovementEnabled || self.movementPaused || self.playingAction || self.mouseHeld || !self.window) return;
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    NSRect bounds = screen.visibleFrame, frame = self.window.frame;
    CGFloat nextX = NSMinX(frame) + self.movementDirection * MovementSpeed / MovementFPS;
    if (nextX <= NSMinX(bounds)) {
        nextX = NSMinX(bounds); self.movementDirection = 1.0;
    } else if (nextX + NSWidth(frame) >= NSMaxX(bounds)) {
        nextX = NSMaxX(bounds) - NSWidth(frame); self.movementDirection = -1.0;
    }
    [self setFacingLeftIfNeeded:self.movementDirection < 0];
    NSArray<NSImage *> *walkFrames = self.facingLeft ? self.walkLeftFrames : self.walkRightFrames;
    if (walkFrames.count > 0) {
        if (self.currentFrames != walkFrames) {
            [self.timer invalidate]; self.timer = nil;
            self.currentFrames = walkFrames; self.frameIndex = 0; self.currentScale = self.walkScale;
        }
        self.currentImage = walkFrames[self.frameIndex++ % walkFrames.count];
        [self setNeedsDisplay:YES];
    }
    [self.window setFrameOrigin:NSMakePoint(nextX, NSMinY(frame))];
    self.restingFrame = self.window.frame;
}

- (void)updateRandomAttackTimer {
    [self.randomAttackTimer invalidate]; self.randomAttackTimer = nil;
    if (!self.randomAttackEnabled) return;
    self.randomAttackTimer = [NSTimer timerWithTimeInterval:RandomAttackInterval target:self
                                                   selector:@selector(randomAttackTick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.randomAttackTimer forMode:NSRunLoopCommonModes];
}

- (void)randomAttackTick:(NSTimer *)timer {
    if (!self.randomAttackEnabled || self.movementPaused || self.mouseHeld || self.playingAction) return;
    [self play:Actions()[arc4random_uniform(3)]];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragMouseStart = NSEvent.mouseLocation; self.dragLastMouse = self.dragMouseStart; self.dragged = NO;
    self.mouseHeld = YES; [self play:@"hited"];
}
- (void)mouseDragged:(NSEvent *)event {
    NSPoint mouse = NSEvent.mouseLocation;
    CGFloat totalX = mouse.x - self.dragMouseStart.x, totalY = mouse.y - self.dragMouseStart.y;
    if (!self.dragged && hypot(totalX, totalY) <= 3.0) return;
    CGFloat dx = mouse.x - self.dragLastMouse.x, dy = mouse.y - self.dragLastMouse.y;
    NSPoint origin = self.window.frame.origin;
    [self.window setFrameOrigin:NSMakePoint(origin.x + dx, origin.y + dy)];
    if (self.playingAction) {
        self.restingFrame = NSOffsetRect(self.restingFrame, dx, dy);
        self.restingCenter = NSMakePoint(self.restingCenter.x + dx, self.restingCenter.y + dy);
    } else {
        self.restingFrame = self.window.frame;
    }
    self.dragged = YES; self.dragLastMouse = mouse;
}
- (void)mouseUp:(NSEvent *)event {
    self.mouseHeld = NO;
    if (self.playingAction) {
        [self.timer invalidate]; self.timer = nil;
        [self restoreIdleWindow]; [self startIdlePlayback];
    }
}
- (void)playAttack:(id)sender { [self play:@"attack"]; }
- (void)playSA:(id)sender { [self play:@"sa"]; }
- (void)playCP:(id)sender { [self play:@"cp"]; }
- (void)playHited:(id)sender { [self play:@"hited"]; }

- (NSString *)actionNamesDefaultsKey {
    return [NSString stringWithFormat:@"actionNames.%@", self.petID];
}

- (NSString *)actionNameForKey:(NSString *)action {
    NSString *custom = [NSUserDefaults.standardUserDefaults dictionaryForKey:self.actionNamesDefaultsKey][action];
    return custom.length > 0 ? custom : DefaultActionNames()[action];
}

- (void)customizeActionNames:(id)sender {
    self.movementPaused = YES;
    NSAlert *alert = [NSAlert new]; alert.messageText = [NSString stringWithFormat:@"%@ 号精灵动作名称", self.petID];
    alert.informativeText = @"名称只对当前精灵生效。";
    [alert addButtonWithTitle:@"保存"]; [alert addButtonWithTitle:@"取消"];
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 116)];
    NSMutableDictionary<NSString *, NSTextField *> *fields = [NSMutableDictionary dictionary];
    NSArray<NSString *> *labels = @[@"普通攻击", @"特殊攻击", @"属性攻击", @"受击"];
    for (NSUInteger i = 0; i < Actions().count; i++) {
        CGFloat y = 88.0 - i * 29.0;
        NSTextField *label = [NSTextField labelWithString:labels[i]]; label.frame = NSMakeRect(0, y + 2, 72, 22);
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(78, y, 242, 24)];
        field.stringValue = [self actionNameForKey:Actions()[i]];
        [form addSubview:label]; [form addSubview:field]; fields[Actions()[i]] = field;
    }
    alert.accessoryView = form;
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSMutableDictionary *names = [NSMutableDictionary dictionary];
        for (NSString *action in Actions()) {
            NSString *name = [fields[action].stringValue stringByTrimmingCharactersInSet:
                              NSCharacterSet.whitespaceAndNewlineCharacterSet];
            names[action] = name.length > 0 ? name : DefaultActionNames()[action];
        }
        [NSUserDefaults.standardUserDefaults setObject:names forKey:self.actionNamesDefaultsKey];
    }
    self.movementPaused = NO;
}

- (void)resetActionNames:(id)sender {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:self.actionNamesDefaultsKey];
}

- (void)toggleFreeMovement:(NSMenuItem *)sender {
    self.freeMovementEnabled = !self.freeMovementEnabled;
    [NSUserDefaults.standardUserDefaults setBool:self.freeMovementEnabled forKey:@"freeMovement"];
    if (!self.freeMovementEnabled) [self startIdlePlayback];
    [self updateMovementTimer];
}

- (void)toggleRandomAttack:(NSMenuItem *)sender {
    self.randomAttackEnabled = !self.randomAttackEnabled;
    [NSUserDefaults.standardUserDefaults setBool:self.randomAttackEnabled forKey:@"randomAttack"];
    [self updateRandomAttackTimer];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    self.movementPaused = YES;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:[NSString stringWithFormat:@"%@ 号精灵", self.petID]];
    menu.autoenablesItems = NO; menu.delegate = self;
    NSArray *items = @[
        @[[self actionNameForKey:@"attack"], NSStringFromSelector(@selector(playAttack:))],
        @[[self actionNameForKey:@"sa"], NSStringFromSelector(@selector(playSA:))],
        @[[self actionNameForKey:@"cp"], NSStringFromSelector(@selector(playCP:))],
        @[[self actionNameForKey:@"hited"], NSStringFromSelector(@selector(playHited:))]
    ];
    for (NSArray *item in items) {
        NSMenuItem *menuItem = [menu addItemWithTitle:item[0] action:NSSelectorFromString(item[1]) keyEquivalent:@""];
        menuItem.target = self;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *freeMovement = [menu addItemWithTitle:@"自由移动" action:@selector(toggleFreeMovement:) keyEquivalent:@""];
    freeMovement.target = self;
    freeMovement.state = self.freeMovementEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *randomAttack = [menu addItemWithTitle:@"每 8 秒随机攻击"
                                               action:@selector(toggleRandomAttack:) keyEquivalent:@""];
    randomAttack.target = self;
    randomAttack.state = self.randomAttackEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *sizeItem = [menu addItemWithTitle:@"调整大小" action:nil keyEquivalent:@""];
    NSMenu *sizeMenu = [[NSMenu alloc] initWithTitle:@"调整大小"];
    for (NSNumber *size in PetSizes()) {
        NSMenuItem *item = [sizeMenu addItemWithTitle:[NSString stringWithFormat:@"%g×", size.doubleValue]
                                               action:@selector(changeSize:) keyEquivalent:@""];
        item.target = self; item.representedObject = size;
        item.state = fabs(size.doubleValue - self.sizeMultiplier) < 0.001 ? NSControlStateValueOn : NSControlStateValueOff;
    }
    sizeItem.submenu = sizeMenu;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *customize = [menu addItemWithTitle:@"自定义动作名称…" action:@selector(customizeActionNames:) keyEquivalent:@""];
    customize.target = self;
    NSMenuItem *reset = [menu addItemWithTitle:@"重置动作名称" action:@selector(resetActionNames:) keyEquivalent:@""];
    reset.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *change = [menu addItemWithTitle:@"更换精灵…" action:@selector(changePet:) keyEquivalent:@""];
    change.target = NSApp.delegate;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [menu addItemWithTitle:@"退出桌宠" action:@selector(terminate:) keyEquivalent:@""];
    quit.target = NSApp;
    return menu;
}

- (void)menuDidClose:(NSMenu *)menu { self.movementPaused = NO; }

- (void)changeSize:(NSMenuItem *)sender {
    CGFloat newSize = [sender.representedObject doubleValue];
    if (![PetSizes() containsObject:@(newSize)] || fabs(newSize - self.sizeMultiplier) < 0.001) return;
    NSRect idleFrame = self.playingAction ? self.restingFrame : self.window.frame;
    NSSize oldDrawn = NSMakeSize(self.idleImage.size.width * self.displayScale,
                                 self.idleImage.size.height * self.displayScale);
    CGFloat oldAnchorX = [self orientedAnchorX:self.idleAnchor.x imageWidth:self.idleImage.size.width];
    NSPoint oldAnchor = NSMakePoint((idleFrame.size.width - oldDrawn.width) / 2.0 +
                                    oldAnchorX * self.displayScale,
                                    (idleFrame.size.height - oldDrawn.height) / 2.0 +
                                    (self.idleImage.size.height - self.idleAnchor.y) * self.displayScale);
    NSPoint anchorScreen = NSMakePoint(NSMinX(idleFrame) + oldAnchor.x, NSMinY(idleFrame) + oldAnchor.y);

    [self.timer invalidate]; self.timer = nil; self.mouseHeld = NO;
    self.sizeMultiplier = newSize;
    self.displayScale = IdleDisplaySize * newSize / MAX(self.idleImage.size.width, self.idleImage.size.height);
    NSSize idleBody = [self.frameBodySizes[@"idle"] ?: self.frameBodySizes[@"sa"] sizeValue];
    NSSize walkBody = [self.frameBodySizes[@"walk-right"] ?: self.frameBodySizes[@"walk-left"] sizeValue];
    self.walkScale = idleBody.height > 0 && walkBody.height > 0 ?
        self.displayScale * idleBody.height / walkBody.height : self.displayScale;
    CGFloat side = BaseWindowSize * newSize;
    NSSize drawn = NSMakeSize(self.idleImage.size.width * self.displayScale,
                              self.idleImage.size.height * self.displayScale);
    CGFloat newAnchorX = [self orientedAnchorX:self.idleAnchor.x imageWidth:self.idleImage.size.width];
    NSPoint anchor = NSMakePoint((side - drawn.width) / 2.0 + newAnchorX * self.displayScale,
                                 (side - drawn.height) / 2.0 +
                                 (self.idleImage.size.height - self.idleAnchor.y) * self.displayScale);
    self.restingFrame = NSMakeRect(anchorScreen.x - anchor.x, anchorScreen.y - anchor.y, side, side);
    self.restingCenter = anchorScreen;
    [self.window setFrame:self.restingFrame display:YES];
    [NSUserDefaults.standardUserDefaults setDouble:newSize forKey:@"petSize"];
    [self startIdlePlayback];
}
@end

@interface PetPanel : NSPanel
@end

@implementation PetPanel
// ponytail: desktop pets intentionally cross screen edges; AppKit's normal window clamp breaks dragging.
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen { return frameRect; }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) PetView *petView;
@property(nonatomic, strong) NSProgressIndicator *conversionProgress;
@property(nonatomic, strong) NSTextField *conversionStatus;
@property(nonatomic) BOOL converting;
@end

@implementation AppDelegate
- (void)runModalBlock:(dispatch_block_t)block {
    block();
}

- (void)performOnModalMainThread:(dispatch_block_t)block {
    if (NSThread.isMainThread) { block(); return; }
    [self performSelectorOnMainThread:@selector(runModalBlock:) withObject:[block copy]
                       waitUntilDone:NO modes:@[NSModalPanelRunLoopMode]];
}

- (void)reportConversionProgress:(double)value status:(NSString *)status {
    [self performOnModalMainThread:^{
        self.conversionProgress.doubleValue = value;
        if (status.length > 0) self.conversionStatus.stringValue = status;
    }];
}

- (NSURL *)supportURL {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"SeerPetDemo"];
}
- (NSURL *)cachedPetURL:(NSString *)petID {
    return [[[self supportURL] URLByAppendingPathComponent:@"pets"] URLByAppendingPathComponent:petID];
}

- (void)installIdleForPetID:(NSString *)petID intoPetURL:(NSURL *)petURL {
    NSURL *destination = [[petURL URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@"idle"];
    NSURL *marker = [destination URLByAppendingPathComponent:@".true-idle"];
    if ([NSFileManager.defaultManager fileExistsAtPath:destination.path] &&
        ![NSFileManager.defaultManager fileExistsAtPath:marker.path]) {
        NSArray<NSURL *> *oldFrames = [NSFileManager.defaultManager contentsOfDirectoryAtURL:destination
                                                                  includingPropertiesForKeys:nil options:0 error:nil];
        NSUInteger pngCount = [oldFrames filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.pathExtension.lowercaseString isEqualToString:@"png"];
        }]].count;
        // ponytail: v0.6 generated exactly 30 mixed-state frames from the pet wrapper; delete that bad cache once.
        if (pngCount == 30) [NSFileManager.defaultManager removeItemAtURL:destination error:nil];
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:destination.path]) return;
    NSURL *source = [[[self supportURL] URLByAppendingPathComponent:@"idle-packs"] URLByAppendingPathComponent:petID];
    if ([NSFileManager.defaultManager fileExistsAtPath:source.path]) {
        [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:nil];
        [NSData.data writeToURL:marker atomically:YES];
    }
}

- (BOOL)runFFDec:(NSArray<NSString *> *)arguments progress:(void (^)(double))progress {
    NSURL *resources = NSBundle.mainBundle.resourceURL;
    NSTask *task = [NSTask new];
    task.executableURL = [[resources URLByAppendingPathComponent:@"runtime/bin"] URLByAppendingPathComponent:@"java"];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-Xmx1024m", @"-jar",
        [[resources URLByAppendingPathComponent:@"ffdec"] URLByAppendingPathComponent:@"ffdec.jar"].path, nil];
    [args addObjectsFromArray:arguments];
    task.arguments = args;
    NSPipe *output = progress ? [NSPipe pipe] : nil;
    task.standardOutput = output ?: NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    @try {
        if (![task launchAndReturnError:nil]) return NO;
        if (output) {
            NSMutableData *pending = [NSMutableData data];
            while (YES) {
                NSData *data = output.fileHandleForReading.availableData;
                if (data.length == 0) break;
                [pending appendData:data];
                NSString *text = [[NSString alloc] initWithData:pending encoding:NSUTF8StringEncoding];
                NSRange lineBreak = [text rangeOfString:@"\n" options:NSBackwardsSearch];
                if (lineBreak.location == NSNotFound) continue;
                NSString *complete = [text substringToIndex:lineBreak.location];
                NSData *remainder = [[text substringFromIndex:lineBreak.location + 1]
                    dataUsingEncoding:NSUTF8StringEncoding];
                pending = remainder.mutableCopy;
                NSRegularExpression *regex = [NSRegularExpression
                    regularExpressionWithPattern:@"Exported frame ([0-9]+)/([0-9]+)" options:0 error:nil];
                NSTextCheckingResult *match = [regex matchesInString:complete options:0
                    range:NSMakeRange(0, complete.length)].lastObject;
                if (match.numberOfRanges == 3) {
                    double current = [[complete substringWithRange:[match rangeAtIndex:1]] doubleValue];
                    double total = [[complete substringWithRange:[match rangeAtIndex:2]] doubleValue];
                    if (total > 0) progress(current / total);
                }
            }
        }
        [task waitUntilExit];
        return task.terminationStatus == 0;
    } @catch (__unused NSException *exception) { return NO; }
}

- (BOOL)runFFDec:(NSArray<NSString *> *)arguments {
    return [self runFFDec:arguments progress:nil];
}

- (NSDictionary<NSString *, NSNumber *> *)idleInfoFromXMLURL:(NSURL *)xmlURL
                                                   actionIDs:(NSArray<NSNumber *> *)actionIDs {
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:xmlURL options:0 error:nil];
    if (!document || actionIDs.count < 3) return nil;
    NSArray<NSXMLNode *> *nodes = [document nodesForXPath:@"//item[@type='DefineSpriteTag']" error:nil];
    NSMutableDictionary<NSNumber *, NSXMLElement *> *sprites = [NSMutableDictionary dictionary];
    for (NSXMLNode *node in nodes) {
        if (node.kind != NSXMLElementKind) continue;
        NSXMLElement *element = (NSXMLElement *)node;
        NSInteger spriteID = [element attributeForName:@"spriteId"].stringValue.integerValue;
        if (spriteID > 0) sprites[@(spriteID)] = element;
    }

    NSMutableSet<NSNumber *> *common = nil;
    for (NSUInteger i = 0; i < 3; i++) {
        NSXMLElement *action = sprites[actionIDs[i]];
        if (!action) return nil;
        NSMutableSet<NSNumber *> *references = [NSMutableSet set];
        for (NSXMLNode *node in [action nodesForXPath:@".//item[@characterId]" error:nil]) {
            if (node.kind != NSXMLElementKind) continue;
            NSInteger characterID = [(NSXMLElement *)node attributeForName:@"characterId"].stringValue.integerValue;
            if (characterID > 0) [references addObject:@(characterID)];
        }
        if (!common) common = references.mutableCopy;
        else [common intersectSet:references];
    }

    NSInteger idleSpriteID = -1;
    for (NSNumber *candidate in common) {
        NSXMLElement *sprite = sprites[candidate];
        NSInteger frameCount = [sprite attributeForName:@"frameCount"].stringValue.integerValue;
        if (frameCount > 1 && candidate.integerValue > idleSpriteID) idleSpriteID = candidate.integerValue;
    }
    if (idleSpriteID < 0) return nil;
    CGFloat fps = [[document.rootElement attributeForName:@"frameRate"].stringValue doubleValue];
    return @{@"spriteID": @(idleSpriteID), @"fps": @(fps > 0 ? fps : 25.0)};
}

- (NSArray<NSNumber *> *)frameCountsFromXMLURL:(NSURL *)xmlURL actionIDs:(NSArray<NSNumber *> *)actionIDs {
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:xmlURL options:0 error:nil];
    if (!document) return @[];
    NSMutableArray<NSNumber *> *counts = [NSMutableArray arrayWithCapacity:actionIDs.count];
    for (NSNumber *actionID in actionIDs) {
        NSString *xpath = [NSString stringWithFormat:
            @"//item[@type='DefineSpriteTag' and @spriteId='%@']", actionID];
        NSXMLElement *sprite = (NSXMLElement *)[document nodesForXPath:xpath error:nil].firstObject;
        NSInteger frameCount = [[sprite attributeForName:@"frameCount"].stringValue integerValue];
        [counts addObject:@(frameCount)];
    }
    return counts;
}

- (NSDictionary<NSString *, NSNumber *> *)movementInfoFromXMLURL:(NSURL *)xmlURL
                                                         spriteID:(NSInteger)spriteID {
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:xmlURL options:0 error:nil];
    if (!document || spriteID <= 0) return nil;
    NSString *xpath = [NSString stringWithFormat:
        @"//item[@type='DefineSpriteTag' and @spriteId='%ld']", (long)spriteID];
    NSXMLElement *sprite = (NSXMLElement *)[document nodesForXPath:xpath error:nil].firstObject;
    NSXMLElement *subTags = [sprite elementsForName:@"subTags"].firstObject;
    if (!subTags) return nil;

    NSInteger frame = 1;
    NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
    for (NSXMLNode *node in subTags.children) {
        if (node.kind != NSXMLElementKind) continue;
        NSXMLElement *element = (NSXMLElement *)node;
        NSString *type = [element attributeForName:@"type"].stringValue;
        if ([type isEqualToString:@"FrameLabelTag"]) {
            NSString *name = [element attributeForName:@"name"].stringValue;
            if (name.length > 0) [labels addObject:@{@"name": name, @"start": @(frame)}];
        } else if ([type isEqualToString:@"ShowFrameTag"]) {
            frame++;
        }
    }

    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < labels.count; i++) {
        NSString *name = labels[i][@"name"];
        if (![name isEqualToString:@"left"] && ![name isEqualToString:@"right"]) continue;
        NSInteger start = [labels[i][@"start"] integerValue];
        NSInteger end = i + 1 < labels.count ? [labels[i + 1][@"start"] integerValue] - 1 : frame - 1;
        result[[name stringByAppendingString:@"Start"]] = @(start);
        result[[name stringByAppendingString:@"End"]] = @(end);
    }
    CGFloat fps = [[document.rootElement attributeForName:@"frameRate"].stringValue doubleValue];
    result[@"fps"] = @(fps > 0 ? fps : 25.0);
    return result[@"leftStart"] && result[@"rightStart"] ? result : nil;
}

- (void)installWalkFramesForPetID:(NSString *)petID
                    intoFramesURL:(NSURL *)framesURL
                     temporaryURL:(NSURL *)temporaryURL {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSInteger numericID = petID.integerValue;
    NSString *path = numericID > 500 ?
        [NSString stringWithFormat:@"groupFightResource/pet/%ld.swf", (long)numericID] :
        [NSString stringWithFormat:@"pet/swf/%ld.swf", (long)numericID];
    NSData *data = [NSData dataWithContentsOfURL:
        [NSURL URLWithString:[@"https://seer.61.com/resource/" stringByAppendingString:path]]];
    if (data.length < 4) return;

    NSURL *swf = [temporaryURL URLByAppendingPathComponent:@"movement.swf"];
    if (![data writeToURL:swf atomically:YES]) return;
    NSURL *symbols = [temporaryURL URLByAppendingPathComponent:@"movement-symbols"];
    [fm createDirectoryAtURL:symbols withIntermediateDirectories:YES attributes:nil error:nil];
    if (![self runFFDec:@[@"-export", @"symbolClass", symbols.path, swf.path]]) return;
    NSString *csv = [NSString stringWithContentsOfURL:[symbols URLByAppendingPathComponent:@"symbols.csv"]
                                              encoding:NSUTF8StringEncoding error:nil];
    NSInteger spriteID = -1;
    for (NSString *line in [csv componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (![line containsString:@"\"pet\""]) continue;
        spriteID = [[[line componentsSeparatedByString:@";"] firstObject] integerValue]; break;
    }
    if (spriteID <= 0) return;

    NSURL *xml = [temporaryURL URLByAppendingPathComponent:@"movement.xml"];
    if (![self runFFDec:@[@"-swf2xml", swf.path, xml.path]]) return;
    NSDictionary<NSString *, NSNumber *> *info = [self movementInfoFromXMLURL:xml spriteID:spriteID];
    if (!info) return;

    NSURL *exportURL = [temporaryURL URLByAppendingPathComponent:@"movement-export"];
    [fm createDirectoryAtURL:exportURL withIntermediateDirectories:YES attributes:nil error:nil];
    if (![self runFFDec:@[@"-selectid", @(spriteID).stringValue, @"-ignorebackground", @"-zoom", @"4",
                          @"-format", @"sprite:png", @"-export", @"sprite", exportURL.path, swf.path]]) return;
    NSString *prefix = [NSString stringWithFormat:@"DefineSprite_%ld", (long)spriteID];
    NSURL *source = [[fm contentsOfDirectoryAtURL:exportURL includingPropertiesForKeys:nil options:0 error:nil]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.lastPathComponent hasPrefix:prefix];
        }]].firstObject;
    if (!source) return;

    NSArray<NSURL *> *frames = [[fm contentsOfDirectoryAtURL:source includingPropertiesForKeys:nil options:0 error:nil]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.pathExtension.lowercaseString isEqualToString:@"png"];
        }]];
    for (NSString *direction in @[@"left", @"right"]) {
        NSInteger start = [info[[direction stringByAppendingString:@"Start"]] integerValue];
        NSInteger end = [info[[direction stringByAppendingString:@"End"]] integerValue];
        NSURL *destination = [framesURL URLByAppendingPathComponent:
            [@"walk-" stringByAppendingString:direction]];
        [fm createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSURL *frameURL in frames) {
            NSInteger frameNumber = frameURL.lastPathComponent.stringByDeletingPathExtension.integerValue;
            if (frameNumber >= start && frameNumber <= end) {
                [fm copyItemAtURL:frameURL toURL:[destination URLByAppendingPathComponent:
                                                  frameURL.lastPathComponent] error:nil];
            }
        }
        NSArray *copied = [fm contentsOfDirectoryAtURL:destination includingPropertiesForKeys:nil options:0 error:nil];
        if (copied.count == 0) [fm removeItemAtURL:destination error:nil];
    }
}

- (NSURL *)installPetID:(NSString *)petID error:(NSError **)error {
    [self reportConversionProgress:2 status:@"检查本地缓存…"];
    NSURL *cached = [self cachedPetURL:petID];
    [self installIdleForPetID:petID intoPetURL:cached];
    NSURL *idleScanMarker = [cached URLByAppendingPathComponent:@".idle-scan-v1"];
    NSURL *walkScanMarker = [cached URLByAppendingPathComponent:@".walk-scan-v2"];
    NSURL *rasterMarker = [cached URLByAppendingPathComponent:@".raster-v3"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[[cached URLByAppendingPathComponent:@"frames"] path]] &&
        [[NSFileManager defaultManager] fileExistsAtPath:idleScanMarker.path] &&
        [[NSFileManager defaultManager] fileExistsAtPath:walkScanMarker.path]) {
        if ([NSFileManager.defaultManager
             fileExistsAtPath:[[cached URLByAppendingPathComponent:@".raster-v1"] path]] ||
            [NSFileManager.defaultManager
             fileExistsAtPath:[[cached URLByAppendingPathComponent:@".raster-v2"] path]]) {
            [NSFileManager.defaultManager removeItemAtURL:cached error:nil];
        } else {
            if (![NSFileManager.defaultManager fileExistsAtPath:rasterMarker.path]) {
                [self reportConversionProgress:85 status:@"优化旧缓存的帧尺寸…"];
                if (!NormalizeFramesAtURL([cached URLByAppendingPathComponent:@"frames"], @{}, ^(double fraction) {
                    [self reportConversionProgress:85 + fraction * 12 status:@"优化旧缓存的帧尺寸…"];
                })) {
                    SetError(error, @"动作帧尺寸优化失败"); return nil;
                }
                [NSData.data writeToURL:rasterMarker atomically:YES];
            }
            NSURL *framesURL = [cached URLByAppendingPathComponent:@"frames"];
            if (![NSFileManager.defaultManager
                 fileExistsAtPath:[[framesURL URLByAppendingPathComponent:@".layout-v1.plist"] path]]) {
                [self reportConversionProgress:97 status:@"分析帧边界与动作位置…"];
                PetView *scanner = [[PetView alloc] initWithFrame:NSZeroRect];
                if (![scanner writeLayoutMetadataForFramesURL:framesURL progress:^(double fraction) {
                    [self reportConversionProgress:97 + fraction * 2 status:@"分析帧边界与动作位置…"];
                }]) {
                    SetError(error, @"动作位置分析失败"); return nil;
                }
            }
            [self reportConversionProgress:100 status:@"缓存准备完成"];
            return cached;
        }
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *temp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [fm createDirectoryAtURL:temp withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *swf = [temp URLByAppendingPathComponent:[petID stringByAppendingPathExtension:@"swf"]];
    NSURL *remote = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://seer.61.com/resource/fightResource/pet/swf/%@.swf", petID]];
    [self reportConversionProgress:5 status:@"下载官方战斗资源…"];
    NSData *data = [NSData dataWithContentsOfURL:remote options:0 error:error];
    if (data.length < 4 || ![data writeToURL:swf options:NSDataWritingAtomic error:error]) {
        [fm removeItemAtURL:temp error:nil];
        if (data.length < 4) SetError(error, @"没有找到这个编号的 SWF 资源");
        return nil;
    }

    NSURL *symbols = [temp URLByAppendingPathComponent:@"symbols"];
    [fm createDirectoryAtURL:symbols withIntermediateDirectories:YES attributes:nil error:nil];
    [self reportConversionProgress:12 status:@"读取精灵动作表…"];
    if (![self runFFDec:@[@"-export", @"symbolClass", symbols.path, swf.path]]) {
        SetError(error, @"无法读取这个 SWF 的动作表"); [fm removeItemAtURL:temp error:nil]; return nil;
    }
    NSString *csv = [NSString stringWithContentsOfURL:[symbols URLByAppendingPathComponent:@"symbols.csv"]
                                              encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
    __block NSInteger petSpriteID = NSIntegerMax;
    for (NSString *line in [csv componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange separator = [line rangeOfString:@";"];
        if (separator.location == NSNotFound) continue;
        NSInteger spriteID = [[line substringToIndex:separator.location] integerValue];
        if ([line containsString:@"\"pet\""]) petSpriteID = spriteID;
        else if (spriteID > 0) [ids addObject:@(spriteID)];
    }
    [ids filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSNumber *value, NSDictionary *_) {
        return value.integerValue < petSpriteID;
    }]];
    [ids sortUsingSelector:@selector(compare:)];
    if (ids.count < 4) {
        SetError(error, @"这个 SWF 不是兼容的四动作精灵格式"); [fm removeItemAtURL:temp error:nil]; return nil;
    }
    ids = [[ids subarrayWithRange:NSMakeRange(ids.count - 4, 4)] mutableCopy];
    NSMutableArray<NSString *> *idStrings = [NSMutableArray array];
    for (NSNumber *value in ids) [idStrings addObject:value.stringValue];

    NSURL *xml = [temp URLByAppendingPathComponent:@"structure.xml"];
    NSDictionary<NSString *, NSNumber *> *idleInfo = nil;
    NSArray<NSNumber *> *frameCounts = @[];
    [self reportConversionProgress:18 status:@"分析待机与动作结构…"];
    if ([self runFFDec:@[@"-swf2xml", swf.path, xml.path]]) {
        idleInfo = [self idleInfoFromXMLURL:xml actionIDs:[ids subarrayWithRange:NSMakeRange(0, 3)]];
        frameCounts = [self frameCountsFromXMLURL:xml actionIDs:ids];
    }
    NSMutableArray<NSString *> *exportIDStrings = idStrings.mutableCopy;
    if (idleInfo) [exportIDStrings addObject:idleInfo[@"spriteID"].stringValue];

    NSURL *exportURL = [temp URLByAppendingPathComponent:@"export"];
    [fm createDirectoryAtURL:exportURL withIntermediateDirectories:YES attributes:nil error:nil];
    // ponytail: export one sprite per JVM so complex pets cannot retain every action in one heap.
    NSInteger totalFrames = 0;
    for (NSNumber *count in frameCounts) totalFrames += count.integerValue;
    BOOL complexPet = totalFrames > 320;
    NSMutableDictionary<NSString *, NSNumber *> *exportScales = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < exportIDStrings.count; i++) {
        NSString *spriteID = exportIDStrings[i];
        NSString *name = i < Actions().count ? DefaultActionNames()[Actions()[i]] : @"待机动作";
        CGFloat zoom = 1.0;
        if (complexPet && i < 3) zoom = 0.5;
        NSString *action = i < Actions().count ? Actions()[i] : @"idle";
        exportScales[action] = @(zoom);
        double actionStart = 25 + 50.0 * i / exportIDStrings.count;
        double actionSpan = 50.0 / exportIDStrings.count;
        [self reportConversionProgress:actionStart
                                status:[NSString stringWithFormat:@"提取%@（%lu/%lu）…", name,
                                        (unsigned long)i + 1, (unsigned long)exportIDStrings.count]];
        if (![self runFFDec:@[@"-selectid", spriteID, @"-ignorebackground", @"-zoom",
                              [NSString stringWithFormat:@"%g", zoom], @"-format", @"sprite:png",
                              @"-export", @"sprite", exportURL.path, swf.path]
                       progress:^(double fraction) {
            [self reportConversionProgress:actionStart + actionSpan * fraction
                                    status:[NSString stringWithFormat:@"提取%@（%lu/%lu，%.0f%%）…", name,
                                            (unsigned long)i + 1, (unsigned long)exportIDStrings.count,
                                            fraction * 100]];
        }]) {
            SetError(error, @"动作帧提取失败"); [fm removeItemAtURL:temp error:nil]; return nil;
        }
    }

    NSURL *stagedPet = [temp URLByAppendingPathComponent:@"pet"];
    NSURL *stagedFrames = [stagedPet URLByAppendingPathComponent:@"frames"];
    [self reportConversionProgress:76 status:@"整理动作帧…"];
    [fm createDirectoryAtURL:stagedFrames withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray<NSURL *> *exported = [fm contentsOfDirectoryAtURL:exportURL includingPropertiesForKeys:nil options:0 error:nil];
    for (NSUInteger i = 0; i < 4; i++) {
        NSString *prefix = [NSString stringWithFormat:@"DefineSprite_%@_", idStrings[i]];
        NSURL *source = [exported filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.lastPathComponent hasPrefix:prefix];
        }]].firstObject;
        if (!source || ![fm copyItemAtURL:source toURL:[stagedFrames URLByAppendingPathComponent:Actions()[i]] error:error]) {
            SetError(error, @"动作目录不完整"); [fm removeItemAtURL:temp error:nil]; return nil;
        }
    }
    if (idleInfo) {
        NSString *prefix = [NSString stringWithFormat:@"DefineSprite_%@", idleInfo[@"spriteID"]];
        NSURL *source = [exported filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.lastPathComponent hasPrefix:prefix];
        }]].firstObject;
        NSURL *idleDestination = [stagedFrames URLByAppendingPathComponent:@"idle"];
        if (source && [fm copyItemAtURL:source toURL:idleDestination error:nil]) {
            [NSData.data writeToURL:[idleDestination URLByAppendingPathComponent:@".true-idle"] atomically:YES];
            NSString *fps = [NSString stringWithFormat:@"%g\n", idleInfo[@"fps"].doubleValue];
            [[fps dataUsingEncoding:NSUTF8StringEncoding]
                writeToURL:[idleDestination URLByAppendingPathComponent:@"idle-fps.txt"] atomically:YES];
        }
    }
    [self reportConversionProgress:80 status:@"提取左右移动动作…"];
    [self installWalkFramesForPetID:petID intoFramesURL:stagedFrames temporaryURL:temp];
    [self reportConversionProgress:85 status:@"优化帧尺寸和内存占用…"];
    if (!NormalizeFramesAtURL(stagedFrames, exportScales, ^(double fraction) {
        [self reportConversionProgress:85 + fraction * 12 status:@"优化帧尺寸和内存占用…"];
    })) {
        SetError(error, @"动作帧尺寸优化失败"); [fm removeItemAtURL:temp error:nil]; return nil;
    }
    [self reportConversionProgress:97 status:@"分析帧边界与动作位置…"];
    PetView *scanner = [[PetView alloc] initWithFrame:NSZeroRect];
    if (![scanner writeLayoutMetadataForFramesURL:stagedFrames progress:^(double fraction) {
        [self reportConversionProgress:97 + fraction * 2 status:@"分析帧边界与动作位置…"];
    }]) {
        SetError(error, @"动作位置分析失败"); [fm removeItemAtURL:temp error:nil]; return nil;
    }
    [NSData.data writeToURL:[stagedPet URLByAppendingPathComponent:@".idle-scan-v1"] atomically:YES];
    [NSData.data writeToURL:[stagedPet URLByAppendingPathComponent:@".walk-scan-v2"] atomically:YES];
    [NSData.data writeToURL:[stagedPet URLByAppendingPathComponent:@".raster-v3"] atomically:YES];
    [fm createDirectoryAtURL:cached.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [fm removeItemAtURL:cached error:nil];
    if (![fm moveItemAtURL:stagedPet toURL:cached error:error]) { [fm removeItemAtURL:temp error:nil]; return nil; }
    [self installIdleForPetID:petID intoPetURL:cached];
    [fm removeItemAtURL:temp error:nil];
    [self reportConversionProgress:100 status:@"精灵准备完成"];
    return cached;
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning; alert.messageText = @"更换精灵失败";
    alert.informativeText = message ?: @"未知错误"; [alert runModal];
}

- (void)changePet:(id)sender {
    if (self.converting) return;
    if (sender) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self changePet:nil]; });
        return;
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *input = [NSAlert new];
    input.messageText = @"更换赛尔号精灵";
    input.informativeText = @"输入精灵编号。首次使用该编号需要联网下载并转换。";
    [input addButtonWithTitle:@"更换"]; [input addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
    field.placeholderString = @"例如：1"; field.stringValue = self.petView.petID ?: @"1"; input.accessoryView = field;
    input.window.initialFirstResponder = field;
    [input.window makeKeyAndOrderFront:nil];
    [input.window makeFirstResponder:field];
    [field selectText:nil];
    BOOL testingInput = NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_INPUT"] != nil;
    NSTimer *focusTimer = [NSTimer timerWithTimeInterval:0 repeats:NO block:^(__unused NSTimer *timer) {
        BOOL focused = [input.window makeFirstResponder:field];
        [field selectText:nil];
        if (testingInput) exit(focused ? 0 : 12);
    }];
    [NSRunLoop.mainRunLoop addTimer:focusTimer forMode:NSModalPanelRunLoopMode];
    if ([input runModal] != NSAlertFirstButtonReturn) return;
    NSString *petID = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (petID.length == 0 || [petID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound || petID.integerValue <= 0) {
        [self showError:@"编号只能是大于 0 的整数"]; return;
    }

    self.converting = YES;
    __block NSURL *petURL = nil;
    __block NSError *conversionError = nil;
    NSView *progressView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 48)];
    self.conversionStatus = [NSTextField labelWithString:@"准备转换…"];
    self.conversionStatus.frame = NSMakeRect(0, 28, 320, 18);
    self.conversionProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 4, 320, 16)];
    self.conversionProgress.indeterminate = NO;
    self.conversionProgress.minValue = 0; self.conversionProgress.maxValue = 100;
    self.conversionProgress.doubleValue = 0;
    [progressView addSubview:self.conversionStatus];
    [progressView addSubview:self.conversionProgress];
    NSAlert *progress = [NSAlert new];
    progress.messageText = [NSString stringWithFormat:@"正在准备 %@ 号精灵…", petID];
    progress.informativeText = @"复杂精灵可能需要几分钟，转换期间会限制内存占用。";
    progress.accessoryView = progressView;
    [progress addButtonWithTitle:@"请稍候"].enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        petURL = [self installPetID:petID error:&conversionError];
        [self performOnModalMainThread:^{ [NSApp abortModal]; }];
    });
    [progress runModal];
    self.conversionProgress = nil; self.conversionStatus = nil;
    self.converting = NO;
    if (!petURL || ![self.petView loadFramesFromURL:petURL petID:petID]) {
        if (petURL) [NSFileManager.defaultManager removeItemAtURL:petURL error:nil];
        [self showError:conversionError.localizedDescription ?: @"提取出的动作帧无法播放"]; return;
    }
    [NSUserDefaults.standardUserDefaults setObject:petID forKey:@"petID"];
    [self.petView play:@"sa"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *petID = [NSUserDefaults.standardUserDefaults stringForKey:@"petID"] ?: @"1";
    NSURL *resourceURL = [self cachedPetURL:petID];
    [self installIdleForPetID:petID intoPetURL:resourceURL];
    BOOL hasCachedFrames = [NSFileManager.defaultManager
        fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@"frames"] path]];
    BOOL needsUpgrade = hasCachedFrames &&
        (![NSFileManager.defaultManager fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@".walk-scan-v2"] path]] ||
         ![NSFileManager.defaultManager fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@".raster-v3"] path]] ||
         ![NSFileManager.defaultManager fileExistsAtPath:
             [[[resourceURL URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@".layout-v1.plist"] path]]);
    if (needsUpgrade) {
        NSURL *upgraded = [self installPetID:petID error:nil];
        if (upgraded) resourceURL = upgraded;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@"frames"] path]]) {
        petID = @"1"; resourceURL = NSBundle.mainBundle.resourceURL;
    }
    NSSize size = NSMakeSize(BaseWindowSize, BaseWindowSize);
    self.petView = [[PetView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)
                                      resourceURL:resourceURL petID:petID];
    if (!self.petView && ![resourceURL isEqual:NSBundle.mainBundle.resourceURL]) {
        petID = @"1"; resourceURL = NSBundle.mainBundle.resourceURL;
        self.petView = [[PetView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)
                                          resourceURL:resourceURL petID:petID];
    }
    if (!self.petView) { [NSApp terminate:nil]; return; }
    CGFloat side = BaseWindowSize * self.petView.sizeMultiplier;
    size = NSMakeSize(side, side);
    [self.petView setFrameSize:size];
    self.panel = [[PetPanel alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                                             styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    self.panel.opaque = NO; self.panel.backgroundColor = NSColor.clearColor; self.panel.hasShadow = NO;
    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.hidesOnDeactivate = NO; self.panel.contentView = self.petView;
    NSPoint mouse = NSEvent.mouseLocation; NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(mouse, candidate.frame)) { screen = candidate; break; }
    NSRect visible = screen.visibleFrame;
    [self.panel setFrameOrigin:NSMakePoint(NSMidX(visible) - size.width / 2.0, NSMidY(visible) - size.height / 2.0)];
    [NSApp activateIgnoringOtherApps:YES]; [self.panel makeKeyAndOrderFront:nil];

    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_MODAL_CALLBACK"]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"测试模态回调";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [self performOnModalMainThread:^{ [NSApp abortModal]; }];
        });
        [alert runModal];
        exit(0);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_INPUT"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self changePet:NSMenuItem.new]; });
        return;
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_UNCONSTRAINED"]) {
        NSPoint target = NSMakePoint(NSMinX(screen.frame), NSMaxY(screen.frame) + 100.0);
        [self.panel setFrameOrigin:target];
        exit(NSEqualPoints(self.panel.frame.origin, target) ? 0 : 8);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_MOVEMENT"]) {
        [self.petView.movementTimer invalidate]; self.petView.movementTimer = nil;
        self.petView.freeMovementEnabled = YES; self.petView.movementPaused = NO;
        self.petView.playingAction = NO; self.petView.mouseHeld = NO;
        NSRect travel = screen.visibleFrame, frame = self.panel.frame;
        [self.panel setFrameOrigin:NSMakePoint(NSMidX(travel) - NSWidth(frame) / 2.0, NSMinY(frame))];
        CGFloat before = NSMinX(self.panel.frame); self.petView.movementDirection = -1.0;
        [self.petView movementTick:nil];
        BOOL movedLeft = NSMinX(self.panel.frame) < before && self.petView.facingLeft;
        BOOL usedLeftWalk = self.petView.walkLeftFrames.count > 1 &&
            self.petView.currentFrames == self.petView.walkLeftFrames;
        self.petView.freeMovementEnabled = NO; [self.petView startIdlePlayback];
        BOOL stoppedLeft = self.petView.facingLeft && self.petView.currentFrames == self.petView.idleFrames;
        self.petView.freeMovementEnabled = YES;
        [self.panel setFrameOrigin:NSMakePoint(NSMinX(travel), NSMinY(frame))];
        self.petView.movementDirection = -1.0; [self.petView movementTick:nil];
        BOOL bounced = self.petView.movementDirection > 0 && !self.petView.facingLeft;
        BOOL usedRightWalk = self.petView.walkRightFrames.count > 1 &&
            self.petView.currentFrames == self.petView.walkRightFrames;
        NSSize idleBody = [self.petView.frameBodySizes[@"idle"] ?: self.petView.frameBodySizes[@"sa"] sizeValue];
        NSSize walkBody = [self.petView.frameBodySizes[@"walk-right"] ?:
                           self.petView.frameBodySizes[@"walk-left"] sizeValue];
        BOOL sameWalkScale = idleBody.height <= 0 || walkBody.height <= 0 ||
            fabs(idleBody.height * self.petView.displayScale -
                 walkBody.height * self.petView.walkScale) < 1.0;
        self.petView.facingLeft = YES;
        BOOL mirrored = fabs([self.petView orientedAnchorX:10 imageWidth:100] - 90.0) < 0.01;
        [self.petView play:@"attack"];
        BOOL mirroredActionAligned = hypot(self.petView.actionAnchorScreenPosition.x - self.petView.restingCenter.x,
                                           self.petView.actionAnchorScreenPosition.y - self.petView.restingCenter.y) < 1.0;
        [self.petView.timer invalidate]; [self.petView restoreIdleWindow]; [self.petView startIdlePlayback];

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id oldA = [defaults objectForKey:@"actionNames.__testA"];
        id oldB = [defaults objectForKey:@"actionNames.__testB"];
        NSString *originalPetID = self.petView.petID;
        [defaults setObject:@{@"attack": @"测试动作"} forKey:@"actionNames.__testA"];
        [defaults removeObjectForKey:@"actionNames.__testB"];
        self.petView.petID = @"__testA"; BOOL customized = [[self.petView actionNameForKey:@"attack"] isEqualToString:@"测试动作"];
        [self.petView resetActionNames:nil];
        BOOL reset = [[self.petView actionNameForKey:@"attack"] isEqualToString:DefaultActionNames()[@"attack"]];
        self.petView.petID = @"__testB"; BOOL isolated = ![[self.petView actionNameForKey:@"attack"] isEqualToString:@"测试动作"];
        self.petView.petID = originalPetID;
        if (oldA) [defaults setObject:oldA forKey:@"actionNames.__testA"]; else [defaults removeObjectForKey:@"actionNames.__testA"];
        if (oldB) [defaults setObject:oldB forKey:@"actionNames.__testB"]; else [defaults removeObjectForKey:@"actionNames.__testB"];
        exit(movedLeft && usedLeftWalk && stoppedLeft && bounced && usedRightWalk && sameWalkScale && mirrored &&
             mirroredActionAligned && customized && reset && isolated ? 0 : 9);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_RANDOM_ATTACK"]) {
        [self.petView.randomAttackTimer invalidate]; self.petView.randomAttackTimer = nil;
        self.petView.randomAttackEnabled = YES; self.petView.movementPaused = NO;
        self.petView.mouseHeld = NO; self.petView.playingAction = NO;
        [self.petView randomAttackTick:nil];
        BOOL selectedAttack = self.petView.playingAction &&
            [[Actions() subarrayWithRange:NSMakeRange(0, 3)] containsObject:self.petView.currentAction];
        self.petView.randomAttackEnabled = NO; [self.petView updateRandomAttackTimer];
        exit(selectedAttack && !self.petView.randomAttackTimer ? 0 : 10);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_MOUSE"]) {
        NSEvent *testEvent = [NSEvent new];
        [self.petView mouseDown:testEvent];
        BOOL started = self.petView.mouseHeld && self.petView.playingAction &&
            [self.petView.currentAction isEqualToString:@"hited"];
        self.petView.frameIndex = self.petView.currentFrames.count;
        [self.petView nextFrame:nil];
        BOOL loopedCompletely = self.petView.frameIndex == 1 &&
            NSMaxX(self.petView.currentSourceRect) <= self.petView.currentImage.size.width &&
            NSMaxY(self.petView.currentSourceRect) <= self.petView.currentImage.size.height;
        for (NSURL *url in self.petView.actionURLs[@"hited"]) {
            NSValue *visibleValue = [self.petView visibleBoundsAtURL:url maxSide:CGFLOAT_MAX];
            NSRect visible = AppKitRectFromTopOriginRect(visibleValue.rectValue,
                                                         SourcePixelSizeAtURL(url).height);
            loopedCompletely = loopedCompletely &&
                NSContainsRect(self.petView.currentSourceRect, visible);
        }
        [self.petView mouseUp:testEvent];
        exit(started && loopedCompletely && !self.petView.mouseHeld && !self.petView.playingAction ? 0 : 7);
    }
    NSString *testPetID = NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_PET_ID"];
    if (testPetID) {
        NSError *error = nil; NSURL *url = [self installPetID:testPetID error:&error];
        BOOL loaded = url && [self.petView loadFramesFromURL:url petID:testPetID];
        BOOL movementLoaded = ![testPetID isEqualToString:@"1"] ||
            (self.petView.walkLeftFrames.count > 1 && self.petView.walkRightFrames.count > 1);
        exit(loaded && movementLoaded &&
             (![testPetID isEqualToString:@"1"] || self.petView.idleFrames.count > 1) ? 0 : 4);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_SCALE"]) {
        NSSize idleSize = self.panel.frame.size;
        [self.petView play:@"attack"];
        NSSize actionSize = self.panel.frame.size;
        NSSize canvas = self.petView.currentImage.size;
        BOOL complete = canvas.width * self.petView.currentScale <= actionSize.width &&
                        canvas.height * self.petView.currentScale <= actionSize.height &&
                        actionSize.width >= idleSize.width && actionSize.height >= idleSize.height;
        BOOL sameSourceScale = fabs(self.petView.currentScale *
                                    [self.petView.sourceRasterScales[@"attack"] doubleValue] -
                                    self.petView.displayScale * self.petView.idleRasterScale) < 0.001;
        BOOL aligned = hypot(self.petView.actionAnchorScreenPosition.x - self.petView.restingCenter.x,
                             self.petView.actionAnchorScreenPosition.y - self.petView.restingCenter.y) < 1.0;
        CGFloat originalSize = self.petView.sizeMultiplier;
        [self.petView.timer invalidate];
        [self.petView restoreIdleWindow];
        [self.petView startIdlePlayback];
        BOOL sizesValid = YES;
        for (NSNumber *value in PetSizes()) {
            NSMenuItem *item = [NSMenuItem new]; item.representedObject = value;
            [self.petView changeSize:item];
            sizesValid = sizesValid &&
                fabs(self.panel.frame.size.width - BaseWindowSize * value.doubleValue) < 1.0;
        }
        NSMenuItem *restore = [NSMenuItem new]; restore.representedObject = @(originalSize);
        [self.petView changeSize:restore];
        exit(complete && sameSourceScale && aligned && sizesValid ? 0 : 6);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_LAYOUT"]) {
        for (NSString *action in Actions()) {
            NSArray<NSImage *> *frames = self.petView.actionFrames[action];
            NSSize expected = frames.firstObject.size;
            for (NSImage *image in frames) if (!NSEqualSizes(image.size, expected)) exit(5);
        }
        exit(0);
    }
    NSString *testAction = NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_ACTION"];
    if (testAction) {
        NSUInteger count = self.petView.actionFrames[testAction].count; [self.petView play:testAction];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((count / 25.0 + 0.5) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CGFloat side = BaseWindowSize * self.petView.sizeMultiplier;
            BOOL restored = !self.petView.playingAction &&
                            NSEqualSizes(self.panel.frame.size, NSMakeSize(side, side));
            exit(restored ? 0 : 3);
        });
    }
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new]; application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular]; [application run];
    }
    return 0;
}
