// One-shot fallback when hs.spaces.moveWindowToSpace silently does nothing.
// The bridge used by yabai/ferry is private; look it up at runtime and fail
// closed if its class, selector or function is unavailable after an OS update.
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/nlist.h>
#import <objc/message.h>

static void *bridge(void) {
    const char *name = "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation";
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *path = _dyld_get_image_name(index);
        if (!path || !strstr(path, "/SkyLight.framework/")) continue;
        const struct mach_header_64 *image = (const void *)_dyld_get_image_header(index);
        if (image->magic != MH_MAGIC_64) return NULL;
        intptr_t slide = _dyld_get_image_vmaddr_slide(index);
        const struct segment_command_64 *link = NULL;
        const struct symtab_command *table = NULL;
        const struct load_command *cmd = (const void *)(image + 1);
        for (uint32_t j = 0; j < image->ncmds; j++) {
            if (cmd->cmd == LC_SYMTAB) table = (const void *)cmd;
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const void *)cmd;
                if (!strcmp(segment->segname, SEG_LINKEDIT)) link = segment;
            }
            cmd = (const void *)((const char *)cmd + cmd->cmdsize);
        }
        if (!link || !table) return NULL;
        const char *base = (const char *)(slide + link->vmaddr - link->fileoff);
        const struct nlist_64 *entries = (const void *)(base + table->symoff);
        for (uint32_t j = 0; j < table->nsyms; j++) {
            uint32_t str = entries[j].n_un.n_strx;
            if (str < table->strsize && entries[j].n_value && (entries[j].n_type & N_TYPE) == N_SECT
                && !strcmp(base + table->stroff + str, name))
                return (void *)(slide + entries[j].n_value);
        }
        return NULL;
    }
    return NULL;
}

static uint64_t number(const char *s, uint64_t maximum) {
    if (!*s || strspn(s, "0123456789") != strlen(s)) return 0;
    char *end; errno = 0;
    uint64_t value = strtoull(s, &end, 10);
    return !errno && !*end && value <= maximum ? value : 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 4) return 2;
        pid_t pid = (pid_t)number(argv[1], INT_MAX);
        CGWindowID wid = (CGWindowID)number(argv[2], UINT32_MAX);
        uint64_t space = number(argv[3], UINT64_MAX);
        if (!pid || !wid || !space) return 2;
        NSArray *rows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, wid));
        NSDictionary *row = rows.firstObject;
        if ([row[(id)kCGWindowOwnerPID] intValue] != pid || [row[(id)kCGWindowNumber] unsignedIntValue] != wid
            || [row[(id)kCGWindowLayer] intValue] != 0) return 3;
        void *lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!lib) return 4;
        int (*connection)(void) = dlsym(lib, "SLSMainConnectionID");
        int (*spaceType)(int, uint64_t) = dlsym(lib, "SLSSpaceGetType");
        void (*submit)(id) = bridge();
        Class cls = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
        SEL initialize = NSSelectorFromString(@"initWithWindows:spaceID:");
        if (!submit || !connection || !spaceType || ![cls instancesRespondToSelector:initialize]) return 4;
        if (spaceType(connection(), space) != 0) return 3;
        @try {
            id request = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)([cls alloc], initialize, @[@(wid)], space);
            if (!request) return 4;
            submit(request);
        } @catch (NSException *exception) { return 4; }
        return 0; // Hammerspoon checks the window's membership before raising it.
    }
}
