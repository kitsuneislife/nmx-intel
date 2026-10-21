// xe-a8test: the glyph-atlas pattern of Terminal (A8Unorm 576x576, managed) and ghostty (R8Unorm 512x512, shared):
// small CPU replaceRegion blocks at non-zero offsets, then read by the GPU (shader read and nearest sample) and checked
// on the CPU. HYB-8: every other texture test passed on the Iris Xe while text glyphs were missing on screen.
//   clang -fobjc-arc -o xe-a8test xe-a8test.m -framework Metal -framework Foundation
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>

static NSString *SRC = @"#include <metal_stdlib>\nusing namespace metal;\n"
  "kernel void rd(texture2d<half, access::read> t [[texture(0)]], device uchar4 *o [[buffer(0)]], uint2 g [[thread_position_in_grid]]) {"
  "  if (g.x < t.get_width() && g.y < t.get_height()) o[g.y * t.get_width() + g.x] = uchar4(t.read(g) * 255.0h + 0.5h); }\n"
  "kernel void sm(texture2d<half> t [[texture(0)]], sampler s [[sampler(0)]], device uchar4 *o [[buffer(0)]], uint2 g [[thread_position_in_grid]]) {"
  "  if (g.x < t.get_width() && g.y < t.get_height()) o[g.y * t.get_width() + g.x] = uchar4(t.sample(s, (float2(g) + 0.5) / float2(t.get_width(), t.get_height())) * 255.0h + 0.5h); }\n";

enum { NB = 12, BW = 14, BH = 20 };

int main(void) { @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) { printf("no Metal device\n"); return 1; }
    printf("device: %s\n", dev.name.UTF8String);
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithSource:SRC options:nil error:&err];
    if (!lib) { printf("compile failed: %s\n", err.description.UTF8String); return 1; }
    id<MTLComputePipelineState> prd = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"rd"] error:&err];
    id<MTLComputePipelineState> psm = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"sm"] error:&err];
    if (!prd || !psm) { printf("pipeline failed: %s\n", err.description.UTF8String); return 1; }
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];   // nearest, clamp: the default
    id<MTLSamplerState> smp = [dev newSamplerStateWithDescriptor:sd];
    id<MTLCommandQueue> q = [dev newCommandQueue];

    struct { MTLPixelFormat f; int bpp, ch; const char *n; } F[] = {
        {MTLPixelFormatA8Unorm, 1, 3, "A8Unorm"}, {MTLPixelFormatR8Unorm, 1, 0, "R8Unorm"},
        {MTLPixelFormatRG8Unorm, 2, 0, "RG8Unorm"}, {MTLPixelFormatBGRA8Unorm, 4, 0, "BGRA8Unorm"}};
    struct { MTLStorageMode m; const char *n; } S[] = {{MTLStorageModeShared, "shared"}, {MTLStorageModeManaged, "managed"}};
    int sizes[] = {512, 576};
    for (unsigned fi = 0; fi < 4; fi++) for (unsigned si = 0; si < 2; si++) for (unsigned zi = 0; zi < 2; zi++) {
        int W = sizes[zi], bpp = F[fi].bpp;
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:F[fi].f width:W height:W mipmapped:NO];
        td.storageMode = S[si].m; td.usage = MTLTextureUsageShaderRead;
        id<MTLTexture> t = [dev newTextureWithDescriptor:td];
        if (!t) { printf("%-10s %-7s %d: texture failed\n", F[fi].n, S[si].n, W); continue; }
        NSMutableData *zero = [NSMutableData dataWithLength:(NSUInteger)W * W * bpp];
        [t replaceRegion:MTLRegionMake2D(0, 0, W, W) mipmapLevel:0 withBytes:zero.bytes bytesPerRow:W * bpp];
        uint8_t blk[BW * BH * 4];
        int bx[NB], by[NB];
        for (int k = 0; k < NB; k++) {   // offsets like a glyph atlas: odd x, rows not aligned to tiles
            bx[k] = 7 + k * 41; by[k] = 3 + k * 37;
            memset(blk, 17 * (k + 1), sizeof blk);
            [t replaceRegion:MTLRegionMake2D(bx[k], by[k], BW, BH) mipmapLevel:0 withBytes:blk bytesPerRow:BW * bpp];
        }
        for (int pass = 0; pass < 2; pass++) {
            id<MTLBuffer> out = [dev newBufferWithLength:(NSUInteger)W * W * 4 options:MTLResourceStorageModeShared];
            id<MTLCommandBuffer> cb = [q commandBuffer];
            id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
            [e setComputePipelineState:pass ? psm : prd];
            [e setTexture:t atIndex:0]; [e setBuffer:out offset:0 atIndex:0];
            if (pass) [e setSamplerState:smp atIndex:0];
            [e dispatchThreadgroups:MTLSizeMake((W + 15) / 16, (W + 15) / 16, 1) threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
            [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
            if (cb.error) { printf("%-10s %-7s %d %s: GPU error %s\n", F[fi].n, S[si].n, W, pass ? "sample" : "read", cb.error.description.UTF8String); continue; }
            const uint8_t *o = out.contents;
            int bad = 0, ch = F[fi].ch; char first[160] = "";
            for (int k = 0; k < NB; k++) {
                int v = 17 * (k + 1), wrong = 0, got = -1;
                for (int y = 0; y < BH && !wrong; y++) for (int x = 0; x < BW; x++) {
                    int p = o[((by[k] + y) * W + bx[k] + x) * 4 + ch];
                    if (p != v) { wrong = 1; got = p; break; }
                }
                int gap = o[((by[k] + BH + 1) * W + bx[k]) * 4 + ch];   // the row below the block must stay 0
                if (wrong || gap) {
                    if (!bad) snprintf(first, sizeof first, " first: block %d at (%d,%d) read %d expected %d, gap %d", k, bx[k], by[k], got, v, gap);
                    bad++;
                }
            }
            printf("%-10s %-7s %d %-6s wrong blocks: %d of %d%s\n", F[fi].n, S[si].n, W, pass ? "sample" : "read", bad, NB, first);
        }
    }
    return 0;
}}
