#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="${AGENT_TCP_TUNE_WORK_DIR:-/root/agent-tcp-tune}"
LOG_DIR="${WORK_DIR}/logs"
UPSTREAM="${WORK_DIR}/net-tcp-tune.sh"
LIB="${WORK_DIR}/net-tcp-tune-lib.sh"

log() { printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

ensure_workdir() {
  mkdir -p "$WORK_DIR" "$LOG_DIR"
}

require_root() {
  [ "$(id -u)" = "0" ] || die "run as root"
}

is_xanmod_kernel() {
  uname -r | grep -qi xanmod
}

is_container_env() {
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt --container --quiet 2>/dev/null && return 0
  fi
  grep -qaE '/(docker|lxc|kubepods|containerd)/' /proc/1/cgroup 2>/dev/null
}

prepare_lib() {
  ensure_workdir
  [ -s "$UPSTREAM" ] || die "missing upstream script: $UPSTREAM"
  sed '/^[[:space:]]*main[[:space:]]*"\$@"[[:space:]]*$/d' "$UPSTREAM" > "$LIB"
  bash -n "$LIB"
}

backup_system_state() {
  ensure_workdir
  local backup_dir="${WORK_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  cp -a /etc/sysctl.conf /etc/sysctl.d /etc/security/limits.conf "$backup_dir"/ 2>/dev/null || true
  cp -a /etc/apt/sources.list /etc/apt/sources.list.d "$backup_dir"/ 2>/dev/null || true
  cp -a /etc/systemd/resolved.conf /etc/resolv.conf "$backup_dir"/ 2>/dev/null || true
  sysctl -a > "${backup_dir}/sysctl-before.txt" 2>/dev/null || true
  ip route show > "${backup_dir}/route-before.txt" 2>/dev/null || true
  log "BACKUP_DIR=$backup_dir"
}

cpu_x64_level() {
  local flags level=1
  flags="$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)"
  if printf '%s' "$flags" | grep -qw avx512f; then level=4
  elif printf '%s' "$flags" | grep -qw avx2; then level=3
  elif printf '%s' "$flags" | grep -qw sse4_2; then level=2
  fi
  echo "$level"
}

candidate_version() {
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
}

candidate_ok() {
  local cand="$1"
  [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

install_xanmod_kernel_robust() {
  require_root
  ensure_workdir
  if is_xanmod_kernel; then
    log "XanMod already running: $(uname -r)"
    return 0
  fi
  if is_container_env; then
    log "Container environment detected; skip custom kernel install."
    return 0
  fi
  [ "$(uname -m)" = "x86_64" ] || die "automatic XanMod install supports x86_64 only"
  [ -r /etc/os-release ] || die "missing /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "unsupported distro for automatic XanMod install: ${ID:-unknown}" ;;
  esac

  backup_system_state

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >>"${LOG_DIR}/apt.log" 2>&1 || true
  apt-get install -y curl wget gnupg ca-certificates lsb-release apt-transport-https >>"${LOG_DIR}/apt.log" 2>&1

  local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
  local key_tmp
  key_tmp="$(mktemp)"
  if curl -fsSL https://raw.githubusercontent.com/kejilion/sh/main/archive.key -o "$key_tmp" >>"${LOG_DIR}/xanmod-key.log" 2>&1; then
    :
  elif curl -fL --http1.1 -A "Mozilla/5.0 Agent-TCP-Tune" --connect-timeout 10 --max-time 30 --retry 2 https://dl.xanmod.org/archive.key -o "$key_tmp" >>"${LOG_DIR}/xanmod-key.log" 2>&1; then
    :
  else
    rm -f "$key_tmp"
    die "failed to download XanMod GPG key; see ${LOG_DIR}/xanmod-key.log"
  fi
  grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$key_tmp" || {
    rm -f "$key_tmp"
    die "downloaded XanMod key is not an ASCII armored PGP key"
  }
  gpg --dearmor -o "$keyring" --yes < "$key_tmp" >>"${LOG_DIR}/xanmod-key.log" 2>&1
  rm -f "$key_tmp"

  local level repo_file distro_codename suites=() suite pkg cand selected_pkg="" selected_suite=""
  level="$(cpu_x64_level)"
  distro_codename="${VERSION_CODENAME:-}"
  [ -n "$distro_codename" ] || distro_codename="$(lsb_release -sc 2>/dev/null || true)"
  [ -n "$distro_codename" ] || distro_codename="releases"
  suites+=("$distro_codename" bookworm trixie releases)
  repo_file="/etc/apt/sources.list.d/xanmod-release.list"
  : > "${LOG_DIR}/xanmod-select.log"

  for suite in "${suites[@]}"; do
    [ -n "$suite" ] || continue
    if grep -qxF "seen:$suite" "${LOG_DIR}/xanmod-select.log" 2>/dev/null; then
      continue
    fi
    echo "seen:$suite" >> "${LOG_DIR}/xanmod-select.log"
    echo "deb [signed-by=${keyring}] https://deb.xanmod.org ${suite} main" > "$repo_file"
    log "Probing XanMod suite: $suite"
    apt-get update -y >>"${LOG_DIR}/xanmod-select.log" 2>&1 || true
    for prefix in linux-xanmod-lts-x64v linux-xanmod-x64v linux-xanmod-edge-x64v; do
      local n
      for n in $(seq "$level" -1 1); do
        pkg="${prefix}${n}"
        cand="$(candidate_version "$pkg")"
        echo "${suite} ${pkg} candidate=${cand:-none}" >> "${LOG_DIR}/xanmod-select.log"
        if candidate_ok "$cand"; then
          selected_suite="$suite"
          selected_pkg="$pkg"
          break 3
        fi
      done
    done
  done

  [ -n "$selected_pkg" ] || die "no installable XanMod package found; see ${LOG_DIR}/xanmod-select.log"
  log "Installing ${selected_pkg} from suite ${selected_suite}"
  apt-get install -y "$selected_pkg" >>"${LOG_DIR}/xanmod-install.log" 2>&1
  dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+${selected_pkg}[[:space:]]" || die "XanMod package verification failed"
  update-grub >>"${LOG_DIR}/xanmod-install.log" 2>&1 || true

  rm -f "$repo_file"
  apt-get update -y >>"${LOG_DIR}/apt-after-xanmod.log" 2>&1 || true
  log "XanMod installed. Reboot is required to boot the new kernel."
  return 10
}

preset_for_bandwidth() {
  case "$1" in
    100) echo 1 ;;
    200) echo 2 ;;
    300) echo 3 ;;
    500) echo 4 ;;
    700) echo 5 ;;
    1000) echo 6 ;;
    1500) echo 7 ;;
    2000) echo 8 ;;
    2500) echo 9 ;;
    *) echo 10 ;;
  esac
}

