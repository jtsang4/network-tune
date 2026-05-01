# Package Policy

Install packages only after preflight says the host can tolerate package work.

## Checks Before Installing

```bash
ssh -n root@HOST 'df -h / /boot /var /tmp 2>/dev/null || df -h /; dpkg --audit 2>/dev/null || true; pgrep -af "apt|dpkg" || true'
```

Mark the host blocked when disk space is tight, `dpkg --audit` reports half-configured packages, or apt/dpkg is already active for unrelated work.

## Preferred Install Command

```bash
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends wireguard-tools iproute2 iperf3 ethtool
```

`wireguard-tools` is enough when the current kernel already supports WireGuard. Installing a meta-package that pulls kernels can trigger initramfs work on small VPS disks.

## Kernel Capability First

Run the WireGuard device probe before package work:

```bash
ip link add __wg_probe type wireguard
ip link del __wg_probe
```

When the probe fails because the kernel lacks WireGuard support, repair the kernel or reboot plan as a separate host-maintenance task.

## Half-Configured Package Handling

When package installation leaves `dpkg --audit` output, stop relationship changes for that host. Report:

```text
host
failed package
root and boot free space
last apt/dpkg log lines
current working network path
```
