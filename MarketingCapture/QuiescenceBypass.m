#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// XCTest will not tap while SpriteKit is simulating. This test-bundle-only
// replacement makes that wait return immediately. It does not ship in the app.
static void ESPNoopWait(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
}

static void ESPInstallQuiescenceBypass(void) {
    static int installed = 0;
    const char *classes[] = {"XCUIApplicationProcess", "XCUIApplicationProcessTracker", "XCAXClient_iOS"};
    const char *sels[] = {
        // Leave waitForQuiescenceIncludingAnimationsIdle:usingActivity:isPreEvent:
        // alone. While XCTest sits in that wait, the simulator keeps presenting
        // frames and the falling coin shows up in the recording. No-oping it
        // drops the capture to well under one frame per second.
        "waitForQuiescenceIncludingAnimationsIdle:",
        "waitForQuiescenceIncludingAnimationsIdle:isPreEvent:",
    };
    int replaced = 0;
    for (int i = 0; i < (int)(sizeof(classes) / sizeof(classes[0])); i++) {
        Class cls = objc_getClass(classes[i]);
        if (!cls) continue;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int m = 0; m < count; m++) {
            NSString *name = NSStringFromSelector(method_getName(methods[m]));
            NSString *lower = name.lowercaseString;
            if ([lower containsString:@"idle"] || [lower containsString:@"quies"]) {
                NSLog(@"ESP_METHOD %@ %@", NSStringFromClass(cls), name);
            }
        }
        free(methods);
        for (int s = 0; s < (int)(sizeof(sels) / sizeof(sels[0])); s++) {
            Method method = class_getInstanceMethod(cls, sel_registerName(sels[s]));
            if (!method) continue;
            method_setImplementation(method, (IMP)ESPNoopWait);
            replaced++;
            NSLog(@"ESP_SWIZZLED %@ %s", NSStringFromClass(cls), sels[s]);
        }
    }
    if (replaced > 0) installed = replaced;
    NSLog(@"ESP_SWIZZLE_COUNT %d", installed);
}

__attribute__((constructor))
static void ESPInstallAtLoad(void) {
    ESPInstallQuiescenceBypass();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ESPInstallQuiescenceBypass();
    });
}
