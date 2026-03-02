run-web:
  #!/usr/bin/env bash
  zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseSmall
  cp zig-out/bin/rx.wasm www
  cd www && python3 -m http.server 8080

watch:
  zig build --watch

profile script="benchmarks/fib/fib.rxt":
  zig build -Doptimize=ReleaseSafe
  valgrind --tool=callgrind ./zig-out/bin/rxt {{script}}
