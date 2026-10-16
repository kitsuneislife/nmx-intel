/*
 * nmx-mirror: while NMXGPU's framebuffer (NMXGPUFB) or NMIntelFB drives the panel, WindowServer still keeps the
 * firmware's display (.Display_boot) as a second screen to the right, and that screen draws into the same pages the
 * panel shows (test 32: flicker, the cursor wrapping to the left edge, the Dock missing). Mirroring it onto the main display hides it.
 * Only displays with the same panel (vendor, model and serial as the main one) are mirrored, so an external monitor
 * is left alone. It stays running and mirrors again after every display change.
 * It logs to syslog (`log show --predicate 'process == "nmx-mirror"'`), not to a file: the login-window instance runs
 * as root, and a root-owned log file made the user-session instance fail to spawn (launchd EX_CONFIG 78).
 */
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <syslog.h>

static bool service_present(const char *cls)
{
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(cls));
    if (!s)
        return false;
    IOObjectRelease(s);
    return true;
}

/* NMXGPUFB (i915 path) or NMIntelFB (RTX path): both leave the firmware display behind */
static bool nmx_fb_present(void)
{
    return service_present("NMXGPUFB") || service_present("NMIntelFB");
}

static void mirror_now(void)
{
    if (!nmx_fb_present())
        return;
    CGDirectDisplayID main = CGMainDisplayID(), ids[16];
    uint32_t n = 0;
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess)
        return;
    CGDisplayConfigRef cfg = NULL;
    int todo = 0;
    for (uint32_t i = 0; i < n; i++) {
        CGDirectDisplayID d = ids[i];
        if (d == main || CGDisplayMirrorsDisplay(d) == main)
            continue;
        if (CGDisplayVendorNumber(d) != CGDisplayVendorNumber(main) || CGDisplayModelNumber(d) != CGDisplayModelNumber(main) ||
            CGDisplaySerialNumber(d) != CGDisplaySerialNumber(main))
            continue;
        if (cfg == NULL && CGBeginDisplayConfiguration(&cfg) != kCGErrorSuccess)
            return;
        CGConfigureDisplayMirrorOfDisplay(cfg, d, main);
        syslog(LOG_NOTICE, "nmx-mirror: %x onto %x", d, main);
        todo++;
    }
    if (cfg != NULL) {
        if (todo)
            syslog(LOG_NOTICE, "nmx-mirror: complete %d", CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession));
        else
            CGCancelDisplayConfiguration(cfg);
    }
}

static void reconfigured(CGDirectDisplayID d, CGDisplayChangeSummaryFlags flags, void *ctx)
{
    (void)d; (void)ctx;
    if (!(flags & kCGDisplayBeginConfigurationFlag))
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ mirror_now(); });
}

int main(void)
{
    mirror_now();
    CGDisplayRegisterReconfigurationCallback(reconfigured, NULL);
    /* WindowServer may add the display after we start: look again for the first minute */
    for (int i = 1; i <= 12; i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)i * 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ mirror_now(); });
    CFRunLoopRun();
    return 0;
}
