/**
 * rx_api.h — Rx VM plugin (port/NIF) public C API
 *
 * Include this header and compile as a shared library:
 *   cc -shared -fPIC -o libmyplugin.so plugin.c
 *
 * Your plugin must export:
 *   void rx_load(rx_scheduler_t* sched);
 *
 * Inside rx_load(), call rx_spawn_port() to create ports and
 * rx_register_port() to make them discoverable by name from Rx scripts.
 */
#ifndef RX_API_H
#define RX_API_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void rx_scheduler_t;

/** NaN-boxed 64-bit value — same layout as Zig's Value packed struct. */
typedef struct { uint64_t bits; } rx_value_t;

/* Tag constants for manual value inspection */
#define RX_TAG_MASK    ((uint64_t)0x7)
#define RX_TAG_POINTER ((uint64_t)0x0)
#define RX_TAG_INTEGER ((uint64_t)0x1)
#define RX_TAG_NIL     ((uint64_t)0x2)
#define RX_TAG_BOOLEAN ((uint64_t)0x3)

typedef void (*rx_handler_t)(void* ctx, rx_value_t msg, rx_scheduler_t* sched);
typedef void (*rx_deinit_t)(void* ctx);

/* --- Port management ---------------------------------------------------- */

/** Spawn a port. Returns its ActorId (0 on failure). */
uint32_t rx_spawn_port(rx_scheduler_t* sched,
                       void*           ctx,
                       rx_handler_t    handler,
                       rx_deinit_t     deinit);

/** Register an ActorId under a name so Rx scripts can SEND to it by name. */
void rx_register_port(rx_scheduler_t* sched, const char* name, uint32_t actor_id);

/** Send a message to any actor/port by ActorId. */
void rx_port_send(rx_scheduler_t* sched, uint32_t target_id, rx_value_t msg);

/* --- Value constructors ------------------------------------------------- */

rx_value_t rx_make_nil(void);
rx_value_t rx_make_bool(bool b);
rx_value_t rx_make_int(int64_t v);

/* --- Type tests --------------------------------------------------------- */

bool rx_is_nil    (rx_value_t v);
bool rx_is_bool   (rx_value_t v);
bool rx_is_int    (rx_value_t v);
bool rx_is_pointer(rx_value_t v);
bool rx_is_string (rx_value_t v);

/* --- Extractors --------------------------------------------------------- */

bool    rx_get_bool(rx_value_t v);
int64_t rx_get_int (rx_value_t v);

/** String data pointer — valid ONLY during the handler call. */
const char* rx_string_data(rx_value_t v);
size_t      rx_string_len (rx_value_t v);

/* --- Plugin entry point ------------------------------------------------- */

/** Called once by the VM after loading your shared library. */
void rx_load(rx_scheduler_t* sched);

#ifdef __cplusplus
}
#endif

#endif /* RX_API_H */
