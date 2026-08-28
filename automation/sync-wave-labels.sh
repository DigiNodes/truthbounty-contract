#!/usr/bin/env bash
set -euo pipefail

MODE="dry-run"
CONFIG_FILE=".github/labels/wave-workflow.json"

usage() {
  echo "Usage: $0 [--dry-run|--apply] [--config PATH]"
}

while (($#)); do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --apply)
      MODE="apply"
      shift
      ;;
    --config)
      CONFIG_FILE="${2:?--config requires a path}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command_name in gh jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is unavailable: $command_name" >&2
    exit 1
  fi
done

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Configuration file not found: $CONFIG_FILE" >&2
  exit 1
fi

jq -e '
  .version == 1
  and (.repository | type == "string" and length > 0)
  and (.target.issue_number_min | type == "number")
  and (.target.issue_number_max | type == "number")
  and (.target.identifier_min | type == "number")
  and (.target.identifier_max | type == "number")
  and (.target.required_body_marker | type == "string" and length > 0)
  and (.lifecycle_labels | length == 4)
  and ([.lifecycle_labels[].name] | unique | length == 4)
  and (.forbidden_activation_labels | length == 3)
' "$CONFIG_FILE" >/dev/null

configured_repo="$(jq -r '.repository' "$CONFIG_FILE")"
repo="${GH_REPO:-$configured_repo}"

if [[ "$repo" != "$configured_repo" ]]; then
  echo "GH_REPO ($repo) does not match configured repository ($configured_repo)" >&2
  exit 1
fi

issue_min="$(jq -r '.target.issue_number_min' "$CONFIG_FILE")"
issue_max="$(jq -r '.target.issue_number_max' "$CONFIG_FILE")"
identifier_min="$(jq -r '.target.identifier_min' "$CONFIG_FILE")"
identifier_max="$(jq -r '.target.identifier_max' "$CONFIG_FILE")"
body_marker="$(jq -r '.target.required_body_marker' "$CONFIG_FILE")"
expected_count=$((issue_max - issue_min + 1))
identifier_count=$((identifier_max - identifier_min + 1))

if ((expected_count != 40 || identifier_count != 40 || expected_count != identifier_count)); then
  echo "The protected target must contain exactly 40 mapped issues and identifiers" >&2
  exit 1
fi

lifecycle_json="$(jq -c '[.lifecycle_labels[].name]' "$CONFIG_FILE")"
forbidden_json="$(jq -c '.forbidden_activation_labels' "$CONFIG_FILE")"

if jq -e --argjson lifecycle "$lifecycle_json" --argjson forbidden "$forbidden_json" '
  any($lifecycle[]; . as $name | $forbidden | index($name))
' "$CONFIG_FILE" >/dev/null; then
  echo "Lifecycle and activation-label sets must be disjoint" >&2
  exit 1
fi

labels_snapshot="$(mktemp)"
issue_plan="$(mktemp)"
trap 'rm -f "$labels_snapshot" "$issue_plan"' EXIT

gh api "repos/$repo/labels?per_page=100" >"$labels_snapshot"

echo "Mode: $MODE"
echo "Repository: $repo"
echo "Protected issues: #$issue_min-#$issue_max"
echo

echo "Label plan:"
while IFS= read -r label; do
  name="$(jq -r '.name' <<<"$label")"
  color="$(jq -r '.color | ascii_upcase' <<<"$label")"
  description="$(jq -r '.description' <<<"$label")"
  existing="$(jq -c --arg name "$name" '.[] | select(.name == $name)' "$labels_snapshot" | head -n 1)"

  if [[ -z "$existing" ]]; then
    action="create"
  else
    existing_color="$(jq -r '.color | ascii_upcase' <<<"$existing")"
    existing_description="$(jq -r '.description // ""' <<<"$existing")"
    if [[ "$existing_color" == "$color" && "$existing_description" == "$description" ]]; then
      action="keep"
    else
      action="update"
    fi
  fi

  printf '  %-7s %s\n' "$action" "$name"
done < <(jq -c '.lifecycle_labels[]' "$CONFIG_FILE")

echo
echo "Validating protected issue set before any mutation..."

for ((number = issue_min; number <= issue_max; number++)); do
  sequence=$((identifier_min + number - issue_min))
  printf -v expected_id 'V2-SC-%03d' "$sequence"
  expected_prefix="$expected_id — "

  issue_json="$(gh api "repos/$repo/issues/$number")"

  if ! jq -e '.pull_request == null and .state == "open"' <<<"$issue_json" >/dev/null; then
    echo "Issue #$number is missing, closed, or is a pull request" >&2
    exit 1
  fi

  if ! jq -e --arg prefix "$expected_prefix" '.title | startswith($prefix)' <<<"$issue_json" >/dev/null; then
    actual_title="$(jq -r '.title' <<<"$issue_json")"
    echo "Issue #$number title mismatch. Expected prefix '$expected_prefix'; found '$actual_title'" >&2
    exit 1
  fi

  if ! jq -e --arg marker "$body_marker" '.body | contains($marker)' <<<"$issue_json" >/dev/null; then
    echo "Issue #$number does not contain the required candidate-state marker" >&2
    exit 1
  fi

  forbidden_count="$(jq --argjson forbidden "$forbidden_json" '
    [.labels[].name as $name | select($forbidden | index($name))] | length
  ' <<<"$issue_json")"
  if ((forbidden_count > 0)); then
    echo "Issue #$number already contains a forbidden activation label" >&2
    exit 1
  fi

  lifecycle_count="$(jq --argjson lifecycle "$lifecycle_json" '
    [.labels[].name as $name | select($lifecycle | index($name))] | unique | length
  ' <<<"$issue_json")"
  if ((lifecycle_count > 1)); then
    echo "Issue #$number contains multiple lifecycle labels" >&2
    exit 1
  fi

  lifecycle_name="$(jq -r --argjson lifecycle "$lifecycle_json" '
    [.labels[].name as $name | select($lifecycle | index($name))] | unique | .[0] // ""
  ' <<<"$issue_json")"

  if [[ -z "$lifecycle_name" ]]; then
    action="add"
    lifecycle_name="wave-candidate"
  else
    action="keep"
  fi

  printf '%s\t%s\t%s\t%s\n' "$number" "$expected_id" "$action" "$lifecycle_name" >>"$issue_plan"
done

if [[ "$(wc -l <"$issue_plan" | tr -d ' ')" != "40" ]]; then
  echo "Dry-run validation did not produce exactly 40 issue actions" >&2
  exit 1
fi

add_count="$(awk -F '\t' '$3 == "add" {count++} END {print count+0}' "$issue_plan")"
keep_count="$(awk -F '\t' '$3 == "keep" {count++} END {print count+0}' "$issue_plan")"

echo "Validated 40 clean-slate V2 issues."
echo "Lifecycle plan: add=$add_count keep=$keep_count"

if [[ "$MODE" == "dry-run" ]]; then
  echo "Dry run complete. No labels or issues were mutated."
  exit 0
fi

echo
echo "Applying lifecycle label definitions..."
while IFS= read -r label; do
  name="$(jq -r '.name' <<<"$label")"
  color="$(jq -r '.color' <<<"$label")"
  description="$(jq -r '.description' <<<"$label")"
  existing="$(jq -c --arg name "$name" '.[] | select(.name == $name)' "$labels_snapshot" | head -n 1)"

  if [[ -z "$existing" ]]; then
    gh api --method POST "repos/$repo/labels"       -f "name=$name"       -f "color=$color"       -f "description=$description" >/dev/null
  else
    gh api --method PATCH "repos/$repo/labels/$name"       -f "new_name=$name"       -f "color=$color"       -f "description=$description" >/dev/null
  fi
done < <(jq -c '.lifecycle_labels[]' "$CONFIG_FILE")

echo "Applying missing candidate labels without regressing reviewed, ready, or blocked issues..."
while IFS=$'\t' read -r number expected_id action lifecycle_name; do
  if [[ "$action" == "add" ]]; then
    jq -n '{labels: ["wave-candidate"]}' |
      gh api --method POST "repos/$repo/issues/$number/labels" --input - >/dev/null
  fi
  printf '  %-4s #%s %s\n' "$action" "$number" "$expected_id"
done <"$issue_plan"

echo
echo "Verifying final lifecycle and activation state..."
for ((number = issue_min; number <= issue_max; number++)); do
  issue_json="$(gh api "repos/$repo/issues/$number")"

  forbidden_count="$(jq --argjson forbidden "$forbidden_json" '
    [.labels[].name as $name | select($forbidden | index($name))] | length
  ' <<<"$issue_json")"
  lifecycle_count="$(jq --argjson lifecycle "$lifecycle_json" '
    [.labels[].name as $name | select($lifecycle | index($name))] | unique | length
  ' <<<"$issue_json")"

  if ((forbidden_count != 0 || lifecycle_count != 1)); then
    echo "Final verification failed for issue #$number" >&2
    exit 1
  fi
done

echo "Synchronization complete: 40 issues have exactly one internal lifecycle label and no activation label."
