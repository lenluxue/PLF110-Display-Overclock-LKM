/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef PLF110_BRIGHTNESS_CONFIG_H
#define PLF110_BRIGHTNESS_CONFIG_H
#include <stddef.h>
#include <string.h>
#include "brightness_gain.h"

#define PLF_BRIGHTNESS_CONFIG_CAP 512U
struct plf_brightness_config {
    unsigned int gain;
    unsigned int sync;
    plf_curve_word curve;
};

static inline char *plf_config_trim(char *p)
{
    while (*p == ' ' || *p == '\t' || *p == '\r') p++;
    char *end = p + strlen(p);
    while (end > p && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r')) --end;
    *end = 0;
    return p;
}

/* Parse the entire profile before publishing any field. No shell evaluation.
 * Duplicate/unknown/missing keys, NULs and oversized files are rejected.
 * The caller retains its last validated profile on a partial/invalid edit. */
static inline int plf_parse_brightness_config(const char *text, size_t length,
    struct plf_brightness_config *out)
{
    char buffer[PLF_BRIGHTNESS_CONFIG_CAP];
    struct plf_brightness_config next = {0};
    unsigned int seen = 0;
    if (!length || length >= sizeof(buffer) || memchr(text, 0, length)) return -1;
    memcpy(buffer, text, length); buffer[length] = 0;
    for (char *line = buffer; line;) {
        char *following = strchr(line, '\n');
        if (following) *following++ = 0;
        char *key = plf_config_trim(line);
        if (*key && *key != '#') {
            char *value = strchr(key, '=');
            if (!value) return -1;
            *value++ = 0;
            key = plf_config_trim(key); value = plf_config_trim(value);
            unsigned int bit;
            if (!strcmp(key, "gain")) {
                bit = 1; const char *p = value;
                if (plf_parse_gain(&p, &next.gain) || !plf_curve_end(p)) return -1;
            } else if (!strcmp(key, "sync")) {
                bit = 2;
                if (!strcmp(value, "0")) next.sync = 0;
                else if (!strcmp(value, "1")) next.sync = 1;
                else return -1;
            } else if (!strcmp(key, "curve")) {
                bit = 4;
                if (plf_parse_curve(value, &next.curve)) return -1;
            } else return -1;
            if (seen & bit) return -1;
            seen |= bit;
        }
        line = following;
    }
    if (seen != 7) return -1;
    *out = next;
    return 0;
}
#endif
