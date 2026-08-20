#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Verify jfk Fluss storage config without printing credential values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.harness/fluss_jfk_hosts.sh
source "${SCRIPT_DIR}/fluss_jfk_hosts.sh"

CONFIG_PATH="/vdb/fluss-1.0-SNAPSHOT/conf/server.yaml"
CLUSTER="jfk"

usage() {
  cat <<'EOF'
Usage:
  ./.harness/fluss_verify_storage_config.sh [options]

Options:
  --cluster jfk                    Target cluster. Only jfk is supported.
  --config PATH                    Remote server.yaml path.
  -h, --help                       Show this help.

The script prints remote.data.dir and whether S3 credentials are set. It never
prints credential values.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

verify_host() {
  local role="$1"
  local host="$2"
  local command

  printf '== %s %s ==\n' "${role}" "${host}"
  command="sudo su - root -c 'config=$(shell_quote "${CONFIG_PATH}"); if [[ ! -f \"\$config\" ]]; then echo missing config: \"\$config\"; exit 1; fi; if grep -Eq \"^[[:space:]]*remote\\.data\\.dirs[[:space:]]*:\" \"\$config\"; then grep -E \"^[[:space:]]*remote\\.data\\.dirs[[:space:]]*:\" \"\$config\"; else printf \"%s\\n\" \"remote.data.dirs=absent\"; fi; grep -E \"^[[:space:]]*remote\\.data\\.dir[[:space:]]*:\" \"\$config\"; if grep -Eq \"^[[:space:]]*fs\\.s3a\\.access\\.key[[:space:]]*:\" \"\$config\"; then echo \"fs.s3a.access.key=<set>\"; else echo \"fs.s3a.access.key=<missing>\"; fi; if grep -Eq \"^[[:space:]]*fs\\.s3a\\.secret\\.key[[:space:]]*:\" \"\$config\"; then echo \"fs.s3a.secret.key=<set>\"; else echo \"fs.s3a.secret.key=<missing>\"; fi'"
  ssh -n -o BatchMode=yes "waphz@${host}" "${command}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      CLUSTER="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ "${CLUSTER}" == "jfk" ]] || die "only jfk cluster is supported"
[[ -n "${CONFIG_PATH}" ]] || die "--config is required"

while read -r role host; do
  verify_host "${role}" "${host}"
done < <(fluss_jfk_each_host)
