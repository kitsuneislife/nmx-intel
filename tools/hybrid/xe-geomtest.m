// xe-geomtest: the same rotated square drawn by plain Metal in nine ways (triangle list, strip, indexed 16/32-bit,
// vertex descriptor, setVertexBytes, blending, instanced small quads, 4x MSAA resolved), then the covered pixels of each tile are counted.
// HYB-12: on the Iris Xe CoreAnimation lost one triangle of a rotated layer, rows of path fills, text and icons.
//   clang -fobjc-arc -o xe-geomtest xe-geomtest.m -framework Metal -framework Foundation
#import <Metal/Metal.h>
#include <math.h>
#include <stdio.h>

static NSString *SRC = @"#include <metal_stdlib>\nusing namespace metal;\n"
  "struct V { float4 p [[position]]; };\n"
  "vertex V vid(const device float2 *v [[buffer(0)]], uint i [[vertex_id]]) { V o; o.p = float4(v[i], 0, 1); return o; }\n"
  "struct A { float2 p [[attribute(0)]]; };\n"
  "vertex V vin(A a [[stage_in]]) { V o; o.p = float4(a.p, 0, 1); return o; }\n"
  "vertex V vinst(const device float2 *v [[buffer(0)]], uint i [[vertex_id]], uint k [[instance_id]]) {\n"
  "  V o; o.p = float4(v[i] + float2(k % 8, k / 8) * 0.03, 0, 1); return o; }\n"
  "fragment half4 frag() { return half4(0, 0, 0, 1); }\n"
  "fragment half4 fragh() { return half4(0, 0, 0, 0.5); }\n";

enum { T = 128, NT = 9, W = T * NT };

