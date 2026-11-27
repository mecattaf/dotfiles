/* SPDX-License-Identifier: MIT
 * No GPU queue or command submission is created by this program.
 */
#define _DEFAULT_SOURCE
#include <amdgpu.h>
#include <amdgpu_drm.h>
#include <xf86drm.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#ifndef PROBE_SOURCE_SHA256
#define PROBE_SOURCE_SHA256 "unrecorded-source"
#endif
#define MIB UINT64_C(1048576)
#define MIN_RESERVE (UINT64_C(256) * MIB)
#define CHUNK_PAGES 16384U

static volatile sig_atomic_t interrupted;
static struct {
    const char *node;
    uint64_t bytes, available, total, gtt_total, gtt_usage, gtt_max;
    uint64_t gpu_va, page_size, touched_pages, resident_pages;
    uint32_t asic, family;
    bool touch, bo_accepted, va_accepted, cpu_mapped, residency_known;
    bool cpu_samples_pass;
} report;

static void on_signal(int sig) { interrupted = sig; }

static void json_string(const char *s)
{
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)(s ? s : ""); *p; ++p) {
        switch (*p) {
        case '"': fputs("\\\"", stdout); break;
        case '\\': fputs("\\\\", stdout); break;
        case '\n': fputs("\\n", stdout); break;
        case '\r': fputs("\\r", stdout); break;
        case '\t': fputs("\\t", stdout); break;
        default:
            if (*p < 32) printf("\\u%04x", *p);
            else putchar(*p);
        }
    }
    putchar('"');
}

static void event(const char *stage, const char *status, int rc, const char *detail)
{
    fputs("{\"schemaVersion\":1,\"tool\":\"ps4-memory-probe\",\"sourceSha256\":", stdout);
    json_string(PROBE_SOURCE_SHA256);
    fputs(",\"node\":", stdout); json_string(report.node);
    fputs(",\"stage\":", stdout); json_string(stage);
    fputs(",\"status\":", stdout); json_string(status);
    printf(",\"returnCode\":%d,\"detail\":", rc); json_string(detail);
    printf(",\"requestedBytes\":%" PRIu64 ",\"reserveBytes\":%" PRIu64
           ",\"memTotalBytes\":%" PRIu64 ",\"memAvailableBytes\":%" PRIu64
           ",\"gttReportedBytes\":%" PRIu64 ",\"gttReportedUsageBytes\":%" PRIu64
           ",\"gttReportedMaxAllocationBytes\":%" PRIu64
           ",\"asicId\":%" PRIu32 ",\"familyId\":%" PRIu32
           ",\"gpuVa\":\"0x%" PRIx64 "\",\"pageBytes\":%" PRIu64
           ",\"cpuTouchedPages\":%" PRIu64 ",\"cpuResidentPages\":",
           report.bytes, MIN_RESERVE, report.total, report.available,
           report.gtt_total, report.gtt_usage, report.gtt_max,
           report.asic, report.family, report.gpu_va, report.page_size,
           report.touched_pages);
    if (report.residency_known) printf("%" PRIu64, report.resident_pages);
    else fputs("null", stdout);
    printf(",\"touchRequested\":%s,\"allocationAccepted\":%s,\"gpuVaMappingAccepted\":%s"
           ",\"cpuMappingAccepted\":%s,\"cpuSampleReadbackPassed\":%s"
           ",\"gpuSubmissionPerformed\":false,\"gpuReadQualified\":false"
           ",\"gpuBandwidthQualified\":false,\"gpuCoherenceQualified\":false"
           ",\"memoryPinned\":false}\n",
           report.touch ? "true" : "false", report.bo_accepted ? "true" : "false",
           report.va_accepted ? "true" : "false", report.cpu_mapped ? "true" : "false",
           report.cpu_samples_pass ? "true" : "false");
    fflush(stdout);
}

static int fail(const char *stage, int rc, const char *detail)
{
    char message[384];
    if (rc < 0 && rc >= -4095)
        snprintf(message, sizeof(message), "%s: %s", detail, strerror(-rc));
    else snprintf(message, sizeof(message), "%s", detail);
    event(stage, "fail", rc, message);
    return 1;
}

static int memory_available(void)
{
    FILE *f = fopen("/proc/meminfo", "re");
    char line[256];
    uint64_t value;
    bool got_available = false, got_total = false;
    if (!f) return -errno;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "MemAvailable: %" SCNu64 " kB", &value) == 1) {
            if (value > UINT64_MAX / 1024) { fclose(f); return -EOVERFLOW; }
            report.available = value * 1024;
            got_available = true;
        } else if (sscanf(line, "MemTotal: %" SCNu64 " kB", &value) == 1) {
            if (value > UINT64_MAX / 1024) { fclose(f); return -EOVERFLOW; }
            report.total = value * 1024;
            got_total = true;
        }
    }
    int read_error = ferror(f);
    fclose(f);
    return read_error ? -EIO : got_available && got_total ? 0 : -ENODATA;
}

