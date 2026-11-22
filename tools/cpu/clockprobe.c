// clockprobe.c: effective clock per thread on x86, from a dependent add chain (1 add per cycle on
// Golden Cove and Gracemont). It uses add reg,reg: Golden Cove folds dependent add-immediate chains at
// rename, so "add $1" reads 15 GHz. It shows which core type a thread ran on (P ~4.6 GHz max, E ~3.4 GHz max)
// and how far the clock drops when N threads run at once (package power limit).
//   cc -O2 -o clockprobe clockprobe.c -lpthread
//   ./clockprobe single 20        20 single-thread runs, one after another
//   ./clockprobe multi N          N threads at once, one line per thread
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ITERS 2000000000ULL /* 2 G adds: ~0.5 s at 4 GHz */

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static double run_chain(void) {
    unsigned long long n = ITERS / 10, x = 0, one = 1;
    double t0 = now();
    __asm__ volatile(
        "1:\n\t"
        "add %2, %0\n\tadd %2, %0\n\tadd %2, %0\n\tadd %2, %0\n\tadd %2, %0\n\t"
        "add %2, %0\n\tadd %2, %0\n\tadd %2, %0\n\tadd %2, %0\n\tadd %2, %0\n\t"
        "dec %1\n\tjnz 1b\n\t"
        : "+r"(x), "+r"(n) : "r"(one));
    double dt = now() - t0;
    return (double)ITERS / dt / 1e9; /* GHz, assuming one dependent add per cycle */
}

static double results[64];
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static int waiting, total;
/* all threads start the measured run together, after one warm-up run each */
static void *worker(void *arg) {
    int i = (int)(long)arg;
    run_chain();
    pthread_mutex_lock(&mu);
    if (++waiting == total) pthread_cond_broadcast(&cv); else while (waiting < total) pthread_cond_wait(&cv, &mu);
    pthread_mutex_unlock(&mu);
    results[i] = run_chain();
    return NULL;
}

int main(int argc, char **argv) {
    if (argc == 3 && !strcmp(argv[1], "single")) {
        int k = atoi(argv[2]);
        for (int i = 0; i < k; i++) printf("single %2d %.2f GHz\n", i, run_chain());
        return 0;
    }
    if (argc == 3 && !strcmp(argv[1], "multi")) {
        int n = atoi(argv[2]); if (n < 1 || n > 64) return 1;
        pthread_t t[64]; total = n;
        for (int i = 0; i < n; i++) pthread_create(&t[i], NULL, worker, (void *)(long)i);
        double sum = 0;
        for (int i = 0; i < n; i++) { pthread_join(t[i], NULL); sum += results[i]; }
        printf("multi n=%d per-thread:", n);
        for (int i = 0; i < n; i++) printf(" %.2f", results[i]);
        printf("  sum=%.1f GHz-equiv\n", sum);
        return 0;
    }
    fprintf(stderr, "usage: %s single K | multi N\n", argv[0]);
    return 1;
}