run_bbr_direct() {
  ensure_workdir
  local bandwidth="$1" region="$2" region_choice preset input log_file
  prepare_lib
  case "$region" in
    asia|apac|sg|singapore) region_choice=1 ;;
    overseas|us|eu|america|europe) region_choice=2 ;;
    *) die "unknown region: $region" ;;
  esac
  preset="$(preset_for_bandwidth "$bandwidth")"
  if [ "$preset" = "10" ]; then
    input="$(printf '3\n10\n%s\n%s\n' "$bandwidth" "$region_choice")"
  else
    input="$(printf '3\n%s\n%s\n' "$preset" "$region_choice")"
  fi
  log_file="${LOG_DIR}/bbr-direct-$(date +%Y%m%d-%H%M%S).log"
  printf '%s' "$input" | bash -c ". '$LIB'; AUTO_MODE=1; bbr_configure_direct" 2>&1 | tee "$log_file"
  log "BBR_LOG=$log_file"
}

run_dns_purify() {
  ensure_workdir
  prepare_lib
  local log_file="${LOG_DIR}/dns-purify-$(date +%Y%m%d-%H%M%S).log"
  bash -c ". '$LIB'; AUTO_MODE=1; dns_purify_and_harden" 2>&1 | tee "$log_file"
  log "DNS_LOG=$log_file"
}

run_realm_fix() {
  ensure_workdir
  prepare_lib
  local log_file="${LOG_DIR}/realm-fix-$(date +%Y%m%d-%H%M%S).log"
  bash -c ". '$LIB'; AUTO_MODE=1; realm_fix_timeout" 2>&1 | tee "$log_file"
  log "REALM_LOG=$log_file"
}

run_disable_ipv6() {
  ensure_workdir
  prepare_lib
  local log_file="${LOG_DIR}/disable-ipv6-$(date +%Y%m%d-%H%M%S).log"
  bash -c ". '$LIB'; AUTO_MODE=1; disable_ipv6_permanent" 2>&1 | tee "$log_file"
  log "IPV6_LOG=$log_file"
}

