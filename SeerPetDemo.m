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
static NSString * const PetInstancesKey = @"petInstances.v1";
static BOOL RunningTests(void) {
    for (NSString *key in NSProcessInfo.processInfo.environment)
        if ([key hasPrefix:@"SEER_PET_TEST_"]) return YES;
    return NO;
}
static NSImage *PetBagButtonImage(NSString *name, NSString *state) {
    NSURL *directory = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetBagButtons"];
    return [[NSImage alloc] initWithContentsOfURL:
        [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", name, state]]];
}
static NSImage *PetBagSlotImage(NSString *name) {
    NSURL *directory = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetBagSlots"];
    return [[NSImage alloc] initWithContentsOfURL:[directory URLByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.png", name]]];
}
static NSImage *PetBagInfoImage(NSString *name) {
    NSURL *directory = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetBagInfo"];
    return [[NSImage alloc] initWithContentsOfURL:[directory URLByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.png", name]]];
}
static NSAttributedString *PetBagFieldText(NSString *label, NSString *value) {
    NSDictionary *white = @{NSFontAttributeName: [NSFont systemFontOfSize:14],
                            NSForegroundColorAttributeName: NSColor.whiteColor};
    NSDictionary *yellow = @{NSFontAttributeName: [NSFont systemFontOfSize:14],
                             NSForegroundColorAttributeName: NSColor.yellowColor};
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:label attributes:white];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:yellow]];
    return text;
}
static NSString *NormalizedPetID(NSString *petID) {
    return [NSString stringWithFormat:@"%ld", (long)petID.integerValue];
}
static NSArray<NSNumber *> *PetBaseStats(NSString *petID) {
    static NSDictionary<NSString *, NSArray<NSNumber *> *> *allStats;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allStats = [NSDictionary dictionaryWithContentsOfURL:
            [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetStats.plist"]] ?: @{};
    });
    return allStats[NormalizedPetID(petID)];
}
static NSString *PetDefaultName(NSString *petID) {
    static NSDictionary<NSString *, NSString *> *allNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allNames = [NSDictionary dictionaryWithContentsOfURL:
            [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetNames.plist"]] ?: @{};
    });
    NSString *normalizedID = NormalizedPetID(petID);
    return allNames[normalizedID] ?: [NSString stringWithFormat:@"%@ 号精灵", normalizedID];
}
static NSArray *PetMetadata(NSString *petID) {
    static NSDictionary<NSString *, NSArray *> *allMetadata;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allMetadata = [NSDictionary dictionaryWithContentsOfURL:
            [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetMeta.plist"]] ?: @{};
    });
    return allMetadata[NormalizedPetID(petID)];
}
static NSArray *PetMoveInfo(NSNumber *skillID) {
    static NSDictionary<NSString *, NSArray *> *allMoves;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allMoves = [NSDictionary dictionaryWithContentsOfURL:
            [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetMoves.plist"]] ?: @{};
    });
    return allMoves[skillID.stringValue];
}
static NSString *PetActionForMoveInfo(NSArray *move) {
    NSInteger category = move.count > 3 ? [move[3] integerValue] : 1;
    return category == 2 ? @"sa" : (category == 4 ? @"cp" : @"attack");
}
static NSString *PetTypeName(NSNumber *typeID) {
    static NSDictionary<NSString *, NSString *> *allTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allTypes = [NSDictionary dictionaryWithContentsOfURL:
            [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetTypes.plist"]] ?: @{};
    });
    return allTypes[typeID.stringValue] ?: @"--";
}
static NSImage *PetTypeIconNamed(NSString *name) {
    NSURL *directory = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetTypeIcons"];
    NSURL *url = [directory URLByAppendingPathComponent:
        [name stringByAppendingPathExtension:@"png"]];
    return [[NSImage alloc] initWithContentsOfURL:url];
}
static NSImage *PetTypeIcon(NSNumber *typeID) { return PetTypeIconNamed(typeID.stringValue); }
static NSImage *PetGenderIcon(NSInteger gender) {
    NSURL *directory = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"PetGenderIcons"];
    NSURL *url = [directory URLByAppendingPathComponent:
        [[NSString stringWithFormat:@"%ld", (long)gender] stringByAppendingPathExtension:@"png"]];
    return [[NSImage alloc] initWithContentsOfURL:url];
}
static NSArray<NSNumber *> *PetDefaultSkillIDs(NSString *petID) {
    NSArray *metadata = PetMetadata(petID), *moves = metadata.count > 5 ? metadata[5] : @[];
    NSMutableArray *slots = [@[[NSNull null], [NSNull null], [NSNull null], [NSNull null]] mutableCopy];
    for (NSArray *move in moves) {
        NSInteger tag = move.count > 3 && [move[2] boolValue] ? [move[3] integerValue] : 0;
        if (tag >= 1 && tag <= 4) slots[tag - 1] = move[0];
    }
    for (NSArray *move in moves.reverseObjectEnumerator) {
        if ([slots containsObject:move[0]]) continue;
        NSUInteger empty = [slots indexOfObject:NSNull.null];
        if (empty == NSNotFound) break;
        slots[empty] = move[0];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:4];
    for (id skillID in slots) if ([skillID isKindOfClass:NSNumber.class]) [result addObject:skillID];
    return result;
}
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

@class PetView;
@protocol PetViewOwner <NSObject>
- (void)savePetInstances;
- (void)showPetManager:(id)sender;
- (void)changePet:(id)sender;
@end

@interface PetView : NSView <NSMenuDelegate>
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<NSImage *> *> *actionFrames;
@property(nonatomic, strong) NSArray<NSImage *> *idleFrames;
@property(nonatomic, strong) NSArray<NSImage *> *walkLeftFrames;
@property(nonatomic, strong) NSArray<NSImage *> *walkRightFrames;
@property(nonatomic, strong) NSArray<NSImage *> *currentFrames;
@property(nonatomic, strong) NSImage *currentImage;
@property(nonatomic, strong) NSImage *idleImage;
@property(nonatomic, strong) NSImage *bagImage;
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
@property(nonatomic, weak) id<PetViewOwner> owner;
@property(nonatomic, copy) NSString *instanceID;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, copy) NSString *petID;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *selectedSkillIDs;
@property(nonatomic, copy) NSString *currentAction;
@property(nonatomic) CGFloat displayScale;
@property(nonatomic) CGFloat currentScale;
@property(nonatomic) CGFloat idleFPS;
@property(nonatomic) CGFloat idleRasterScale;
@property(nonatomic) CGFloat walkScale;
@property(nonatomic) CGFloat sizeMultiplier;
@property(nonatomic) CGFloat movementDirection;
@property(nonatomic) NSTimeInterval createdAt;
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
@property(nonatomic) BOOL desktopVisible;
@property(nonatomic) BOOL movementPaused;
@property(nonatomic) BOOL facingLeft;
- (instancetype)initWithFrame:(NSRect)frame resourceURL:(NSURL *)resourceURL record:(NSDictionary *)record;
- (BOOL)loadFramesFromURL:(NSURL *)resourceURL petID:(NSString *)petID;
- (void)play:(NSString *)action;
- (void)startIdlePlayback;
- (void)changeSize:(NSMenuItem *)sender;
- (void)movementTick:(NSTimer *)timer;
- (void)randomAttackTick:(NSTimer *)timer;
- (void)resetDefaultSkills;
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

- (instancetype)initWithFrame:(NSRect)frame resourceURL:(NSURL *)resourceURL record:(NSDictionary *)record {
    if ((self = [super initWithFrame:frame])) {
        NSString *petID = [record[@"petID"] description] ?: @"1";
        self.instanceID = [record[@"id"] description] ?: NSUUID.UUID.UUIDString;
        self.displayName = [record[@"name"] description] ?: PetDefaultName(petID);
        self.createdAt = [record[@"createdAt"] doubleValue];
        if (self.createdAt <= 0) self.createdAt = NSDate.date.timeIntervalSince1970;
        CGFloat savedSize = [record[@"size"] doubleValue];
        self.sizeMultiplier = [PetSizes() containsObject:@(savedSize)] ? savedSize : 1.0;
        self.freeMovementEnabled = [record[@"freeMovement"] boolValue];
        self.randomAttackEnabled = [record[@"randomAttack"] boolValue];
        self.desktopVisible = record[@"visible"] ? [record[@"visible"] boolValue] : YES;
        self.movementDirection = 1.0;
        if (![self loadFramesFromURL:resourceURL petID:petID]) return nil;
        NSMutableSet *available = [NSMutableSet set];
        NSArray *metadata = PetMetadata(petID);
        for (NSArray *move in (metadata.count > 5 ? metadata[5] : @[])) [available addObject:move[0]];
        NSMutableArray *savedSkills = [NSMutableArray arrayWithCapacity:4];
        for (NSNumber *skillID in (record[@"skills"] ?: @[]))
            if ([available containsObject:skillID] && ![savedSkills containsObject:skillID] && savedSkills.count < 4)
                [savedSkills addObject:skillID];
        self.selectedSkillIDs = savedSkills.count ? savedSkills : PetDefaultSkillIDs(petID).mutableCopy;
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

- (void)resetDefaultSkills {
    self.selectedSkillIDs = PetDefaultSkillIDs(self.petID).mutableCopy;
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
    NSURL *bagImageURL = [[[resourceURL URLByAppendingPathComponent:@"frames"]
                           URLByAppendingPathComponent:@"bag-front"] URLByAppendingPathComponent:@"1.png"];
    NSValue *bagBounds = [self visibleBoundsAtURL:bagImageURL maxSide:MaxRasterSide];
    self.bagImage = bagBounds ? [self imageAtURL:bagImageURL croppedTo:bagBounds.rectValue
                                                       maxSide:MaxRasterSide] : self.idleImage;
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
    [self.owner savePetInstances];
}
- (void)playConfiguredSkill:(NSMenuItem *)sender {
    NSArray *move = PetMoveInfo(sender.representedObject);
    [self play:PetActionForMoveInfo(move)];
}

- (void)renamePet:(id)sender {
    self.movementPaused = YES;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"重命名桌宠";
    [alert addButtonWithTitle:@"保存"]; [alert addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    field.stringValue = self.displayName ?: @""; alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    NSTimer *focusTimer = [NSTimer timerWithTimeInterval:0 repeats:NO block:^(__unused NSTimer *timer) {
        [alert.window makeFirstResponder:field]; [field selectText:nil];
    }];
    [NSRunLoop.mainRunLoop addTimer:focusTimer forMode:NSModalPanelRunLoopMode];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *name = [field.stringValue stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length > 0) { self.displayName = name; [self.owner savePetInstances]; }
    }
    self.movementPaused = NO;
}

- (void)toggleFreeMovement:(NSMenuItem *)sender {
    self.freeMovementEnabled = !self.freeMovementEnabled;
    if (!self.freeMovementEnabled) [self startIdlePlayback];
    [self updateMovementTimer];
    [self.owner savePetInstances];
}

- (void)toggleRandomAttack:(NSMenuItem *)sender {
    self.randomAttackEnabled = !self.randomAttackEnabled;
    [self updateRandomAttackTimer];
    [self.owner savePetInstances];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    self.movementPaused = YES;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:
        [NSString stringWithFormat:@"%@（%@ 号）", self.displayName, self.petID]];
    menu.autoenablesItems = NO; menu.delegate = self;
    for (NSNumber *skillID in self.selectedSkillIDs) {
        NSArray *move = PetMoveInfo(skillID);
        NSString *title = move.count ? move[0] : [NSString stringWithFormat:@"技能 %@", skillID];
        NSMenuItem *menuItem = [menu addItemWithTitle:title action:@selector(playConfiguredSkill:) keyEquivalent:@""];
        menuItem.target = self; menuItem.representedObject = skillID;
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
    NSMenuItem *rename = [menu addItemWithTitle:@"重命名…" action:@selector(renamePet:) keyEquivalent:@""];
    rename.target = self;
    NSMenuItem *skills = [menu addItemWithTitle:@"更换技能…" action:@selector(replaceManagedPetSkills:) keyEquivalent:@""];
    skills.target = NSApp.delegate; skills.representedObject = self;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *change = [menu addItemWithTitle:@"更换精灵…" action:@selector(changePet:) keyEquivalent:@""];
    change.target = NSApp.delegate; change.representedObject = self;
    NSMenuItem *manager = [menu addItemWithTitle:@"宠物管理…" action:@selector(showPetManager:) keyEquivalent:@""];
    manager.target = NSApp.delegate;
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
    [self startIdlePlayback];
    [self.owner savePetInstances];
}
@end

@interface PetPanel : NSPanel
@end

@implementation PetPanel
// ponytail: desktop pets intentionally cross screen edges; AppKit's normal window clamp breaks dragging.
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen { return frameRect; }
@end

@interface PetBagButton : NSButton
@property(nonatomic, strong) NSImage *upImage;
@property(nonatomic, strong) NSImage *overImage;
@property(nonatomic, strong) NSTrackingArea *hoverArea;
- (void)setUpImage:(NSImage *)upImage overImage:(NSImage *)overImage;
@end

@implementation PetBagButton
- (void)setUpImage:(NSImage *)upImage overImage:(NSImage *)overImage {
    _upImage = upImage; _overImage = overImage; self.image = upImage;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea];
}
- (void)mouseEntered:(NSEvent *)event { self.image = self.overImage ?: self.upImage; }
- (void)mouseExited:(NSEvent *)event { self.image = self.upImage; }
- (void)mouseDown:(NSEvent *)event {
    self.image = self.upImage; [super mouseDown:event];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.image = NSPointInRect(point, self.bounds) ? (self.overImage ?: self.upImage) : self.upImage;
}
@end

@interface PetBagSlotButton : NSButton
@property(nonatomic, strong) NSImage *petImage;
@property(nonatomic, copy) NSString *petName;
@property(nonatomic, copy) NSString *petNumber;
@property(nonatomic) BOOL primarySlot;
@property(nonatomic) BOOL selectedSlot;
@property(nonatomic) BOOL petShown;
@property(nonatomic) BOOL occupied;
@end

@implementation PetBagSlotButton
- (BOOL)isFlipped { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    NSString *color = self.primarySlot ? @"yellow" : @"blue";
    NSString *state = self.selectedSlot ? @"selected" : @"normal";
    [PetBagSlotImage([NSString stringWithFormat:@"%@-%@", color, state])
        drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    if (!self.occupied) return;

    NSRect petBox = NSMakeRect(3, 9, 56, 56);
    NSSize size = self.petImage.size;
    CGFloat scale = size.width > 0 && size.height > 0 ? MIN(NSWidth(petBox) / size.width, NSHeight(petBox) / size.height) : 1;
    NSSize drawn = NSMakeSize(size.width * scale, size.height * scale);
    NSRect petRect = NSMakeRect(NSMidX(petBox) - drawn.width / 2, NSMidY(petBox) - drawn.height / 2,
                                drawn.width, drawn.height);
    [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
    [self.petImage drawInRect:petRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                     fraction:1.0 respectFlipped:YES hints:nil];

    NSDictionary *nameStyle = @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                                NSForegroundColorAttributeName: NSColor.whiteColor};
    NSDictionary *smallStyle = @{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
                                 NSForegroundColorAttributeName: NSColor.whiteColor};
    [self.petName drawInRect:NSMakeRect(52, 29, 68, 18) withAttributes:nameStyle];
    [@"lv.--" drawInRect:NSMakeRect(20, 4, 44, 15) withAttributes:smallStyle];
    [@"100/100" drawInRect:NSMakeRect(73, 4, 47, 15) withAttributes:smallStyle];
    [[NSColor colorWithWhite:0.25 alpha:0.9] setFill]; NSRectFill(NSMakeRect(50, 24, 61, 4));
    [[NSColor colorWithRed:0.94 green:0.10 blue:0.13 alpha:1] setFill]; NSRectFill(NSMakeRect(50, 24, 61, 4));
}
@end

@interface PetBagSkillView : NSControl
@property(nonatomic, strong) NSNumber *skillID;
@property(nonatomic, copy) NSString *skillName;
@property(nonatomic, copy) NSString *typeName;
@property(nonatomic, strong) NSImage *typeIcon;
@property(nonatomic, copy) NSString *powerText;
@property(nonatomic, copy) NSString *ppText;
@end

@implementation PetBagSkillView
- (void)setSkillName:(NSString *)skillName { _skillName = skillName.copy; [self setNeedsDisplay:YES]; }
- (void)setTypeIcon:(NSImage *)typeIcon { _typeIcon = typeIcon; [self setNeedsDisplay:YES]; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseDown:(NSEvent *)event { if (self.enabled) [self sendAction:self.action to:self.target]; }
- (void)drawRect:(NSRect)dirtyRect {
    NSImage *background = PetBagInfoImage(@"skill-up");
    [background drawInRect:self.bounds fromRect:NSMakeRect(6, 6, 257, 97)
                 operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    NSDictionary *nameStyle = @{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
                                NSForegroundColorAttributeName: NSColor.whiteColor};
    NSDictionary *detailStyle = @{NSFontAttributeName: [NSFont systemFontOfSize:10],
                                  NSForegroundColorAttributeName: [NSColor colorWithWhite:0.86 alpha:1]};
    NSMutableParagraphStyle *right = [NSMutableParagraphStyle new]; right.alignment = NSTextAlignmentRight;
    NSMutableDictionary *rightDetail = detailStyle.mutableCopy; rightDetail[NSParagraphStyleAttributeName] = right;
    CGFloat nameWidth = 91;
    if (self.typeIcon) {
        NSSize size = self.typeIcon.size;
        CGFloat scale = MIN(24.0 / size.width, 21.0 / size.height);
        NSSize iconSize = NSMakeSize(size.width * scale, size.height * scale);
        NSRect iconRect = NSMakeRect(NSWidth(self.bounds) - 8 - iconSize.width,
            NSHeight(self.bounds) - iconSize.height - 2, iconSize.width, iconSize.height);
        nameWidth = MAX(0, NSMinX(iconRect) - 12);
        [self.typeIcon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                        fraction:1 respectFlipped:YES hints:nil];
    }
    [self.skillName ?: @"" drawInRect:NSMakeRect(8, 25, nameWidth, 17) withAttributes:nameStyle];
    [[NSString stringWithFormat:@"威力:%@", self.powerText ?: @"--"]
        drawInRect:NSMakeRect(8, 7, 54, 12) withAttributes:detailStyle];
    [[NSString stringWithFormat:@"PP:%@", self.ppText ?: @"--/--"]
        drawInRect:NSMakeRect(62, 7, 58, 12) withAttributes:rightDetail];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, PetViewOwner>
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) PetView *petView;
@property(nonatomic, strong) NSMutableArray<PetView *> *petViews;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *petPanels;
@property(nonatomic, strong) NSWindow *managerWindow;
@property(nonatomic, strong) NSArray<NSButton *> *managerSlots;
@property(nonatomic, strong) NSArray<NSButton *> *managerPageButtons;
@property(nonatomic, strong) PetBagButton *managerFollowButton;
@property(nonatomic, strong) NSImageView *managerPreview;
@property(nonatomic, strong) NSTextField *managerDetail;
@property(nonatomic, strong) NSArray<NSTextField *> *managerInfoLabels;
@property(nonatomic, strong) NSTextField *managerFeatureLabel;
@property(nonatomic, strong) NSImageView *managerTypeIcon;
@property(nonatomic, strong) NSImageView *managerGenderIcon;
@property(nonatomic, strong) NSButton *managerEvolutionButton;
@property(nonatomic, strong) NSArray<NSTextField *> *managerStatLabels;
@property(nonatomic, strong) NSArray<NSTextField *> *managerEVLabels;
@property(nonatomic, strong) NSArray<PetBagSkillView *> *managerSkillViews;
@property(nonatomic, strong) NSTextField *managerPageLabel;
@property(nonatomic) NSInteger managerSelectedIndex;
@property(nonatomic) NSInteger managerPage;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSProgressIndicator *conversionProgress;
@property(nonatomic, strong) NSTextField *conversionStatus;
@property(nonatomic) BOOL converting;
- (void)updateManagerDetails;
- (void)refreshManagerSlots;
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

- (unsigned long long)allocatedSizeAtURL:(NSURL *)url {
    unsigned long long size = 0;
    NSDirectoryEnumerator<NSURL *> *files = [NSFileManager.defaultManager
        enumeratorAtURL:url includingPropertiesForKeys:@[NSURLFileAllocatedSizeKey, NSURLFileSizeKey]
        options:0 errorHandler:nil];
    for (NSURL *file in files) {
        NSNumber *allocatedSize, *fileSize;
        [file getResourceValue:&allocatedSize forKey:NSURLFileAllocatedSizeKey error:nil];
        [file getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        size += (allocatedSize ?: fileSize).unsignedLongLongValue;
    }
    return size;
}

- (NSArray<NSURL *> *)unusedCachedPetURLs {
    NSMutableSet<NSString *> *activePetIDs = [NSMutableSet set];
    for (PetView *view in self.petViews) [activePetIDs addObject:NormalizedPetID(view.petID)];
    NSURL *cacheURL = [[self supportURL] URLByAppendingPathComponent:@"pets"];
    NSArray<NSURL *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtURL:cacheURL
        includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:nil] ?: @[];
    NSMutableArray<NSURL *> *unused = [NSMutableArray array];
    for (NSURL *entry in entries) {
        NSNumber *isDirectory;
        [entry getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        NSString *petID = NormalizedPetID(entry.lastPathComponent);
        if (isDirectory.boolValue && petID.integerValue > 0 &&
            ![activePetIDs containsObject:petID])
            [unused addObject:entry];
    }
    return unused;
}

- (void)showCachePanel:(id)sender {
    NSURL *cacheURL = [[self supportURL] URLByAppendingPathComponent:@"pets"];
    unsigned long long totalSize = [self allocatedSizeAtURL:cacheURL];
    NSArray<NSURL *> *unused = [self unusedCachedPetURLs];
    unsigned long long unusedSize = 0;
    for (NSURL *url in unused) unusedSize += [self allocatedSizeAtURL:url];

    NSView *details = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 58)];
    NSTextField *path = [NSTextField labelWithString:cacheURL.path];
    path.frame = NSMakeRect(0, 32, 460, 22); path.selectable = YES;
    path.lineBreakMode = NSLineBreakByTruncatingMiddle; path.toolTip = cacheURL.path;
    NSTextField *size = [NSTextField labelWithString:[NSString stringWithFormat:@"占用空间：%@（可清理 %@）",
        [NSByteCountFormatter stringFromByteCount:totalSize countStyle:NSByteCountFormatterCountStyleFile],
        [NSByteCountFormatter stringFromByteCount:unusedSize countStyle:NSByteCountFormatterCountStyleFile]]];
    size.frame = NSMakeRect(0, 4, 460, 22); [details addSubview:path]; [details addSubview:size];

    NSAlert *alert = [NSAlert new]; alert.messageText = @"清理缓存";
    alert.informativeText = [NSString stringWithFormat:@"缓存路径（%lu 个未创建精灵缓存）：", (unsigned long)unused.count];
    alert.accessoryView = details;
    [alert addButtonWithTitle:@"清理未创建精灵缓存"]; [alert addButtonWithTitle:@"关闭"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSUInteger removed = 0; unsigned long long freed = 0;
    for (NSURL *url in unused) {
        unsigned long long itemSize = [self allocatedSizeAtURL:url];
        if ([NSFileManager.defaultManager removeItemAtURL:url error:nil]) { removed++; freed += itemSize; }
    }
    NSAlert *result = [NSAlert new]; result.messageText = @"缓存已清理";
    result.informativeText = removed ? [NSString stringWithFormat:@"已清理 %lu 个未创建精灵缓存，释放 %@。",
        (unsigned long)removed, [NSByteCountFormatter stringFromByteCount:freed countStyle:NSByteCountFormatterCountStyleFile]] :
        @"没有可清理的未创建精灵缓存。";
    [result runModal];
}

- (NSArray<NSDictionary *> *)savedPetRecords {
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:PetInstancesKey];
    if (saved.count > 0) return saved;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *petID = [defaults stringForKey:@"petID"] ?: @"1";
    NSString *instanceID = NSUUID.UUID.UUIDString;
    CGFloat size = [defaults doubleForKey:@"petSize"];
    if (![PetSizes() containsObject:@(size)]) size = 1.0;
    NSDictionary *record = @{ @"id": instanceID, @"name": PetDefaultName(petID),
                              @"petID": petID, @"size": @(size), @"createdAt": @(NSDate.date.timeIntervalSince1970),
                              @"visible": @YES,
                              @"freeMovement": @([defaults boolForKey:@"freeMovement"]),
                              @"randomAttack": @([defaults boolForKey:@"randomAttack"]) };
    [defaults setObject:@[record] forKey:PetInstancesKey];
    return @[record];
}

- (void)savePetInstances {
    if (!self.petViews) return;
    NSMutableArray *records = [NSMutableArray arrayWithCapacity:self.petViews.count];
    for (PetView *view in self.petViews) {
        NSRect frame = view.playingAction ? view.restingFrame : view.window.frame;
        [records addObject:@{ @"id": view.instanceID ?: NSUUID.UUID.UUIDString,
                              @"name": view.displayName ?: @"桌宠", @"petID": view.petID ?: @"1",
                              @"size": @(view.sizeMultiplier), @"visible": @(view.desktopVisible),
                              @"createdAt": @(view.createdAt),
                              @"skills": view.selectedSkillIDs ?: @[],
                              @"freeMovement": @(view.freeMovementEnabled),
                              @"randomAttack": @(view.randomAttackEnabled),
                              @"x": @(NSMinX(frame)), @"y": @(NSMinY(frame)) }];
    }
    [NSUserDefaults.standardUserDefaults setObject:records forKey:PetInstancesKey];
    [self refreshManagerSlots];
    [self updateManagerDetails];
}

- (NSURL *)readyResourceForPetID:(NSString *)petID {
    NSURL *resourceURL = [self cachedPetURL:petID];
    [self installIdleForPetID:petID intoPetURL:resourceURL];
    BOOL hasFrames = [NSFileManager.defaultManager
        fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@"frames"] path]];
    BOOL needsPetException = ([petID isEqualToString:@"9"] || [petID isEqualToString:@"70"]) &&
        ![NSFileManager.defaultManager fileExistsAtPath:
            [[resourceURL URLByAppendingPathComponent:@".pet-exceptions-v1"] path]];
    BOOL needsPet70Idle = [petID isEqualToString:@"70"] &&
        ![NSFileManager.defaultManager fileExistsAtPath:
            [[[[resourceURL URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@"idle"]
                URLByAppendingPathComponent:@".true-idle"] path]];
    BOOL needsUpgrade = hasFrames &&
        (needsPetException || needsPet70Idle ||
         ![NSFileManager.defaultManager fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@".idle-scan-v1"] path]] ||
         ![NSFileManager.defaultManager fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@".walk-scan-v2"] path]] ||
         ![NSFileManager.defaultManager fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@".bag-front-v1"] path]] ||
         ![NSFileManager.defaultManager fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@".raster-v3"] path]] ||
         ![NSFileManager.defaultManager fileExistsAtPath:
             [[[resourceURL URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@".layout-v1.plist"] path]]);
    if (needsUpgrade) resourceURL = [self installPetID:petID error:nil] ?: resourceURL;
    if (![NSFileManager.defaultManager fileExistsAtPath:[[resourceURL URLByAppendingPathComponent:@"frames"] path]])
        return [petID isEqualToString:@"1"] ? NSBundle.mainBundle.resourceURL : nil;
    return resourceURL;
}

