#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

extern int64_t athena3_budget_uj(int64_t capacity, int64_t standby,
        int64_t sensors, int64_t radio, int64_t autonomous);
extern int64_t yokai_max_left(int64_t stock, int64_t consumed);

static int check(const char *name, int64_t actual, int64_t expected)
{
    if (actual != expected) {
        fprintf(stderr, "FAIL: %s: expected %" PRId64 ", got %" PRId64 "\n",
                name, expected, actual);
        return 0;
    }
    return 1;
}

int main(void)
{
    /* 64-bit values + fifth stack-passed Win64 argument. */
    if (!check("athena3/energy-budget",
            athena3_budget_uj(INT64_C(8589934592), 31, 97, 503, 11),
            INT64_C(8589933950))) return 1;

    /* Autonomous behavior must not be silently ignored. */
    if (!check("athena3/autonomous-consumption",
            athena3_budget_uj(8192, 0, 0, 0, 1337), 6855)) return 1;

    if (!check("athena3/over-budget",
            athena3_budget_uj(10, 9, 17, 25, 11), -52)) return 1;

    if (!check("yokai-max/stock",
            yokai_max_left(13, 12), 1)) return 1;

    puts("PASS: athena3 telemetry / yokai-max stock");
    return 0;
}