run_tune_66() {
  local bandwidth=1000 region=asia dns=1 realm=1 ipv6=1
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bandwidth-mbps) bandwidth="$2"; shift 2 ;;
      --region) region="$2"; shift 2 ;;
      --no-dns) dns=0; shift ;;
      --no-realm) realm=0; shift ;;
      --keep-ipv6) ipv6=0; shift ;;
      *) die "unknown tune option: $1" ;;
    esac
  done
  run_bbr_direct "$bandwidth" "$region"
  [ "$dns" = "1" ] && run_dns_purify
  [ "$realm" = "1" ] && run_realm_fix
  [ "$ipv6" = "1" ] && run_disable_ipv6
}

preflight() {
  require_root
  echo "HOST=$(hostname)"
  echo "KERNEL=$(uname -r)"
  echo "ARCH=$(uname -m)"
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "OS=${PRETTY_NAME:-${ID:-unknown}}"
    echo "CODENAME=${VERSION_CODENAME:-unknown}"
  fi
  echo "CONTAINER=$(is_container_env && echo yes || echo no)"
  echo "XANMOD=$(is_xanmod_kernel && echo yes || echo no)"
  echo "CONGESTION=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo "QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  df -h / /boot 2>/dev/null || df -h /
  free -h || true
}

verify() {
  require_root
  echo "HOST=$(hostname)"
  echo "UPTIME=$(uptime -p)"
  echo "KERNEL=$(uname -r)"
  echo "CONGESTION=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo "QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  echo "TCP_RMEM=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo unknown)"
  echo "TCP_WMEM=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo unknown)"
  echo "RMEM_MAX=$(sysctl -n net.core.rmem_max 2>/dev/null || echo unknown)"
  echo "WMEM_MAX=$(sysctl -n net.core.wmem_max 2>/dev/null || echo unknown)"
  echo "DEFAULT_ROUTE=$(ip route show default | head -1)"
  echo "IPV6_ALL=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo unknown)"
  echo "IPV6_DEFAULT=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo unknown)"
  echo "CONNTRACK=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo unknown)"
  echo "BBR_PERSIST_ENABLED=$(systemctl is-enabled bbr-optimize-persist.service 2>/dev/null || true)"
  echo "BBR_PERSIST_ACTIVE=$(systemctl is-active bbr-optimize-persist.service 2>/dev/null || true)"
  echo "DNS_PERSIST_ENABLED=$(systemctl is-enabled dns-purify-persist.service 2>/dev/null || true)"
  echo "DNS_PERSIST_ACTIVE=$(systemctl is-active dns-purify-persist.service 2>/dev/null || true)"
  echo "RESOLVED_ACTIVE=$(systemctl is-active systemd-resolved 2>/dev/null || true)"
  echo "RESOLV_CONF=$(readlink -f /etc/resolv.conf 2>/dev/null || echo none)"
  echo "DNS_GITHUB=$(getent hosts github.com | head -1 || true)"
  echo "PUBLIC_IP=$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || echo fail)"
  local dev
  for dev in $(ls /sys/class/net 2>/dev/null | grep -vE '^(lo|docker|veth|br-|virbr|tun|tap)'); do
    echo "QDISC_${dev}=$(tc qdisc show dev "$dev" 2>/dev/null | head -1 || true)"
  done
  echo "IPTABLES_MSS_COUNT=$(iptables -t mangle -S FORWARD 2>/dev/null | grep -c TCPMSS || true)"
}

usage() {
  cat <<'EOF'
remote-tcp-tune.sh <command>

Commands:
  preflight
  install-kernel
  tune-66 [--bandwidth-mbps N] [--region asia|overseas] [--no-dns] [--no-realm] [--keep-ipv6]
  full [same options as tune-66]
  verify

Exit code 10 from install-kernel/full means reboot is required before tuning.
EOF
}

main() {
  local cmd="${1:-}"
  [ -n "$cmd" ] || { usage; exit 2; }
  shift || true
  case "$cmd" in
    preflight) preflight ;;
    install-kernel)
      set +e
      install_xanmod_kernel_robust
      local code=$?
      set -e
      exit "$code"
      ;;
    tune-66) run_tune_66 "$@" ;;
    full)
      set +e
      install_xanmod_kernel_robust
      local code=$?
      set -e
      if [ "$code" = "10" ]; then
        exit 10
      elif [ "$code" != "0" ]; then
        exit "$code"
      fi
      run_tune_66 "$@"
      ;;
    verify) verify ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
