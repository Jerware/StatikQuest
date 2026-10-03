// SPDX-License-Identifier: MIT
//
// Lets Mesa's Turnip driver talk to the Adreno kernel driver (KGSL) on Meta Quest.
//
// Horizon OS filters KGSL ioctls by number for applications and only lets through the ones its
// own graphics driver uses, the "GPUOBJ" generation of the interface. Turnip still issues a few
// calls of the generation before, which are answered with EACCES there:
//
//   IOCTL_KGSL_GPUMEM_ALLOC_ID               allocate a buffer
//   IOCTL_KGSL_GPUMEM_FREE_ID                free it
//   IOCTL_KGSL_GPUMEM_GET_INFO               describe it
//   IOCTL_KGSL_GPUMEM_SYNC_CACHE(_BULK)      flush CPU caches for it
//   IOCTL_KGSL_CMDSTREAM_READTIMESTAMP_CTXTID  ask how far a context has got
//
// This library is preloaded into the emulator process (the glibc loader's --preload) and stands
// in front of libc's ioctl(): those calls are carried out with what is permitted, everything else
// goes to the kernel untouched.

#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define KGSL_IOC_TYPE 0x09

// --- the calls that are refused ----------------------------------------------------------------

struct kgsl_gpumem_alloc_id {
    unsigned int id;
    unsigned int flags;
    size_t size;
    size_t mmapsize;
    unsigned long gpuaddr;
    unsigned long pad[2];
};

struct kgsl_gpumem_free_id {
    unsigned int id;
    unsigned int pad;
};

struct kgsl_gpumem_get_info {
    unsigned long gpuaddr;
    unsigned int id;
    unsigned int flags;
    size_t size;
    size_t mmapsize;
    unsigned long useraddr;
    unsigned long pad[4];
};

struct kgsl_gpumem_sync_cache {
    unsigned long gpuaddr;
    unsigned int id;
    unsigned int op;
    size_t offset;
    size_t length;
};

struct kgsl_gpumem_sync_cache_bulk {
    unsigned int* id_list;
    unsigned int count;
    unsigned int op;
    unsigned int pad[2];
};

struct kgsl_cmdstream_readtimestamp_ctxtid {
    unsigned int context_id;
    unsigned int type;
    unsigned int timestamp;
};

enum {
    NR_WAITTIMESTAMP_CTXTID = 0x07,
    NR_DRAWCTXT_CREATE = 0x13,
    NR_READTIMESTAMP_CTXTID = 0x16,
    NR_TIMESTAMP_EVENT = 0x33,
    NR_GPUMEM_ALLOC_ID = 0x34,
    NR_GPUMEM_FREE_ID = 0x35,
    NR_GPUMEM_GET_INFO = 0x36,
    NR_GPUMEM_SYNC_CACHE = 0x37,
    NR_GPUMEM_SYNC_CACHE_BULK = 0x3c,
    NR_GPU_COMMAND = 0x4a,
    NR_GPU_AUX_COMMAND = 0x57,
};

// --- the calls that are permitted --------------------------------------------------------------

struct kgsl_device_waittimestamp_ctxtid {
    unsigned int context_id;
    unsigned int timestamp;
    unsigned int timeout;
};
#define IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID \
    _IOW(KGSL_IOC_TYPE, 0x7, struct kgsl_device_waittimestamp_ctxtid)

struct kgsl_gpuobj_alloc {
    uint64_t size;
    uint64_t flags;
    uint64_t va_len;
    uint64_t mmapsize;
    unsigned int id;
    unsigned int metadata_len;
    uint64_t metadata;
};
#define IOCTL_KGSL_GPUOBJ_ALLOC _IOWR(KGSL_IOC_TYPE, 0x45, struct kgsl_gpuobj_alloc)

struct kgsl_gpuobj_free {
    uint64_t flags;
    uint64_t priv;
    unsigned int id;
    unsigned int type;
    unsigned int len;
};
#define IOCTL_KGSL_GPUOBJ_FREE _IOW(KGSL_IOC_TYPE, 0x46, struct kgsl_gpuobj_free)