static int parse_mib(const char *s, uint64_t *result)
{
    if (!s || !*s) return -EINVAL;
    for (const unsigned char *p = (const unsigned char *)s; *p; ++p)
        if (!isdigit(*p)) return -EINVAL;
    errno = 0;
    uintmax_t n = strtoumax(s, NULL, 10);
    if (errno || !n || n > UINT64_MAX / MIB || n > SIZE_MAX / MIB)
        return -EOVERFLOW;
    *result = (uint64_t)n * MIB;
    return *result > UINT64_MAX - MIN_RESERVE ? -EOVERFLOW : 0;
}

static bool valid_node_name(const char *s)
{
    const char prefix[] = "/dev/dri/renderD";
    if (!s || strncmp(s, prefix, sizeof(prefix) - 1)) return false;
    s += sizeof(prefix) - 1;
    if (!*s) return false;
    for (; *s; ++s) if (!isdigit((unsigned char)*s)) return false;
    return true;
}

static int verify_amd_fd(int fd)
{
    struct stat st;
    char sysfs[128], vendor[32];
    if (fstat(fd, &st)) return -errno;
    if (!S_ISCHR(st.st_mode) || major(st.st_rdev) != 226 || minor(st.st_rdev) < 128)
        return -ENODEV;
    snprintf(sysfs, sizeof(sysfs), "/sys/dev/char/%u:%u/device/vendor",
             major(st.st_rdev), minor(st.st_rdev));
    FILE *f = fopen(sysfs, "re");
    if (!f) return -errno;
    bool okay = fgets(vendor, sizeof(vendor), f) && strtoul(vendor, NULL, 0) == 0x1002;
    fclose(f);
    return okay ? 0 : -ENODEV;
}

static int query_heap(amdgpu_device_handle device)
{
    struct amdgpu_heap_info info = {0};
    int rc = amdgpu_query_heap_info(device, AMDGPU_GEM_DOMAIN_GTT, 0, &info);
    if (!rc) {
        report.gtt_total = info.heap_size;
        report.gtt_usage = info.heap_usage;
        report.gtt_max = info.max_allocation;
    }
    return rc;
}

static int touch_pages(void *mapping)
{
    volatile unsigned char *p = mapping;
    const uint64_t pages = report.bytes / report.page_size;
    for (uint64_t i = 0; i < pages; ++i) {
        if (interrupted) return -EINTR;
        if (i % CHUNK_PAGES == 0) {
            int rc = memory_available();
            if (rc) return rc;
            if (report.available < MIN_RESERVE) return -ENOMEM;
            if (i) event("cpu-touch-progress", "pass", 0, "CPU pages touched; no GPU work submitted");
        }
        size_t offset = (size_t)(i * report.page_size);
        unsigned char value = (unsigned char)(0xa5U ^ (unsigned char)i);
        p[offset] = value;
        p[offset + report.page_size - 1] = (unsigned char)~value;
        report.touched_pages = i + 1;
    }
    const uint64_t samples[] = {0, pages / 2, pages - 1};
    for (size_t i = 0; i < sizeof(samples) / sizeof(samples[0]); ++i) {
        size_t offset = (size_t)(samples[i] * report.page_size);
        unsigned char value = (unsigned char)(0xa5U ^ (unsigned char)samples[i]);
        unsigned char end = (unsigned char)~value;
        if (p[offset] != value || p[offset + report.page_size - 1] != end) return -EIO;
    }
    report.cpu_samples_pass = true;
    return 0;
}

static int count_resident(void *mapping)
{
    unsigned char vec[CHUNK_PAGES];
    uint64_t pages = report.bytes / report.page_size;
    uint64_t count = 0;
    for (uint64_t i = 0; i < pages; i += CHUNK_PAGES) {
        if (interrupted) return -EINTR;
        size_t n = pages - i < CHUNK_PAGES ? (size_t)(pages - i) : CHUNK_PAGES;
        if (mincore((unsigned char *)mapping + (size_t)(i * report.page_size),
                    n * (size_t)report.page_size, vec)) return -errno;
        for (size_t j = 0; j < n; ++j) count += !!(vec[j] & 1U);
    }
    report.resident_pages = count;
    report.residency_known = true;
    return 0;
}

