#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
int main(void) {
    CGDirectDisplayID ids[16]; uint32_t n = 0;
    CGGetOnlineDisplayList(16, ids, &n); printf("online %u\n", n);
    for (uint32_t i = 0; i < n; i++) { CGRect b = CGDisplayBounds(ids[i]);
        printf(" id %x main %d active %d asleep %d mirror %x bounds %.0f,%.0f %.0fx%.0f\n", ids[i], CGDisplayIsMain(ids[i]),
               CGDisplayIsActive(ids[i]), CGDisplayIsAsleep(ids[i]), CGDisplayMirrorsDisplay(ids[i]), b.origin.x, b.origin.y, b.size.width, b.size.height); }
    CGGetActiveDisplayList(16, ids, &n); printf("active %u\n", n);
    CGEventRef e = CGEventCreate(NULL); CGPoint p = CGEventGetLocation(e); printf("mouse %.0f,%.0f\n", p.x, p.y);
    return 0;
}