struct kgsl_gpuobj_info {
    uint64_t gpuaddr;
    uint64_t flags;
    uint64_t size;
    uint64_t va_len;
    uint64_t va_addr;
    unsigned int id;
};
#define IOCTL_KGSL_GPUOBJ_INFO _IOWR(KGSL_IOC_TYPE, 0x47, struct kgsl_gpuobj_info)

struct kgsl_gpuobj_sync_obj {
    uint64_t offset;
    uint64_t length;
    unsigned int id;
    unsigned int op;
};

struct kgsl_gpuobj_sync {
    uint64_t objs;
    unsigned int obj_len;
    unsigned int count;
};
#define IOCTL_KGSL_GPUOBJ_SYNC _IOW(KGSL_IOC_TYPE, 0x49, struct kgsl_gpuobj_sync)

/// The parts of the two submit calls that are of interest here: they share this tail.
struct kgsl_gpu_command {
    uint64_t flags;
    uint64_t cmdlist;
    unsigned int cmdsize;
    unsigned int numcmds;
    uint64_t objlist;
    unsigned int objsize;
    unsigned int numobjs;
    uint64_t synclist;
    unsigned int syncsize;
    unsigned int numsyncs;
    unsigned int context_id;
    unsigned int timestamp;
};

struct kgsl_gpu_aux_command {
    uint64_t flags;
    uint64_t cmdlist;
    unsigned int cmdsize;
    unsigned int numcmds;
    uint64_t synclist;
    unsigned int syncsize;
    unsigned int numsyncs;
    unsigned int context_id;
    unsigned int timestamp;
};

static int kernel_ioctl(int fd, unsigned long request, void* arg) {
    return (int)syscall(SYS_ioctl, fd, request, arg);
}

static int tracing(void);
static void trace(const char* format, ...);

// --- buffers -----------------------------------------------------------------------------------

static size_t g_allocated;

static int gpumem_alloc_id(int fd, struct kgsl_gpumem_alloc_id* legacy) {
    struct kgsl_gpuobj_alloc alloc;
    memset(&alloc, 0, sizeof(alloc));
    alloc.size = legacy->size;
    alloc.flags = legacy->flags;
    if (kernel_ioctl(fd, IOCTL_KGSL_GPUOBJ_ALLOC, &alloc) != 0) {
        return -1;
    }

    // The old call also reported where the buffer sits in the GPU's address space.
    struct kgsl_gpuobj_info info;
    memset(&info, 0, sizeof(info));
    info.id = alloc.id;
    if (kernel_ioctl(fd, IOCTL_KGSL_GPUOBJ_INFO, &info) != 0) {
        const int error = errno;
        struct kgsl_gpuobj_free release;
        memset(&release, 0, sizeof(release));
        release.id = alloc.id;
        kernel_ioctl(fd, IOCTL_KGSL_GPUOBJ_FREE, &release);
        errno = error;
        return -1;
    }

    legacy->id = alloc.id;
    legacy->flags = (unsigned int)info.flags;
    legacy->size = info.size;
    legacy->mmapsize = alloc.mmapsize;
    legacy->gpuaddr = info.gpuaddr;

    // GPU memory is ordinary memory here, backed by pages from the moment it is allocated, and
    // a headset has little of it to spare: with tracing on, the large allocations are listed.
    const size_t total = __atomic_add_fetch(&g_allocated, info.size, __ATOMIC_RELAXED);
    if (tracing() && info.size >= (8u << 20)) {
        trace("allocated %zu MB of GPU memory, %zu MB in all", (size_t)info.size >> 20,
              total >> 20);
    }
    return 0;
}