- (PetView *)addPetFromRecord:(NSDictionary *)record resourceURL:(NSURL *)resourceURL {
    PetView *view = [[PetView alloc] initWithFrame:NSMakeRect(0, 0, BaseWindowSize, BaseWindowSize)
                                       resourceURL:resourceURL record:record];
    if (!view) return nil;
    view.owner = self;
    CGFloat side = BaseWindowSize * view.sizeMultiplier;
    [view setFrameSize:NSMakeSize(side, side)];
    NSPanel *panel = [[PetPanel alloc] initWithContentRect:NSMakeRect(0, 0, side, side)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    panel.opaque = NO; panel.backgroundColor = NSColor.clearColor; panel.hasShadow = NO;
    panel.level = NSFloatingWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.hidesOnDeactivate = NO; panel.contentView = view;

    NSNumber *savedX = record[@"x"], *savedY = record[@"y"];
    if (savedX && savedY) {
        [panel setFrameOrigin:NSMakePoint(savedX.doubleValue, savedY.doubleValue)];
    } else {
        NSScreen *screen = NSScreen.mainScreen; NSRect visible = screen.visibleFrame;
        CGFloat offset = self.petViews.count * 36.0;
        [panel setFrameOrigin:NSMakePoint(NSMidX(visible) - side / 2.0 + offset,
                                          NSMidY(visible) - side / 2.0 - offset)];
    }
    [self.petViews addObject:view]; [self.petPanels addObject:panel];
    if (view.desktopVisible) [panel orderFront:nil];
    else {
        [view.timer invalidate]; view.timer = nil;
        [view.movementTimer invalidate]; view.movementTimer = nil;
        [view.randomAttackTimer invalidate]; view.randomAttackTimer = nil;
    }
    return view;
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

- (BOOL)installBagFrontForPetID:(NSString *)petID
                  intoFramesURL:(NSURL *)framesURL
                   temporaryURL:(NSURL *)temporaryURL {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *destination = [[framesURL URLByAppendingPathComponent:@"bag-front"]
                          URLByAppendingPathComponent:@"1.png"];
    if ([fm fileExistsAtPath:destination.path]) return YES;

    NSURL *swf = [temporaryURL URLByAppendingPathComponent:@"bag-front.swf"];
    NSString *relativePath = [NSString stringWithFormat:@"groupFightResource/pet/%@.swf", petID];
    NSURL *localResource = [[NSURL fileURLWithPath:NSHomeDirectory()]
        URLByAppendingPathComponent:[@"Library/Application Support/seer-game/serverFile/resource"
                                     stringByAppendingPathComponent:relativePath]];
    if ([fm fileExistsAtPath:localResource.path]) {
        if (![fm copyItemAtURL:localResource toURL:swf error:nil]) return NO;
    } else {
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:
            [@"https://seer.61.com/resource/" stringByAppendingString:relativePath]]];
        if (data.length < 4 || ![data writeToURL:swf atomically:YES]) return NO;
    }

    NSURL *symbols = [temporaryURL URLByAppendingPathComponent:@"bag-front-symbols"];
    [fm createDirectoryAtURL:symbols withIntermediateDirectories:YES attributes:nil error:nil];
    if (![self runFFDec:@[@"-export", @"symbolClass", symbols.path, swf.path]]) return NO;
    NSString *csv = [NSString stringWithContentsOfURL:[symbols URLByAppendingPathComponent:@"symbols.csv"]
                                              encoding:NSUTF8StringEncoding error:nil];
    NSInteger spriteID = -1;
    for (NSString *line in [csv componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (![line containsString:@"\"pet\""]) continue;
        spriteID = line.integerValue; break;
    }
    if (spriteID <= 0) return NO;

    NSURL *exportURL = [temporaryURL URLByAppendingPathComponent:@"bag-front-export"];
    [fm createDirectoryAtURL:exportURL withIntermediateDirectories:YES attributes:nil error:nil];
    if (![self runFFDec:@[@"-selectid", @(spriteID).stringValue, @"-ignorebackground", @"-zoom", @"4",
                          @"-format", @"sprite:png", @"-export", @"sprite", exportURL.path, swf.path]]) return NO;
    NSString *prefix = [NSString stringWithFormat:@"DefineSprite_%ld", (long)spriteID];
    NSURL *spriteDirectory = [[fm contentsOfDirectoryAtURL:exportURL includingPropertiesForKeys:nil
                                                    options:0 error:nil]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.lastPathComponent hasPrefix:prefix];
        }]].firstObject;
    NSURL *source = [spriteDirectory URLByAppendingPathComponent:@"1.png"];
    if (![fm fileExistsAtPath:source.path]) return NO;
    [fm createDirectoryAtURL:destination.URLByDeletingLastPathComponent
  withIntermediateDirectories:YES attributes:nil error:nil];
    return [fm copyItemAtURL:source toURL:destination error:nil];
}

