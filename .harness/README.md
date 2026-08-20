<!--
SPDX-License-Identifier: Apache-2.0
-->

# Fluss Operational Harness

This folder contains small operator scripts that Codex agents can reuse for
the jfk Fluss cluster. They are intentionally separate from product code and
must not contain credentials.

## Scripts

- `fluss_jfk_hosts.sh` contains the jfk coordinator and tablet server host
  lists shared by the harness scripts.
- `fluss_update_storage_config.sh` updates `/vdb/fluss-1.0-SNAPSHOT/conf/server.yaml`
  on all jfk coordinator and tablet server nodes. It writes `remote.data.dir`,
  `fs.s3a.access.key`, and `fs.s3a.secret.key`, and can optionally also set
  `remote.data.dirs`. The script is dry-run by default and only applies changes
  with `--execute`.
- `fluss_verify_storage_config.sh` checks the active storage configuration on
  all jfk nodes. It prints `remote.data.dir`, reports whether `remote.data.dirs`
  is present, and only reports S3 credential fields as `<set>` or `<missing>`.

## Usage

Dry-run the current default storage target:

```bash
./.harness/fluss_update_storage_config.sh
```

Apply a storage config update. The script prompts for the access key and secret
key using hidden input if no file or environment source is supplied:

```bash
./.harness/fluss_update_storage_config.sh \
  --remote-dir s3://wap-udp-cus-dashboard-prod-useast1/fluss \
  --execute
```

Verify without printing credential values:

```bash
./.harness/fluss_verify_storage_config.sh
```

## Safety Notes

- Always connect as `waphz` and escalate remotely with `sudo su - root -c`.
- Do not pass secrets as command-line arguments.
- Do not print `server.yaml` contents directly because it may contain
  credentials.
- Updating the config files does not restart Fluss services. Restart
  coordinator and tablet servers separately when the new config must be loaded.