static int gpumem_free_id(int fd, const struct kgsl_gpumem_free_id* legacy) {
    struct kgsl_gpuobj_free release;
    memset(&release, 0, sizeof(release));
    release.id = legacy->id;
    return kernel_ioctl(fd, IOCTL_KGSL_GPUOBJ_FREE, &release);
}

static int gpumem_get_info(int fd, struct kgsl_gpumem_get_info* legacy) {
    if (legacy->id == 0) {
        // Looking a buffer up by address has no successor.
        errno = EINVAL;
        return -1;
    }
    struct kgsl_gpuobj_info info;
    memset(&info, 0, sizeof(info));
    info.id = legacy->id;
    if (kernel_ioctl(fd, IOCTL_KGSL_GPUOBJ_INFO, &info) != 0) {
        return -1;
    }
    legacy->gpuaddr = info.gpuaddr;
    legacy->flags = (unsigned int)info.flags;
    legacy->size = info.size;
    legacy->mmapsize = info.va_len != 0 ? info.va_len : info.size;
    legacy->useraddr = info.va_addr;
    return 0;
}

static int gpumem_sync_cache(int fd, const struct kgsl_gpumem_sync_cache* legacy) {
    struct kgsl_gpuobj_sync_obj object;
    memset(&object, 0, sizeof(object));
    object.offset = legacy->offset;
    object.length = legacy->length;
    object.id = legacy->id;
    object.op = legacy->op;
    struct kgsl_gpuobj_sync sync;
    memset(&sync, 0, sizeof(sync));
    sync.objs = (uintptr_t)&object;
    sync.obj_len = sizeof(object);
    sync.count = 1;
    return kernel_ioctl(fd, IOCTL_KGSL_GPUOBJ_SYNC, &sync);
}

static int gpumem_sync_cache_bulk(int fd, const struct kgsl_gpumem_sync_cache_bulk* legacy) {
    if (legacy->count == 0) {
        return 0;
    }
    struct kgsl_gpuobj_sync_obj* objects = calloc(legacy->count, sizeof(*objects));
    if (objects == NULL) {
        errno = ENOMEM;
        return -1;
    }
    for (unsigned int i = 0; i < legacy->count; ++i) {
        // Without the "range" bit in op the whole buffer is meant.
        objects[i].id = legacy->id_list[i];
        objects[i].op = legacy->op;
    }
    struct kgsl_gpuobj_sync sync;
    memset(&sync, 0, sizeof(sync));
    sync.objs = (uintptr_t)objects;
    sync.obj_len = sizeof(*objects);
    sync.count = legacy->count;
    const int result = kernel_ioctl(fd, IOCTL_KGSL_GPUOBJ_SYNC, &sync);
    const int error = errno;
    free(objects);
    errno = error;
    return result;
}

// --- timestamps --------------------------------------------------------------------------------
//
// The call that reads how far a context has got is refused. The kernel also publishes those
// counters in a page any process may map read-only though, the "memstore", which is how
// Qualcomm's own driver follows them, and reading that costs no system call at all.
//
// Should the page not be available, the timestamps handed out on submission are noted and "the
// last retired one" is found by asking, one by one, whether they have been reached. That call
// can only wait: a timeout of zero means forever, so the shortest real one is used, and Turnip,
// which asks on every submission, then spends its time waiting for the GPU.

struct kgsl_shadowprop {
    unsigned long gpuaddr;
    size_t size;
    unsigned int flags;
};

struct kgsl_device_getproperty {
    unsigned int type;
    void* value;
    size_t sizebytes;
};
#define KGSL_PROP_DEVICE_SHADOW 0x2
#define IOCTL_KGSL_DEVICE_GETPROPERTY _IOWR(KGSL_IOC_TYPE, 0x2, struct kgsl_device_getproperty)

/// One entry per context id.
struct kgsl_devmemstore {
    volatile unsigned int soptimestamp; // last command batch started
    unsigned int sbz;
    volatile unsigned int eoptimestamp; // last command batch finished
    unsigned int sbz2;
    volatile unsigned int preempted;
    unsigned int sbz3;
    volatile unsigned int ref_wait_ts;
    unsigned int sbz4;
    unsigned int current_context;
    unsigned int sbz5;
};

