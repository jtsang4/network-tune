# Config Patterns

## WireGuard Link

Use one WireGuard interface per relay-exit relationship when isolation and rollback clarity matter.

Relay:

```ini
[Interface]
Address = 10.66.45.1/30
PrivateKey = RELAY_PRIVATE_KEY
MTU = 1440

[Peer]
PublicKey = EXIT_PUBLIC_KEY
PresharedKey = LINK_PSK
AllowedIPs = 10.66.45.2/32
Endpoint = EXIT_PUBLIC_IP:51845
PersistentKeepalive = 25
```

Exit:

```ini
[Interface]
Address = 10.66.45.2/30
ListenPort = 51845
PrivateKey = EXIT_PRIVATE_KEY
MTU = 1440

[Peer]
PublicKey = RELAY_PUBLIC_KEY
PresharedKey = LINK_PSK
AllowedIPs = 10.66.45.1/32
```

Enable:

```bash
systemctl daemon-reload
systemctl enable --now wg-quick@wg-RELAY-EXIT
wg show wg-RELAY-EXIT
```

## Exit NAT Egress

Use this for fresh builds where the exit machine acts as the Internet egress gateway.

```bash
sysctl -w net.ipv4.ip_forward=1
printf '%s\n' 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/90-proxy-networking-forward.conf
iptables -t nat -C POSTROUTING -s RELAY_WG_CIDR -o EXIT_PUBLIC_IF -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s RELAY_WG_CIDR -o EXIT_PUBLIC_IF -j MASQUERADE
```

Persist with a small oneshot service when the host lacks an existing firewall manager.

## Relay sing-box Multi-Inbound

Use inbound tags to map public ports to exits. If v2ray-agent owns sing-box, merge this pattern into its generated config after backing up `/etc/v2ray-agent`.

Minimal structure:

```json
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-8-to-45",
      "listen": "::",
      "listen_port": 15659,
      "users": [
        {
          "uuid": "UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "SNI",
            "server_port": 443
          },
          "private_key": "REALITY_PRIVATE_KEY",
          "short_id": ["SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "wg-8-to-45",
      "server": "EXIT_PUBLIC_IP",
      "server_port": 51845,
      "local_address": ["10.66.45.1/30"],
      "private_key": "RELAY_PRIVATE_KEY",
      "peer_public_key": "EXIT_PUBLIC_KEY",
      "pre_shared_key": "LINK_PSK",
      "mtu": 1440
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": ["in-8-to-45"],
        "outbound": "wg-8-to-45"
      }
    ]
  }
}
```

Before reload:

```bash
sing-box check -c /etc/sing-box/config.json
systemctl reload sing-box || systemctl restart sing-box
```

## Existing Realm Bridge

Use this when the client-facing VLESS Reality credentials remain on the exit Xray.

Before:

```toml
[[endpoints]]
listen = "0.0.0.0:15659"
remote = "45.8.112.125:15659"
```

After:

```toml
[[endpoints]]
listen = "0.0.0.0:15659"
remote = "10.66.45.2:15659"
```

Validate:

```bash
scripts/patch-realm-endpoint.py --file /root/realm.toml --listen 0.0.0.0:15659 --remote 10.66.45.2:15659
systemctl restart realm.service
journalctl -u realm.service -n 80 --no-pager
nc -vz -w 3 127.0.0.1 15659
nc -vz -w 3 10.66.45.2 15659
```

See `realm-safety.md` before editing Realm in a multi-endpoint relay.

## WireGuard Pacing And Buffers

Use pacing when public UDP can burst above the stable rate and then drops packets.

```bash
cat > /etc/sysctl.d/98-wg-LINK-opt.conf <<EOF
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.netdev_max_backlog = 30000
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
EOF

sysctl -p /etc/sysctl.d/98-wg-LINK-opt.conf
ip link set dev PUBLIC_IF txqueuelen 10000
ip link set dev WG_IF mtu 1440
ip link set dev WG_IF txqueuelen 10000
ethtool -K PUBLIC_IF rx-udp-gro-forwarding on 2>/dev/null || true
tc qdisc replace dev WG_IF root tbf rate 680mbit burst 8mb latency 50ms
```

Persist as a oneshot service:

```ini
[Unit]
Description=Optimize WireGuard LINK tunnel pacing and buffers
After=wg-quick@LINK.service network-online.target
Wants=wg-quick@LINK.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/LINK-optimize.sh

[Install]
WantedBy=multi-user.target
```

Pick `rate` from tests:

```text
clean 500M, lossy 800M -> pace around 620-680M
clean 1G, lossy 1.5G -> pace around 1G
```

## Verification Checklist

```bash
systemctl is-enabled wg-quick@LINK proxy-service
systemctl is-active wg-quick@LINK proxy-service
wg show LINK
ip route get EXIT_WG_IP
ping -c 3 EXIT_WG_IP
tc -s qdisc show dev WG_IF
curl -4 --max-time 10 https://www.youtube.com/generate_204 -o /dev/null -w '%{http_code} %{remote_ip} %{time_total}\n'
```

For reboot verification, reboot one side at a time and confirm `wg show` has a recent handshake.

## Rollback

Restore the timestamped backup, disable new services, then restart the original service owner:

```bash
cp -a /root/proxy-networking-backup-TS/realm.toml /root/realm.toml
systemctl restart realm.service
systemctl disable --now wg-quick@LINK wg-LINK-optimize.service
```
