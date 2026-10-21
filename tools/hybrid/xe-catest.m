// xe-catest: one CoreAnimation primitive per tile (corners, shadow, shape fill/stroke, CATextLayer, gradient, icon,
// mask, blur, CG drawing sync and async), composed by CARenderer (the engine of WindowServer) into a Metal texture.
// Prints the mean colour and the share of near-black pixels per tile and writes the grid to a PNG, so the Iris Xe can
// be compared with the RTX. HYB-11: the simple Metal tests pass while text, icons and triangles break on screen.
//   clang -fobjc-arc -o xe-catest xe-catest.m -framework AppKit -framework QuartzCore -framework Metal
//   ./xe-catest out.png
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include <stdio.h>

enum { T = 120, N = 4, W = T * N };

@interface Drawer : NSObject <CALayerDelegate>
@end
@implementation Drawer
- (void)drawLayer:(CALayer *)l inContext:(CGContextRef)c {   // what AppKit views do: CG text and paths
    CGContextSetRGBFillColor(c, 0, 0.6, 0, 1);
    CGContextMoveToPoint(c, 10, 10); CGContextAddLineToPoint(c, 60, 90); CGContextAddLineToPoint(c, 110, 10); CGContextFillPath(c);
    CGContextSetRGBStrokeColor(c, 0, 0, 1, 1); CGContextSetLineWidth(c, 3); CGContextStrokeEllipseInRect(c, CGRectMake(70, 60, 40, 40));
    NSAttributedString *s = [[NSAttributedString alloc] initWithString:@"Ag12"
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:22], NSForegroundColorAttributeName: NSColor.blackColor}];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    CGContextSetTextPosition(c, 8, 92); CTLineDraw(line, c); CFRelease(line);
}
@end

