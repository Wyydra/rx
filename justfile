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

# Build a Zig plugin. Usage: just build-plugin test_plugin/echo.zig
build-plugin src="test_plugin/echo.zig":
  zig build-lib -dynamic -lc -I rx/include {{src}} -femit-bin={{without_extension(src)}}.so

# Build a C plugin. Usage: just build-plugin-c test_plugin/echo.c
build-plugin-c src="test_plugin/echo.c":
  cc -shared -fPIC -I rx/include -o {{without_extension(src)}}.so {{src}}