- (NSURL *)installPetID:(NSString *)petID error:(NSError **)error {
    [self reportConversionProgress:2 status:@"检查本地缓存…"];
    NSURL *cached = [self cachedPetURL:petID];
    [self installIdleForPetID:petID intoPetURL:cached];
    NSURL *idleScanMarker = [cached URLByAppendingPathComponent:@".idle-scan-v1"];
    NSURL *walkScanMarker = [cached URLByAppendingPathComponent:@".walk-scan-v2"];
    NSURL *bagFrontMarker = [cached URLByAppendingPathComponent:@".bag-front-v1"];
    NSURL *rasterMarker = [cached URLByAppendingPathComponent:@".raster-v3"];
    BOOL hasPetException = ![petID isEqualToString:@"9"] && ![petID isEqualToString:@"70"] ||
        [NSFileManager.defaultManager fileExistsAtPath:
            [[cached URLByAppendingPathComponent:@".pet-exceptions-v1"] path]];
    BOOL hasPet70Idle = ![petID isEqualToString:@"70"] ||
        [NSFileManager.defaultManager fileExistsAtPath:
            [[[[cached URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@"idle"]
                URLByAppendingPathComponent:@".true-idle"] path]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[[cached URLByAppendingPathComponent:@"frames"] path]] &&
        [[NSFileManager defaultManager] fileExistsAtPath:idleScanMarker.path] &&
        [[NSFileManager defaultManager] fileExistsAtPath:walkScanMarker.path] && hasPetException && hasPet70Idle) {
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
            if (![NSFileManager.defaultManager fileExistsAtPath:bagFrontMarker.path]) {
                [self reportConversionProgress:99 status:@"提取背包正面形象…"];
                NSURL *temp = [NSURL fileURLWithPath:[NSTemporaryDirectory()
                    stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
                [NSFileManager.defaultManager createDirectoryAtURL:temp withIntermediateDirectories:YES
                                                         attributes:nil error:nil];
                if ([self installBagFrontForPetID:petID intoFramesURL:framesURL temporaryURL:temp])
                    [NSData.data writeToURL:bagFrontMarker atomically:YES];
                [NSFileManager.defaultManager removeItemAtURL:temp error:nil];
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
    NSArray<NSNumber *> *idleActionIDs = [ids subarrayWithRange:NSMakeRange(0, 3)];
    // 70 has an extra attack1 before the normal four actions; ignore it and restore attack/sa/cp/hited order.
    if ([petID isEqualToString:@"70"])
        ids = [@[ids[3], ids[0], ids[1], ids[2]] mutableCopy];
    NSMutableArray<NSString *> *idStrings = [NSMutableArray array];
    for (NSNumber *value in ids) [idStrings addObject:value.stringValue];

    NSURL *xml = [temp URLByAppendingPathComponent:@"structure.xml"];
    NSDictionary<NSString *, NSNumber *> *idleInfo = nil;
    NSArray<NSNumber *> *frameCounts = @[];
    [self reportConversionProgress:18 status:@"分析待机与动作结构…"];
    if ([self runFFDec:@[@"-swf2xml", swf.path, xml.path]]) {
        idleInfo = [self idleInfoFromXMLURL:xml actionIDs:idleActionIDs];
        // 9's highest shared child is a two-frame tail effect; sprite 19 is its complete body loop.
        if ([petID isEqualToString:@"9"])
            idleInfo = @{@"spriteID": @19, @"fps": idleInfo[@"fps"] ?: @25};
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
    [self reportConversionProgress:82 status:@"提取背包正面形象…"];
    BOOL hasBagFront = [self installBagFrontForPetID:petID intoFramesURL:stagedFrames temporaryURL:temp];
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
    if (hasBagFront) [NSData.data writeToURL:[stagedPet URLByAppendingPathComponent:@".bag-front-v1"] atomically:YES];
    [NSData.data writeToURL:[stagedPet URLByAppendingPathComponent:@".raster-v3"] atomically:YES];
    if ([petID isEqualToString:@"9"] || [petID isEqualToString:@"70"])
        [NSData.data writeToURL:[stagedPet URLByAppendingPathComponent:@".pet-exceptions-v1"] atomically:YES];
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
    alert.alertStyle = NSAlertStyleWarning; alert.messageText = @"操作失败";
    alert.informativeText = message ?: @"未知错误"; [alert runModal];
}

- (NSURL *)preparePetID:(NSString *)petID error:(NSError **)error {
    if (self.converting) { SetError(error, @"另一个精灵正在转换，请稍候"); return nil; }
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
    [progressView addSubview:self.conversionStatus]; [progressView addSubview:self.conversionProgress];
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
    self.conversionProgress = nil; self.conversionStatus = nil; self.converting = NO;
    if (error) *error = conversionError;
    return petURL;
}

- (void)changePetForView:(PetView *)target {
    if (!target || self.converting) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *input = [NSAlert new];
    input.messageText = @"更换赛尔号精灵";
    input.informativeText = @"输入精灵编号。首次使用该编号需要联网下载并转换。";
    [input addButtonWithTitle:@"更换"]; [input addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
    field.placeholderString = @"例如：1"; field.stringValue = target.petID ?: @"1"; input.accessoryView = field;
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
    NSError *conversionError = nil;
    NSURL *petURL = [self preparePetID:petID error:&conversionError];
    if (!petURL || ![target loadFramesFromURL:petURL petID:petID]) {
        [self showError:conversionError.localizedDescription ?: @"提取出的动作帧无法播放"]; return;
    }
    [target resetDefaultSkills];
    [self savePetInstances]; [target play:@"sa"];
}

- (void)changePet:(id)sender {
    PetView *target = [sender isKindOfClass:NSMenuItem.class] ? [sender representedObject] : nil;
    target = target ?: self.petView;
    if (sender) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self changePetForView:target]; });
        return;
    }
    [self changePetForView:target];
}

- (NSDictionary *)petEditorValuesForView:(PetView *)view title:(NSString *)title {
    NSAlert *alert = [NSAlert new]; alert.messageText = title;
    alert.informativeText = @"每个桌宠的名称、形象和行为设置彼此独立。";
    [alert addButtonWithTitle:@"保存"]; [alert addButtonWithTitle:@"取消"];
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 176)];
    NSString *initialID = view.petID ?: @"1";
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(92, 144, 248, 24)];
    name.stringValue = view.displayName ?: PetDefaultName(initialID);
    NSTextField *petID = [[NSTextField alloc] initWithFrame:NSMakeRect(92, 112, 248, 24)];
    petID.stringValue = initialID;
    NSPopUpButton *size = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(92, 80, 120, 26)];
    for (NSNumber *value in PetSizes())
        [size addItemWithTitle:[NSString stringWithFormat:@"%g×", value.doubleValue]];
    CGFloat selectedSize = view ? view.sizeMultiplier : 1.0;
    [size selectItemWithTitle:[NSString stringWithFormat:@"%g×", selectedSize]];
    NSButton *movement = [NSButton checkboxWithTitle:@"自由移动" target:nil action:nil];
    movement.frame = NSMakeRect(92, 52, 110, 22); movement.state = view.freeMovementEnabled;
    NSButton *random = [NSButton checkboxWithTitle:@"每 8 秒随机攻击" target:nil action:nil];
    random.frame = NSMakeRect(205, 52, 135, 22); random.state = view.randomAttackEnabled;
    NSButton *visible = [NSButton checkboxWithTitle:@"显示在桌面" target:nil action:nil];
    visible.frame = NSMakeRect(92, 22, 120, 22);
    visible.state = !view || view.desktopVisible ? NSControlStateValueOn : NSControlStateValueOff;
    NSArray *labels = @[@"名称", @"精灵编号", @"大小"];
    for (NSUInteger i = 0; i < labels.count; i++) {
        NSTextField *label = [NSTextField labelWithString:labels[i]];
        label.frame = NSMakeRect(0, 146 - i * 32, 82, 22); label.alignment = NSTextAlignmentRight;
        [form addSubview:label];
    }
    for (NSView *control in @[name, petID, size, movement, random, visible]) [form addSubview:control];
    NSTextField *firstField = view ? name : petID;
    alert.accessoryView = form; alert.window.initialFirstResponder = firstField;
    NSTimer *focusTimer = [NSTimer timerWithTimeInterval:0 repeats:NO block:^(__unused NSTimer *timer) {
        [alert.window makeFirstResponder:firstField]; [firstField selectText:nil];
    }];
    [NSRunLoop.mainRunLoop addTimer:focusTimer forMode:NSModalPanelRunLoopMode];
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    NSString *trimmedName = [name.stringValue stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *trimmedID = [petID.stringValue stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!view && [trimmedName isEqualToString:PetDefaultName(initialID)])
        trimmedName = PetDefaultName(trimmedID);
    if (trimmedName.length == 0 || trimmedID.length == 0 ||
        [trimmedID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound ||
        trimmedID.integerValue <= 0) {
        [self showError:@"名称不能为空，精灵编号必须是大于 0 的整数"]; return nil;
    }
    CGFloat sizeValue = [PetSizes()[size.indexOfSelectedItem] doubleValue];
    return @{ @"name": trimmedName, @"petID": trimmedID, @"size": @(sizeValue),
              @"visible": @(visible.state == NSControlStateValueOn),
              @"freeMovement": @(movement.state == NSControlStateValueOn),
              @"randomAttack": @(random.state == NSControlStateValueOn) };
}

- (PetView *)selectedManagedPet {
    NSInteger index = self.managerSelectedIndex;
    return index >= 0 && index < (NSInteger)self.petViews.count ? self.petViews[index] : nil;
}

- (void)selectManagerSlot:(NSButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.petViews.count) return;
    self.managerSelectedIndex = sender.tag;
    [self refreshManagerSlots]; [self updateManagerDetails];
}