static void usage(FILE *f)
{
    fputs("Usage: ps4-memory-probe --node /dev/dri/renderD<number> [--allocate-mib N [--touch]]\n"
          "Default: query only. Allocation needs MemAvailable >= requested bytes + 256 MiB.\n"
          "--touch writes two bytes per CPU page and samples readback; no GPU commands execute.\n"
          "Output: JSON Lines for each stage, including cleanup.\n", f);
}

int main(int argc, char **argv)
{
    static const struct option options[] = {
        {"node", required_argument, NULL, 'n'},
        {"allocate-mib", required_argument, NULL, 'a'},
        {"touch", no_argument, NULL, 't'},
        {"help", no_argument, NULL, 'h'},
        {NULL, 0, NULL, 0}
    };
    int opt, fd = -1, rc, failed = 0;
    bool gpu_mapped = false, cpu_mapped = false;
    amdgpu_device_handle device = NULL;
    amdgpu_bo_handle bo = NULL;
    amdgpu_va_handle va = NULL;
    void *mapping = NULL;
    uint32_t drm_major = 0, drm_minor = 0;
    while ((opt = getopt_long(argc, argv, "", options, NULL)) != -1) {
        switch (opt) {
        case 'n': report.node = optarg; break;
        case 'a':
            rc = parse_mib(optarg, &report.bytes);
            if (rc) return fail("arguments", rc, "Invalid allocation MiB or arithmetic overflow");
            break;
        case 't': report.touch = true; break;
        case 'h': usage(stdout); return 0;
        default: usage(stderr); return fail("arguments", -EINVAL, "Unknown option");
        }
    }
    if (optind != argc || !valid_node_name(report.node) || (report.touch && !report.bytes))
        return fail("arguments", -EINVAL, "Name one AMD render node; --touch requires --allocate-mib");
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0 || (report.bytes && report.bytes % (uint64_t)page))
        return fail("page-size", -EINVAL, "Requested bytes must be a multiple of CPU page size");
    report.page_size = (uint64_t)page;
    rc = memory_available();
    if (rc) return fail("memory-query", rc, "Cannot read MemAvailable and MemTotal");
    if (report.bytes && report.available < report.bytes + MIN_RESERVE)
        return fail("preflight", -ENOMEM, "Insufficient MemAvailable for request plus 256 MiB reserve");
    event("preflight", "pass", 0, report.bytes ? "Memory reserve preflight passed" : "Query only: no allocation requested");
    struct sigaction action = { .sa_handler = on_signal };
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGINT, &action, NULL) || sigaction(SIGTERM, &action, NULL))
        return fail("signal-handlers", -errno, "Cannot install interruption handlers");
    fd = open(report.node, O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return fail("open-node", -errno, "Cannot open named render node");
    rc = verify_amd_fd(fd);
    if (rc) { failed = fail("verify-device", rc, "Not an AMD DRM render node"); goto cleanup; }
    drmVersionPtr version = drmGetVersion(fd);
    if (!version) { failed = fail("drm-version", -errno, "DRM version query failed"); goto cleanup; }
    bool correct_driver = version->name && !strcmp(version->name, "amdgpu");
    drmFreeVersion(version);
    if (!correct_driver) { failed = fail("verify-driver", -ENODEV, "Driver is not amdgpu"); goto cleanup; }
    rc = amdgpu_device_initialize(fd, &drm_major, &drm_minor, &device);
    if (rc) { failed = fail("initialize", rc, "amdgpu initialization failed"); goto cleanup; }
    struct amdgpu_gpu_info info = {0};
    rc = amdgpu_query_gpu_info(device, &info);
    if (rc) { failed = fail("gpu-query", rc, "Cannot query GPU identity"); goto cleanup; }
    report.asic = info.asic_id; report.family = info.family_id;
    rc = query_heap(device);
    if (rc) { failed = fail("gtt-query", rc, "Cannot query GTT heap"); goto cleanup; }
    event("query", "pass", 0, "Read-only heap/identity queries; heap size is not free or allocated memory");
    if (!report.bytes) goto cleanup;
    if (interrupted) { failed = fail("interrupted", -EINTR, "Interrupted before allocation"); goto cleanup; }
    rc = memory_available();
    if (rc || report.available < report.bytes + MIN_RESERVE) {
        failed = fail("pre-allocation", rc ? rc : -ENOMEM, "Memory reserve no longer satisfied");
        goto cleanup;
    }
    struct amdgpu_bo_alloc_request request = {
        .alloc_size = report.bytes,
        .phys_alignment = report.page_size,
        .preferred_heap = AMDGPU_GEM_DOMAIN_GTT,
        .flags = AMDGPU_GEM_CREATE_CPU_ACCESS_REQUIRED
    };
    rc = amdgpu_bo_alloc(device, &request, &bo);
    if (rc) { failed = fail("allocate-gtt", rc, "GTT BO allocation rejected"); goto cleanup; }
    report.bo_accepted = true;
    event("allocate-gtt", "pass", 0, "One GTT BO accepted; no staging copy or pinning requested");
    rc = amdgpu_va_range_alloc(device, amdgpu_gpu_va_range_general, report.bytes,
                              report.page_size, 0, &report.gpu_va, &va, 0);
    if (rc) { failed = fail("reserve-gpu-va", rc, "GPU VA reservation rejected"); goto cleanup; }
    event("reserve-gpu-va", "pass", 0, "GPU VA reserved independently of CPU mapping");
    rc = amdgpu_bo_va_op(bo, 0, report.bytes, report.gpu_va,
                        AMDGPU_VM_PAGE_READABLE | AMDGPU_VM_PAGE_WRITEABLE,
                        AMDGPU_VA_OP_MAP);
    if (rc) { failed = fail("map-gpu-va", rc, "GPU VA mapping rejected"); goto cleanup; }
    gpu_mapped = report.va_accepted = true;
    event("map-gpu-va", "pass", 0, "GPU VA map accepted; no shader has read these pages");
    if (report.touch) {
        rc = amdgpu_bo_cpu_map(bo, &mapping);
        if (rc) { failed = fail("map-cpu", rc, "CPU mapping rejected"); goto cleanup; }
        cpu_mapped = report.cpu_mapped = true;
        event("map-cpu", "pass", 0, "Same BO CPU mapped; no second weight-sized allocation");
        rc = touch_pages(mapping);
        if (rc) { failed = fail("cpu-touch", rc, "CPU page touch/readback failed or reserve exhausted"); goto cleanup; }
        event("cpu-touch", "pass", 0, "Every CPU page touched; first/middle/last page patterns verified");
        rc = count_resident(mapping);
        if (rc == -EINTR) { failed = fail("cpu-residency", rc, "Interrupted during residency query"); goto cleanup; }
        if (rc) event("cpu-residency", "unknown", rc, "mincore is unavailable for this device mapping; touched pages are not a measured residency count");
        else event("cpu-residency", "pass", 0, "mincore residency observed; this is not a pin or GPU-read proof");
    }
    rc = query_heap(device);
    if (rc) { failed = fail("gtt-query-after", rc, "Post-allocation heap query failed"); goto cleanup; }
    rc = memory_available();
    if (rc) { failed = fail("memory-query-after", rc, "Post-allocation memory query failed"); goto cleanup; }
    event("allocated-state", "pass", 0, "Counters captured before releasing the BO");

cleanup:
    if (cpu_mapped) {
        rc = amdgpu_bo_cpu_unmap(bo);
        if (rc) failed |= fail("release-cpu-map", rc, "CPU unmap failed");
        else event("release-cpu-map", "pass", 0, "CPU mapping released");
    }
    if (gpu_mapped) {
        rc = amdgpu_bo_va_op(bo, 0, report.bytes, report.gpu_va, 0, AMDGPU_VA_OP_UNMAP);
        if (rc) failed |= fail("release-gpu-map", rc, "GPU VA unmap failed");
        else event("release-gpu-map", "pass", 0, "GPU VA mapping released");
    }
    if (va) {
        rc = amdgpu_va_range_free(va);
        if (rc) failed |= fail("release-gpu-va", rc, "GPU VA range release failed");
        else event("release-gpu-va", "pass", 0, "GPU VA reservation released");
    }
    if (bo) {
        rc = amdgpu_bo_free(bo);
        if (rc) failed |= fail("release-bo", rc, "BO release failed");
        else event("release-bo", "pass", 0, "BO released");
    }
    if (device) {
        rc = amdgpu_device_deinitialize(device);
        if (rc) failed |= fail("release-device", rc, "amdgpu device release failed");
        else event("release-device", "pass", 0, "amdgpu handle released");
    }
    if (fd >= 0 && close(fd)) failed |= fail("release-fd", -errno, "DRM fd close failed");
    if (interrupted && !failed) failed = fail("interrupted", -EINTR, "Interrupted");
    event("complete", failed ? "fail" : "pass", failed ? 1 : 0,
          "All owned resources released or release errors reported; GPU execution remains unqualified");
    return failed ? 1 : 0;
}