int main(void) { @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) { printf("no Metal device\n"); return 1; }
    printf("device: %s\n", dev.name.UTF8String);
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithSource:SRC options:nil error:&err];
    if (!lib) { printf("compile failed: %s\n", err.description.UTF8String); return 1; }
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pd.fragmentFunction = [lib newFunctionWithName:@"frag"];
    pd.vertexFunction = [lib newFunctionWithName:@"vid"];
    id<MTLRenderPipelineState> pVid = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    pd.rasterSampleCount = 4;   // libxedrv moves rasterSampleCount when it converts the pipeline descriptor
    id<MTLRenderPipelineState> pMsaa = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    pd.rasterSampleCount = 1;
    pd.vertexFunction = [lib newFunctionWithName:@"vinst"];
    id<MTLRenderPipelineState> pInst = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    pd.vertexFunction = [lib newFunctionWithName:@"vid"]; pd.fragmentFunction = [lib newFunctionWithName:@"fragh"];
    pd.colorAttachments[0].blendingEnabled = YES;   // source-over, as CoreAnimation
    pd.colorAttachments[0].sourceRGBBlendFactor = pd.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pd.colorAttachments[0].destinationRGBBlendFactor = pd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    id<MTLRenderPipelineState> pBlend = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    pd = [MTLRenderPipelineDescriptor new];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pd.vertexFunction = [lib newFunctionWithName:@"vin"]; pd.fragmentFunction = [lib newFunctionWithName:@"frag"];
    MTLVertexDescriptor *vd = [MTLVertexDescriptor vertexDescriptor];
    vd.attributes[0].format = MTLVertexFormatFloat2; vd.attributes[0].bufferIndex = 0; vd.layouts[0].stride = 8;
    pd.vertexDescriptor = vd;
    id<MTLRenderPipelineState> pIn = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!pVid || !pMsaa || !pInst || !pBlend || !pIn) { printf("pipeline failed: %s\n", err.description.UTF8String); return 1; }

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:T mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeManaged;
    id<MTLTexture> rt = [dev newTextureWithDescriptor:td];
    const char *names[NT] = {"list", "strip", "indexed16", "indexed32", "vertex desc", "vertexBytes", "blend 0.5", "instanced", "msaa 4x"};
    id<MTLCommandQueue> q = [dev newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    MTLTextureDescriptor *md = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:T mipmapped:NO];
    md.textureType = MTLTextureType2DMultisample; md.sampleCount = 4; md.usage = MTLTextureUsageRenderTarget; md.storageMode = MTLStorageModePrivate;
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];   // pass 1: the MSAA tile, resolved into rt
    rp.colorAttachments[0].texture = [dev newTextureWithDescriptor:md]; rp.colorAttachments[0].resolveTexture = rt;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1);
    rp.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    for (int i = 0; i < NT; i++) {
        int t = (i + NT - 1) % NT;   // the MSAA tile first, alone in pass 1
        if (i == 1) {   // pass 2: the other tiles drawn over the resolved image
            [e endEncoding];
            MTLRenderPassDescriptor *rp2 = [MTLRenderPassDescriptor renderPassDescriptor];
            rp2.colorAttachments[0].texture = rt; rp2.colorAttachments[0].loadAction = MTLLoadActionLoad;
            rp2.colorAttachments[0].storeAction = MTLStoreActionStore;
            e = [cb renderCommandEncoderWithDescriptor:rp2];
        }
        // a square of side 0.55 T rotated 30 degrees in the middle of tile t (NDC), corners in strip order
        float cx = -1 + (t + 0.5f) * 2.0f / NT, h = t == 7 ? 0.04f : 0.55f, c = cosf(M_PI / 6), s = sinf(M_PI / 6);
        float sx = h / NT, sy = h;   // NDC half extents: one tile is 2/NT wide and 2 high
        float px[4] = {-1, 1, -1, 1}, py[4] = {-1, -1, 1, 1}, st[8];
        for (int k = 0; k < 4; k++) {
            st[k*2] = (t == 7 ? -1 + t * 2.0f / NT + 0.02f : cx) + (px[k] * c - py[k] * s) * sx;
            st[k*2+1] = (t == 7 ? 0.75f : 0) + (px[k] * s + py[k] * c) * sy;
        }
        float list[12]; int li[6] = {0, 1, 2, 2, 1, 3};
        for (int k = 0; k < 6; k++) { list[k*2] = st[li[k]*2]; list[k*2+1] = st[li[k]*2+1]; }
        uint16_t i16[6] = {0, 1, 2, 2, 1, 3}; uint32_t i32[6] = {0, 1, 2, 2, 1, 3};
        id<MTLBuffer> bst = [dev newBufferWithBytes:st length:sizeof st options:MTLResourceStorageModeShared];
        id<MTLBuffer> blist = [dev newBufferWithBytes:list length:sizeof list options:MTLResourceStorageModeShared];
        switch (t) {
        case 0: [e setRenderPipelineState:pVid]; [e setVertexBuffer:blist offset:0 atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6]; break;
        case 1: [e setRenderPipelineState:pVid]; [e setVertexBuffer:bst offset:0 atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4]; break;
        case 2: case 3: [e setRenderPipelineState:pVid]; [e setVertexBuffer:bst offset:0 atIndex:0];
            [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:6 indexType:t == 2 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32
                indexBuffer:[dev newBufferWithBytes:t == 2 ? (void *)i16 : (void *)i32 length:t == 2 ? sizeof i16 : sizeof i32
                options:MTLResourceStorageModeShared] indexBufferOffset:0]; break;
        case 4: [e setRenderPipelineState:pIn]; [e setVertexBuffer:bst offset:0 atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4]; break;
        case 5: [e setRenderPipelineState:pVid]; [e setVertexBytes:st length:sizeof st atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4]; break;
        case 6: [e setRenderPipelineState:pBlend]; [e setVertexBuffer:bst offset:0 atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4]; break;
        case 7: [e setRenderPipelineState:pInst]; [e setVertexBuffer:bst offset:0 atIndex:0];   // 64 glyph-sized quads
            [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:64]; break;
        case 8: [e setRenderPipelineState:pMsaa]; [e setVertexBuffer:bst offset:0 atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4]; break;
        }
    }
    [e endEncoding];
    id<MTLBlitCommandEncoder> b = [cb blitCommandEncoder]; [b synchronizeResource:rt]; [b endEncoding];
    [cb commit]; [cb waitUntilCompleted];
    if (cb.error) { printf("GPU error: %s\n", cb.error.description.UTF8String); return 1; }
    uint8_t *px = malloc(W * T * 4);
    [rt getBytes:px bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, T) mipmapLevel:0];
    for (int t = 0; t < NT; t++) {   // covered = darker than white; left and right halves show a lost triangle
        int half[2] = {0, 0};
        for (int y = 0; y < T; y++) for (int x = t * T; x < (t + 1) * T; x++)
            if (px[(y * W + x) * 4 + 1] < 200) half[x - t * T >= T / 2]++;
        printf("%-12s covered px: left %4d right %4d total %5d\n", names[t], half[0], half[1], half[0] + half[1]);
    }
    return 0;
}}
