#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s <staging|production> <terraform-root>\n' "$0" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

environment="$1"
terraform_root="$2"

case "$environment" in
  staging|production) ;;
  *)
    printf 'Unsupported environment: %s\n' "$environment" >&2
    usage
    exit 64
    ;;
esac

if [[ ! -d "$terraform_root" ]]; then
  printf 'Terraform root does not exist: %s\n' "$terraform_root" >&2
  exit 66
fi

required_vars=(TF_STATE_BUCKET TF_STATE_ENDPOINT AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY)
for variable_name in "${required_vars[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'Missing required environment variable: %s\n' "$variable_name" >&2
    exit 64
  fi
done

case "$terraform_root" in
  */infra/cloudflare/environments/"$environment") state_scope="cloudflare" ;;
  */infra/supabase/environments/"$environment") state_scope="supabase" ;;
  *)
    printf 'Terraform root must be a supported environment root: %s\n' "$terraform_root" >&2
    exit 64
    ;;
esac

state_key="${state_scope}/${environment}/terraform.tfstate"
backend_config="$(mktemp "${TMPDIR:-/tmp}/terraform-backend.XXXXXX")"
cleanup() {
  rm -f "$backend_config"
}
trap cleanup EXIT HUP INT TERM

escape_hcl_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

{
  printf 'bucket = "'
  escape_hcl_string "$TF_STATE_BUCKET"
  printf '"\nkey = "'
  escape_hcl_string "$state_key"
  printf '"\nendpoints = { s3 = "'
  escape_hcl_string "$TF_STATE_ENDPOINT"
  printf '" }\n'
} > "$backend_config"

terraform -chdir="$terraform_root" init \
  -reconfigure \
  -input=false \
  -no-color \
  -backend-config="$backend_config"
