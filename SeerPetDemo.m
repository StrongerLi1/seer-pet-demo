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
static const CGFloat MovementFPS = 30.0;
static const CGFloat MovementSpeed = 60.0;
static void SetError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"SeerPet" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface PetView : NSView <NSMenuDelegate>
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<NSImage *> *> *actionFrames;
@property(nonatomic, strong) NSArray<NSImage *> *idleFrames;
@property(nonatomic, strong) NSArray<NSImage *> *currentFrames;
@property(nonatomic, strong) NSImage *currentImage;
@property(nonatomic, strong) NSImage *idleImage;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSTimer *movementTimer;
@property(nonatomic, strong) NSDictionary<NSString *, NSValue *> *actionAnchors;
@property(nonatomic, copy) NSString *petID;
@property(nonatomic, copy) NSString *currentAction;
@property(nonatomic) CGFloat displayScale;
@property(nonatomic) CGFloat currentScale;
@property(nonatomic) CGFloat idleFPS;
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
@property(nonatomic) BOOL movementPaused;
@property(nonatomic) BOOL facingLeft;
- (instancetype)initWithFrame:(NSRect)frame resourceURL:(NSURL *)resourceURL petID:(NSString *)petID;
- (BOOL)loadFramesFromURL:(NSURL *)resourceURL petID:(NSString *)petID;
- (void)play:(NSString *)action;
- (void)startIdlePlayback;
- (void)changeSize:(NSMenuItem *)sender;
- (void)movementTick:(NSTimer *)timer;
- (NSString *)actionNameForKey:(NSString *)action;
- (CGFloat)orientedAnchorX:(CGFloat)x imageWidth:(CGFloat)width;
@end

@implementation PetView

- (NSSize)pixelSizeAtURL:(NSURL *)url {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return NSZeroSize;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) return NSZeroSize;
    NSSize size = NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image));
    CGImageRelease(image);
    return size;
}

- (NSValue *)visibleBoundsAtURL:(NSURL *)url {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
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

- (NSImage *)imageAtURL:(NSURL *)url croppedTo:(NSRect)bounds {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) return nil;
    CGRect imageBounds = CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image));
    CGImageRef cropped = CGImageCreateWithImageInRect(image, CGRectIntersection(NSRectToCGRect(bounds), imageBounds));
    CGImageRelease(image);
    if (!cropped) return nil;
    NSImage *result = [[NSImage alloc] initWithCGImage:cropped
                                                 size:NSMakeSize(CGImageGetWidth(cropped), CGImageGetHeight(cropped))];
    CGImageRelease(cropped);
    return result;
}

- (instancetype)initWithFrame:(NSRect)frame resourceURL:(NSURL *)resourceURL petID:(NSString *)petID {
    if ((self = [super initWithFrame:frame])) {
        CGFloat savedSize = [NSUserDefaults.standardUserDefaults doubleForKey:@"petSize"];
        self.sizeMultiplier = [PetSizes() containsObject:@(savedSize)] ? savedSize : 1.0;
        self.freeMovementEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"freeMovement"];
        self.movementDirection = 1.0;
        if (![self loadFramesFromURL:resourceURL petID:petID]) return nil;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        [self updateIdleBob];
        [self startIdlePlayback];
        [self updateMovementTimer];
    }
    return self;
}