- (void)showPreviousManagerPage:(id)sender {
    if (self.managerPage <= 0) return;
    self.managerPage--; self.managerSelectedIndex = self.managerPage * 6;
    [self refreshManagerSlots]; [self updateManagerDetails];
}

- (void)showNextManagerPage:(id)sender {
    NSInteger pages = MAX(1, ((NSInteger)self.petViews.count + 5) / 6);
    if (self.managerPage + 1 >= pages) return;
    self.managerPage++; self.managerSelectedIndex = self.managerPage * 6;
    [self refreshManagerSlots]; [self updateManagerDetails];
}

- (void)refreshManagerSlots {
    if (self.managerSlots.count == 0) return;
    NSInteger pages = MAX(1, ((NSInteger)self.petViews.count + 5) / 6);
    self.managerPage = MIN(MAX(0, self.managerPage), pages - 1);
    if (self.managerSelectedIndex >= (NSInteger)self.petViews.count)
        self.managerSelectedIndex = MAX(0, (NSInteger)self.petViews.count - 1);
    for (NSInteger slot = 0; slot < 6; slot++) {
        PetBagSlotButton *button = (PetBagSlotButton *)self.managerSlots[slot];
        NSInteger index = self.managerPage * 6 + slot;
        button.tag = index; button.hidden = NO; button.occupied = index < (NSInteger)self.petViews.count;
        button.enabled = button.occupied;
        if (!button.occupied) {
            button.petImage = nil; button.petName = nil; button.petNumber = nil;
            button.primarySlot = NO; button.selectedSlot = NO; button.petShown = NO;
            button.toolTip = nil; [button setNeedsDisplay:YES]; continue;
        }
        PetView *view = self.petViews[index];
        button.petImage = view.bagImage ?: view.idleImage;
        button.petName = view.displayName; button.petNumber = view.petID;
        button.primarySlot = index == 0; button.selectedSlot = index == self.managerSelectedIndex;
        button.petShown = view.desktopVisible; [button setNeedsDisplay:YES];
        button.toolTip = [NSString stringWithFormat:@"%@（%@号）", view.displayName, view.petID];
    }
    self.managerPageLabel.stringValue = [NSString stringWithFormat:@"%ld / %ld",
        (long)self.managerPage + 1, (long)pages];
    self.managerPageLabel.hidden = pages == 1;
    if (self.managerPageButtons.count == 2) {
        self.managerPageButtons[0].hidden = pages == 1;
        self.managerPageButtons[1].hidden = pages == 1;
        self.managerPageButtons[0].enabled = self.managerPage > 0;
        self.managerPageButtons[1].enabled = self.managerPage + 1 < pages;
    }
}

