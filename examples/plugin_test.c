#include <stdio.h>
#include <unistd.h>
#include "rx_api.h"

void plugin_handler(void* ctx, rx_value_t msg, void* sched) {
    // A simple handler that prints and sleeps minimally to simulate async work.
    printf("[Dynamic Plugin] Received a message! Simulating work...\n");
    usleep(500000); // 0.5 sec
    printf("[Dynamic Plugin] Finished work!\n");
}

void plugin_cleanup(void* ctx) {
    printf("[Dynamic Plugin] System is shutting down, cleaning up port resources...\n");
}

// Ensure the symbol is exported properly without C++ name mangling, though we are compiling as C.
#if defined(_WIN32)
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

EXPORT void rx_plugin_init(void* sched_ptr) {
    printf("[Dynamic Plugin] Initializing plugin inside VM...\n");
    rx_spawn_port(sched_ptr, NULL, plugin_handler, plugin_cleanup);
}
