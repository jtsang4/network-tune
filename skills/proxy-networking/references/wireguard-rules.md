# WireGuard Rules

## Interface Names

Linux interface names are limited to 15 bytes. Pick names that fit before writing files.

Preferred patterns:

```text
wg-8-45
wg-193-lala
wg-82-bage
wg-csg-kuroit
wg-hk-kuroit
wg-hk-waptw
```

Use short relay labels for long names:

```text
clawsg -> csg
isifhk -> hk
softbank -> sb
kuroitsg -> kuroit
greensbjp -> green
```

Check:

```bash
python3 - <<'PY'
name = "wg-csg-kuroit"
assert len(name.encode()) <= 15
PY
```

## Address Planning

Use one `/30` per relationship for simple rollback and isolated pacing.

Example:

```text
relay: 10.66.51.1/30
exit:  10.66.51.2/30
```

Keep a topology table with:

```text
link name
relay SSH target and interface
exit SSH target and interface
relay WG IP
exit WG IP
UDP listen side and port
public relay port
exit target port
pacing rate
```

## Connection Direction

Use exit-listen by default:

```text
relay -> exit_public_ip:udp_port
```

Use relay-listen when the exit has NAT, private primary address, or restricted public UDP ingress:

```text
exit -> relay_public_ip:udp_port
```

Keep `PersistentKeepalive = 25` on the dialing side.

## Existing Realm Bridge

For existing links, preserve client-facing ports and credentials:

```text
client -> relay public port -> Realm -> exit WG IP:exit Xray port
```

This keeps the user's VLESS Reality UUID, public key, SNI, short ID, and client URL stable except for links requested through a new relay.
