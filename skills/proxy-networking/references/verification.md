# Verification

Verify at three layers: tunnel, proxy, and public entry.

## Tunnel Layer

Run on the relay:

```bash
systemctl is-enabled wg-quick@LINK
systemctl is-active wg-quick@LINK
wg show LINK
ping -c 2 -W 2 EXIT_WG_IP
tc qdisc show dev LINK
```

Recent handshake and nonzero transfer counters indicate that the peer path is alive.

## Backend Proxy Layer

Run on the relay:

```bash
nc -vz -w 3 EXIT_WG_IP EXIT_PROXY_PORT
```

Run on the exit:

```bash
systemctl is-active xray sing-box 2>/dev/null || true
ss -lntp | grep "EXIT_PROXY_PORT"
```

## Relay Entry Layer

Run on the relay:

```bash
systemctl is-active realm.service sing-box xray 2>/dev/null || true
nc -vz -w 3 127.0.0.1 PUBLIC_PORT
```

Run from the operator machine:

```bash
nc -vz -w 5 RELAY_PUBLIC_IP PUBLIC_PORT
```

## Persistence

```bash
systemctl is-enabled wg-quick@LINK
systemctl is-enabled LINK-optimize.service
systemctl is-active LINK-optimize.service
```

For reboot verification, reboot one side at a time and confirm the same checks.

## Report Format

```text
Completed:
relay:public_port -> exit_wg_ip:exit_port via LINK

Preserved:
relay:public_port -> existing remote

Blocked:
relationship, host, blocker, current working path

Backups:
/root/realm.toml.bak-...
/etc/wireguard/LINK.conf.bak-...
```