- (BOOL)loadFramesFromURL:(NSURL *)resourceURL petID:(NSString *)petID {
    NSMutableDictionary<NSString *, NSArray<NSImage *> *> *loaded = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSValue *> *anchors = [NSMutableDictionary dictionary];
    NSImage *newIdleImage = nil;
    NSMutableArray<NSString *> *allActions = Actions().mutableCopy;
    [allActions addObject:@"idle"];
    for (NSString *action in allActions) {
        NSURL *directory = [[resourceURL URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:action];
        NSArray<NSURL *> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory
                                                              includingPropertiesForKeys:nil options:0 error:nil];
        urls = [[urls filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
            return [url.pathExtension.lowercaseString isEqualToString:@"png"];
        }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            return [a.lastPathComponent compare:b.lastPathComponent options:NSNumericSearch];
        }];
        if (urls.count == 0) {
            if ([action isEqualToString:@"idle"]) continue;
            return NO;
        }

        // ponytail: one action gets one coordinate system; per-frame cropping causes zooming and drift.
        NSMutableArray *boundsByFrame = [NSMutableArray arrayWithCapacity:urls.count];
        NSRect unionBounds = NSZeroRect;
        BOOL hasVisibleFrame = NO;
        for (NSURL *url in urls) @autoreleasepool {
            NSValue *bounds = [self visibleBoundsAtURL:url];
            [boundsByFrame addObject:bounds ?: NSNull.null];
            if (bounds) {
                unionBounds = hasVisibleFrame ? NSUnionRect(unionBounds, bounds.rectValue) : bounds.rectValue;
                hasVisibleFrame = YES;
            }
        }
        if (!hasVisibleFrame) return NO;
        // Keep transparent source pixels around the union so interpolation cannot eat edge pixels.
        NSSize canvasSize = [self pixelSizeAtURL:urls.firstObject];
        unionBounds = NSIntersectionRect(NSInsetRect(unionBounds, -CropPadding, -CropPadding),
                                         NSMakeRect(0, 0, canvasSize.width, canvasSize.height));
        NSUInteger firstVisible = [boundsByFrame indexOfObjectPassingTest:^BOOL(id value, NSUInteger _, BOOL *__) {
            return value != NSNull.null;
        }];
        NSRect firstBounds = [boundsByFrame[firstVisible] rectValue];
        // Keep body placement stable by aligning the first visible frame at bottom-center.
        anchors[action] = [NSValue valueWithPoint:NSMakePoint(NSMidX(firstBounds) - NSMinX(unionBounds),
                                                              NSMaxY(firstBounds) - NSMinY(unionBounds))];

        NSMutableArray<NSImage *> *images = [NSMutableArray array];
        for (NSUInteger i = 0; i < urls.count; i++) @autoreleasepool {
            if (boundsByFrame[i] == NSNull.null) {
                if (images.lastObject) [images addObject:images.lastObject];
                continue;
            }
            NSImage *image = [self imageAtURL:urls[i] croppedTo:unionBounds];
            if (image) [images addObject:image];
        }
        if (images.count == 0) return NO;
        loaded[action] = images;
        if ([action isEqualToString:@"sa"]) {
            newIdleImage = [self imageAtURL:urls[firstVisible] croppedTo:firstBounds];
        }
    }
    [self.timer invalidate];
    self.timer = nil;
    self.currentFrames = nil;
    self.actionFrames = loaded;
    self.actionAnchors = anchors;
    self.petID = petID;
    self.idleFrames = loaded[@"idle"] ?: @[newIdleImage ?: loaded[@"sa"].firstObject];
    self.idleImage = self.idleFrames.firstObject;
    NSURL *idleFPSURL = [[[resourceURL URLByAppendingPathComponent:@"frames"] URLByAppendingPathComponent:@"idle"]
                         URLByAppendingPathComponent:@"idle-fps.txt"];
    CGFloat configuredIdleFPS = [[NSString stringWithContentsOfURL:idleFPSURL encoding:NSUTF8StringEncoding error:nil]
                                 doubleValue];
    self.idleFPS = configuredIdleFPS > 0 ? configuredIdleFPS : DefaultIdleFPS;
    self.idleAnchor = anchors[@"idle"] ? anchors[@"idle"].pointValue :
        NSMakePoint(self.idleImage.size.width / 2.0, self.idleImage.size.height);
    self.displayScale = IdleDisplaySize * self.sizeMultiplier /
        MAX(self.idleImage.size.width, self.idleImage.size.height);
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
    NSSize imageSize = self.currentImage.size;
    NSSize size = NSMakeSize(imageSize.width * self.currentScale, imageSize.height * self.currentScale);
    NSRect target = NSMakeRect(NSMidX(self.bounds) - size.width / 2.0, NSMidY(self.bounds) - size.height / 2.0,
                               size.width, size.height);
    [NSGraphicsContext saveGraphicsState];
    if (self.facingLeft) {
        NSAffineTransform *mirror = [NSAffineTransform transform];
        [mirror translateXBy:NSWidth(self.bounds) yBy:0]; [mirror scaleXBy:-1 yBy:1]; [mirror concat];
    }
    [self.currentImage drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                         fraction:1.0 respectFlipped:YES hints:nil];
    [NSGraphicsContext restoreGraphicsState];
}

