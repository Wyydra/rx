run-web:
  #!/usr/bin/env bash
  zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseSmall
  cp zig-out/bin/rx.wasm www
  cd www && python3 -m http.server 8080

watch:
  #!/usr/bin/env bash
  zig build --watch