- (void)setPetView:(PetView *)view desktopVisible:(BOOL)visible {
    view.desktopVisible = visible;
    if (visible) {
        [view startIdlePlayback]; [view updateMovementTimer]; [view updateRandomAttackTimer];
        [view.window orderFront:nil];
    } else {
        if (view.playingAction) [view restoreIdleWindow];
        [view startIdlePlayback];
        [view.timer invalidate]; view.timer = nil;
        [view.movementTimer invalidate]; view.movementTimer = nil;
        [view.randomAttackTimer invalidate]; view.randomAttackTimer = nil;
        [view.window orderOut:nil];
    }
}

- (void)addManagedPet:(id)sender {
    NSDictionary *values = [self petEditorValuesForView:nil title:@"增加桌宠"];
    if (!values) return;
    NSError *error = nil; NSURL *url = [self preparePetID:values[@"petID"] error:&error];
    if (!url) { [self showError:error.localizedDescription]; return; }
    NSMutableDictionary *record = values.mutableCopy; record[@"id"] = NSUUID.UUID.UUIDString;
    PetView *view = [self addPetFromRecord:record resourceURL:url];
    if (!view) { [self showError:@"无法加载这个精灵的动作帧"]; return; }
    self.managerSelectedIndex = self.petViews.count - 1;
    self.managerPage = self.managerSelectedIndex / 6;
    [self savePetInstances];
}

- (void)editManagedPet:(id)sender {
    PetView *view = [self selectedManagedPet]; if (!view) return;
    NSDictionary *values = [self petEditorValuesForView:view title:@"编辑桌宠"];
    if (!values) return;
    NSString *newPetID = values[@"petID"];
    if (![newPetID isEqualToString:view.petID]) {
        NSError *error = nil; NSURL *url = [self preparePetID:newPetID error:&error];
        if (!url || ![view loadFramesFromURL:url petID:newPetID]) {
            [self showError:error.localizedDescription ?: @"无法加载这个精灵的动作帧"]; return;
        }
        [view resetDefaultSkills];
    }
    view.displayName = values[@"name"];
    CGFloat newSize = [values[@"size"] doubleValue];
    if (fabs(newSize - view.sizeMultiplier) > 0.001) {
        NSMenuItem *item = [NSMenuItem new]; item.representedObject = @(newSize); [view changeSize:item];
    }
    view.freeMovementEnabled = [values[@"freeMovement"] boolValue]; [view updateMovementTimer];
    view.randomAttackEnabled = [values[@"randomAttack"] boolValue]; [view updateRandomAttackTimer];
    if (!view.freeMovementEnabled) [view startIdlePlayback];
    [self setPetView:view desktopVisible:[values[@"visible"] boolValue]];
    [self savePetInstances];
}

- (void)removeManagedPet:(id)sender {
    PetView *view = [self selectedManagedPet]; if (!view) return;
    if (self.petViews.count <= 1) { [self showError:@"至少保留一个桌宠"]; return; }
    NSUInteger index = [self.petViews indexOfObjectIdenticalTo:view];
    [view.timer invalidate]; [view.movementTimer invalidate]; [view.randomAttackTimer invalidate];
    [self.petPanels[index] orderOut:nil];
    [self.petViews removeObjectAtIndex:index]; [self.petPanels removeObjectAtIndex:index];
    self.petView = self.petViews.firstObject; self.panel = self.petPanels.firstObject;
    self.managerSelectedIndex = MIN((NSInteger)index, (NSInteger)self.petViews.count - 1);
    self.managerPage = self.managerSelectedIndex / 6;
    [self savePetInstances];
}

- (void)updateManagerDetails {
    PetView *view = [self selectedManagedPet];
    self.managerPreview.image = view.bagImage ?: view.idleImage;
    NSArray *metadata = view ? PetMetadata(view.petID) : nil;
    NSNumber *typeID = metadata.count > 0 ? metadata[0] : @0;
    NSString *typeName = view ? PetTypeName(typeID) : @"";
    NSInteger gender = metadata.count > 1 ? [metadata[1] integerValue] : 0;
    NSArray<NSString *> *labels = @[@"序号:", @"名字:", @"等级:", @"升级所需经验值:", @"性格:", @"获得时间:"];
    NSDateFormatter *dateFormatter = [NSDateFormatter new]; dateFormatter.dateFormat = @"yyyy-M-d";
    NSString *createdDate = view ? [dateFormatter stringFromDate:
        [NSDate dateWithTimeIntervalSince1970:view.createdAt]] : @"";
    NSArray<NSString *> *values = view ? @[
        [NSString stringWithFormat:@"%03ld", (long)view.petID.integerValue], view.displayName,
        @"--", @"--", @"--", createdDate
    ] : @[@"", @"", @"", @"", @"", @""];
    for (NSUInteger i = 0; i < self.managerInfoLabels.count; i++)
        self.managerInfoLabels[i].attributedStringValue = PetBagFieldText(labels[i], values[i]);
    self.managerInfoLabels[1].toolTip = view ? [NSString stringWithFormat:@"%@ · 属性：%@", view.displayName, typeName] : nil;
    NSImage *typeIcon = view ? PetTypeIcon(typeID) : nil;
    self.managerTypeIcon.image = typeIcon;
    self.managerTypeIcon.toolTip = view ? [NSString stringWithFormat:@"属性：%@", typeName] : nil;
    NSSize sourceSize = typeIcon.size;
    CGFloat typeScale = typeIcon ? MIN(30.0 / sourceSize.width, 24.0 / sourceSize.height) : 0;
    NSSize typeSize = NSMakeSize(sourceSize.width * typeScale, sourceSize.height * typeScale);
    NSRect nameFrame = self.managerInfoLabels[1].frame;
    CGFloat reservedWidth = 6 + typeSize.width + (gender > 0 ? 24 : 0);
    CGFloat availableNameWidth = MAX(40, 600 - NSMinX(nameFrame) - reservedWidth);
    nameFrame.size.width = MIN(availableNameWidth,
        ceil(self.managerInfoLabels[1].attributedStringValue.size.width) + 6);
    self.managerInfoLabels[1].frame = nameFrame;
    CGFloat typeX = NSMaxX(nameFrame) + 6;
    self.managerTypeIcon.frame = NSMakeRect(typeX, 289 - typeSize.height / 2, typeSize.width, typeSize.height);
    self.managerGenderIcon.image = gender > 0 ? PetGenderIcon(MIN(gender, 2)) : nil;
    self.managerGenderIcon.frame = NSMakeRect(NSMaxX(self.managerTypeIcon.frame) + 6, 279, 18, 20);
    self.managerGenderIcon.hidden = !view || gender == 0;
    self.managerGenderIcon.toolTip = gender == 1 ? @"雄性" : (gender == 2 ? @"雌性" : nil);
    NSInteger evolvesTo = metadata.count > 2 ? [metadata[2] integerValue] : 0;
    NSInteger evolvingLv = metadata.count > 3 ? [metadata[3] integerValue] : 0;
    NSInteger evolvFlag = metadata.count > 4 ? [metadata[4] integerValue] : 0;
    if (!view) self.managerEvolutionButton.toolTip = nil;
    else if (evolvesTo > 0) self.managerEvolutionButton.toolTip = [NSString stringWithFormat:@"%ld级进化为%@",
        (long)evolvingLv, PetDefaultName([NSString stringWithFormat:@"%ld", (long)evolvesTo])];
    else if (evolvFlag > 0) self.managerEvolutionButton.toolTip = evolvingLv > 0 ?
        [NSString stringWithFormat:@"%ld级在实验室进化舱进化", (long)evolvingLv] : @"可在实验室进化舱进化";
    else self.managerEvolutionButton.toolTip = @"已是最终形态";
    self.managerFeatureLabel.attributedStringValue = PetBagFieldText(@"特性:", view ? @"--" : @"");
    NSArray<NSNumber *> *baseStats = view ? PetBaseStats(view.petID) : nil;
    NSArray<NSString *> *statNames = @[@"攻击", @"防御", @"特攻", @"特防", @"速度", @"体力"];
    NSMutableArray<NSString *> *stats = [NSMutableArray arrayWithCapacity:6];
    for (NSUInteger i = 0; i < 6; i++) {
        NSString *value = i < baseStats.count ? baseStats[i].stringValue : @"--";
        [stats addObject:view ? [NSString stringWithFormat:@"%@:%@", statNames[i], value] : @""];
    }
    for (NSUInteger i = 0; i < self.managerStatLabels.count; i++)
        self.managerStatLabels[i].stringValue = stats[i];
    for (NSTextField *label in self.managerEVLabels) label.stringValue = view ? @"0" : @"";
    for (NSUInteger i = 0; i < self.managerSkillViews.count; i++) {
        PetBagSkillView *skillView = self.managerSkillViews[i];
        NSNumber *skillID = view && i < view.selectedSkillIDs.count ? view.selectedSkillIDs[i] : nil;
        NSArray *info = skillID ? PetMoveInfo(skillID) : nil;
        skillView.skillID = skillID;
        skillView.skillName = info.count > 0 ? info[0] : @"";
        skillView.powerText = info.count > 1 ? [info[1] stringValue] : @"--";
        skillView.ppText = info.count > 2 ? [NSString stringWithFormat:@"%@/%@", info[2], info[2]] : @"--/--";
        skillView.typeName = info.count > 4 ? PetTypeName(info[4]) : @"";
        NSInteger category = info.count > 3 ? [info[3] integerValue] : 0;
        skillView.typeIcon = info.count > 4 ? (category == 4 ? PetTypeIconNamed(@"prop") : PetTypeIcon(info[4])) : nil;
        NSString *categoryName = category == 1 ? @"物理攻击" : (category == 2 ? @"特殊攻击" :
            (category == 4 ? @"属性攻击" : @"技能"));
        NSString *detail = info.count > 5 ? info[5] : @"";
        skillView.toolTip = info ? [NSString stringWithFormat:@"%@ · %@ · %@%@",
            skillView.typeName, categoryName, detail.length ? detail : @"点击更换技能",
            detail.length ? @"（点击更换技能）" : @""] : @"点击更换技能";
    }
    if (view && self.managerFollowButton) {
        NSString *name = view.desktopVisible ? @"follow-hide" : @"follow-show";
        [self.managerFollowButton setUpImage:PetBagButtonImage(name, @"up")
                                  overImage:PetBagButtonImage(name, @"over")];
        self.managerFollowButton.toolTip = view.desktopVisible ? @"收回包内" : @"身边跟随";
    }
}

