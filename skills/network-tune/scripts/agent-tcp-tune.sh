#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_SCRIPT="${SCRIPT_DIR}/remote-tcp-tune.sh"
UPSTREAM_SCRIPT="${SCRIPT_DIR}/upstream/net-tcp-tune.sh"
REMOTE_DIR="${REMOTE_DIR:-/root/agent-tcp-tune}"

TARGET=""
BANDWIDTH="1000"
REGION="asia"
REBOOT_VERIFY=0
RUN_DNS=1
RUN_REALM=1
DISABLE_IPV6=1
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)

usage() {
  cat <<'EOF'
agent-tcp-tune.sh --target root@host [options]

Options:
  --target root@host          SSH target. root is expected.
  --bandwidth-mbps N          Manual expected bandwidth for tuning. Default: 1000.
  --region asia|overseas      Region profile for Eric vps-tcp-tune buffer sizing. Default: asia.
  --reboot-verify             Reboot after kernel install and after tuning, then verify persistence.
  --no-dns                    Skip DNS purification.
  --no-realm                  Skip Realm/conntrack tuning.
  --keep-ipv6                 Keep IPv6 enabled.
  --ssh-option VALUE          Add one raw ssh option, repeatable.

The script uploads remote-tcp-tune.sh and Eric's net-tcp-tune.sh to /root/agent-tcp-tune.
Exit code 10 from the remote kernel step means the machine needs a reboot.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --bandwidth-mbps) BANDWIDTH="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --reboot-verify) REBOOT_VERIFY=1; shift ;;
    --no-dns) RUN_DNS=0; shift ;;
    --no-realm) RUN_REALM=0; shift ;;
    --keep-ipv6) DISABLE_IPV6=0; shift ;;
    --ssh-option) SSH_OPTS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$TARGET" ] || { usage >&2; exit 2; }
[ -s "$REMOTE_SCRIPT" ] || { echo "missing $REMOTE_SCRIPT" >&2; exit 1; }
[ -s "$UPSTREAM_SCRIPT" ] || { echo "missing $UPSTREAM_SCRIPT" >&2; exit 1; }

remote() {
  ssh "${SSH_OPTS[@]}" "$TARGET" "$@"
}

upload() {
  remote "mkdir -p '$REMOTE_DIR'"
  scp "${SSH_OPTS[@]}" "$REMOTE_SCRIPT" "$TARGET:${REMOTE_DIR}/remote-tcp-tune.sh" >/dev/null
  scp "${SSH_OPTS[@]}" "$UPSTREAM_SCRIPT" "$TARGET:${REMOTE_DIR}/net-tcp-tune.sh" >/dev/null
  remote "chmod +x '$REMOTE_DIR/remote-tcp-tune.sh' '$REMOTE_DIR/net-tcp-tune.sh'"
}

wait_ssh() {
  local i
  for i in $(seq 1 96); do
    if remote "echo up >/dev/null" 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  echo "SSH did not return in time" >&2
  return 1
}

reboot_and_wait() {
  set +e
  remote "sync; reboot"
  set -e
  sleep 5
  wait_ssh
}

tune_args=(--bandwidth-mbps "$BANDWIDTH" --region "$REGION")
[ "$RUN_DNS" = "1" ] || tune_args+=(--no-dns)
[ "$RUN_REALM" = "1" ] || tune_args+=(--no-realm)
[ "$DISABLE_IPV6" = "1" ] || tune_args+=(--keep-ipv6)

echo "== Uploading bundled scripts to ${TARGET}:${REMOTE_DIR} =="
upload

echo "== Preflight =="
remote "bash '$REMOTE_DIR/remote-tcp-tune.sh' preflight"

echo "== Kernel install =="
set +e
remote "bash '$REMOTE_DIR/remote-tcp-tune.sh' install-kernel"
kernel_code=$?
set -e
if [ "$kernel_code" = "10" ]; then
  echo "Kernel installed; reboot is required."
  if [ "$REBOOT_VERIFY" = "1" ]; then
    reboot_and_wait
  else
    echo "Stop here. Re-run with --reboot-verify after reboot, or reboot manually and run tune-66."
    exit 10
  fi
elif [ "$kernel_code" != "0" ]; then
  echo "Kernel install failed with exit code $kernel_code" >&2
  exit "$kernel_code"
fi

echo "== Tune equivalent of Eric vps-tcp-tune option 66 =="
remote "bash '$REMOTE_DIR/remote-tcp-tune.sh' tune-66 ${tune_args[*]}"

if [ "$REBOOT_VERIFY" = "1" ]; then
  echo "== Reboot for persistence verification =="
  reboot_and_wait
fi

echo "== Verify =="
remote "bash '$REMOTE_DIR/remote-tcp-tune.sh' verify"
