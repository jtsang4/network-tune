# Topology Workflow

## Purpose

Use this guide to build or maintain relay-to-exit proxy networks after host-level tuning has already been handled by `network-tune`.

## Inventory

Run `preflight.md` before this inventory when the task includes live changes.

Run these checks on each host:

```bash
ssh root@HOST 'hostname; uname -r; cat /etc/os-release | sed -n "1,8p"; ip -br addr; ip route; nproc; free -h; ss -tulnp | sed -n "1,120p"'
ssh root@HOST 'systemctl is-active sing-box xray realm 2>/dev/null || true; systemctl list-units "wg-quick@*" --no-pager || true'
ssh root@HOST 'find /etc/wireguard /etc/sing-box /usr/local/etc/sing-box /etc/v2ray-agent/xray/conf -maxdepth 2 -type f 2>/dev/null | sort'
ssh root@HOST 'test -f /root/realm.toml && sed -n "1,220p" /root/realm.toml || true'
ssh root@HOST 'command -v vasma || true; test -d /etc/v2ray-agent && find /etc/v2ray-agent -maxdepth 4 -type f 2>/dev/null | sort | sed -n "1,160p"'
```

Record:

```text
host role: relay or exit
public IP and SSH target
primary interface
bandwidth
current client-facing ports
current proxy service owner for each port
existing WireGuard interfaces and peers
desired relationships
```

## Decision Rules

### Fresh Build

Use v2ray-agent/vasma to create VLESS Reality, then use sing-box-style routing or a local bridge plus WireGuard to each exit.

```text
client -> relay public VLESS Reality inbound -> route by inbound tag -> WireGuard exit -> exit NAT -> Internet
```

Use this when the relay can terminate client sessions and the exit can act as an L3 egress gateway.

### Preserve Existing Client Links

Keep the client-facing service and insert WireGuard behind it.

```text
client -> relay public port -> existing Realm -> exit WireGuard IP -> exit Xray/sing-box
```

Use this when clients already have VLESS Reality links whose credentials live on the exit. This pattern preserves UUID, Reality public key, SNI, short ID, and client URL.

### v2ray-agent Managed Hosts

Use `vasma` for fresh protocol installation, user management, and subscription output. Use direct file edits for the surrounding network graph: WireGuard peers, Realm bridge targets, NAT, pacing, and per-link validation.

### Partial Update

Compare desired topology with discovered state. Add only missing pieces:

```text
missing exit peer -> create WG peer and NAT
missing relay relationship -> add inbound/route or Realm endpoint
changed bandwidth -> retune pacing and buffers
link request only -> inspect configs and generate links
```

## Build Sequence

1. Create a per-link state record from `link-state.md`.

2. Create a timestamped remote backup:

```bash
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p /root/proxy-networking-backup-$TS
cp -a /etc/wireguard /etc/sing-box /usr/local/etc/sing-box /etc/v2ray-agent /root/realm.toml /root/proxy-networking-backup-$TS/ 2>/dev/null || true
```

3. Install required tools according to `package-policy.md`:

```bash
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends wireguard-tools iproute2 iperf3 ethtool
```

4. Generate WireGuard keys and one preshared key per relay-exit relationship:

```bash
umask 077
mkdir -p /etc/wireguard
[ -f /etc/wireguard/LINK.key ] || wg genkey > /etc/wireguard/LINK.key
wg pubkey < /etc/wireguard/LINK.key
wg genpsk
```

5. Configure WireGuard and verify:

```bash
systemctl enable --now wg-quick@LINK
wg show LINK
ping -c 3 EXIT_WG_IP
nc -vz -w 3 EXIT_WG_IP TARGET_PORT
```

6. Configure routing/proxy layer:
   - Fresh build: v2ray-agent creates VLESS Reality; sing-box inbound tags route to WireGuard outbounds when sing-box owns the relay.
   - Existing bridge: Realm endpoint remote target changes from public exit IP to exit WireGuard IP using `realm-safety.md`.

7. Test the client-facing port:

```bash
nc -vz -w 3 RELAY_PUBLIC_IP PUBLIC_PORT
journalctl -u sing-box -u realm -u xray -n 80 --no-pager
```

## Measurement

Measure each relationship in both directions:

```bash
ssh root@EXIT 'nohup iperf3 -s -B EXIT_WG_IP -p 5201 -1 >/tmp/iperf3-wg.log 2>&1 & sleep 0.5'
ssh root@RELAY 'iperf3 -c EXIT_WG_IP -p 5201 -P 1 -t 15'

ssh root@EXIT 'nohup iperf3 -s -B EXIT_WG_IP -p 5201 -1 >/tmp/iperf3-wg-r.log 2>&1 & sleep 0.5'
ssh root@RELAY 'iperf3 -c EXIT_WG_IP -p 5201 -R -P 1 -t 15'
```

Probe public UDP capacity when WireGuard underperforms:

```bash
ssh root@EXIT 'nohup iperf3 -s -p 5202 -1 >/tmp/iperf3-udp.log 2>&1 & sleep 0.5'
ssh root@RELAY 'iperf3 -c EXIT_PUBLIC_IP -p 5202 -u -b 500M -t 10 --get-server-output'
```

Increase test rate gradually. Pick pacing below the first rate with sustained loss.

## Output

Keep reports compact:

```text
Topology:
relay A: port 15659 -> exit X via wg-a-x 10.66.45.2

Services:
relay: sing-box/realm active, wg active
exit: xray/NAT active, wg active

Performance:
WG relay->exit: 650 Mbps, retr N
WG exit->relay: 600 Mbps, retr 0

Rollback:
/root/proxy-networking-backup-YYYYMMDD-HHMMSS
```
