#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

// Define Value structure layout (matching Zig's packed struct)
typedef struct {
    uint64_t bits;
} Value;

// Tags from memory/value.zig
// pointer = 0b000
// integer = 0b001
// nil = 0b010
// boolean = 0b011

#define TAG_BITS 3
#define TAG_MASK 0x7

typedef enum {
    TAG_POINTER = 0,
    TAG_INTEGER = 1,
    TAG_NIL = 2,
    TAG_BOOLEAN = 3
} Tag;

// fn (ctx: ?*anyopaque, msg: Value) void
typedef void (*Handler)(void* ctx, Value msg);

// context: ?*anyopaque
// handler: *const fn ...
typedef struct {
    void* context;
    Handler handler;
} Port;

void console_handler(void* ctx, Value msg) {
    (void)ctx; // Unused
    
    uint8_t tag = msg.bits & TAG_MASK;
    uint64_t payload = msg.bits >> TAG_BITS;
    
    switch (tag) {
        case TAG_NIL:
            printf("nil\n");
            break;
        case TAG_BOOLEAN:
            printf("%s\n", payload ? "true" : "false");
            break;
        case TAG_INTEGER: {
            int64_t signed_bits = (int64_t)msg.bits;
            int64_t val = signed_bits >> TAG_BITS;
            printf("%ld\n", val);
            break;
        }
        case TAG_POINTER:
            printf("<pointer %p>\n", (void*)msg.bits);
            break;
        default:
            printf("Unknown value tag: %d\n", tag);
    }
}

// Exported function to create the port
__attribute__((visibility("default")))
void create_console_port(Port* p) {
    if (p) {
        p->context = NULL;
        p->handler = console_handler;
    }
}
