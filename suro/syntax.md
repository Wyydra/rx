# Suro Syntax

Suro is a minimalist, functional, and actor-oriented language built on **Pattern Duality.**

## Core Principles

- **The Pattern:** A structure description (e.g., `x~int, y~int`).
- **`()` Unboxed (Transient):** Patterns in flight (arguments, stack).
- **`[]` Boxed (Persistent):** Patterns in memory (records, messages).
- **`~` Constraint:** Value matching (`value ~ pattern`).
- **`#` Atom:** Unique constant (`#ok`, `#error`).
- **`^` Pin:** Match against an existing variable's value.
- **`=` Binding:** Assignment.
- **`:` UFCS / Key-Value:** Method chaining and record keys.

---

## 1. Actor State & Dispatch

Actors handle messages by matching against function signatures. An actor's state is preserved by returning the new state from the message handler.

```suro
// State pattern
State = [hp~int, score~int]

// init returns the starting state
init = () [hp: 100, score: 0]

// on_msg matches (current_state, incoming_message)
// Returning a value updates the actor's state.
on_msg = (s~State, [#hit, dmg]) s[hp: s.hp - dmg]
on_msg = (s~State, [#get_score]) {
    print(s.score)
    s // Return state unchanged
}
```

## 2. Functions (Macro Logic)

Function parameters are unboxed patterns. Multiple definitions enable dispatch.

```suro
// Unboxed integer match
add = (x~int, y~int) x + y

// Boxed record match
draw = (p~[x~int, y~int]) {
    ui:send([#draw_rect, p.x, p.y])
}
```

## 3. Local Matching (Micro Logic)

Use `match` to deconstruct data locally. No arrow `->` is needed; the pattern and expression are adjacent.

```suro
handle_res = (res) {
    match res {
        [#ok, val]  print("Success: " + val)
        [#err, msg] log:error(msg)
    }
}
```

## 4. Pinning `^`

```suro
admin_id = #id_001
check_auth = ([#login, ^admin_id]) print("Admin logged in")
```

## 5. Record Updates

Suro uses functional updates for records.

```suro
p1 = [x: 10, y: 20]
p2 = p1[x: 30] // p2 is [x: 30, y: 20]
```

## 6. Complete Actor Example

```suro
module Entity

State = [pos~[int, int], health~int]

init = (x, y) [pos: [x, y], health: 100]

// Logic
on_msg = (s~State, [#move, dx, dy]) {
    new_pos = [s.pos.0 + dx, s.pos.1 + dy]
    s[pos: new_pos]
}

on_msg = (s~State, [#damage, d]) {
    s[health: s.health - d]
}

on_msg = (s~State, _) s
```
