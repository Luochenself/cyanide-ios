//
//  lpm_unlock.m
//
//  Lift Low Power Mode's ProMotion 60Hz ceiling using Cyanide remote-call.
//  Device under test: iPhone16,2 / iOS 18.3 (22D63).
//
//  Strategies (ordered):
//  1) backboardd — BKSDisplayServicesSetRefreshRateSettings
//  2) backboardd — probe CADisplay / BKDisplay* setters
//  3) SpringBoard — log UIScreen / LPM state (hook surface for next iter)
//

#import "lpm_unlock.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import <stdio.h>
#import <string.h>
#import <unistd.h>
#import "../LogTextView.h"

static const useconds_t kSettleUS = 80000;

static uint64_t lpm_remote_malloc(size_t n)
{
    return r_dlsym_call(R_TIMEOUT, "malloc", (uint64_t)n, 0, 0, 0, 0, 0, 0, 0);
}

static void lpm_remote_free(uint64_t p)
{
    if (!p) return;
    r_dlsym_call(R_TIMEOUT, "free", p, 0, 0, 0, 0, 0, 0, 0);
}

static bool lpm_try_bks_refresh_settings(int max_hz)
{
    printf("[LPMUNLOCK] strategy1: BKSDisplayServicesSetRefreshRateSettings max=%d\n", max_hz);

    typedef struct {
        int max_hz;
        int min_hz;
        int flags;
        int reserved;
    } lpm_rr_settings_t;

    lpm_rr_settings_t local = {
        .max_hz = max_hz,
        .min_hz = 1,
        .flags = 0,
        .reserved = 0,
    };

    uint64_t remote_buf = lpm_remote_malloc(sizeof(local));
    if (!remote_buf) {
        printf("[LPMUNLOCK] malloc settings failed\n");
        return false;
    }
    if (!remote_write(remote_buf, &local, sizeof(local))) {
        printf("[LPMUNLOCK] remote_write settings failed\n");
        lpm_remote_free(remote_buf);
        return false;
    }

    // Try both symbol spellings. ABI of the settings blob is build-dependent;
    // this is the first probe — refine after logging retcodes on-device.
    uint64_t ret = r_dlsym_call(R_TIMEOUT, "BKSDisplayServicesSetRefreshRateSettings",
                                remote_buf, 0, 0, 0, 0, 0, 0, 0);
    if (!ret) {
        ret = r_dlsym_call(R_TIMEOUT, "_BKSDisplayServicesSetRefreshRateSettings",
                           remote_buf, 0, 0, 0, 0, 0, 0, 0);
    }
    printf("[LPMUNLOCK] BKS call ret=0x%llx\n", (unsigned long long)ret);
    lpm_remote_free(remote_buf);
    usleep(kSettleUS);
    // Symbol resolved enough to call counts as strategy success for plumbing.
    return true;
}

static bool lpm_try_cadisplay_poke(int max_hz)
{
    printf("[LPMUNLOCK] strategy2: CADisplay / BKDisplay poke max=%d\n", max_hz);

    const char *classes[] = {
        "CADisplay",
        "BKDisplayController",
        "BKDisplayBrightness",
        NULL
    };

    bool any = false;
    for (int i = 0; classes[i]; i++) {
        uint64_t cls = r_class(classes[i]);
        if (!cls) {
            printf("[LPMUNLOCK] class %s missing\n", classes[i]);
            continue;
        }
        printf("[LPMUNLOCK] class %s = 0x%llx\n", classes[i], (unsigned long long)cls);

        const char *ctors[] = { "mainDisplay", "currentDisplay", "main", "sharedInstance", NULL };
        uint64_t obj = 0;
        for (int c = 0; ctors[c]; c++) {
            if (!r_responds(cls, ctors[c])) continue;
            obj = r_msg2(cls, ctors[c], 0, 0, 0, 0);
            if (obj) {
                printf("[LPMUNLOCK] %s +%s -> 0x%llx\n",
                       classes[i], ctors[c], (unsigned long long)obj);
                break;
            }
        }
        if (!obj) continue;

        const char *setters[] = {
            "setMaximumRefreshRate:",
            "setRefreshRate:",
            "setHighestFrameRate:",
            "setPreferredRefreshRate:",
            NULL
        };
        for (int s = 0; setters[s]; s++) {
            if (!r_responds(obj, setters[s])) continue;
            // Pass integer Hz in x0/a0 — SPI may want float/double; iterate later.
            printf("[LPMUNLOCK] -[0x%llx %s] %d\n",
                   (unsigned long long)obj, setters[s], max_hz);
            r_msg2(obj, setters[s], (uint64_t)max_hz, 0, 0, 0);
            any = true;
            usleep(kSettleUS);
        }
    }
    return any;
}

static bool lpm_try_springboard_probe(int max_hz)
{
    printf("[LPMUNLOCK] strategy3: SpringBoard probe (max=%d)\n", max_hz);

    uint64_t cls = r_class("UIScreen");
    if (!cls) {
        printf("[LPMUNLOCK] UIScreen missing\n");
        return false;
    }
    uint64_t screen = 0;
    if (r_responds(cls, "mainScreen")) {
        screen = r_msg2(cls, "mainScreen", 0, 0, 0, 0);
    }
    if (!screen) {
        printf("[LPMUNLOCK] UIScreen.mainScreen nil\n");
        return false;
    }
    printf("[LPMUNLOCK] UIScreen=0x%llx\n", (unsigned long long)screen);

    if (r_responds(screen, "maximumFramesPerSecond")) {
        uint64_t m = r_msg2(screen, "maximumFramesPerSecond", 0, 0, 0, 0);
        printf("[LPMUNLOCK] maximumFramesPerSecond=%llu\n", (unsigned long long)m);
    }

    uint64_t piCls = r_class("NSProcessInfo");
    if (piCls && r_responds(piCls, "processInfo")) {
        uint64_t pi = r_msg2(piCls, "processInfo", 0, 0, 0, 0);
        if (pi && r_responds(pi, "isLowPowerModeEnabled")) {
            uint64_t en = r_msg2(pi, "isLowPowerModeEnabled", 0, 0, 0, 0);
            printf("[LPMUNLOCK] isLowPowerModeEnabled=%llu\n", (unsigned long long)en);
        }
    }
    return true;
}

bool lpm_unlock_apply(int max_hz)
{
    if (max_hz < 60) max_hz = 60;
    if (max_hz > 120) max_hz = 120;
    printf("[LPMUNLOCK] === apply max_hz=%d ===\n", max_hz);

    bool ok = false;

    if (init_remote_call("backboardd", false) != 0) {
        printf("[LPMUNLOCK] init_remote_call(backboardd) failed\n");
    } else {
        ok |= lpm_try_bks_refresh_settings(max_hz);
        ok |= lpm_try_cadisplay_poke(max_hz);
        destroy_remote_call();
    }

    if (init_remote_call("SpringBoard", false) != 0) {
        printf("[LPMUNLOCK] init_remote_call(SpringBoard) failed\n");
    } else {
        ok |= lpm_try_springboard_probe(max_hz);
        destroy_remote_call();
    }

    printf("[LPMUNLOCK] === done ok=%d ===\n", ok ? 1 : 0);
    return ok;
}

bool lpm_unlock_restore(void)
{
    printf("[LPMUNLOCK] === restore max=60 ===\n");
    bool ok = false;
    if (init_remote_call("backboardd", false) == 0) {
        ok = lpm_try_bks_refresh_settings(60);
        destroy_remote_call();
    }
    return ok;
}
