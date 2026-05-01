# Tuning Policy

## Scope

This skill implements an agent-facing equivalent of Eric86777/vps-tcp-tune option 66:

1. Install XanMod + BBR v3 kernel when the host supports it.
2. Apply BBR direct/endpoint tuning.
3. Apply DNS purification.
4. Apply Realm/conntrack timeout tuning.
5. Disable IPv6 when requested.
6. Reboot and verify persistence when the user allows a reboot.

The bundled upstream script is Eric86777/vps-tcp-tune `net-tcp-tune.sh` from commit `eb38a0f` and remains under its MIT license in `scripts/upstream/LICENSE`.

## Lessons Encoded From Real Use

- `dl.xanmod.org/archive.key` can return Cloudflare challenge 403. Prefer the GitHub mirror key first, then fall back to the official key.
- CPU x86-64-v4 support does not imply that a v4 XanMod package exists. Probe APT candidates and safely downgrade to v3/v2/v1 packages.
- Prefer `linux-xanmod-lts-x64vN` before mainline/edge for general VPS tuning.
- Remove the temporary XanMod APT source after installation to avoid mixing distro suites during future `apt update`.
- Do not let a single successful Speedtest decide the tuning profile. Ask for expected bandwidth or use a known-good nearby server. A bad "closest" server can under-report 1Gbps as 300-500Mbps and select too small a TCP buffer.
- For a 1Gbps Singapore/Asia VPS, use `--bandwidth-mbps 1000 --region asia`, which maps Eric's buffer policy to 16MB.
- For high-latency cross-ocean service paths, use `--region overseas`; Eric's policy uses a larger buffer for the same nominal bandwidth.

## Safety Defaults

- Always run SSH preflight before changing anything.
- Create a remote backup under `/root/agent-tcp-tune/backup-*`.
- Treat kernel installation as a two-stage operation: install, reboot, tune.
- Reboot only when the user has allowed it explicitly or the request clearly asks for an end-to-end operation.
- Verify after reboot: kernel, BBR, qdisc, TCP buffers, initcwnd, IPv6, conntrack, DNS, MSS clamp, and systemd persistence services.

## Main Remote Paths

- Work directory: `/root/agent-tcp-tune`
- Logs: `/root/agent-tcp-tune/logs`
- Remote wrapper: `/root/agent-tcp-tune/remote-tcp-tune.sh`
- Bundled upstream script: `/root/agent-tcp-tune/net-tcp-tune.sh`
- DNS rollback: `/root/.dns_purify_backup/<timestamp>/rollback.sh`
- Realm backup: `/root/.realm_fix_backup/<timestamp>`

## Rollback Notes

- DNS purification has its own generated rollback script in `/root/.dns_purify_backup/<timestamp>/rollback.sh`.
- IPv6 can be restored through Eric's cancel function, or by removing `/etc/sysctl.d/99-disable-ipv6.conf` and applying `sysctl --system`.
- BBR direct tuning can be reversed by restoring the backup under `/root/agent-tcp-tune/backup-*`, disabling `bbr-optimize-persist.service`, and reloading sysctl/systemd.
- XanMod kernel rollback is provider/distro-specific: boot a previous kernel through GRUB or remove the XanMod packages after confirming a stock kernel is available.
