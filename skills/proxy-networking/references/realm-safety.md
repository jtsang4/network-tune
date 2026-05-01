# Realm Safety

Realm config changes are high impact because a malformed `/root/realm.toml` can stop every relay endpoint on that machine.

## Safe Update Procedure

1. Back up `/root/realm.toml` with a timestamp.
2. Update exactly one `[[endpoints]]` block by matching its full `listen` value.
3. Validate the resulting config before restarting Realm.
4. Restart `realm.service`.
5. Check the local relay port and backend target.
6. Restore the backup immediately when Realm fails to start.

Preferred update tool:

```bash
scripts/patch-realm-endpoint.py \
  --file /root/realm.toml \
  --listen 0.0.0.0:11071 \
  --remote 10.66.51.6:13397
```

Remote use pattern:

```bash
scp scripts/patch-realm-endpoint.py root@RELAY:/tmp/patch-realm-endpoint.py
ssh -n root@RELAY 'python3 /tmp/patch-realm-endpoint.py --file /root/realm.toml --listen 0.0.0.0:11071 --remote 10.66.51.6:13397'
ssh -n root@RELAY 'systemctl restart realm.service && systemctl is-active realm.service'
```

## Rollback

```bash
ssh -n root@RELAY 'cp -a /root/realm.toml.bak-YYYYMMDD-HHMMSS /root/realm.toml && systemctl restart realm.service'
```

## Validation

```bash
ssh -n root@RELAY 'grep -A1 -B1 "0.0.0.0:11071" /root/realm.toml'
ssh -n root@RELAY 'nc -vz -w 3 127.0.0.1 11071'
ssh -n root@RELAY 'nc -vz -w 3 10.66.51.6 13397'
```

Use a parser or the patch script for Realm updates. Regex string replacement is acceptable only for read-only inspection.
