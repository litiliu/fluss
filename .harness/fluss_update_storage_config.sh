#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Update remote storage config on jfk Fluss nodes without printing credentials.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.harness/fluss_jfk_hosts.sh
source "${SCRIPT_DIR}/fluss_jfk_hosts.sh"

REMOTE_DIR="s3://wap-udp-cus-dashboard-prod-useast1/fluss"
CONFIG_PATH="/vdb/fluss-1.0-SNAPSHOT/conf/server.yaml"
CLUSTER="jfk"
ACCESS_KEY_ENV=""
SECRET_KEY_ENV=""
ACCESS_KEY_FILE=""
SECRET_KEY_FILE=""
EXECUTE=0
INCLUDE_REMOTE_DATA_DIRS=0

usage() {
  cat <<'EOF'
Usage:
  ./.harness/fluss_update_storage_config.sh [options]

Options:
  --cluster jfk                    Target cluster. Only jfk is supported.
  --remote-dir DIR                 remote.data.dir value to write.
  --config PATH                    Remote server.yaml path.
  --access-key-env NAME            Read fs.s3a.access.key from environment variable NAME.
  --secret-key-env NAME            Read fs.s3a.secret.key from environment variable NAME.
  --access-key-file PATH           Read fs.s3a.access.key from a local file.
  --secret-key-file PATH           Read fs.s3a.secret.key from a local file.
  --include-remote-data-dirs       Also set remote.data.dirs to the same single directory.
  --execute                        Apply changes. Without this flag, prints a dry-run plan.
  -h, --help                       Show this help.

Notes:
  - Do not pass secrets as command-line arguments.
  - If no credential source is provided with --execute, the script prompts with hidden input.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

read_file_first_line() {
  local file="$1"
  [[ -f "${file}" ]] || die "missing file: ${file}"
  sed -n '1p' "${file}"
}

read_env_value() {
  local name="$1"
  [[ -n "${name}" ]] || return 0
  [[ -n "${!name:-}" ]] || die "environment variable is empty: ${name}"
  printf '%s' "${!name}"
}

load_credentials() {
  if [[ -n "${ACCESS_KEY_FILE}" ]]; then
    AWS_ACCESS_KEY="$(read_file_first_line "${ACCESS_KEY_FILE}")"
  elif [[ -n "${ACCESS_KEY_ENV}" ]]; then
    AWS_ACCESS_KEY="$(read_env_value "${ACCESS_KEY_ENV}")"
  else
    read -r -s -p "AWS access key: " AWS_ACCESS_KEY
    printf '\n'
  fi

  if [[ -n "${SECRET_KEY_FILE}" ]]; then
    AWS_SECRET_KEY="$(read_file_first_line "${SECRET_KEY_FILE}")"
  elif [[ -n "${SECRET_KEY_ENV}" ]]; then
    AWS_SECRET_KEY="$(read_env_value "${SECRET_KEY_ENV}")"
  else
    read -r -s -p "AWS secret key: " AWS_SECRET_KEY
    printf '\n'
  fi

  [[ -n "${AWS_ACCESS_KEY}" ]] || die "access key is required"
  [[ -n "${AWS_SECRET_KEY}" ]] || die "secret key is required"
}

shell_quote() {
  printf '%q' "$1"
}

make_remote_script() {
  local remote_script="$1"

  cat > "${remote_script}" <<'REMOTE_EOF'
#!/usr/bin/env bash
set -euo pipefail

role="${1:?role required}"
remote_dir="${2:?remote dir required}"
config="${3:?config path required}"
include_remote_data_dirs="${4:?include flag required}"
values_file="/tmp/fluss-storage-values.$$"

cleanup() {
  rm -f "${values_file}"
}
trap cleanup EXIT

umask 077
cat > "${values_file}"
access_key="$(sed -n '1p' "${values_file}")"
secret_key="$(sed -n '2p' "${values_file}")"

[[ -n "${access_key}" ]] || { echo "missing access key on stdin" >&2; exit 1; }
[[ -n "${secret_key}" ]] || { echo "missing secret key on stdin" >&2; exit 1; }
[[ -f "${config}" ]] || { echo "missing active config: ${config}" >&2; exit 1; }

backup="${config}.storage-config.bak.$(date +%Y%m%d%H%M%S)"
cp -p "${config}" "${backup}"

update_key() {
  local key="$1"
  local value="$2"
  local key_regex
  local tmp

  key_regex="$(printf '%s' "${key}" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
  tmp="$(mktemp /tmp/fluss-server-yaml.XXXXXX)"
  awk -v key="${key}" -v key_regex="${key_regex}" -v value="${value}" '
    BEGIN { found = 0 }
    $0 ~ "^[[:space:]]*" key_regex "[[:space:]]*:" {
      if (found == 0) {
        print key ": " value
        found = 1
      }
      next
    }
    { print }
    END {
      if (found == 0) {
        print ""
        print key ": " value
      }
    }
  ' "${config}" > "${tmp}"
  cat "${tmp}" > "${config}"
  rm -f "${tmp}"
}

update_key "remote.data.dir" "${remote_dir}"
if [[ "${include_remote_data_dirs}" == "1" ]]; then
  update_key "remote.data.dirs" "${remote_dir}"
fi
update_key "fs.s3a.access.key" "${access_key}"
update_key "fs.s3a.secret.key" "${secret_key}"

host="$(hostname -f 2>/dev/null || hostname)"
printf '%s %s remote.data.dir=%s\n' "${role}" "${host}" "${remote_dir}"
if grep -Eq '^[[:space:]]*remote\.data\.dirs[[:space:]]*:' "${config}"; then
  grep -E '^[[:space:]]*remote\.data\.dirs[[:space:]]*:' "${config}"
  if [[ "${include_remote_data_dirs}" != "1" ]]; then
    printf 'WARNING: remote.data.dirs is present, so Fluss may ignore remote.data.dir\n'
  fi
else
  printf 'remote.data.dirs=absent\n'
fi
printf '%s %s fs.s3a.access.key=<set>\n' "${role}" "${host}"
printf '%s %s fs.s3a.secret.key=<set>\n' "${role}" "${host}"
REMOTE_EOF

  chmod 700 "${remote_script}"
}

run_host() {
  local role="$1"
  local host="$2"
  local remote_helper="/tmp/fluss_update_storage_config.sh"
  local include_flag="${INCLUDE_REMOTE_DATA_DIRS}"
  local command

  printf '== %s %s ==\n' "${role}" "${host}"
  scp -q "${REMOTE_SCRIPT}" "waphz@${host}:${remote_helper}"
  command="sudo su - root -c '/bin/bash ${remote_helper} $(shell_quote "${role}") $(shell_quote "${REMOTE_DIR}") $(shell_quote "${CONFIG_PATH}") $(shell_quote "${include_flag}"); rm -f ${remote_helper}'"
  printf '%s\n%s\n' "${AWS_ACCESS_KEY}" "${AWS_SECRET_KEY}" \
    | ssh -o BatchMode=yes "waphz@${host}" "${command}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      CLUSTER="${2:-}"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --access-key-env)
      ACCESS_KEY_ENV="${2:-}"
      shift 2
      ;;
    --secret-key-env)
      SECRET_KEY_ENV="${2:-}"
      shift 2
      ;;
    --access-key-file)
      ACCESS_KEY_FILE="${2:-}"
      shift 2
      ;;
    --secret-key-file)
      SECRET_KEY_FILE="${2:-}"
      shift 2
      ;;
    --include-remote-data-dirs)
      INCLUDE_REMOTE_DATA_DIRS=1
      shift
      ;;
    --execute)
      EXECUTE=1
      shift
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
[[ -n "${REMOTE_DIR}" ]] || die "--remote-dir is required"
[[ -n "${CONFIG_PATH}" ]] || die "--config is required"

printf 'Cluster: %s\n' "${CLUSTER}"
printf 'Remote config: %s\n' "${CONFIG_PATH}"
printf 'remote.data.dir: %s\n' "${REMOTE_DIR}"
if [[ "${INCLUDE_REMOTE_DATA_DIRS}" == "1" ]]; then
  printf 'remote.data.dirs: will also be set\n'
else
  printf 'remote.data.dirs: will not be changed\n'
fi
printf 'Targets:\n'
fluss_jfk_each_host | sed 's/^/  /'

if [[ "${EXECUTE}" != "1" ]]; then
  printf '\nDry-run only. Add --execute to apply changes.\n'
  exit 0
fi

load_credentials

REMOTE_SCRIPT="$(mktemp /tmp/fluss-remote-config.XXXXXX.sh)"
cleanup() {
  rm -f "${REMOTE_SCRIPT}"
}
trap cleanup EXIT
make_remote_script "${REMOTE_SCRIPT}"

while read -r role host; do
  run_host "${role}" "${host}"
done < <(fluss_jfk_each_host)
