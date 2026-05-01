# Link State

Use one state record per relay-exit relationship. This makes batch changes resumable after SSH drops, service restarts, or host-specific blockers.

## States

```text
planned
preflight_ok
wg_written
wg_active
backend_reachable
realm_updated
opt_applied
verified
blocked
rollback_needed
```

## Required Evidence

`preflight_ok`:

```text
primary interface known
WireGuard capability confirmed
package state clean enough for planned operation
relevant public and service ports known
connection direction selected
```

`wg_written`:

```text
/etc/wireguard/LINK.conf exists on both hosts
keys and preshared key exist with 0600 permissions
interface name length <= 15 bytes
```

`wg_active`:

```bash
systemctl is-active wg-quick@LINK
wg show LINK
```

`backend_reachable`:

```bash
ping -c 2 EXIT_WG_IP
nc -vz -w 3 EXIT_WG_IP EXIT_PROXY_PORT
```

`realm_updated`:

```text
Realm config backup exists
Realm endpoint maps PUBLIC_PORT -> EXIT_WG_IP:EXIT_PROXY_PORT
realm.service is active
```

`opt_applied`:

```bash
systemctl is-active LINK-optimize.service
tc qdisc show dev LINK
ip link show LINK
```

`verified`:

```bash
nc -vz -w 3 127.0.0.1 PUBLIC_PORT
nc -vz -w 5 RELAY_PUBLIC_IP PUBLIC_PORT
systemctl is-enabled wg-quick@LINK LINK-optimize.service
```

## Resume Rules

Resume from the first missing state. Re-check the previous state before proceeding.

When a host becomes blocked, leave the current working route active. Remove failed one-off units and reset failed systemd state after recording the blocker.

## Batch Rule

Apply and verify one relationship at a time. A later relationship should not depend on shell state from an earlier relationship.