#define KGSL_TIMESTAMP_CONSUMED 1
#define KGSL_TIMESTAMP_RETIRED 2

#define MAX_CONTEXTS 16
#define MAX_PENDING 256

struct context_state {
    unsigned int id;
    int used;
    unsigned int newest;                 // last timestamp handed out
    unsigned int retired;                // last timestamp known to be done
    unsigned int pending[MAX_PENDING];   // submitted and not yet seen done, oldest first
    unsigned int count;
};

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static struct context_state g_contexts[MAX_CONTEXTS];
static const struct kgsl_devmemstore* g_memstore;
static size_t g_memstore_entries;
static int g_memstore_tried;

/// Called with the lock held.
static void map_memstore(int fd) {
    g_memstore_tried = 1;
    struct kgsl_shadowprop shadow;
    memset(&shadow, 0, sizeof(shadow));
    struct kgsl_device_getproperty property;
    memset(&property, 0, sizeof(property));
    property.type = KGSL_PROP_DEVICE_SHADOW;
    property.value = &shadow;
    property.sizebytes = sizeof(shadow);
    if (kernel_ioctl(fd, IOCTL_KGSL_DEVICE_GETPROPERTY, &property) != 0 || shadow.size == 0) {
        fprintf(stderr, "kgsl_compat: no timestamp page (%s), GPU waits will be slow\n",
                strerror(errno));
        return;
    }
    // The kernel recognises the mapping by its offset and insists on read-only and the full size.
    void* mapping = mmap(NULL, shadow.size, PROT_READ, MAP_SHARED, fd, (off_t)shadow.gpuaddr);
    if (mapping == MAP_FAILED) {
        fprintf(stderr,
                "kgsl_compat: cannot map the timestamp page (%s), GPU waits will be slow\n",
                strerror(errno));
        return;
    }
    g_memstore = mapping;
    g_memstore_entries = shadow.size / sizeof(struct kgsl_devmemstore);
    fprintf(stderr, "kgsl_compat: reading timestamps from the kernel page, %zu contexts\n",
            g_memstore_entries);
}

static struct context_state* find_context(unsigned int id) {
    struct context_state* unused = NULL;
    for (int i = 0; i < MAX_CONTEXTS; ++i) {
        if (g_contexts[i].used && g_contexts[i].id == id) {
            return &g_contexts[i];
        }
        if (!g_contexts[i].used && unused == NULL) {
            unused = &g_contexts[i];
        }
    }
    if (unused == NULL) {
        // Contexts come and go rarely; recycle the first slot rather than fail.
        unused = &g_contexts[0];
    }
    memset(unused, 0, sizeof(*unused));
    unused->used = 1;
    unused->id = id;
    return unused;
}

static void note_submission(unsigned int context_id, unsigned int timestamp) {
    pthread_mutex_lock(&g_lock);
    struct context_state* context = find_context(context_id);
    context->newest = timestamp;
    if (g_memstore == NULL) {
        if (context->count == MAX_PENDING) {
            // Nobody asked for a long time. The oldest half is done for sure by now.
            context->retired = context->pending[MAX_PENDING / 2 - 1];
            memmove(context->pending, context->pending + MAX_PENDING / 2,
                    sizeof(context->pending[0]) * (MAX_PENDING / 2));
            context->count = MAX_PENDING / 2;
        }
        context->pending[context->count++] = timestamp;
    }
    pthread_mutex_unlock(&g_lock);
}

static int is_retired(int fd, unsigned int context_id, unsigned int timestamp) {
    struct kgsl_device_waittimestamp_ctxtid wait;
    wait.context_id = context_id;
    wait.timestamp = timestamp;
    wait.timeout = 1;
    return kernel_ioctl(fd, IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID, &wait) == 0;
}

