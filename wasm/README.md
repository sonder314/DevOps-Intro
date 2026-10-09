# Moscow Time Spin Component

I created this component from Spin 3.4.0's canonical `http-go` template and adapted its handler to expose `GET /time`.

The response contains the current Unix epoch, an RFC3339 Moscow timestamp, the local hour and minute, and an explicit UTC+3 timezone label. The component has no outbound network capability.

```bash
source scripts/lab12-env.sh
cd wasm
spin build
spin up
```

In another terminal:

```bash
curl -fsS http://127.0.0.1:3000/time | python3 -m json.tool
```
