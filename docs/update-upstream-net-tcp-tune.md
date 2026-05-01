# Update Upstream net-tcp-tune.sh

This document is for agents updating the bundled Eric86777/vps-tcp-tune source used by `skills/network-tune`.

## Files To Update

```text
skills/network-tune/scripts/upstream/net-tcp-tune.sh
skills/network-tune/scripts/upstream/LICENSE
skills/network-tune/references/tuning-policy.md
```

## Update Steps

Run from the repository root:

```bash
tmpdir=$(mktemp -d)
git clone --depth 1 https://github.com/Eric86777/vps-tcp-tune.git "$tmpdir"

new_commit=$(git -C "$tmpdir" rev-parse --short HEAD)
cp "$tmpdir/net-tcp-tune.sh" skills/network-tune/scripts/upstream/net-tcp-tune.sh
cp "$tmpdir/LICENSE" skills/network-tune/scripts/upstream/LICENSE
chmod +x skills/network-tune/scripts/upstream/net-tcp-tune.sh

rm -rf "$tmpdir"
printf 'Updated upstream to %s\n' "$new_commit"
```

Then update the commit marker in:

```text
skills/network-tune/references/tuning-policy.md
```

Replace the old text like:

```text
from commit `eb38a0f`
```

with the new short commit.

## Required Validation

Run:

```bash
bash -n skills/network-tune/scripts/upstream/net-tcp-tune.sh
bash -n skills/network-tune/scripts/remote-tcp-tune.sh
bash -n skills/network-tune/scripts/agent-tcp-tune.sh
```

Run skill validation. If the local Python environment lacks `yaml`, use a temporary venv:

```bash
python3 -m venv /tmp/skill-validate-venv
/tmp/skill-validate-venv/bin/pip install -q pyyaml
/tmp/skill-validate-venv/bin/python /Users/bytedance/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/network-tune
```

Expected result:

```text
Skill is valid!
```

## Compatibility Check

`skills/network-tune/scripts/remote-tcp-tune.sh` uses the upstream script as a function library by deleting the standalone entry line:

```bash
sed '/^[[:space:]]*main[[:space:]]*"\$@"[[:space:]]*$/d' "$UPSTREAM" > "$LIB"
```

After updating upstream, check that the upstream entrypoint still matches this pattern:

```bash
tail -n 30 skills/network-tune/scripts/upstream/net-tcp-tune.sh
```

If Eric changes the entrypoint, update `prepare_lib()` in `remote-tcp-tune.sh` so sourcing the generated `$LIB` does not open the interactive menu or execute the script automatically.

## Smoke Test Without A Remote VPS

Run:

```bash
skills/network-tune/scripts/agent-tcp-tune.sh --help
skills/network-tune/scripts/remote-tcp-tune.sh --help
```

Both commands should print help without trying to modify the local machine.

## Optional Live Test

Use a disposable Debian/Ubuntu VPS:

```bash
skills/network-tune/scripts/agent-tcp-tune.sh \
  --target root@HOST \
  --bandwidth-mbps 1000 \
  --region asia \
  --reboot-verify
```

Verify the final output includes:

```text
KERNEL=<xanmod kernel>
CONGESTION=bbr
QDISC=fq
TCP_RMEM=4096 87380 16777216
TCP_WMEM=4096 65536 16777216
BBR_PERSIST_ENABLED=enabled
DNS_PERSIST_ENABLED=enabled
```