- (CGFloat)orientedAnchorX:(CGFloat)x imageWidth:(CGFloat)width {
    return self.facingLeft ? width - x : x;
}

- (void)resizeWindowForAction:(NSString *)action {
    NSImage *canvas = self.actionFrames[action].firstObject;
    NSSize imageSize = canvas.size;
    self.currentScale = self.displayScale;
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
            self.currentImage = self.currentFrames[self.frameIndex++];
            [self setNeedsDisplay:YES];
            return;
        }
        [self.timer invalidate]; self.timer = nil;
        [self restoreIdleWindow];
        [self startIdlePlayback];
    } else self.currentImage = self.currentFrames[self.frameIndex++];
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
    [self.window setFrameOrigin:NSMakePoint(nextX, NSMinY(frame))];
    self.restingFrame = self.window.frame;
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
    if (!self.freeMovementEnabled) [self setFacingLeftIfNeeded:NO];
    [self updateMovementTimer];
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
@property(nonatomic) BOOL converting;
@end

@implementation AppDelegate
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

- (BOOL)runFFDec:(NSArray<NSString *> *)arguments {
    NSURL *resources = NSBundle.mainBundle.resourceURL;
    NSTask *task = [NSTask new];
    task.executableURL = [[resources URLByAppendingPathComponent:@"runtime/bin"] URLByAppendingPathComponent:@"java"];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-jar",
        [[resources URLByAppendingPathComponent:@"ffdec"] URLByAppendingPathComponent:@"ffdec.jar"].path, nil];
    [args addObjectsFromArray:arguments];
    task.arguments = args;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    @try {
        if (![task launchAndReturnError:nil]) return NO;
        [task waitUntilExit];
        return task.terminationStatus == 0;
    } @catch (__unused NSException *exception) { return NO; }
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

