# Preflight

Run preflight before changing a relay, exit, or relationship. Record results in the per-link plan.

## Host Checks

```bash
ssh -n root@HOST 'set -e
hostname
uname -r
cat /etc/os-release | sed -n "1,8p"
ip -br -4 addr
ip -4 route show default
df -h / /boot /var /tmp 2>/dev/null || df -h /
dpkg --audit 2>/dev/null || true
systemctl is-system-running || true
ss -tulnp | sed -n "1,160p"
systemctl is-active realm.service sing-box xray 2>/dev/null || true
systemctl list-units "wg-quick@*.service" --no-pager || true
'
```

Mark the host as blocked when:

- Root filesystem or `/boot` is too full for package or initramfs work.
- `dpkg --audit` reports half-configured packages.
- Required service owner is down and its config cannot be validated.
- SSH is unstable enough to prevent isolated per-link operations.

## WireGuard Capability

Check kernel capability before installing extra packages:

```bash
ssh -n root@HOST 'set -e
if ip link add __wg_probe type wireguard 2>/tmp/wg-probe.err; then
  ip link del __wg_probe
  echo wireguard-kernel-ok
else
  cat /tmp/wg-probe.err
  modprobe wireguard 2>&1 || true
fi
'
```

Mark the relationship as blocked when the exit or relay cannot create a WireGuard device. Keep the existing TCP/Realm path active.

## Port And Direction Checks

For each relationship, check:

```bash
ssh -n root@EXIT 'ss -lunp; ss -lntp'
ssh -n root@RELAY 'nc -vz -w 3 EXIT_PUBLIC_IP WG_UDP_PORT || true'
ssh -n root@EXIT 'nc -vz -w 3 RELAY_PUBLIC_IP WG_UDP_PORT || true'
```

Use relay-dials-exit when exit public UDP ingress works.
Use exit-dials-relay when the exit is behind NAT or has restricted public UDP ingress and the relay can accept UDP.

## Existing Proxy Checks

For Realm:

```bash
ssh -n root@RELAY 'test -f /root/realm.toml && sed -n "1,240p" /root/realm.toml'
```

For v2ray-agent/Xray:

```bash
ssh -n root@EXIT 'find /etc/v2ray-agent/xray/conf -maxdepth 1 -type f -name "*.json" -print -exec grep -H "\"port\"\\|serverNames\\|shortIds\\|publicKey\\|\"id\"" {} \;'
```

Record the client-facing relay port and the exit Xray target port before changing a relationship.
