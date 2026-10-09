# Lab 12 — WebAssembly Containers with Spin

I implemented a QuickNotes-style Moscow time endpoint as a Spin HTTP component, measured it against my Lab 6 container, and rebuilt the same logic as a standalone WASI CLI module for the bonus comparison.

## Test environment

```text
Machine: ASUS ExpertBook, 12th Gen Intel Core i5-1235U (12 logical CPUs)
OS: Ubuntu 26.04.1 LTS, Linux 7.0.0-34-generic, x86_64
Spin 3.4.0
TinyGo 0.41.1 with Go 1.26.7 and LLVM 20.1.1
Wasmtime 47.0.3
hyperfine 1.19.0
```

## Task 1 — Spin HTTP component

I scaffolded [`wasm/`](../wasm/) from Spin 3.4.0's canonical `http-go` template and then changed only the application metadata, route, and handler. The generated build command still targets `wasip1` with `-buildmode=c-shared`, and `allowed_outbound_hosts` remains an empty list.

### Build and artifact

```text
Building component moscow-time with `tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm .`
Finished building all Spin components
wasm/main.wasm 370386 bytes
```

### Runtime response

```json
{
  "unix": 1791530502,
  "iso": "2026-10-09T10:21:42+03:00",
  "hour_minute": "10:21",
  "timezone": "Europe/Moscow (UTC+3)"
}
```

The implementation is in [`wasm/main.go`](../wasm/main.go), and the manifest is [`wasm/spin.toml`](../wasm/spin.toml).

### Design questions

#### a) Browser WASM versus server WASM

The browser target `js/wasm` expects a JavaScript host and browser APIs supplied through `wasm_exec.js`; it does not provide a standalone server-side system interface. The `wasip1` target omits the browser DOM and JavaScript integration and instead imports a small, capability-oriented WASI surface from its runtime. This gives me a portable server module with predictable host calls and no ambient browser authority.

#### b) Why is `-buildmode=c-shared` required?

The Spin Go SDK registers the handler during initialization, and Spin expects the guest to export the reactor-style entry points used by its HTTP adapter. TinyGo's `c-shared` mode keeps those callable exports instead of producing only a command-style `_start` program. Without it, Spin cannot invoke the registered HTTP handler and requests fail because the required guest exports are absent.

#### c) Capability security and `allowed_outbound_hosts = []`

A WASM component receives only host capabilities declared by the application. With an empty outbound-host list, the component has no authority to open an outbound HTTP connection even if compromised code attempts it. Docker's `--network none` removes the container network namespace's interfaces at a coarser process boundary, whereas Spin denies the specific host-call capability and does not expose a general socket API to this guest.

#### d) TinyGo standard-library gaps encountered

TinyGo does not embed the complete IANA time-zone database, so `time.LoadLocation("Europe/Moscow")` is not reliable in this target. I used UTC plus a fixed three-hour offset and emitted `+03:00` explicitly. I also avoided reflection-heavy `encoding/json` over `map[string]any` and formatted a small, fixed JSON object directly.

## Task 2 — Performance comparison

I used 5 cold-start samples for each server and 50 measured warm requests after 5 warmups. The endpoints were `GET /health` for QuickNotes and `GET /time` for Spin.

| Dimension | Lab 6 Docker | Lab 12 WASM/Spin |
|---|---:|---:|
| Artifact size | 14,088,422 bytes | 370,386 bytes |
| Cold start p50 | 711.910 ms | 164.861 ms |
| Warm latency p50 | 67.039 ms | 52.448 ms |
| Warm latency p95 | 82.674 ms | 62.369 ms |

The Docker baseline was the local `quicknotes:lab6` image with ID
`sha256:88cc5d3e66f0ff3c673545cc8059a121fe66e17cccea26403e77859148b5cfd4`.
I measured warm latency by invoking `curl` through `hyperfine --warmup 5
--runs 50`. The five cold-start samples, measured from runtime launch to the
first successful HTTP response, were:

```text
Docker: 1019.579, 688.510, 711.910, 786.074, 664.201 ms
Spin:    282.796, 186.449, 164.861, 161.784, 155.849 ms
```

