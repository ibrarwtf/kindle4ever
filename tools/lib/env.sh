# Shared setup for the host tools (sourced, not run).
# Settings come from environment variables. For convenience they can also live in a file:
#   $K4_ENV, else <devkit>/k4.env, else <devkit>/../k4.env
# Variables already set in the environment win over the file.
# See k4.env.example for the full list.

K4_ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$K4_ROOT/tools/lib/env.sh" ] || K4_ROOT=$(cd "$(dirname "$0")/../.." && pwd)

k4_load_env() {
  for f in "${K4_ENV:-}" "$K4_ROOT/k4.env" "$K4_ROOT/../k4.env"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    # shellcheck disable=SC2034  # used by scripts that source this file
    K4_ENV_FILE=$f
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(printf '%s' "$line" | tr -d '\r')
      case "$line" in ''|'#'*) continue ;; *=*) ;; *) continue ;; esac
      key=${line%%=*}
      eval "[ -n \"\${$key+x}\" ]" && continue  # environment wins
      export "$key=${line#*=}"
    done < "$f"
    break
  done
}
k4_load_env

# Defaults.
: "${K4_DEVICE_DIR:=/mnt/us/kindle4ever}"
: "${K4_SSH_USER:=root}"
: "${K4_VENDOR:=$K4_ROOT/vendor}"

k4_need() {  # k4_need VAR... -> exit with a hint if unset
  for v in "$@"; do
    eval "[ -n \"\${$v:-}\" ]" || { echo "k4: $v is not set (env var or k4.env, see k4.env.example)" >&2; exit 2; }
  done
}

# k4_ssh <remote command...>
# Options suit the Kindle's old dropbear (RSA host key, RSA user key).
k4_ssh() {
  k4_need K4_HOST K4_SSH_KEY
  ssh -i "$K4_SSH_KEY" \
    -o "UserKnownHostsFile=${K4_KNOWN_HOSTS:-$K4_ROOT/.known_hosts}" \
    -o StrictHostKeyChecking=accept-new \
    -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -o ConnectTimeout=10 -o ServerAliveInterval=15 \
    "$K4_SSH_USER@$K4_HOST" "$@"
}

# PATH on the device for our commands (ssh sessions only get /usr/bin:/bin).
# shellcheck disable=SC2034  # used by scripts that source this file
K4_REMOTE_ENV="export PATH=$K4_DEVICE_DIR/bin:/usr/sbin:/sbin:/usr/bin:/bin:/mnt/us/usbnet/bin;"
