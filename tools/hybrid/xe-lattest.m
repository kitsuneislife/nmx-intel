// xe-lattest: how long a tiny Metal job waits before the GPU starts it (submission latency).
// The job itself runs in microseconds, so the wall time is almost all driver queueing/scheduling.
// Build: clang -fobjc-arc -O2 -framework Metal -framework Foundation -o /tmp/xe-lattest tools/hybrid/xe-lattest.m
// Run with as few other apps open as possible; output: percentiles per idle gap, in ms.
// `xe-lattest render` sends a tiny render pass (clear of a 16x16 texture) instead of the compute job, so it rides the
// render ring like WindowServer's own work, whatever -wex-noccs does to compute.
// `xe-lattest event` sends the render pass, signals an MTLSharedEvent from it and waits on the event from the CPU
// (the Chrome Graphite path of WhateverXe #130); `wall` is then commit -> event seen, and `>50 ms` counts the stalls.
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static double now_ms(void) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return mach_absolute_time() * (double)tb.numer / tb.denom / 1e6;
}
static int cmp(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}
static void pct(const char *name, double *v, int n) {
    qsort(v, n, sizeof v[0], cmp);
    printf("  %-16s p50 %6.2f  p90 %6.2f  p99 %6.2f  max %6.2f ms\n", name, v[n / 2], v[n * 9 / 10], v[n * 99 / 100], v[n - 1]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        id<MTLDevice> d = MTLCreateSystemDefaultDevice();
        if (!d) { fprintf(stderr, "no Metal device\n"); return 1; }
        NSError *err = nil;
        id<MTLLibrary> lib = [d newLibraryWithSource:
            @"kernel void t(device float *o [[buffer(0)]], uint i [[thread_position_in_grid]]) { o[i] = i; }"
                                             options:nil error:&err];
        id<MTLComputePipelineState> p = lib ? [d newComputePipelineStateWithFunction:[lib newFunctionWithName:@"t"] error:&err] : nil;
        if (!p) { fprintf(stderr, "pipeline: %s\n", err.localizedDescription.UTF8String); return 1; }
        id<MTLBuffer> buf = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared];
        id<MTLCommandQueue> q = [d newCommandQueue];
        const int event = argc > 1 && !strcmp(argv[1], "event");
        const int render = event || (argc > 1 && !strcmp(argv[1], "render"));
        id<MTLSharedEvent> ev = [d newSharedEvent];
        uint64_t evValue = 0;
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                       width:16 height:16 mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget;
        td.storageMode = MTLStorageModePrivate;
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = [d newTextureWithDescriptor:td];
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        if (!rp.colorAttachments[0].texture) { fprintf(stderr, "no render target\n"); return 1; }
        printf("%s, %s job, %s\n", d.name.UTF8String, event ? "render+event" : render ? "render" : "compute", [[NSProcessInfo processInfo] operatingSystemVersionString].UTF8String);
        const int gaps[] = {0, 8000, 16000};
        enum { N = 300 };
        static double wall[N], start[N], exec[N];
        for (unsigned g = 0; g < sizeof gaps / sizeof gaps[0]; g++) {
            for (int r = 0; r < N; r++) {
                if (gaps[g]) usleep(gaps[g]);
                double t0 = now_ms();
                id<MTLCommandBuffer> cb = [q commandBuffer];
                if (render) {
                    [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
                } else {
                    id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
                    [e setComputePipelineState:p];
                    [e setBuffer:buf offset:0 atIndex:0];
                    [e dispatchThreads:MTLSizeMake(1024, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
                    [e endEncoding];
                }
                if (event) [cb encodeSignalEvent:ev value:++evValue];
                [cb commit];
                if (event && ![ev waitUntilSignaledValue:evValue timeoutMS:2000]) { fprintf(stderr, "event timeout\n"); return 1; }
                if (event) wall[r] = now_ms() - t0;
                [cb waitUntilCompleted];
                if (cb.status != MTLCommandBufferStatusCompleted) { fprintf(stderr, "command buffer failed\n"); return 1; }
                if (!event) wall[r] = now_ms() - t0;
                start[r] = (cb.GPUStartTime - cb.kernelStartTime) * 1e3;
                exec[r] = (cb.GPUEndTime - cb.GPUStartTime) * 1e3;
            }
            int slow = 0;
            for (int r = 0; r < N; r++) slow += wall[r] > 50;
            printf("gap %d ms, %d jobs, %d over 50 ms:\n", gaps[g] / 1000, N, slow);
            pct("wall", wall, N);
            pct("kernel->gpu", start, N);
            pct("gpu exec", exec, N);
        }
    }
    return 0;
}
