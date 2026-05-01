# SSH Execution

Batch network changes often mix here-documents, stdin, service restarts, and long-running package commands. Use these rules for predictable execution.

## Command Shape

Use `ssh -n` for ordinary remote commands:

```bash
ssh -n -o ConnectTimeout=12 root@HOST 'systemctl is-active realm.service'
```

Use stdin only when intentionally writing a remote file:

```bash
ssh root@HOST 'cat > /etc/wireguard/LINK.conf.tmp && mv /etc/wireguard/LINK.conf.tmp /etc/wireguard/LINK.conf' < LINK.conf
```

Run each relationship as its own unit of work. Keep no important state only in the local shell.

## Service Restarts

Expect SSH sessions to drop when network-facing services restart. After a drop:

```bash
ssh -n root@HOST 'systemctl is-active SERVICE; wg show LINK || true'
```

Resume from the recorded link state.

## Timeouts

Use explicit connect and operation timeouts:

```bash
ssh -o ConnectTimeout=12 root@HOST '...'
nc -vz -w 3 HOST PORT
ping -c 2 -W 2 IP
```

## Output

Capture enough output to identify the failing state:

```bash
systemctl status UNIT --no-pager -l | sed -n "1,80p"
journalctl -u UNIT -n 80 --no-pager
```