static int read_timestamp(int fd, struct kgsl_cmdstream_readtimestamp_ctxtid* request) {
    const int saved_errno = errno;
    pthread_mutex_lock(&g_lock);
    if (!g_memstore_tried) {
        map_memstore(fd);
    }
    struct context_state* context = find_context(request->context_id);
    if (request->type != KGSL_TIMESTAMP_CONSUMED && request->type != KGSL_TIMESTAMP_RETIRED) {
        // Queued: the newest one handed out.
        request->timestamp = context->newest;
    } else if (g_memstore != NULL && request->context_id < g_memstore_entries) {
        const struct kgsl_devmemstore* entry = &g_memstore[request->context_id];
        request->timestamp = request->type == KGSL_TIMESTAMP_RETIRED ? entry->eoptimestamp
                                                                     : entry->soptimestamp;
    } else {
        // Submissions retire in order: drop every leading one that is done.
        unsigned int done = 0;
        while (done < context->count &&
               is_retired(fd, request->context_id, context->pending[done])) {
            context->retired = context->pending[done];
            ++done;
        }
        if (done > 0) {
            memmove(context->pending, context->pending + done,
                    sizeof(context->pending[0]) * (context->count - done));
            context->count -= done;
        }
        request->timestamp = context->retired;
    }
    pthread_mutex_unlock(&g_lock);
    errno = saved_errno;
    return 0;
}

// --- priority ----------------------------------------------------------------------------------
//
// The GPU works through the commands of several programs: here the emulator's, the host app's
// (which copies each finished picture to where the headset's compositor takes it from) and the
// compositor's. The kernel driver keeps one queue per priority level and lets a higher one
// interrupt a lower one. Turnip asks for no priority, which makes the emulator the equal of the
// host app: the app's small copy then waits behind everything the emulator has queued up, tens
// of milliseconds when the game is busy, and a picture that is ready is not shown.
//
// KGSL_COMPAT_PRIORITY=<n> gives the emulator's GPU contexts priority n instead: 0 is the
// highest, 8 what a context gets when it asks for nothing, 12 to 15 the lowest level. Should the
// kernel refuse, the context is created the way the driver asked for it.

struct kgsl_drawctxt_create {
    unsigned int flags;
    unsigned int drawctxt_id;
};

#define KGSL_CONTEXT_PRIORITY_MASK 0x0000f000u
#define KGSL_CONTEXT_PRIORITY_SHIFT 12

static int create_context(int fd, unsigned long request, struct kgsl_drawctxt_create* create) {
    const unsigned int asked = create->flags;
    const char* setting = getenv("KGSL_COMPAT_PRIORITY");
    const int priority = setting != NULL && setting[0] != '\0' ? atoi(setting) : -1;
    if (priority >= 0 && priority <= 15) {
        create->flags = (asked & ~KGSL_CONTEXT_PRIORITY_MASK) |
                        ((unsigned int)priority << KGSL_CONTEXT_PRIORITY_SHIFT);
    }
    int result = kernel_ioctl(fd, request, create);
    if (result != 0 && create->flags != asked) {
        const int error = errno;
        create->flags = asked;
        result = kernel_ioctl(fd, request, create);
        fprintf(stderr, "kgsl_compat: priority %d refused (%s), context created as asked\n",
                priority, strerror(error));
    }
    if (result == 0) {
        // The kernel writes back what the context got.
        fprintf(stderr, "kgsl_compat: GPU context %u, priority %u (flags 0x%x, asked 0x%x)\n",
                create->drawctxt_id,
                (create->flags & KGSL_CONTEXT_PRIORITY_MASK) >> KGSL_CONTEXT_PRIORITY_SHIFT,
                create->flags, asked);
    }
    return result;
}

// --- tracing -----------------------------------------------------------------------------------
//
// KGSL_COMPAT_TRACE=1 in the environment logs every submission and every timestamp call to
// stderr, with the calling thread and a millisecond clock: enough to see why a fence does not
// signal or what a thread is waiting for.

