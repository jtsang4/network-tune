# VLESS Reality Links

## Purpose

Generate share links only when the user asks for them. Treat links as credentials.

## Required Fields

```text
uuid
host: relay public IP or domain
port: relay public inbound port
security: reality
encryption: none
type: tcp
sni: Reality SNI/server_name
pbk: Reality public key
sid: Reality short ID
flow: xtls-rprx-vision when Vision is enabled
name: readable label
```

Optional fields:

```text
fp: browser fingerprint, commonly chrome
alpn: h2,http/1.1
spx: spiderX path
```

## Discovery

For v2ray-agent Xray configs:

```bash
ssh root@HOST 'grep -RInE "uuid|publicKey|privateKey|shortIds|serverNames|dest|flow" /etc/v2ray-agent/xray/conf 2>/dev/null'
```

For v2ray-agent-managed hosts, also use `vasma` subscription/user views when the generated fragments are hard to reconstruct from grep.

For sing-box:

```bash
ssh root@HOST 'find /etc/sing-box /usr/local/etc/sing-box -type f -name "*.json" -maxdepth 3 2>/dev/null | xargs -r jq "."'
```

For existing Realm preservation, remember:

```text
The client-facing host and port are the relay public host and Realm listen port.
The VLESS Reality credentials are still owned by the exit Xray.
```

## Generate With Script

```bash
scripts/gen-vless-link.py \
  --host RELAY_PUBLIC_HOST \
  --port PUBLIC_PORT \
  --uuid UUID \
  --sni SNI \
  --public-key REALITY_PUBLIC_KEY \
  --short-id SHORT_ID \
  --flow xtls-rprx-vision \
  --name "relay-to-exit"
```

For multiple relationships, generate one link per client-facing inbound:

```text
relay 8 port 15659 -> exit 45
relay 8 port 17740 -> exit B
relay 9 port 15659 -> exit C
```

## Link Format

```text
vless://UUID@HOST:PORT?encryption=none&security=reality&sni=SNI&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&flow=xtls-rprx-vision#NAME
```

## Validation

After generating links:

```bash
nc -vz -w 3 RELAY_PUBLIC_HOST PUBLIC_PORT
journalctl -u sing-box -u realm -u xray -n 120 --no-pager
```

If the link uses a preserved Realm bridge, the relay logs show a TCP bridge and the exit Xray logs show accepted VLESS Reality sessions from the relay.