- (void)toggleManagedPetVisibility:(id)sender {
    PetView *view = [self selectedManagedPet]; if (!view) return;
    [self setPetView:view desktopVisible:!view.desktopVisible]; [self savePetInstances];
}

- (void)makeManagedPetPrimary:(id)sender {
    PetView *view = [self selectedManagedPet]; if (!view) return;
    NSUInteger index = [self.petViews indexOfObjectIdenticalTo:view];
    if (index > 0) {
        NSPanel *panel = self.petPanels[index];
        [self.petViews removeObjectAtIndex:index]; [self.petPanels removeObjectAtIndex:index];
        [self.petViews insertObject:view atIndex:0]; [self.petPanels insertObject:panel atIndex:0];
    }
    self.petView = view; self.panel = self.petPanels.firstObject; self.managerSelectedIndex = 0; self.managerPage = 0;
    [self savePetInstances];
}

- (void)restoreManagedPet:(id)sender {
    PetView *view = [self selectedManagedPet]; if (!view) return;
    if (view.playingAction) [view restoreIdleWindow];
    [view startIdlePlayback];
    NSScreen *screen = view.window.screen ?: NSScreen.mainScreen; NSRect area = screen.visibleFrame;
    [view.window setFrameOrigin:NSMakePoint(NSMidX(area) - NSWidth(view.window.frame) / 2.0,
                                            NSMidY(area) - NSHeight(view.window.frame) / 2.0)];
    view.restingFrame = view.window.frame; [self savePetInstances];
}

- (void)toggleManagedPetRandomAttack:(id)sender {
    PetView *view = [self selectedManagedPet]; if (!view) return;
    view.randomAttackEnabled = !view.randomAttackEnabled; [view updateRandomAttackTimer];
    [self savePetInstances];
}

- (void)replaceManagedPetSkills:(id)sender {
    PetView *view = [sender isKindOfClass:NSMenuItem.class] ? [sender representedObject] : [self selectedManagedPet];
    if (!view) return;
    NSArray *metadata = PetMetadata(view.petID), *moves = metadata.count > 5 ? metadata[5] : @[];
    if (moves.count == 0) { [self showError:@"这个编号没有可用的技能配置"]; return; }
    NSUInteger slotCount = MIN(4, moves.count);
    NSAlert *alert = [NSAlert new]; alert.messageText = [NSString stringWithFormat:@"%@ · 更换技能", view.displayName];
    alert.informativeText = @"从原版已学技能中选择最多四个携带技能，同一技能不能重复。";
    [alert addButtonWithTitle:@"保存"]; [alert addButtonWithTitle:@"取消"];
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 390, slotCount * 36)];
    NSMutableArray<NSPopUpButton *> *popups = [NSMutableArray arrayWithCapacity:slotCount];
    for (NSUInteger slot = 0; slot < slotCount; slot++) {
        CGFloat y = (slotCount - slot - 1) * 36;
        NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"技能 %lu", slot + 1]];
        label.frame = NSMakeRect(0, y + 3, 55, 22); label.alignment = NSTextAlignmentRight;
        NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(64, y, 326, 26) pullsDown:NO];
        for (NSArray *move in moves) {
            NSNumber *skillID = move[0]; NSArray *info = PetMoveInfo(skillID);
            NSString *title = [NSString stringWithFormat:@"%@  Lv.%@  %@  威力%@",
                info.count ? info[0] : [@"技能" stringByAppendingString:skillID.stringValue], move[1],
                info.count > 4 ? PetTypeName(info[4]) : @"--", info.count > 1 ? info[1] : @"--"];
            [popup addItemWithTitle:title]; popup.lastItem.representedObject = skillID;
        }
        NSNumber *selected = slot < view.selectedSkillIDs.count ? view.selectedSkillIDs[slot] : nil;
        for (NSMenuItem *item in popup.itemArray)
            if ([item.representedObject isEqual:selected]) { [popup selectItem:item]; break; }
        [form addSubview:label]; [form addSubview:popup]; [popups addObject:popup];
    }
    alert.accessoryView = form;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSMutableArray<NSNumber *> *selected = [NSMutableArray arrayWithCapacity:slotCount];
    for (NSPopUpButton *popup in popups) [selected addObject:popup.selectedItem.representedObject];
    if ([NSSet setWithArray:selected].count != selected.count) { [self showError:@"同一技能不能重复携带"]; return; }
    view.selectedSkillIDs = selected; [self savePetInstances];
}

- (void)closePetManager:(id)sender { [self.managerWindow performClose:nil]; }