I used [`scripts/lab12-benchmark.py`](../scripts/lab12-benchmark.py) to keep
the endpoints, sample counts, readiness checks, and percentile calculation
identical and reproducible.

### Design questions

#### e) What dominates cold start?

The container path asks the daemon to create namespaces, mount its layered filesystem, apply runtime configuration, start the process, and wait for the HTTP listener. Spin loads the WASM component, validates or retrieves compiled code, creates a Wasmtime instance, wires its permitted host interfaces, and starts the HTTP trigger. The smaller module and lighter isolation boundary usually reduce Spin's startup work.

#### f) Where does each model fit?

WASM is attractive for small request handlers, edge functions, plugins, and dense multi-tenant execution where startup time and least-privilege host calls matter. Docker remains the better default for existing applications that need full OS APIs, native libraries, arbitrary processes, mature debugging tools, or software that cannot compile to WASI.

#### g) Concrete multi-tenant security advantage

An attacker in a WASM guest cannot simply issue arbitrary syscalls to scan the host filesystem, inspect neighbouring processes, create raw sockets, or exploit an accidentally mounted Docker socket; those operations do not exist unless the host explicitly supplies matching capabilities. Linux namespaces reduce visibility but still expose a large syscall and kernel attack surface shared by every container on the host.

## Bonus — Two WASM execution models

I built [`wasm-cli/`](../wasm-cli/) with the same response fields but a CGI-shaped interface: it reads `REQUEST_METHOD` and `PATH_INFO`, writes headers and JSON to stdout, and exits.

```text
$ tinygo build -o wasm-cli/main.wasm -target=wasi -no-debug ./wasm-cli/main.go
$ stat -c '%n %s bytes' wasm-cli/main.wasm
wasm-cli/main.wasm 196783 bytes

$ wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time wasm-cli/main.wasm
Content-Type: application/json

{"unix":1791529889,"iso":"2026-10-09T10:11:29+03:00","hour_minute":"10:11","timezone":"Europe/Moscow (UTC+3)"}

20 per-invocation samples: p50 18.389 ms, p95 22.948 ms
```

| WASM model | Module size | Cold-start model | Measured p50 |
|---|---:|---|---:|
| Spin `wasi-http` component | 370,386 bytes | Persistent HTTP host, measured from host launch to HTTP readiness | 164.861 ms |
| Standalone WASI CLI | 196,783 bytes | New Wasmtime process per request, measured until command exit | 18.389 ms |

These cold-start values describe different interfaces: the Spin measurement
includes starting and probing an HTTP server, while the CLI measurement only
starts Wasmtime, writes one response to stdout, and exits. They therefore show
execution-model overhead rather than equivalent end-to-end requests.

### Design questions

#### h) Why can the Spin component not run with bare `wasmtime run`?

The Spin artifact is a reactor-style HTTP component whose callable export implements the Spin/wasi-http handler contract. It is not a WASI command with a `_start` entry point, so bare `wasmtime run` has no command function to execute and no HTTP request context to pass.

#### i) What does Spin add above Wasmtime?

Spin uses Wasmtime as its execution engine but adds the persistent HTTP server and routing manifest, component lifecycle and instance reuse, wasi-http adaptation, observability, application configuration, and capability policy such as `allowed_outbound_hosts`. Wasmtime alone executes a module or component but does not interpret this Spin application model.

#### j) When does each execution model fit?

Per-invocation `wasmtime run` fits batch filters, scheduled jobs, build steps, and CGI-like commands where process-style input/output and a clean instance per call are desirable. Spin's persistent wasi-http model fits APIs and edge services that must accept many requests with low warm latency while routing and policy remain managed by one long-running host.

## Conclusion

On my machine, the Spin artifact was about 38 times smaller than the Lab 6
Docker image, and its median cold start was about 4.3 times faster. Spin also
had lower measured warm p50 and p95 latency in this small test. The standalone
WASI command was smaller again and had an 18.389 ms median per-process runtime,
but it did not include an HTTP listener. These results support using WASM for
small, capability-limited handlers, while Docker remains the more compatible
choice for full applications and native OS dependencies.
