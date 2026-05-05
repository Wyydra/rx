# Suro Syntax

Suro is a minimalist, functional, and actor-oriented language. It is built on a single, unified logic: **The Pattern Duality.**

## Core Principles

- **The Pattern:** A description of structure (e.g., `x~int, y~int`).
- **`()` Unboxed (Transient):** A pattern in flight (arguments, registers, stack).
- **`[]` Boxed (Persistent):** A pattern in memory (heap, messages, records).
- **`~` Constraint:** Matches a value against a pattern (`value ~ pattern`).
- **`#` Atom:** A global, unique constant (e.g., `#active`, `#ok`).
- **`^` Pin:** Forces a pattern to match an existing variable's value.
- **`=` Binding:** Assigns a value or a pattern to a name.
- **`:` UFCS / Key-Value:** Used for keyed data (`key: value`) and method chaining (`obj:call()`).

---

## 1. Pattern Duality

Suro unifies types and data under **Patterns**. The brackets determine the "storage mode":

- **Unboxed `()`**: Transient data (function arguments).
- **Boxed `[]`**: Persistent data (records, messages, memory).

## 2. Functions and Dispatch (Macro Logic)

In Suro, an Actor's logic is defined by multiple functions. The system automatically dispatches incoming messages to the first matching function.

```suro
// The system unboxes incoming messages into the function pattern
player_loop = ([#key_down, #left])  { physics:move(-200) }
player_loop = ([#key_down, #right]) { physics:move(200) }
player_loop = (_)                   { () }
```

## 3. Local Pattern Matching (Micro Logic)

To deconstruct boxed data inside a function, use the `match` keyword.

```suro
connect = (config~Config) {
    match db:init(config) {
        [#ok, conn]  -> conn:start_pool()
        [#err, msg]  -> log:error(msg)
    }
}
```

## 4. Pinning `^`

In a pattern, an identifier usually creates a new binding. Use `^` to match against the value of an existing variable.

```suro
target = #user_1
handle = ([#update, ^target, data]) { 
    // Matches only if the second element is #user_1
    save(data)
}
```

## 5. Types as Patterns

A "Type" is simply a name bound to a pattern.

```suro
Point = [x~int, y~int]

// Usage as constraint
draw = (p~Point) { ... }

// Usage as constructor
p = Point[x: 10, y: 20]
```

## 6. Uniform Function Call Syntax (UFCS) `:`

The `:` operator passes the left-hand side as the first argument to the right-hand side function.

```suro
user = User[name: "Gabbro"]
user:print() // equivalent to print(user)
```

## 7. Complete Actor Example

```suro
module Game

// Constructor-like logic
init = (game) {
    me = self()
    game:send([#register, me, #rect, 400, 300])
}

// Actor message handling via multiple dispatch
on_msg = ([#key_down, #left])  { game:send([#physics, self(), -200, 0]) }
on_msg = ([#key_down, #right]) { game:send([#physics, self(), 200, 0]) }
on_msg = ([#collide, ^other])  { game:send([#shake, 15]) }
on_msg = (_)                   { () }
```