- (void)showPetManager:(id)sender {
    if (!self.managerWindow) {
        self.managerWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 612, 329)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
            backing:NSBackingStoreBuffered defer:NO];
        self.managerWindow.title = @"赛尔号桌宠管理"; self.managerWindow.releasedWhenClosed = NO;
        self.managerWindow.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary;
        NSView *content = self.managerWindow.contentView;
        content.wantsLayer = YES; content.layer.backgroundColor = [NSColor colorWithRed:0.02 green:0.11 blue:0.25 alpha:1].CGColor;
        NSImageView *background = [[NSImageView alloc] initWithFrame:NSMakeRect(-204, -132, 974, 574)];
        background.image = [NSBundle.mainBundle imageForResource:@"PetBagLegacy"];
        background.imageScaling = NSImageScaleNone; [content addSubview:background];
        NSView *infoBacking = [[NSView alloc] initWithFrame:NSMakeRect(312, 5, 291, 314)];
        infoBacking.wantsLayer = YES;
        infoBacking.layer.backgroundColor = [NSColor colorWithRed:0 green:0.10 blue:0.27 alpha:1].CGColor;
        [content addSubview:infoBacking];
        NSImageView *infoPanel = [[NSImageView alloc] initWithFrame:NSMakeRect(306, 3, 303, 333)];
        infoPanel.image = PetBagInfoImage(@"panel"); infoPanel.imageScaling = NSImageScaleAxesIndependently;
        [content addSubview:infoPanel];
        NSView *effectCover = [[NSView alloc] initWithFrame:NSMakeRect(496, 208, 105, 31)];
        effectCover.wantsLayer = YES;
        effectCover.layer.backgroundColor = [NSColor colorWithRed:0 green:0.10 blue:0.27 alpha:1].CGColor;
        [content addSubview:effectCover];

        NSMutableArray *slots = [NSMutableArray arrayWithCapacity:6];
        for (NSInteger slot = 0; slot < 6; slot++) {
            NSInteger column = slot % 2, row = slot / 2;
            PetBagSlotButton *button = [[PetBagSlotButton alloc] initWithFrame:
                NSMakeRect(20 + column * 132, 47 + (2 - row) * 73, 126, 73)];
            button.target = self; button.action = @selector(selectManagerSlot:); button.bordered = NO;
            button.toolTip = @"选择桌宠"; [content addSubview:button]; [slots addObject:button];
        }
        self.managerSlots = slots;

        NSButton *previous = [NSButton buttonWithTitle:@"◀" target:self action:@selector(showPreviousManagerPage:)];
        NSButton *next = [NSButton buttonWithTitle:@"▶" target:self action:@selector(showNextManagerPage:)];
        previous.frame = NSMakeRect(17, 280, 28, 24); next.frame = NSMakeRect(82, 280, 28, 24);
        previous.bordered = NO; next.bordered = NO;
        previous.contentTintColor = NSColor.whiteColor; next.contentTintColor = NSColor.whiteColor;
        self.managerPageLabel = [NSTextField labelWithString:@"1 / 1"];
        self.managerPageLabel.frame = NSMakeRect(45, 283, 38, 18);
        self.managerPageLabel.textColor = NSColor.whiteColor; self.managerPageLabel.alignment = NSTextAlignmentCenter;
        self.managerPageButtons = @[previous, next];
        [content addSubview:previous]; [content addSubview:self.managerPageLabel]; [content addSubview:next];

        self.managerPreview = [[NSImageView alloc] initWithFrame:NSMakeRect(324, 191, 100, 120)];
        self.managerPreview.imageScaling = NSImageScaleProportionallyDown;
        self.managerPreview.imageAlignment = NSImageAlignCenter; [content addSubview:self.managerPreview];
        NSMutableArray *infoLabels = [NSMutableArray arrayWithCapacity:6];
        NSArray<NSValue *> *infoFrames = @[
            [NSValue valueWithRect:NSMakeRect(438, 304, 150, 18)],
            [NSValue valueWithRect:NSMakeRect(438, 282, 102, 18)],
            [NSValue valueWithRect:NSMakeRect(438, 260, 72, 18)],
            [NSValue valueWithRect:NSMakeRect(438, 238, 150, 18)],
            [NSValue valueWithRect:NSMakeRect(438, 216, 72, 18)],
            [NSValue valueWithRect:NSMakeRect(438, 194, 150, 18)]
        ];
        for (NSInteger i = 0; i < 6; i++) {
            NSTextField *label = [NSTextField labelWithString:@""];
            label.frame = infoFrames[i].rectValue;
            label.textColor = NSColor.whiteColor; label.lineBreakMode = NSLineBreakByTruncatingTail;
            label.font = [NSFont systemFontOfSize:14];
            [content addSubview:label]; [infoLabels addObject:label];
        }
        self.managerInfoLabels = infoLabels; self.managerDetail = infoLabels[1];
        self.managerFeatureLabel = [NSTextField labelWithString:@""];
        self.managerFeatureLabel.frame = NSMakeRect(508, 260, 94, 18);
        [content addSubview:self.managerFeatureLabel];
        self.managerTypeIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        self.managerTypeIcon.imageScaling = NSImageScaleProportionallyDown;
        self.managerTypeIcon.imageAlignment = NSImageAlignCenter;
        [content addSubview:self.managerTypeIcon];
        self.managerGenderIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 284, 18, 20)];
        self.managerGenderIcon.imageScaling = NSImageScaleProportionallyDown;
        self.managerGenderIcon.imageAlignment = NSImageAlignCenter;
        [content addSubview:self.managerGenderIcon];
        self.managerEvolutionButton = [NSButton buttonWithTitle:@"" target:nil action:nil];
        self.managerEvolutionButton.frame = NSMakeRect(392, 289, 62, 31);
        self.managerEvolutionButton.bordered = NO;
        [content addSubview:self.managerEvolutionButton];

        NSMutableArray *statLabels = [NSMutableArray arrayWithCapacity:6];
        NSArray<NSValue *> *statFrames = @[
            [NSValue valueWithRect:NSMakeRect(346, 170, 62, 18)], [NSValue valueWithRect:NSMakeRect(482, 170, 62, 18)],
            [NSValue valueWithRect:NSMakeRect(346, 146, 62, 18)], [NSValue valueWithRect:NSMakeRect(482, 146, 62, 18)],
            [NSValue valueWithRect:NSMakeRect(346, 122, 62, 18)], [NSValue valueWithRect:NSMakeRect(482, 122, 62, 18)]
        ];
        for (NSValue *frame in statFrames) {
            NSTextField *label = [NSTextField labelWithString:@""];
            label.frame = frame.rectValue; label.textColor = NSColor.whiteColor;
            label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
            label.alignment = NSTextAlignmentLeft; label.lineBreakMode = NSLineBreakByTruncatingTail;
            [content addSubview:label]; [statLabels addObject:label];
        }
        self.managerStatLabels = statLabels;
        NSMutableArray *evLabels = [NSMutableArray arrayWithCapacity:6];
        for (NSValue *frame in @[
            [NSValue valueWithRect:NSMakeRect(430, 170, 34, 18)], [NSValue valueWithRect:NSMakeRect(566, 170, 34, 18)],
            [NSValue valueWithRect:NSMakeRect(430, 146, 34, 18)], [NSValue valueWithRect:NSMakeRect(566, 146, 34, 18)],
            [NSValue valueWithRect:NSMakeRect(430, 122, 34, 18)], [NSValue valueWithRect:NSMakeRect(566, 122, 34, 18)]
        ]) {
            NSTextField *label = [NSTextField labelWithString:@""];
            label.frame = frame.rectValue; label.textColor = NSColor.yellowColor;
            label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
            [content addSubview:label]; [evLabels addObject:label];
        }
        self.managerEVLabels = evLabels;
        NSMutableArray *skillViews = [NSMutableArray arrayWithCapacity:4];
        for (NSInteger i = 0; i < 4; i++) {
            PetBagSkillView *skill = [[PetBagSkillView alloc] initWithFrame:
                NSMakeRect(324 + (i % 2) * 138, 69 - (i / 2) * 57, 129, 49)];
            skill.target = self; skill.action = @selector(replaceManagedPetSkills:);
            [content addSubview:skill]; [skillViews addObject:skill];
        }
        self.managerSkillViews = skillViews;
        PetBagButton *close = [[PetBagButton alloc] initWithFrame:NSMakeRect(262, 289, 30, 30)];
        close.target = self; close.action = @selector(closePetManager:); close.bordered = NO;
        close.imageScaling = NSImageScaleProportionallyDown;
        [close setUpImage:PetBagInfoImage(@"close-up") overImage:PetBagInfoImage(@"close-over")];
        close.toolTip = @"关闭"; [content addSubview:close];
        NSArray<NSString *> *tips = @[@"身边跟随", @"设为首选", @"更换技能", @"随机攻击开关",
            @"增加桌宠", @"删除桌宠", @"编辑桌宠", @"清理缓存"];
        NSArray<NSString *> *actions = @[NSStringFromSelector(@selector(toggleManagedPetVisibility:)),
            NSStringFromSelector(@selector(makeManagedPetPrimary:)), NSStringFromSelector(@selector(replaceManagedPetSkills:)),
            NSStringFromSelector(@selector(toggleManagedPetRandomAttack:)), NSStringFromSelector(@selector(addManagedPet:)),
            NSStringFromSelector(@selector(removeManagedPet:)), NSStringFromSelector(@selector(editManagedPet:)),
            NSStringFromSelector(@selector(showCachePanel:))];
        NSArray<NSString *> *names = @[@"follow-show", @"default", @"countermark", @"skill-stone",
            @"pet-storage", @"storage", @"item", @"cure"];
        NSArray<NSValue *> *frames = @[
            [NSValue valueWithRect:NSMakeRect(20, 1, 32, 34)], [NSValue valueWithRect:NSMakeRect(53, 2, 36, 31)],
            [NSValue valueWithRect:NSMakeRect(79, -6, 48, 48)], [NSValue valueWithRect:NSMakeRect(121, 0, 32, 36)],
            [NSValue valueWithRect:NSMakeRect(155, 1, 34, 33)], [NSValue valueWithRect:NSMakeRect(190, 1, 34, 34)],
            [NSValue valueWithRect:NSMakeRect(224, 2, 34, 32)], [NSValue valueWithRect:NSMakeRect(259, 1, 34, 34)]
        ];
        for (NSInteger i = 0; i < tips.count; i++) {
            PetBagButton *button = [[PetBagButton alloc] initWithFrame:frames[i].rectValue];
            button.target = self; button.action = NSSelectorFromString(actions[i]); button.bordered = NO;
            button.imagePosition = NSImageOnly; button.imageScaling = NSImageScaleProportionallyDown;
            [button setUpImage:PetBagButtonImage(names[i], @"up")
                     overImage:PetBagButtonImage(names[i], @"over")];
            button.toolTip = tips[i]; button.accessibilityLabel = tips[i]; [content addSubview:button];
            if (i == 0) self.managerFollowButton = button;
        }
        [self.managerWindow center];
    }
    if (self.managerSelectedIndex < 0 || self.managerSelectedIndex >= (NSInteger)self.petViews.count)
        self.managerSelectedIndex = 0;
    self.managerPage = self.managerSelectedIndex / 6;
    [self refreshManagerSlots];
    [self updateManagerDetails];
    [NSApp activateIgnoringOtherApps:YES]; [self.managerWindow makeKeyAndOrderFront:nil];
}

