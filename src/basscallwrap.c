#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>

typedef int BOOL;

// values taken from bass.h
#define BASS_CONFIG_DEV_BUFFER		27
#define BASS_CONFIG_DEV_PERIOD		53

#define PFX	"osu-latency-tweaker: "

int BASSCALLWRAP_getenv_int(const char *name, int default_) {
    const char *env = getenv(name);
    if (!env || *env == '\0') {
        fprintf(stderr, PFX"env %s not set or empty, using default: %d\n", name, default_);
        return default_;
    }

    char *end;
    errno = 0;
    long val = strtol(env, &end, 10);

    if (errno != 0 || *end != '\0' || val < INT_MIN || val > INT_MAX) {
        fprintf(stderr, PFX"invalid value for env %s='%s', using default: %d\n", name, env, default_);
        return default_;
    }

    fprintf(stderr, PFX"envvar OK: %s=%d\n", name, val);
    return (int)val;
}

typedef int (*bass_setconfig_fn_t)(
    int option,
    int value
);

// https://www.un4seen.com/doc/#bass/BASS_SetConfig.html
void BASSCALLWRAP_BASS_SetConfig(int option, int value) {
    static bass_setconfig_fn_t BASS_SetConfig = NULL;

    if (!BASS_SetConfig) {
        BASS_SetConfig = (bass_setconfig_fn_t)dlsym(RTLD_DEFAULT, "BASS_SetConfig");
    }

    fprintf(stderr, PFX"BASS_SetConfig call (option=%d, value=%d)\n", option, value);

    BASS_SetConfig(option, value);
}

typedef int (*bass_init_fn_t)(
    int device,
    int freq,
    int flags,
    int *win,
    int *clsid
);

// https://www.un4seen.com/doc/#bass/BASS_Init.html
BOOL BASS_Init(int device, int _freq, int flags, int *win, int *clsid) {
    static bass_init_fn_t BASS_Init__orig = NULL;

    fprintf(stderr, PFX"BASS_Init intercepted!\n");

    if (!BASS_Init__orig) {
        BASS_Init__orig = (bass_init_fn_t)dlsym(RTLD_DEFAULT, "BASS_Init__orig");
    }

    int forced_freq = BASSCALLWRAP_getenv_int("OSU_LATENCY_TWEAKER_FREQ", 44100);
    fprintf(stderr, PFX"requested=%d, forcing=%d\n", _freq, forced_freq);

    // Device period normally is in milliseconds, but it might be set to a negative
    // value too for an exact sample size, e.g. -256 for 256 samples.
    // https://www.un4seen.com/doc/#bass/BASS_CONFIG_DEV_PERIOD.html
    BASSCALLWRAP_BASS_SetConfig(BASS_CONFIG_DEV_PERIOD, BASSCALLWRAP_getenv_int("OSU_LATENCY_TWEAKER_PERIOD", -256));

    // 1ms is definitely too low, but we're setting such low number on purpose,
    // in order for BASS to automatically set it to twice the length of BASS_CONFIG_DEV_PERIOD,
    // This behaviour is documented.
    // https://www.un4seen.com/doc/#bass/BASS_CONFIG_DEV_BUFFER.html
    BASSCALLWRAP_BASS_SetConfig(BASS_CONFIG_DEV_BUFFER, 1);

    return BASS_Init__orig(device, forced_freq, flags, win, clsid);
}
