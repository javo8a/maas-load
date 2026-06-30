#!/bin/bash

# Configuration
MODEL_URL="${MODEL_URL:-http://localhost:8000/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-5}"
TOTAL_REQUESTS="${TOTAL_REQUESTS:-50}"
MODEL_NAME="${MODEL_NAME:-Qwen/Qwen3-0.6B}"
PROMPT="${PROMPT:-Why is the sky blue?}"
STREAM="${STREAM:-false}"
MAX_TOKENS="${MAX_TOKENS:-50}"
NEW_KEY_PER_REQUEST="${NEW_KEY_PER_REQUEST:-false}"
# Optional: export API_KEY="your-token"
# When NEW_KEY_PER_REQUEST=true, set MAAS_HOST (or rely on OpenShift cluster discovery)
MAAS_HOST="${MAAS_HOST:-}"
MAAS_HOST="${MAAS_HOST//$'\r'/}"
MAAS_HOST="${MAAS_HOST//$'\n'/}"
if [[ -z "$MAAS_HOST" ]] && command -v oc &>/dev/null; then
  CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
  CLUSTER_DOMAIN="${CLUSTER_DOMAIN//$'\r'/}"
  CLUSTER_DOMAIN="${CLUSTER_DOMAIN//$'\n'/}"
  [[ -n "$CLUSTER_DOMAIN" ]] && MAAS_HOST="https://maas.${CLUSTER_DOMAIN}"
fi

export MODEL_URL MODEL_NAME PROMPT API_KEY STREAM MAX_TOKENS NEW_KEY_PER_REQUEST MAAS_HOST

echo "Load test: $TOTAL_REQUESTS requests, concurrency=$CONCURRENCY"
echo "MODEL_URL=$MODEL_URL  MODEL_NAME=$MODEL_NAME  STREAM=$STREAM  MAX_TOKENS=$MAX_TOKENS  NEW_KEY_PER_REQUEST=$NEW_KEY_PER_REQUEST"
if [[ "$NEW_KEY_PER_REQUEST" == "true" ]]; then
  if [[ -z "$MAAS_HOST" ]]; then
    echo "Error: NEW_KEY_PER_REQUEST=true requires MAAS_HOST or an OpenShift cluster (oc)" >&2
    exit 1
  fi
  if [[ ! "$MAAS_HOST" =~ ^https?:// ]]; then
    echo "Error: MAAS_HOST must start with http:// or https:// (got: '$MAAS_HOST')" >&2
    exit 1
  fi
  echo "MAAS_HOST=$MAAS_HOST"
fi
echo "---"

run_request() {
  local i="$1"
  echo "Sending request $i"
  auth=()
  if [[ "$NEW_KEY_PER_REQUEST" == "true" ]]; then
    local api_keys_url="${MAAS_HOST%/}/maas-api/v1/api-keys"
    local oc_token key_payload api_key_response

    oc_token=$(oc whoami -t 2>/dev/null | tr -d '\r\n')
    if [[ -z "$oc_token" ]]; then
      echo "Req $i | Error: oc whoami -t failed; are you logged in?" >&2
      return 1
    fi

    key_payload=$(cat <<JSON
{
  "name": "load-test-key-$i",
  "description": "Key for load test",
  "expiresIn": "1h",
  "ephemeral": true,
  "subscription": "free-models-subscription"
}
JSON
)

    api_key_response=$(curl -sSk \
      -H "Authorization: Bearer ${oc_token}" \
      -H "Content-Type: application/json" \
      -X POST \
      -d "$key_payload" \
      "$api_keys_url") || {
        echo "Req $i | Error: curl failed for $api_keys_url" >&2
        return 1
      }

    API_KEY=$(echo "$api_key_response" | jq -r .key)
    if [[ -z "$API_KEY" || "$API_KEY" == "null" ]]; then
      echo "Req $i | Error: failed to obtain API key from $api_keys_url" >&2
      echo "Req $i | Response: $api_key_response" >&2
      return 1
    fi
  fi
  [[ -n "$API_KEY" && "$API_KEY" != "null" ]] && auth=(-H "Authorization: Bearer $API_KEY")

  accept="application/json"
  [[ "$STREAM" == "true" ]] && accept="text/event-stream"

  payload=$(cat <<JSON
{
  "model": "$MODEL_NAME",
  "stream": $STREAM,
  "max_tokens": $MAX_TOKENS,
  "messages": [
    {
      "role": "user",
      "content": "$PROMPT"
    }
  ]
}
JSON
)

  metrics=$(curl -s -o /dev/null -w "%{http_code} %{time_total} %{time_starttransfer}" \
    -H "accept: $accept" \
    -H "Content-Type: application/json" \
    "${auth[@]}" \
    -d "$payload" \
    "$MODEL_URL")

  read -r status time_total ttfb <<< "$metrics"
  printf "Req %s | Status: %s | Time: %ss | TTFB: %ss\n" "$i" "$status" "$time_total" "$ttfb"
}
export -f run_request

seq 1 "$TOTAL_REQUESTS" | xargs -P"$CONCURRENCY" -n1 bash -c 'run_request "$1"' _ 

echo "---"
echo "Done."
