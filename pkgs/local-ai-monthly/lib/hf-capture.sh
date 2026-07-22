set -euo pipefail

requests="${1:?usage: local-ai-monthly-hf-capture <requests.json> <output-dir> [max-response-bytes]}"
output_dir="${2:?}"
max_response_bytes="${3:-5000000}"

export LC_ALL=C
umask 077
[[ "$max_response_bytes" =~ ^[1-9][0-9]*$ ]]
jq -e 'type == "array" and all(.[ ];
  (.repository | test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"))
  and (.api_url == ("https://huggingface.co/api/models/" + .repository + "?blobs=true")))' \
  "$requests" >/dev/null

mkdir -p "$output_dir/responses"
manifest_tmp="$output_dir/manifest.json.tmp"
printf '{"schema_version":1,"responses":[]}\n' > "$output_dir/manifest.json"

index=0
while IFS= read -r request; do
  index=$((index + 1))
  repository="$(jq -r '.repository' <<<"$request")"
  api_url="$(jq -r '.api_url' <<<"$request")"
  response_rel="responses/$(printf '%03d' "$index").json"
  response="$output_dir/$response_rel"
  temporary="$response.tmp"

  http_status="$(curl \
    --silent --show-error --location --fail-with-body \
    --retry 2 --retry-all-errors \
    --connect-timeout 15 --max-time 90 \
    --max-filesize "$max_response_bytes" \
    --header 'Accept: application/json' \
    --user-agent 'mecattaf-local-ai-monthly/2' \
    --output "$temporary" \
    --write-out '%{http_code}' \
    "$api_url")"
  [[ "$http_status" == 200 ]]
  response_bytes="$(wc -c < "$temporary")"
  if ((response_bytes > max_response_bytes)); then
    printf 'local-ai-monthly: HF metadata response exceeds limit: %s\n' "$repository" >&2
    exit 1
  fi
  jq -e --arg repository "$repository" '
    .id == $repository and (.sha | test("^[0-9a-f]{40}$")) and (.siblings | type == "array")
  ' "$temporary" >/dev/null
  mv "$temporary" "$response"
  digest="$(sha256sum "$response" | cut -d' ' -f1)"

  row="$(jq -n \
    --arg repository "$repository" \
    --arg api_url "$api_url" \
    --arg response "$response_rel" \
    --arg sha256 "$digest" \
    --argjson http_status "$http_status" \
    --argjson bytes "$response_bytes" \
    '{repository: $repository, api_url: $api_url, response: $response,
      sha256: $sha256, http_status: $http_status, bytes: $bytes}')"
  jq --argjson row "$row" '.responses += [$row]' "$output_dir/manifest.json" \
    > "$manifest_tmp"
  mv "$manifest_tmp" "$output_dir/manifest.json"
done < <(jq -c '.[]' "$requests")

jq --sort-keys . "$output_dir/manifest.json" > "$manifest_tmp"
mv "$manifest_tmp" "$output_dir/manifest.json"
