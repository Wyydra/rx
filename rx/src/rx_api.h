#ifndef _RX_API_H_
#define _RX_API_H_

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// The Scheduler is opaque to C code
typedef void rx_scheduler_t;

// The Value is 64 bits (NaN-boxed depending on implementation, but treated as opaque uint64_t by C)
typedef struct {
    uint64_t bits;
} rx_value_t;

// Port callbacks
typedef void (*rx_port_handler_t)(void* ctx, rx_value_t msg, rx_scheduler_t* sched);
typedef void (*rx_port_cleanup_t)(void* ctx);

// Spawn a new Port. Returns its Actor ID (0 on failure).
uint32_t rx_spawn_port(
    rx_scheduler_t* sched,
    void* context,
    rx_port_handler_t handler,
    rx_port_cleanup_t cleanup
);

// Send a message to an Actor by ID.
void rx_port_send(rx_scheduler_t* sched, uint32_t target_actor_id, rx_value_t msg);

// Constructors for primitive values (safe, no GC allocation needed)
rx_value_t rx_make_nil(void);
rx_value_t rx_make_bool(bool b);
rx_value_t rx_make_int(int64_t val);

// String helpers (extracting data safely)
// Returns a pointer to the UTF-8 payload. Note: The pointer is ONLY valid
// for the duration of the port handler callback, because the Garbage Collector
// may move or free the string afterwards. If you need it longer, copy it.
const char* rx_string_data(rx_value_t val);

// Returns the length of the string in bytes.
size_t rx_string_len(rx_value_t val);

// Type checkers
bool rx_is_nil(rx_value_t val);
bool rx_is_bool(rx_value_t val);
bool rx_is_int(rx_value_t val);
bool rx_is_pointer(rx_value_t val);
bool rx_is_string(rx_value_t val);

// Primitive extractors
bool rx_get_bool(rx_value_t val);
int64_t rx_get_int(rx_value_t val);

#ifdef __cplusplus
}
#endif

#endif