- (void)installStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSImage *icon = NSApp.applicationIconImage.copy;
    icon.size = NSMakeSize(18, 18);
    self.statusItem.button.image = icon;
    self.statusItem.button.toolTip = @"赛尔号桌宠";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"赛尔号桌宠"];
    NSMenuItem *manager = [menu addItemWithTitle:@"宠物管理…"
        action:@selector(showPetManager:) keyEquivalent:@","];
    manager.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [menu addItemWithTitle:@"退出赛尔号桌宠"
        action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    self.statusItem.menu = menu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self installStatusItem];
    self.petViews = [NSMutableArray array]; self.petPanels = [NSMutableArray array];
    NSArray *launchRecords = RunningTests() ? @[@{ @"id": @"test-pet", @"name": @"皮皮",
        @"petID": @"1", @"size": @1, @"createdAt": @0, @"visible": @YES,
        @"freeMovement": @NO, @"randomAttack": @NO }] : [self savedPetRecords];
    for (NSDictionary *savedRecord in launchRecords) {
        NSMutableDictionary *record = savedRecord.mutableCopy;
        NSString *petID = [record[@"petID"] description] ?: @"1";
        NSURL *resourceURL = [self readyResourceForPetID:petID];
        if (!resourceURL) resourceURL = [self installPetID:petID error:nil];
        if (!resourceURL) { record[@"petID"] = @"1"; resourceURL = NSBundle.mainBundle.resourceURL; }
        [self addPetFromRecord:record resourceURL:resourceURL];
    }
    if (self.petViews.count == 0) { [NSApp terminate:nil]; return; }
    self.petView = self.petViews.firstObject; self.panel = self.petPanels.firstObject;
    [self savePetInstances];
    NSPoint mouse = NSEvent.mouseLocation; NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(mouse, candidate.frame)) { screen = candidate; break; }
    for (PetView *view in self.petViews) if (view.desktopVisible) {
        [NSApp activateIgnoringOtherApps:YES]; [view.window makeKeyAndOrderFront:nil]; break;
    }

    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_STATUS_ITEM"]) {
        BOOL valid = NSApp.activationPolicy == NSApplicationActivationPolicyAccessory &&
            self.statusItem.button.image && self.statusItem.menu.numberOfItems == 3;
        exit(valid ? 0 : 14);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_SKILL_MENU"]) {
        NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:0];
        NSMenu *menu = [self.petView menuForEvent:event];
        BOOL valid = self.petView.selectedSkillIDs.count == 4 &&
            [PetActionForMoveInfo(@[@"", @0, @0, @1]) isEqualToString:@"attack"] &&
            [PetActionForMoveInfo(@[@"", @0, @0, @2]) isEqualToString:@"sa"] &&
            [PetActionForMoveInfo(@[@"", @0, @0, @4]) isEqualToString:@"cp"] &&
            [menu itemWithTitle:@"自定义动作名称…"] == nil && [menu itemWithTitle:@"重置动作名称"] == nil;
        for (NSUInteger i = 0; valid && i < self.petView.selectedSkillIDs.count; i++) {
            NSNumber *skillID = self.petView.selectedSkillIDs[i]; NSArray *move = PetMoveInfo(skillID);
            NSMenuItem *item = menu.itemArray[i];
            valid = [item.title isEqualToString:move[0]] && [item.representedObject isEqual:skillID] &&
                item.action == @selector(playConfiguredSkill:);
        }
        if (valid) {
            NSMenuItem *first = menu.itemArray.firstObject; [self.petView playConfiguredSkill:first];
            valid = [self.petView.currentAction isEqualToString:PetActionForMoveInfo(PetMoveInfo(first.representedObject))];
        }
        [self.petView menuDidClose:menu]; exit(valid ? 0 : 15);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_LONG_NAME"]) {
        self.petView.petID = @"309"; self.petView.displayName = PetDefaultName(@"309");
        [self showPetManager:nil];
        CGFloat required = ceil(self.managerInfoLabels[1].attributedStringValue.size.width) + 6;
        BOOL valid = [self.managerInfoLabels[1].stringValue containsString:@"魔焰猩猩"] &&
            NSWidth(self.managerInfoLabels[1].frame) >= required && !self.managerGenderIcon.hidden &&
            NSMaxX(self.managerGenderIcon.frame) <= 600;
        exit(valid ? 0 : 16);
    }

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
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_MULTI"]) {
        NSArray *oldRecords = [NSUserDefaults.standardUserDefaults arrayForKey:PetInstancesKey];
        NSUInteger before = self.petViews.count;
        NSDictionary *record = @{ @"id": @"__multi_test", @"name": @"第二只",
                                  @"petID": self.petView.petID, @"size": @0.5,
                                  @"visible": @NO, @"freeMovement": @NO, @"randomAttack": @YES };
        PetView *second = [self addPetFromRecord:record
                                     resourceURL:[self readyResourceForPetID:self.petView.petID]];
        [self savePetInstances];
        NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:PetInstancesKey];
        [self showPetManager:nil];
        NSView *managerContent = self.managerWindow.contentView;
        NSBitmapImageRep *managerRender = [managerContent bitmapImageRepForCachingDisplayInRect:managerContent.bounds];
        [managerContent cacheDisplayInRect:managerContent.bounds toBitmapImageRep:managerRender];
        BOOL rendered = [[managerRender representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:@"/tmp/seer-manager-render.png" atomically:YES];
        NSImage *normalButtonImage = self.managerFollowButton.image;
        NSEvent *hoverEvent = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:0 pressure:0];
        [self.managerFollowButton mouseEntered:hoverEvent];
        BOOL originalHover = self.managerFollowButton.image == self.managerFollowButton.overImage &&
            self.managerFollowButton.image != normalButtonImage;
        [self.managerFollowButton mouseExited:hoverEvent];
        BOOL hidden = !second.desktopVisible && !second.window.visible &&
            ![saved.lastObject[@"visible"] boolValue] && !second.timer &&
            !second.movementTimer && !second.randomAttackTimer;
        [self setPetView:second desktopVisible:YES];
        BOOL shown = second.desktopVisible && second.window.visible && second.randomAttackTimer;
        NSUInteger occupiedSlots = 0;
        for (PetBagSlotButton *slot in self.managerSlots) if (slot.occupied && !slot.hidden) occupiedSlots++;
        NSInteger remaining = MAX(0, (NSInteger)self.petViews.count - self.managerPage * 6);
        BOOL originalEmptySlots = occupiedSlots == (NSUInteger)MIN(6, remaining) &&
            [self.managerSlots filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PetBagSlotButton *slot, NSDictionary *_) {
                return slot.hidden;
            }]].count == 0;
        NSArray *recommended5000 = PetDefaultSkillIDs(@"5000");
        BOOL skillConfig = self.petView.selectedSkillIDs.count > 0 &&
            [self.managerSkillViews.firstObject.skillName isEqualToString:
                PetMoveInfo(self.petView.selectedSkillIDs.firstObject).firstObject];
        BOOL propertyIconsValid = YES;
        for (PetBagSkillView *skillView in self.managerSkillViews) {
            NSArray *move = PetMoveInfo(skillView.skillID);
            if (move.count > 3 && [move[3] integerValue] == 4)
                propertyIconsValid = propertyIconsValid && [skillView.typeIcon.TIFFRepresentation
                    isEqualToData:PetTypeIconNamed(@"prop").TIFFRepresentation];
        }
        BOOL independent = second && self.petViews.count == before + 1 &&
            ![second.instanceID isEqualToString:self.petView.instanceID] &&
            ![second.displayName isEqualToString:self.petView.displayName] &&
            second.sizeMultiplier == 0.5 && !second.freeMovementEnabled && second.randomAttackEnabled &&
            self.managerSlots.count == 6 && self.managerPageLabel.stringValue.length > 0 &&
            [self.managerSlots.firstObject isKindOfClass:PetBagSlotButton.class] &&
            NSEqualSizes(self.managerSlots.firstObject.frame.size, NSMakeSize(126, 73)) &&
            self.petView.bagImage &&
            ((PetBagSlotButton *)self.managerSlots.firstObject).petImage == self.petView.bagImage &&
            self.managerInfoLabels.count == 6 && self.managerStatLabels.count == 6 &&
            self.managerEVLabels.count == 6 && self.managerSkillViews.count == 4 &&
            second.createdAt > 0 && NSMinY(self.managerPreview.frame) == 191 &&
            [self.managerFeatureLabel.stringValue hasPrefix:@"特性:"] &&
            [self.managerStatLabels[0].stringValue isEqualToString:[NSString stringWithFormat:@"攻击:%@",
                PetBaseStats(self.petView.petID).firstObject]] &&
            [PetDefaultName(@"095") isEqualToString:@"尼布"] &&
            [PetDefaultName(@"300") isEqualToString:@"谱尼"] &&
            [PetDefaultName(@"5000") isEqualToString:@"圣灵谱尼"] &&
            [recommended5000 isEqualToArray:@[@31140, @25678, @25679, @31142]] &&
            skillConfig && second.selectedSkillIDs.count > 0 && [saved.lastObject[@"skills"] count] > 0 &&
            self.managerTypeIcon.image != nil &&
            [self.managerTypeIcon.toolTip containsString:PetTypeName(PetMetadata(self.petView.petID)[0])] &&
            self.managerSkillViews.firstObject.typeIcon != nil &&
            propertyIconsValid &&
            fabs(NSMinX(self.managerTypeIcon.frame) - NSMaxX(self.managerInfoLabels[1].frame) - 6) < 0.1 &&
            fabs(NSMinX(self.managerGenderIcon.frame) - NSMaxX(self.managerTypeIcon.frame) - 6) < 0.1 &&
            PetGenderIcon(1) != nil &&
            NSMaxX(self.managerGenderIcon.frame) <= NSWidth(self.managerWindow.contentView.bounds) - 10 &&
            self.managerEvolutionButton.toolTip.length > 0 &&
            [self.managerInfoLabels[0].stringValue hasPrefix:@"序号:"] &&
            [self.managerInfoLabels[1].stringValue hasPrefix:@"名字:"] &&
            [self.managerInfoLabels[2].stringValue hasPrefix:@"等级:"] &&
            [self.managerInfoLabels[3].stringValue hasPrefix:@"升级所需经验值:"] &&
            [self.managerInfoLabels[4].stringValue hasPrefix:@"性格:"] &&
            [self.managerInfoLabels[5].stringValue hasPrefix:@"获得时间:"] &&
            self.managerFollowButton.upImage && self.managerFollowButton.overImage &&
            fabs(NSHeight(managerContent.bounds) - 329.0) < 0.1 &&
            NSEqualSizes(self.managerPreview.frame.size, NSMakeSize(100, 120)) &&
            self.managerPreview.image == self.petView.bagImage && self.managerDetail.stringValue.length > 0 &&
            saved.count == self.petViews.count &&
            hidden && shown && rendered && originalHover && originalEmptySlots;
        [second.window orderOut:nil];
        [self.petPanels removeLastObject]; [self.petViews removeLastObject];
        [NSUserDefaults.standardUserDefaults setObject:oldRecords forKey:PetInstancesKey];
        exit(independent ? 0 : 13);
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

        exit(movedLeft && usedLeftWalk && stoppedLeft && bounced && usedRightWalk && sameWalkScale && mirrored &&
             mirroredActionAligned ? 0 : 9);
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
        NSURL *bagURL = [[[url URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@"bag-front"]
                         URLByAppendingPathComponent:@"1.png"];
        NSValue *bagBounds = [self.petView visibleBoundsAtURL:bagURL maxSide:MaxRasterSide];
        BOOL bagTrimmed = bagBounds && NSEqualSizes(self.petView.bagImage.size, bagBounds.rectValue.size);
        BOOL movementLoaded = ![testPetID isEqualToString:@"1"] ||
            (self.petView.walkLeftFrames.count > 1 && self.petView.walkRightFrames.count > 1);
        BOOL pet9Valid = ![testPetID isEqualToString:@"9"] ||
            (self.petView.idleFrames.count == 16 && self.petView.idleImage.size.height >= 400);
        BOOL pet70Valid = ![testPetID isEqualToString:@"70"] ||
            (self.petView.idleFrames.count == 17 &&
             self.petView.actionFrames[@"attack"].count == 75 && self.petView.actionFrames[@"sa"].count == 75 &&
             self.petView.actionFrames[@"cp"].count == 74 && self.petView.actionFrames[@"hited"].count == 8);
        BOOL pet300Valid = ![testPetID isEqualToString:@"300"] ||
            (self.petView.idleFrames.count == 32 && self.petView.idleImage.size.width >= 700 &&
             self.petView.idleImage.size.height >= 400);
        exit(loaded && bagTrimmed && movementLoaded &&
             (![testPetID isEqualToString:@"1"] || self.petView.idleFrames.count > 1) &&
             pet9Valid && pet70Valid && pet300Valid ? 0 : 4);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_SCALE"]) {
        NSSize idleSize = self.panel.frame.size;
        [self.petView play:@"attack"];
        NSSize actionSize = self.panel.frame.size;
        NSSize canvas = self.petView.currentImage.size;
        BOOL complete = canvas.width * self.petView.currentScale <= actionSize.width &&
                        canvas.height * self.petView.currentScale <= actionSize.height &&
                        actionSize.width >= idleSize.width && actionSize.height >= idleSize.height;
        NSNumber *attackSourceScale = self.petView.sourceRasterScales[@"attack"] ?: @1.0;
        BOOL sameSourceScale = fabs(self.petView.currentScale * attackSourceScale.doubleValue -
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
        if (!(complete && sameSourceScale && aligned && sizesValid))
            fprintf(stderr, "scale test: complete=%d source=%d aligned=%d sizes=%d action=%g*%g idle=%g*%g\n",
                complete, sameSourceScale, aligned, sizesValid, self.petView.currentScale,
                attackSourceScale.doubleValue, self.petView.displayScale,
                self.petView.idleRasterScale);
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

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self savePetInstances];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new]; application.delegate = delegate;
        NSMenu *mainMenu = [NSMenu new]; NSMenuItem *appItem = [NSMenuItem new];
        [mainMenu addItem:appItem]; NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"赛尔号桌宠"];
        NSMenuItem *manager = [appMenu addItemWithTitle:@"宠物管理…"
            action:@selector(showPetManager:) keyEquivalent:@","];
        manager.target = delegate; [appMenu addItem:NSMenuItem.separatorItem];
        NSMenuItem *quit = [appMenu addItemWithTitle:@"退出赛尔号桌宠"
            action:@selector(terminate:) keyEquivalent:@"q"];
        quit.target = application; appItem.submenu = appMenu; application.mainMenu = mainMenu;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory]; [application run];
    }
    return 0;
}
