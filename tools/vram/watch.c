#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#define TW 64
#define TH 60
#define NX (1920/TW)
#define NY (1080/TH)
#define N 40
static uint64_t sums[N][NY][NX];
int main(void) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("NMXGPUFB"));
    io_connect_t c; if (IOServiceOpen(s, mach_task_self(), 1, &c)) return 1;
    mach_vm_address_t a = 0; mach_vm_size_t sz = 0;
    if (IOConnectMapMemory64(c, 110, mach_task_self(), &a, &sz, kIOMapAnywhere)) return 1;
    uint32_t *fb = (uint32_t *)a; static uint32_t copy[1920*1080];
    for (int f = 0; f < N; f++) {
        memcpy(copy, fb, sizeof copy);
        for (int ty = 0; ty < NY; ty++) for (int tx = 0; tx < NX; tx++) {
            uint64_t h = 1469598103934665603ull;
            for (int y = ty*TH; y < ty*TH+TH; y++) for (int x = tx*TW; x < tx*TW+TW; x++) { h ^= copy[y*1920+x]; h *= 1099511628211ull; }
            sums[f][ty][tx] = h;
        }
        usleep(20000);
    }
    int changed = 0, flips = 0;
    for (int ty = 0; ty < NY; ty++) { for (int tx = 0; tx < NX; tx++) {
        int ch = 0, fl = 0;
        for (int f = 1; f < N; f++) { if (sums[f][ty][tx] != sums[f-1][ty][tx]) ch++; if (f > 1 && sums[f][ty][tx] == sums[f-2][ty][tx] && sums[f][ty][tx] != sums[f-1][ty][tx]) fl++; }
        if (ch) changed++; if (fl) flips++;
        putchar(fl ? 'F' : ch ? (ch > 9 ? '#' : '0' + ch) : '.');
    } putchar('\n'); }
    printf("tiles changed %d, flip-flopping %d (of %d), %d frames\n", changed, flips, NX*NY, N);
    return 0;
}