struct kgsl_timestamp_event {
    int type;
    unsigned int timestamp;
    unsigned int context_id;
    void* priv;
    size_t len;
};

static int tracing(void) {
    static int enabled = -1;
    if (enabled < 0) {
        enabled = getenv("KGSL_COMPAT_TRACE") != NULL;
    }
    return enabled;
}

static void trace(const char* format, ...) {
    const int saved_errno = errno;
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    char line[256];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(line, sizeof(line), format, arguments);
    va_end(arguments);
    fprintf(stderr, "kgsl %ld.%03ld [%ld] %s\n", (long)(now.tv_sec % 1000),
            now.tv_nsec / 1000000, (long)syscall(SYS_gettid), line);
    errno = saved_errno;
}

// --- entry point -------------------------------------------------------------------------------

int ioctl(int fd, unsigned long request, ...) {
    va_list arguments;
    va_start(arguments, request);
    void* arg = va_arg(arguments, void*);
    va_end(arguments);

    if (_IOC_TYPE(request) != KGSL_IOC_TYPE || arg == NULL) {
        return kernel_ioctl(fd, request, arg);
    }

    switch (_IOC_NR(request)) {
    case NR_DRAWCTXT_CREATE:
        return create_context(fd, request, arg);
    case NR_GPUMEM_ALLOC_ID:
        return gpumem_alloc_id(fd, arg);
    case NR_GPUMEM_FREE_ID:
        return gpumem_free_id(fd, arg);
    case NR_GPUMEM_GET_INFO:
        return gpumem_get_info(fd, arg);
    case NR_GPUMEM_SYNC_CACHE:
        return gpumem_sync_cache(fd, arg);
    case NR_GPUMEM_SYNC_CACHE_BULK:
        return gpumem_sync_cache_bulk(fd, arg);
    case NR_READTIMESTAMP_CTXTID: {
        const int result = read_timestamp(fd, arg);
        if (tracing()) {
            const struct kgsl_cmdstream_readtimestamp_ctxtid* read = arg;
            trace("read context %u type %u -> %u", read->context_id, read->type,
                  read->timestamp);
        }
        return result;
    }
    case NR_WAITTIMESTAMP_CTXTID: {
        const struct kgsl_device_waittimestamp_ctxtid* wait = arg;
        const unsigned int timestamp = wait->timestamp;
        const unsigned int timeout = wait->timeout;
        const int result = kernel_ioctl(fd, request, arg);
        if (tracing()) {
            trace("wait context %u for %u, timeout %u -> %d%s%s", wait->context_id, timestamp,
                  timeout, result, result != 0 ? " " : "", result != 0 ? strerror(errno) : "");
        }
        return result;
    }
    case NR_TIMESTAMP_EVENT: {
        const int result = kernel_ioctl(fd, request, arg);
        if (tracing()) {
            const struct kgsl_timestamp_event* event = arg;
            trace("fence for context %u timestamp %u -> %d", event->context_id,
                  event->timestamp, result);
        }
        return result;
    }
    case NR_GPU_COMMAND: {
        const int result = kernel_ioctl(fd, request, arg);
        const struct kgsl_gpu_command* command = arg;
        if (result == 0) {
            note_submission(command->context_id, command->timestamp);
        }
        if (tracing()) {
            trace("submit context %u, %u commands, %u sync points -> %d timestamp %u%s%s",
                  command->context_id, command->numcmds, command->numsyncs, result,
                  command->timestamp, result != 0 ? " " : "", result != 0 ? strerror(errno) : "");
        }
        return result;
    }
    case NR_GPU_AUX_COMMAND: {
        const int result = kernel_ioctl(fd, request, arg);
        if (result == 0) {
            const struct kgsl_gpu_aux_command* command = arg;
            note_submission(command->context_id, command->timestamp);
        }
        return result;
    }
    default:
        return kernel_ioctl(fd, request, arg);
    }
}
