// Tweak.x —— 零依赖注入钩子（不链接 substrate，非越狱机可直接跑）
//
// 用法：
//   1. 把 TARGET_CLASS / 方法名改成你要干的目标（用 frida / class-dump 找）
//   2. make -f Makefile.dylib  （或走 GitHub Actions）
//   3. python tools/patch_ipa.py target.ipa -o out.ipa --dylib HookKit.dylib
//   4. 全能签签名安装
//
// 加载说明：__attribute__((constructor)) 会在 dylib 被 dyld 载入时立刻执行，
// 不需要 substrate、不需要 SpringBoard 注入。

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <unistd.h>
#import <stdlib.h>
#import <string.h>

// ============================================================
// 目标配置：按实际 App 改这里
// ============================================================
#define TARGET_CLASS        "VipManager"        // 目标类名
#define TARGET_VIP_SEL      "isVip"             // 实例方法：是否会员
#define TARGET_JAIL_SEL     "isJailbroken"      // 实例方法：越狱检测
#define TARGET_LOGIN_SEL    "isLoggedIn"        // 实例方法：登录态

// ============================================================
// 通用工具
// ============================================================

/// 替换实例方法实现
static inline BOOL hookInstanceMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    method_setImplementation(m, newImp);
    return YES;
}

/// 替换类方法实现
static inline BOOL hookClassMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NO;
    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;
    method_setImplementation(m, newImp);
    return YES;
}

/// 给类动态添加方法（目标类原本没有该方法时用）
static inline BOOL addInstanceMethod(Class cls, SEL sel, IMP imp, const char *types) {
    if (!cls) return NO;
    return class_addMethod(cls, sel, imp, types);
}

// ============================================================
// Hook 实现体
// ============================================================

static BOOL hk_isVip(id self, SEL _cmd) {
    NSLog(@"[HookKit] isVip -> YES");
    return YES;
}

static BOOL hk_isJailbroken(id self, SEL _cmd) {
    NSLog(@"[HookKit] isJailbroken -> NO");
    return NO;
}

static BOOL hk_isLoggedIn(id self, SEL _cmd) {
    NSLog(@"[HookKit] isLoggedIn -> YES");
    return YES;
}

// 越狱环境常见探测点：批量把它们全部打回“不存在”
static BOOL hk_fileExistsAtPath(id self, SEL _cmd, NSString *path) {
    static NSArray<NSString *> *bad = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bad = @[ @"/Applications/Cydia.app",
                 @"/Library/MobileSubstrate",
                 @"/var/jb",
                 @"/var/lib/dpkg",
                 @"/bin/bash",
                 @"/usr/sbin/sshd",
                 @"/etc/apt",
                 @"/private/var/lib/apt",
                 @"cydia://",
                 @"sileo://" ];
    });
    for (NSString *s in bad) {
        if ([path containsString:s]) {
            NSLog(@"[HookKit] 拦截越狱探针: %@", path);
            return NO;
        }
    }
    // 关键：不能用 objc_msgSend 调回 fileExistsAtPath:，那会递归到我们自己。
    // 直接走 libc 的 access()，等价语义且不会重入。
    if (!path || path.length == 0) return NO;
    return access(path.fileSystemRepresentation, F_OK) == 0;
}

// ============================================================
// 入口
// ============================================================

__attribute__((constructor))
static void HookKitInit(void) {
    NSLog(@"[HookKit] dylib loaded, pid=%d", getpid());

    Class cls = NSClassFromString(@TARGET_CLASS);
    if (!cls) {
        NSLog(@"[HookKit] 类 %s 未找到 —— 确认类名正确，或该 App 还没加载到这个类", TARGET_CLASS);
        // 类可能延迟加载：轮询 20 次，每次 0.5s
        static int tries = 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (++tries > 20) return;
            Class c = NSClassFromString(@TARGET_CLASS);
            if (c) {
                hookInstanceMethod(c, sel_registerName(TARGET_VIP_SEL), (IMP)hk_isVip);
                hookInstanceMethod(c, sel_registerName(TARGET_JAIL_SEL), (IMP)hk_isJailbroken);
                hookInstanceMethod(c, sel_registerName(TARGET_LOGIN_SEL), (IMP)hk_isLoggedIn);
                NSLog(@"[HookKit] 延迟挂钩成功: %s", TARGET_CLASS);
            }
        });
        return;
    }

    BOOL a = hookInstanceMethod(cls, sel_registerName(TARGET_VIP_SEL), (IMP)hk_isVip);
    BOOL b = hookInstanceMethod(cls, sel_registerName(TARGET_JAIL_SEL), (IMP)hk_isJailbroken);
    BOOL c = hookInstanceMethod(cls, sel_registerName(TARGET_LOGIN_SEL), (IMP)hk_isLoggedIn);
    NSLog(@"[HookKit] hook isVip=%d isJailbroken=%d isLoggedIn=%d", a, b, c);

    // 越狱探针：NSFileManager 是系统类，全局生效
    hookInstanceMethod([NSFileManager class], @selector(fileExistsAtPath:), (IMP)hk_fileExistsAtPath);

    // 遍历所有已加载类，自动挂钩同名方法（应对混淆后改名的情况）
    int total = objc_getClassList(NULL, 0);
    if (total > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * total);
        total = objc_getClassList(classes, total);
        for (int i = 0; i < total; i++) {
            Class k = classes[i];
            const char *name = class_getName(k);
            if (!name) continue;
            if (strstr(name, "Vip") || strstr(name, "VIP") || strstr(name, "Member")) {
                if (class_getInstanceMethod(k, sel_registerName(TARGET_VIP_SEL))) {
                    hookInstanceMethod(k, sel_registerName(TARGET_VIP_SEL), (IMP)hk_isVip);
                    NSLog(@"[HookKit] 自动挂钩: %s", name);
                }
            }
        }
        free(classes);
    }
}
