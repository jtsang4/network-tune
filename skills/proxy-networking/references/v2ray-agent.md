# v2ray-agent Integration

## Source

Primary project: <https://github.com/mack-a/v2ray-agent>

The project README describes an Xray-core/sing-box installer with VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy, subscription management, and traffic routing features including WireGuard. It installs through `install.sh`; the management menu opens with `vasma`.

## Install Or Reopen

Install:

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"
chmod 700 /root/install.sh
/root/install.sh
```

Open the menu:

```bash
vasma
```

Use a TTY for menu work:

```bash
ssh -tt root@HOST 'vasma'
```

## Role In This Skill

Use v2ray-agent for:

- Fresh Xray or sing-box VLESS Reality installation on relays or exits.
- Adding users, ports, Reality/Vision combinations, and subscriptions.
- Inspecting and reusing generated Xray or sing-box config paths.
- Hosts already managed by v2ray-agent, especially under `/etc/v2ray-agent`.

Use direct edits around v2ray-agent for:

- WireGuard relay-to-exit tunnels.
- Existing Realm bridges whose public client port should stay stable.
- Link-level pacing, MTU, UDP buffer, and qdisc tuning.
- Small config repairs where rerunning `vasma` would touch unrelated services.

## Common Paths

Check these paths during inventory:

```bash
ls -la /etc/v2ray-agent /etc/v2ray-agent/xray /etc/v2ray-agent/sing-box 2>/dev/null || true
find /etc/v2ray-agent -maxdepth 4 -type f 2>/dev/null | sort | sed -n '1,160p'
systemctl status xray sing-box --no-pager -l 2>/dev/null | sed -n '1,120p'
```

Common Xray config root:

```text
/etc/v2ray-agent/xray/conf
```

Common binary/service shape:

```text
/etc/v2ray-agent/xray/xray
xray.service
sing-box.service
```

## Fresh VLESS Reality Build Pattern

When the user wants the relay itself to terminate VLESS Reality:

1. Use `vasma` to install Xray or sing-box and create the VLESS Reality inbound.
2. Record generated UUID, Reality public key, private key location, short ID, SNI, flow, and public port.
3. Add a WireGuard relationship from relay to exit.
4. Route the relay inbound to the selected exit:
   - sing-box managed relay: add or update route/outbound config.
   - Xray managed relay: use Xray routing plus a WireGuard/TUN approach, or keep Xray as edge and add a local forwarder when simpler.

When the user wants to keep exit-owned Reality credentials:

1. Leave exit Xray/VLESS Reality in place.
2. Add WireGuard between relay and exit.
3. Change relay Realm target from `EXIT_PUBLIC_IP:PORT` to `EXIT_WG_IP:PORT`.
4. Keep the client link host/port pointed at the relay.

## Extract VLESS Reality Fields

Use config grep first:

```bash
grep -RInE '"id"|"uuid"|"flow"|"serverNames"|"shortIds"|"publicKey"|"privateKey"|"dest"|"listen"|"port"' /etc/v2ray-agent 2>/dev/null
```

Then use `vasma` subscription or user management screens when the config is split across generated fragments.

For preserved Realm bridges:

```text
Share link host = relay public IP or domain
Share link port = relay Realm listen port
Reality UUID/key/SNI/short ID = exit Xray values
```

## Operational Guidance

- Back up `/etc/v2ray-agent`, `/root/realm.toml`, and `/etc/wireguard` before running `vasma` or editing generated files.
- Prefer adding a new port for a new relationship. Reuse an existing port only when the user asks to preserve a client link.
- Validate generated configs with the owning service's checker when available.
- After `vasma` changes, re-check custom WireGuard routes and local bridge targets because menu-driven updates can rewrite service configs.
- Record enough fields to regenerate VLESS links later: relay host, relay port, exit owner, UUID, SNI, public key, short ID, flow, fingerprint, label.
