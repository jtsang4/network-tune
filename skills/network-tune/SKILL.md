---
name: network-tune
description: Agent-facing VPS TCP/BBR tuning over SSH, equivalent to Eric86777/vps-tcp-tune option 66 with safer orchestration. Use when Codex needs to optimize a Linux VPS given an SSH target, IP address, hostname, or root@host; install XanMod/BBR v3, apply TCP buffer/FQ/MSS/initcwnd tuning, DNS purification, Realm/conntrack fixes, IPv6 policy, reboot, verify persistence, or diagnose why vps-tcp-tune returns to its menu during kernel installation.
---

# Network Tune

## Goal

Tune a remote Debian/Ubuntu VPS over SSH using an agent-safe equivalent of Eric86777/vps-tcp-tune option 66. Prefer the bundled wrapper instead of manually pasting large shell functions.

## Core Command

Run from this skill directory:

```bash
scripts/agent-tcp-tune.sh --target root@HOST --bandwidth-mbps 1000 --region asia --reboot-verify
```

Use `--target root@IP` when the user gives only an IP. Use `--bandwidth-mbps` from the user's plan or provider spec; avoid relying on one automatic Speedtest result. Use `--region asia` for Singapore/HK/JP/KR and `--region overseas` for high-latency transoceanic service paths.

Options:

```text
--no-dns       skip DNS purification
--no-realm     skip Realm/conntrack tuning
--keep-ipv6    keep IPv6 enabled
```

The wrapper uploads:

```text
scripts/remote-tcp-tune.sh
scripts/upstream/net-tcp-tune.sh
```

to `/root/agent-tcp-tune` on the remote host.

## Workflow

1. Confirm the SSH target and expected bandwidth. If the user asks for a complete operation, reboot verification is allowed; otherwise ask before rebooting.
2. Run `scripts/agent-tcp-tune.sh` with manual bandwidth and region.
3. If the wrapper exits `10`, it installed a kernel and stopped before reboot because `--reboot-verify` was omitted. Re-run with `--reboot-verify` or reboot manually and then run the remote `tune-66` command.
4. Report the final verification keys: kernel, congestion control, qdisc, TCP buffers, initcwnd/initrwnd, IPv6 status, conntrack, DNS, MSS clamp, and persistence services.

## Important Policy

Read `references/tuning-policy.md` when you need rationale, rollback notes, or failure handling details.

Critical defaults:

- Prefer manual `--bandwidth-mbps` over automatic Speedtest.
- Treat 1Gbps Singapore VPS as `--bandwidth-mbps 1000 --region asia`, which gives Eric's 16MB TCP buffer profile.
- Probe XanMod packages instead of hard-installing `x64v4`; v4 CPUs often need v3 packages because the repo may not publish v4.
- Prefer XanMod LTS packages, then mainline, then edge.
- Remove temporary XanMod APT sources after install.
- Verify after reboot when the user permits rebooting.

## Direct Remote Commands

For manual recovery or debugging after upload:

```bash
ssh root@HOST 'bash /root/agent-tcp-tune/remote-tcp-tune.sh preflight'
ssh root@HOST 'bash /root/agent-tcp-tune/remote-tcp-tune.sh install-kernel'
ssh root@HOST 'bash /root/agent-tcp-tune/remote-tcp-tune.sh tune-66 --bandwidth-mbps 1000 --region asia'
ssh root@HOST 'bash /root/agent-tcp-tune/remote-tcp-tune.sh verify'
```

Remote logs live in `/root/agent-tcp-tune/logs`.

## Output Standard

Keep the final report short and concrete:

```text
Kernel: 6.x-xanmod
BBR: bbr
Qdisc: fq
TCP buffer: 16MB
initcwnd/initrwnd: 32
DNS persistence: enabled/active
BBR persistence: enabled/active
IPv6: disabled or kept
Rollback: /root/agent-tcp-tune/backup-* and DNS rollback path if created
```
