# Standalone WASI Moscow Time Module

I use this module to compare a per-invocation WASI CLI program with Spin's persistent `wasi-http` component model.

```bash
source scripts/lab12-env.sh
tinygo build -o wasm-cli/main.wasm -target=wasi -no-debug ./wasm-cli/main.go
wasmtime run \
  --env REQUEST_METHOD=GET \
  --env PATH_INFO=/time \
  wasm-cli/main.wasm
```
