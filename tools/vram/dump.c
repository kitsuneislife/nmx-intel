#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsTypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("NMXGPUFB"));
    if (!s) { printf("no NMXGPUFB\n"); return 1; }
    io_connect_t c; kern_return_t kr = IOServiceOpen(s, mach_task_self(), kIOFBSharedConnectType, &c);
    printf("open %x\n", kr); if (kr) return 1;
    mach_vm_address_t a = 0; mach_vm_size_t sz = 0;
    kr = IOConnectMapMemory64(c, 110, mach_task_self(), &a, &sz, kIOMapAnywhere);
    printf("map %x size %llu\n", kr, sz); if (kr) return 1;
    size_t n = 7680u * 1080u;
    unsigned char *buf = malloc(n); memcpy(buf, (void *)a, n);
    FILE *f = fopen(argv[1], "wb");
    fprintf(f, "P6\n1920 1080\n255\n");
    for (size_t i = 0; i < 1920u * 1080u; i++) { unsigned char *p = buf + i * 4; fputc(p[2], f); fputc(p[1], f); fputc(p[0], f); }
    fclose(f); return 0;
}
