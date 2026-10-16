/*
 * nmx-probe: what Metal's Intel path sees, without a screen. Lists the DRM nodes, asks libdrm for its devices (the
 * way Mesa's ANV enumerates them), opens each node and asks i915's version, then creates a Vulkan instance straight
 * on ANV (libvulkan_intel.dylib, as NVMTL does) and counts its physical devices. Everything goes to stdout.
 *
 *   clang -O1 -o nmx-probe nmx-probe.c
 */
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define NVMTL "/Library/GPUBundles/nvmtl/"

/* libdrm's drmDevice, as far as this program reads it (xf86drm.h) */
typedef struct {
    uint16_t vendor_id, device_id, subvendor_id, subdevice_id;
    uint8_t revision_id;
} drmPciDeviceInfo;
typedef struct {
    uint16_t domain;
    uint8_t bus, dev, func;
} drmPciBusInfo;
typedef struct {
    char **nodes;
    int available_nodes;
    int bustype;
    union { drmPciBusInfo *pci; void *other; } businfo;
    union { drmPciDeviceInfo *pci; void *other; } deviceinfo;
} drmDevice, *drmDevicePtr;
typedef struct {
    int version_major, version_minor, version_patchlevel;
    int name_len;
    char *name;
    int date_len;
    char *date;
    int desc_len;
    char *desc;
} drmVersion;

/* the few Vulkan types the instance needs (vulkan_core.h) */
typedef int32_t VkResult;
typedef void *VkInstance;
typedef void *VkPhysicalDevice;
typedef void (*PFN_vkVoidFunction)(void);
typedef struct {
    int sType; const void *pNext; const char *pApplicationName; uint32_t applicationVersion;
    const char *pEngineName; uint32_t engineVersion; uint32_t apiVersion;
} VkApplicationInfo;
typedef struct {
    int sType; const void *pNext; uint32_t flags; const VkApplicationInfo *pApplicationInfo;
    uint32_t enabledLayerCount; const char *const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char *const *ppEnabledExtensionNames;
} VkInstanceCreateInfo;
typedef struct {
    uint32_t apiVersion, driverVersion, vendorID, deviceID;
    int deviceType;
    char deviceName[256];
    uint8_t pad[1024];
} VkPhysicalDeviceProperties;

static void list_dir(const char *dir)
{
    DIR *d = opendir(dir);
    if (d == NULL) {
        printf("%s: %s\n", dir, strerror(errno));
        return;
    }
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.')
            continue;
        char path[512];
        struct stat st;
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
        if (stat(path, &st) == 0)
            printf("  %s mode %o dev %d,%d\n", path, st.st_mode & 07777, major(st.st_rdev), minor(st.st_rdev));
        else
            printf("  %s: stat %s\n", path, strerror(errno));
    }
    closedir(d);
}

static void probe_drm(void)
{
    void *h = dlopen(NVMTL "libdrm.2.dylib", RTLD_NOW);
    if (h == NULL) {
        printf("libdrm: %s\n", dlerror());
        return;
    }
    int (*get_devices2)(uint32_t, drmDevicePtr *, int) = dlsym(h, "drmGetDevices2");
    drmVersion *(*get_version)(int) = dlsym(h, "drmGetVersion");
    if (get_devices2 == NULL || get_version == NULL) {
        printf("libdrm: symbols missing\n");
        return;
    }
    drmDevicePtr devs[8] = { 0 };
    int n = get_devices2(0, devs, 8);
    printf("drmGetDevices2: %d device(s)%s\n", n, n < 0 ? " (error)" : "");
    for (int i = 0; i < n && i < 8; i++) {
        drmDevicePtr d = devs[i];
        printf("  device %d: bustype %d, nodes mask 0x%x", i, d->bustype, d->available_nodes);
        if (d->bustype == 0 && d->deviceinfo.pci)
            printf(", pci %04x:%04x", d->deviceinfo.pci->vendor_id, d->deviceinfo.pci->device_id);
        printf("\n");
        for (int t = 0; t < 3; t++)
            if (d->available_nodes & (1 << t))
                printf("    node[%d] %s\n", t, d->nodes[t]);
    }
    const char *nodes[] = { "/dev/dri/renderD128", "/dev/dri/card0" };
    for (int i = 0; i < 2; i++) {
        int fd = open(nodes[i], O_RDWR | O_CLOEXEC);
        if (fd < 0) {
            printf("open %s: %s\n", nodes[i], strerror(errno));
            continue;
        }
        drmVersion *v = get_version(fd);
        if (v != NULL)
            printf("open %s: driver %.*s %d.%d.%d\n", nodes[i], v->name_len, v->name, v->version_major,
                   v->version_minor, v->version_patchlevel);
        else
            printf("open %s: drmGetVersion failed (%s)\n", nodes[i], strerror(errno));
        close(fd);
    }
}

static void probe_vulkan(void)
{
    void *h = dlopen(NVMTL "libvulkan_intel.dylib", RTLD_NOW);
    if (h == NULL) {
        printf("ANV: %s\n", dlerror());
        return;
    }
    PFN_vkVoidFunction (*gipa)(VkInstance, const char *) = dlsym(h, "vk_icdGetInstanceProcAddr");
    VkResult (*negotiate)(uint32_t *) = dlsym(h, "vk_icdNegotiateLoaderICDInterfaceVersion");
    if (gipa == NULL) {
        printf("ANV: no vk_icdGetInstanceProcAddr\n");
        return;
    }
    uint32_t ver = 5;
    if (negotiate)
        printf("ANV: negotiate -> %d, interface %u\n", negotiate(&ver), ver);
    VkResult (*create)(const VkInstanceCreateInfo *, const void *, VkInstance *) =
        (void *)gipa(NULL, "vkCreateInstance");
    if (create == NULL) {
        printf("ANV: no vkCreateInstance\n");
        return;
    }
    VkApplicationInfo app = { 0, NULL, "nmx-probe", 1, "nmx-probe", 1, (1u << 22) | (3u << 12) };
    VkInstanceCreateInfo ci = { 1, NULL, 0, &app, 0, NULL, 0, NULL };
    VkInstance inst = NULL;
    VkResult r = create(&ci, NULL, &inst);
    printf("ANV: vkCreateInstance -> %d\n", r);
    if (r != 0)
        return;
    VkResult (*enumerate)(VkInstance, uint32_t *, VkPhysicalDevice *) =
        (void *)gipa(inst, "vkEnumeratePhysicalDevices");
    void (*props)(VkPhysicalDevice, VkPhysicalDeviceProperties *) =
        (void *)gipa(inst, "vkGetPhysicalDeviceProperties");
    uint32_t count = 0;
    r = enumerate(inst, &count, NULL);
    printf("ANV: vkEnumeratePhysicalDevices -> %d, %u device(s)\n", r, count);
    VkPhysicalDevice pd[4];
    if (count > 4)
        count = 4;
    if (count && enumerate(inst, &count, pd) == 0 && props)
        for (uint32_t i = 0; i < count; i++) {
            VkPhysicalDeviceProperties p;
            memset(&p, 0, sizeof(p));
            props(pd[i], &p);
            printf("  %u: %s, %04x:%04x, api %u.%u\n", i, p.deviceName, p.vendorID, p.deviceID,
                   p.apiVersion >> 22, (p.apiVersion >> 12) & 0x3ff);
        }
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("== /dev/dri\n");
    list_dir("/dev/dri");
    printf("== libdrm\n");
    probe_drm();
    printf("== ANV\n");
    probe_vulkan();
    return 0;
}
