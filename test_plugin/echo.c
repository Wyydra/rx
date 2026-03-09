#include "../rx/include/rx_api.h"
#include <stdio.h>

static void echo_handler(void* ctx, rx_value_t msg, rx_scheduler_t* sched) {
    (void)ctx; (void)sched;
    fprintf(stderr, "Echo port received a message! tag=%llu\n",
            (unsigned long long)(msg.bits & RX_TAG_MASK));
}

void rx_load(rx_scheduler_t* sched) {
    uint32_t pid = rx_spawn_port(sched, NULL, echo_handler, NULL);
    if (pid != 0) rx_register_port(sched, "echo", pid);
}
