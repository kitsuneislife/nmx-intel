#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    CGDirectDisplayID main = CGMainDisplayID(), ids[16]; uint32_t n = 0;
    CGGetOnlineDisplayList(16, ids, &n);
    CGDisplayConfigRef cfg; CGBeginDisplayConfiguration(&cfg);
    for (uint32_t i = 0; i < n; i++) if (ids[i] != main)
        printf("mirror %x -> %x: %d\n", ids[i], main, CGConfigureDisplayMirrorOfDisplay(cfg, ids[i], argc > 1 ? kCGNullDirectDisplay : main));
    printf("complete %d\n", CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession));
    return 0;
}