static CGPathRef triangle(void) {
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, 10, 10); CGPathAddLineToPoint(p, NULL, 60, 100); CGPathAddLineToPoint(p, NULL, 110, 10); CGPathCloseSubpath(p);
    return p;
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 2) { printf("usage: xe-catest out.png\n"); return 1; }
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) { printf("no Metal device\n"); return 1; }
    printf("device: %s\n", dev.name.UTF8String);
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:W mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; d.storageMode = MTLStorageModeManaged;
    id<MTLTexture> target = [dev newTextureWithDescriptor:d];
    CARenderer *r = [CARenderer rendererWithMTLTexture:target
                     options:@{kCARendererColorSpace: (__bridge id)CGColorSpaceCreateWithName(kCGColorSpaceSRGB)}];
    CALayer *root = [CALayer layer]; root.frame = CGRectMake(0, 0, W, W); root.backgroundColor = CGColorGetConstantColor(kCGColorWhite);
    Drawer *drawer = [Drawer new];
    const char *names[N * N] = {"solid", "corner radius", "border", "shadow", "shape fill", "shape stroke", "text 36",
        "text 12", "gradient", "icon", "opacity 0.5", "shape mask", "blur filter", "rotated 30", "CG draw sync", "CG draw async"};
    CGColorRef red = CGColorCreateGenericRGB(0.9, 0.1, 0.1, 1), blue = CGColorCreateGenericRGB(0.1, 0.2, 0.9, 1);
    for (int i = 0; i < N * N; i++) {
        CGRect cell = CGRectMake((i % N) * T, W - (i / N + 1) * T, T, T);   // tile 0 top left
        CALayer *l;
        switch (i) {
        case 4: case 5: case 11: { CAShapeLayer *s = [CAShapeLayer layer]; s.path = triangle(); l = s;
            if (i == 4) s.fillColor = red;
            if (i == 5) { s.fillColor = NULL; s.strokeColor = blue; s.lineWidth = 5; }
            if (i == 11) { l = [CALayer layer]; l.backgroundColor = blue; s.fillColor = CGColorGetConstantColor(kCGColorBlack); l.mask = s; }
            break; }
        case 6: case 7: { CATextLayer *t = [CATextLayer layer]; t.string = @"Ag12 xyz"; t.fontSize = i == 6 ? 36 : 12;
            t.foregroundColor = CGColorGetConstantColor(kCGColorBlack); t.wrapped = YES; t.contentsScale = 1; l = t; break; }
        case 8: { CAGradientLayer *g = [CAGradientLayer layer]; g.colors = @[(__bridge id)red, (__bridge id)blue]; l = g; break; }
        default: l = [CALayer layer];
        }
        l.frame = CGRectInset(cell, 0, 0);
        if (i < 4 || i == 10 || i == 12 || i == 13) { l.frame = CGRectInset(cell, 20, 20); l.backgroundColor = i == 10 ? blue : red; }
        if (i == 1) { l.cornerRadius = 30; l.masksToBounds = YES; }
        if (i == 2) { l.backgroundColor = NULL; l.borderWidth = 6; l.borderColor = blue; }
        if (i == 3) { l.shadowOpacity = 1; l.shadowRadius = 8; l.shadowOffset = CGSizeMake(4, -4); }
        if (i == 9) { NSImage *ic = [[NSWorkspace sharedWorkspace] iconForFile:@"/System/Applications/Calculator.app"];
            ic.size = NSMakeSize(T, T); l.contents = [ic layerContentsForContentsScale:1.0]; }
        if (i == 10) l.opacity = 0.5;
        if (i == 12) l.filters = @[[CIFilter filterWithName:@"CIGaussianBlur" withInputParameters:@{kCIInputRadiusKey: @6}]];
        if (i == 13) { l.transform = CATransform3DMakeRotation(M_PI / 6, 0, 0, 1); l.allowsEdgeAntialiasing = YES; }
        if (i >= 14) { l.delegate = drawer; l.drawsAsynchronously = i == 15; [l setNeedsDisplay]; }
        [root addSublayer:l];
    }
    r.layer = root; r.bounds = root.frame;
    [CATransaction flush];
    for (int f = 0; f < 3; f++) {   // async drawing and the icon may need more than one frame
        [r beginFrameAtTime:CACurrentMediaTime() timeStamp:NULL]; [r addUpdateRect:r.bounds]; [r render]; [r endFrame];
    }
    id<MTLCommandBuffer> cb = [[dev newCommandQueue] commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e synchronizeResource:target]; [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    if (cb.error) { printf("GPU error: %s\n", cb.error.description.UTF8String); return 1; }
    uint8_t *px = malloc(W * W * 4);
    [target getBytes:px bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, W) mipmapLevel:0];
    for (int y = 0; y < W / 2; y++) for (int x = 0; x < W * 4; x++) {   // CARenderer leaves row 0 at the bottom: flip
        uint8_t t = px[y * W * 4 + x]; px[y * W * 4 + x] = px[(W - 1 - y) * W * 4 + x]; px[(W - 1 - y) * W * 4 + x] = t;
    }
    for (int i = 0; i < N * N; i++) {   // tile i at column i%N, row i/N from the top
        long s[3] = {0}, black = 0;
        for (int y = (i / N) * T; y < (i / N + 1) * T; y++) for (int x = (i % N) * T; x < (i % N + 1) * T; x++) {
            uint8_t *p = px + (y * W + x) * 4;
            s[0] += p[2]; s[1] += p[1]; s[2] += p[0];
            if (p[0] < 30 && p[1] < 30 && p[2] < 30) black++;
        }
        printf("%2d %-14s mean RGB=(%3ld,%3ld,%3ld) black=%5.1f%%\n", i, names[i], s[0] / (T * T), s[1] / (T * T), s[2] / (T * T), 100.0 * black / (T * T));
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:W bitsPerSample:8
        samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
    for (int k = 0; k < W * W; k++) { rep.bitmapData[k*4] = px[k*4+2]; rep.bitmapData[k*4+1] = px[k*4+1]; rep.bitmapData[k*4+2] = px[k*4]; rep.bitmapData[k*4+3] = 255; }
    if (![[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[1]) atomically:YES]) {
        printf("cannot write %s\n", argv[1]); return 1;
    }
    printf("png: %s\n", argv[1]);
} return 0; }
