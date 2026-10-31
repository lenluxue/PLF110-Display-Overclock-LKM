// SPDX-License-Identifier: GPL-2.0-only
/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef PLF110_BRIGHTNESS_GAIN_H
#define PLF110_BRIGHTNESS_GAIN_H

/* Integer fixed-point: 865 means 86.5%, never floating point in the kernel. */
#define PLF_GAIN_SCALE 10U
#define PLF_GAIN_MIN 700U
#define PLF_GAIN_MAX 1000U

/* Parse one percentage, leaving a colon/whitespace/end for the caller.
 * Accept existing integer percentages and exactly one optional decimal digit.
 * Reject excess precision rather than silently rounding a user's value. */
static inline int plf_parse_gain(const char **cursor, unsigned int *units)
{
    const char *p = *cursor;
    unsigned int whole = 0, digits = 0, value;
    while (*p >= '0' && *p <= '9') {
        if (++digits > 5) return -1;
        whole = whole * 10 + (*p++ - '0');
    }
    if (!digits) return -1;
    value = whole * PLF_GAIN_SCALE;
    if (*p == '.') {
        p++;
        if (*p < '0' || *p > '9') return -1;
        value += *p++ - '0';
        if (*p >= '0' && *p <= '9') return -1;
    }
    if (value < PLF_GAIN_MIN || value > PLF_GAIN_MAX) return -1;
    *cursor = p;
    *units = value;
    return 0;
}

static inline unsigned int plf_gain_target(unsigned int request,
    unsigned int units)
{
    unsigned int output;
    if (request <= 1 || request > 3515) return request;
    output = (request * units + 500U) / 1000U;
    return output < 2 ? 2 : output;
}
#endif
