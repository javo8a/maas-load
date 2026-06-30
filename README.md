# Load testing with `load.sh`

`load.sh` sends concurrent chat completion requests to a model endpoint and prints per-request metrics (HTTP status, total time, and time to first byte).

## Prerequisites

- `bash`, `curl`, `jq`, and `seq`
- For MaaS / OpenShift targets: `oc` logged in to the cluster
- A reachable chat completions endpoint (local or remote)

## Quick start

```bash
chmod +x load.sh
./load.sh
```

By default this sends **50** requests with **5** concurrent workers to `http://localhost:8000/v1/chat/completions`.

## Configuration

All options are environment variables. Set them inline or `export` them before running the script.

| Variable | Default | Description |
|----------|---------|-------------|
| `MODEL_URL` | `http://localhost:8000/v1/chat/completions` | Full URL of the chat completions endpoint |
| `MODEL_NAME` | `Qwen/Qwen3-0.6B` | Model ID sent in the request body |
| `PROMPT` | `Why is the sky blue?` | User message content |
| `TOTAL_REQUESTS` | `50` | Total number of requests to send |
| `CONCURRENCY` | `5` | Maximum parallel requests |
| `STREAM` | `false` | Set to `true` for streaming responses (`text/event-stream`) |
| `API_KEY` | *(unset)* | Bearer token for `Authorization` header |
| `NEW_KEY_PER_REQUEST` | `false` | Set to `true` to mint a new API key before each request |
| `MAAS_HOST` | *(auto)* | MaaS gateway URL (`https://maas.<cluster-domain>`). Do not use `HOST` — on macOS that is the machine hostname. |

### Authentication modes

**Static API key** — reuse one key for all requests:

```bash
export API_KEY="your-api-key"
./load.sh
```

**New key per request** — useful for testing API key creation or rate limits with fresh credentials. Each worker calls the MaaS API keys endpoint before the inference request:

```bash
NEW_KEY_PER_REQUEST=true ./load.sh
```

When `NEW_KEY_PER_REQUEST=true`, the script discovers `MAAS_HOST` from OpenShift if `oc` is available:

```bash
MAAS_HOST="https://maas.${CLUSTER_DOMAIN}"
```

You can also set `MAAS_HOST` explicitly:

```bash
NEW_KEY_PER_REQUEST=true MAAS_HOST="https://maas.example.com" ./load.sh
```

If `NEW_KEY_PER_REQUEST=true` and `MAAS_HOST` cannot be resolved, the script exits with an error.

## Examples

### Local model server

```bash
MODEL_URL="http://localhost:8000/v1/chat/completions" \
MODEL_NAME="Qwen/Qwen3-0.6B" \
TOTAL_REQUESTS=100 \
CONCURRENCY=10 \
./load.sh
```

### MaaS on OpenShift (single API key)

Follow the [Models as a Service validation guide](https://opendatahub-io.github.io/models-as-a-service/latest/install/validation/) to obtain the gateway endpoint, `API_KEY`, `MODEL_NAME`, and `MODEL_URL`, then:

```bash
export API_KEY="..." 
export MODEL_URL="https://.../v1/chat/completions"
export MODEL_NAME="your-model-id"

TOTAL_REQUESTS=200 CONCURRENCY=20 ./load.sh
```

### MaaS with streaming

```bash
export API_KEY="..."
export MODEL_URL="..."
export MODEL_NAME="..."
STREAM=true ./load.sh
```

### MaaS with a new key per request

```bash
export MODEL_URL="..."
export MODEL_NAME="..."

NEW_KEY_PER_REQUEST=true TOTAL_REQUESTS=50 CONCURRENCY=5 ./load.sh
```

### Custom prompt and higher load

```bash
PROMPT="Summarize quantum computing in one sentence." \
TOTAL_REQUESTS=500 \
CONCURRENCY=50 \
./load.sh
```

## Output

The script prints a summary line, then one line per request:

```
Load test: 50 requests, concurrency=5
MODEL_URL=http://localhost:8000/v1/chat/completions  MODEL_NAME=Qwen/Qwen3-0.6B  STREAM=false  NEW_KEY_PER_REQUEST=false
---
Sending request 1
Req 1 | Status: 200 | Time: 1.234s | TTFB: 0.456s
...
---
Done.
```

| Field | Meaning |
|-------|---------|
| **Status** | HTTP response code |
| **Time** | Total request duration (seconds) |
| **TTFB** | Time to first byte (seconds) |

Response bodies are discarded; only status and timing are recorded.

## Related docs

- [Models as a Service validation guide](https://opendatahub-io.github.io/models-as-a-service/latest/install/validation/) — obtain gateway endpoint, API key, model URL, and run a single validation request
