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

/* One aligned ARM64 word is the whole profile: readers never see a mixture
 * of two updates. No new kernel locks, imports, allocation or floating point. */
typedef unsigned long long plf_curve_word;
#define PLF_CURVE_ENABLE (1ULL << 63)
#define PLF_CURVE_CORE_MASK (PLF_CURVE_ENABLE | ((1ULL << 42) - 1))
/* Additional output correction is restricted to the two tails. */
#define PLF_LOW_FULL_DBV 4U
#define PLF_LOW_END_DBV 64U
#define PLF_HIGH_START_DBV 3072U
#define PLF_HIGH_EXTRA_MAX 50U /* 5.0 percentage points; derivative stays positive. */
static inline unsigned int plf_curve_low_extra(plf_curve_word v) { return (v >> 42) & 1U; }
static inline unsigned int plf_curve_high_extra(plf_curve_word v) { return (v >> 43) & 63U; }
static inline unsigned int plf_curve_pivot(plf_curve_word v) { return v & 4095U; }
static inline unsigned int plf_curve_low(plf_curve_word v) { return (v >> 12) & 1023U; }
static inline unsigned int plf_curve_mid(plf_curve_word v) { return (v >> 22) & 1023U; }
static inline unsigned int plf_curve_high(plf_curve_word v) { return (v >> 32) & 1023U; }
static inline int plf_curve_valid(plf_curve_word v)
{
    unsigned int pivot, low, mid, high;
    if (!v) return 1;
    if (!(v & PLF_CURVE_ENABLE) || (v & ~(PLF_CURVE_ENABLE | ((1ULL << 49) - 1))))
        return 0;
    pivot = plf_curve_pivot(v); low = plf_curve_low(v);
    mid = plf_curve_mid(v); high = plf_curve_high(v);
    return pivot >= 3 && pivot <= 3514 && low >= PLF_GAIN_MIN &&
        low <= mid && mid <= high && high <= PLF_GAIN_MAX &&
        plf_curve_high_extra(v) <= PLF_HIGH_EXTRA_MAX;
}
static inline int plf_curve_end(const char *p)
{
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    return !*p;
}
/* Percent with 0.1-point resolution, restricted to 0..5.0. */
static inline int plf_parse_extra(const char **cursor, unsigned int *units)
{
    const char *p = *cursor;
    unsigned int whole = 0, digits = 0, v;
    while (*p >= '0' && *p <= '9') {
        if (++digits > 2) return -1;
        whole = whole * 10 + (*p++ - '0');
    }
    if (!digits) return -1;
    v = whole * 10;
    if (*p == '.') {
        p++;
        if (*p < '0' || *p > '9') return -1;
        v += *p++ - '0';
        if (*p >= '0' && *p <= '9') return -1;
    }
    if (v > PLF_HIGH_EXTRA_MAX) return -1;
    *cursor = p; *units = v; return 0;
}
/* Existing five fields stay valid. Optional two fields are:
 * LOW_EXTRA_DBV(0/1):HIGH_EXTRA_PERCENT(0..5.0), enabled only by curve_api=2.
 * One u64 still publishes the complete core+tails without torn updates. */
static inline int plf_parse_curve(const char *p, plf_curve_word *out)
{
    unsigned int pivot = 0, digits = 0, low, mid, high, low_extra = 0, high_extra = 0;
    plf_curve_word v;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (*p == '0' && plf_curve_end(p + 1)) { *out = 0; return 0; }
    if (*p++ != '1' || *p++ != ':') return -1;
    while (*p >= '0' && *p <= '9') {
        if (++digits > 4) return -1;
        pivot = pivot * 10 + (*p++ - '0');
    }
    if (!digits || *p++ != ':' || plf_parse_gain(&p, &low) ||
        *p++ != ':' || plf_parse_gain(&p, &mid) ||
        *p++ != ':' || plf_parse_gain(&p, &high) ||
        pivot < 3 || pivot > 3514 || low > mid || mid > high) return -1;
    if (*p == ':') {
        p++;
        if ((*p != '0' && *p != '1') || p[1] != ':') return -1;
        low_extra = *p - '0'; p += 2;
        if (plf_parse_extra(&p, &high_extra)) return -1;
    }
    if (!plf_curve_end(p)) return -1;
    v = PLF_CURVE_ENABLE | pivot | ((plf_curve_word)low << 12) |
        ((plf_curve_word)mid << 22) | ((plf_curve_word)high << 32) |
        ((plf_curve_word)low_extra << 42) | ((plf_curve_word)high_extra << 43);
    if (!plf_curve_valid(v)) return -1;
    *out = v; return 0;
}
static inline unsigned int plf_curve_gain(unsigned int request,
    unsigned int base, plf_curve_word v)
{
    unsigned int pivot, low, mid, high, interp, span, distance;
    int effective;
    /* 100% remains the original global no-compensation control. */
    if (base == PLF_GAIN_MAX || request <= 1 || request > 3515 || !v ||
        !plf_curve_valid(v)) return base;
    pivot = plf_curve_pivot(v); low = plf_curve_low(v);
    mid = plf_curve_mid(v); high = plf_curve_high(v);
    if (request <= pivot) {
        span = pivot - 2; distance = request - 2;
        interp = low + ((mid - low) * distance + span / 2) / span;
    } else {
        span = 3515 - pivot; distance = request - pivot;
        interp = mid + ((high - mid) * distance + span / 2) / span;
    }
    effective = (int)base + (int)interp - (int)mid;
    if (effective < (int)PLF_GAIN_MIN) effective = PLF_GAIN_MIN;
    if (effective > (int)PLF_GAIN_MAX) effective = PLF_GAIN_MAX;
    return (unsigned int)effective;
}
static inline unsigned int plf_curve_target(unsigned int request,
    unsigned int base, plf_curve_word v)
{
    unsigned int gain = plf_curve_gain(request, base, v);
    unsigned int low_extra, high_extra, span, numerator, denominator, output;
    if (base == PLF_GAIN_MAX || request <= 1 || request > 3515 || !v ||
        !plf_curve_valid(v)) return plf_gain_target(request, gain);
    low_extra = plf_curve_low_extra(v); high_extra = plf_curve_high_extra(v);
    if (low_extra && request < PLF_LOW_END_DBV) {
        if (request <= PLF_LOW_FULL_DBV) {
            numerator = request * gain - low_extra * 1000U;
            denominator = 1000U;
        } else {
            span = PLF_LOW_END_DBV - PLF_LOW_FULL_DBV;
            numerator = request * gain * span -
                low_extra * 1000U * (PLF_LOW_END_DBV - request);
            denominator = 1000U * span;
        }
    } else if (high_extra && request > PLF_HIGH_START_DBV) {
        span = 3515U - PLF_HIGH_START_DBV;
        numerator = request * gain * span -
            request * high_extra * (request - PLF_HIGH_START_DBV);
        denominator = 1000U * span;
    } else return plf_gain_target(request, gain);
    /* Single final rounding preserves the soft tail and monotonic output.
     * Subtracting a separately rounded integer could produce a downward step. */
    output = (numerator + denominator / 2) / denominator;
    return output < 2 ? 2 : output;
}
#endif