- (NSURL *)installPetID:(NSString *)petID error:(NSError **)error {
    NSURL *cached = [self cachedPetURL:petID];
    [self installIdleForPetID:petID intoPetURL:cached];
    NSURL *idleScanMarker = [cached URLByAppendingPathComponent:@".idle-scan-v1"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[[cached URLByAppendingPathComponent:@"frames"] path]] &&
        [[NSFileManager defaultManager] fileExistsAtPath:idleScanMarker.path]) return cached;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *temp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [fm createDirectoryAtURL:temp withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *swf = [temp URLByAppendingPathComponent:[petID stringByAppendingPathExtension:@"swf"]];
    NSURL *remote = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://seer.61.com/resource/fightResource/pet/swf/%@.swf", petID]];
    NSData *data = [NSData dataWithContentsOfURL:remote options:0 error:error];
    if (data.length < 4 || ![data writeToURL:swf options:NSDataWritingAtomic error:error]) {
        [fm removeItemAtURL:temp error:nil];
        if (data.length < 4) SetError(error, @"没有找到这个编号的 SWF 资源");
        return nil;
    }

    NSURL *symbols = [temp URLByAppendingPathComponent:@"symbols"];
    [fm createDirectoryAtURL:symbols withIntermediateDirectories:YES attributes:nil error:nil];
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
    if ([self runFFDec:@[@"-swf2xml", swf.path, xml.path]]) {
        idleInfo = [self idleInfoFromXMLURL:xml actionIDs:[ids subarrayWithRange:NSMakeRange(0, 3)]];
    }
    NSMutableArray<NSString *> *exportIDStrings = idStrings.mutableCopy;
    if (idleInfo) [exportIDStrings addObject:idleInfo[@"spriteID"].stringValue];

    NSURL *exportURL = [temp URLByAppendingPathComponent:@"export"];
    [fm createDirectoryAtURL:exportURL withIntermediateDirectories:YES attributes:nil error:nil];
    if (![self runFFDec:@[@"-selectid", [exportIDStrings componentsJoinedByString:@","], @"-ignorebackground",
                          @"-format", @"sprite:png", @"-export", @"sprite", exportURL.path, swf.path]]) {
        SetError(error, @"动作帧提取失败"); [fm removeItemAtURL:temp error:nil]; return nil;
    }

    NSURL *stagedPet = [temp URLByAppendingPathComponent:@"pet"];
    NSURL *stagedFrames = [stagedPet URLByAppendingPathComponent:@"frames"];
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
    [NSData.data writeToURL:[stagedPet URLByAppendingPathComponent:@".idle-scan-v1"] atomically:YES];
    [fm createDirectoryAtURL:cached.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [fm removeItemAtURL:cached error:nil];
    if (![fm moveItemAtURL:stagedPet toURL:cached error:error]) { [fm removeItemAtURL:temp error:nil]; return nil; }
    [self installIdleForPetID:petID intoPetURL:cached];
    [fm removeItemAtURL:temp error:nil];
    return cached;
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning; alert.messageText = @"更换精灵失败";
    alert.informativeText = message ?: @"未知错误"; [alert runModal];
}

- (void)changePet:(id)sender {
    if (self.converting) return;
    NSAlert *input = [NSAlert new];
    input.messageText = @"更换赛尔号精灵";
    input.informativeText = @"输入精灵编号。首次使用该编号需要联网下载并转换。";
    [input addButtonWithTitle:@"更换"]; [input addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
    field.placeholderString = @"例如：1"; field.stringValue = self.petView.petID ?: @"1"; input.accessoryView = field;
    if ([input runModal] != NSAlertFirstButtonReturn) return;
    NSString *petID = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (petID.length == 0 || [petID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound || petID.integerValue <= 0) {
        [self showError:@"编号只能是大于 0 的整数"]; return;
    }

    self.converting = YES;
    __block NSURL *petURL = nil;
    __block NSError *conversionError = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        petURL = [self installPetID:petID error:&conversionError];
        dispatch_async(dispatch_get_main_queue(), ^{ [NSApp abortModal]; });
    });
    NSAlert *progress = [NSAlert new];
    progress.messageText = [NSString stringWithFormat:@"正在准备 %@ 号精灵…", petID];
    progress.informativeText = @"首次转换通常需要几秒钟，请稍候。";
    [progress addButtonWithTitle:@"请稍候"].enabled = NO;
    [progress runModal];
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
        [self.panel setFrameOrigin:NSMakePoint(NSMinX(travel), NSMinY(frame))];
        self.petView.movementDirection = -1.0; [self.petView movementTick:nil];
        BOOL bounced = self.petView.movementDirection > 0 && !self.petView.facingLeft;
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
        exit(movedLeft && bounced && mirrored && mirroredActionAligned && customized && reset && isolated ? 0 : 9);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_MOUSE"]) {
        NSEvent *testEvent = [NSEvent new];
        [self.petView mouseDown:testEvent];
        BOOL started = self.petView.mouseHeld && self.petView.playingAction &&
            [self.petView.currentAction isEqualToString:@"hited"];
        [self.petView mouseUp:testEvent];
        exit(started && !self.petView.mouseHeld && !self.petView.playingAction ? 0 : 7);
    }
    NSString *testPetID = NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_PET_ID"];
    if (testPetID) {
        NSError *error = nil; NSURL *url = [self installPetID:testPetID error:&error];
        BOOL loaded = url && [self.petView loadFramesFromURL:url petID:testPetID];
        exit(loaded && (![testPetID isEqualToString:@"1"] || self.petView.idleFrames.count > 1) ? 0 : 4);
    }
    if (NSProcessInfo.processInfo.environment[@"SEER_PET_TEST_SCALE"]) {
        NSSize idleSize = self.panel.frame.size;
        [self.petView play:@"attack"];
        NSSize actionSize = self.panel.frame.size;
        BOOL expanded = actionSize.width > idleSize.width || actionSize.height > idleSize.height;
        BOOL aligned = hypot(self.petView.actionAnchorScreenPosition.x - self.petView.restingCenter.x,
                             self.petView.actionAnchorScreenPosition.y - self.petView.restingCenter.y) < 1.0;
        CGFloat originalSize = self.petView.sizeMultiplier;
        BOOL sizesValid = YES;
        for (NSNumber *value in PetSizes()) {
            NSMenuItem *item = [NSMenuItem new]; item.representedObject = value;
            [self.petView changeSize:item];
            sizesValid = sizesValid && fabs(self.panel.frame.size.width - BaseWindowSize * value.doubleValue) < 1.0;
        }
        NSMenuItem *restore = [NSMenuItem new]; restore.representedObject = @(originalSize);
        [self.petView changeSize:restore];
        exit(expanded && aligned && sizesValid ? 0 : 6);
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
            BOOL restored = !self.petView.playingAction && self.petView.currentFrames == self.petView.idleFrames &&
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
