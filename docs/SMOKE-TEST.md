# Smoke-Test Checklist (P1.4)

**Mode:** Bank pilot  
**Target:** Install → doctor → compliance → uninstall

## Automated

```bash
./scripts/install-bank.sh
./scripts/smoke-test.sh
```

## Manual checklist

| # | Step | Expected | ☐ |
|---|------|----------|---|
| 1 | Install (`install-bank.sh` or pkg) | binary at `~/Library/heald/heald` | |
| 2 | `heald --version` | semver prints | |
| 3 | `heald doctor` | Preset=bank, Cloud=DISABLED, Device set | |
| 4 | `heald policy` | consent=log, cloudEnabled=false, processKill=false | |
| 5 | `heald enroll --show` | deviceId + serial | |
| 6 | `heald compliance` | schema `heald.compliance/v2` | |
| 7 | Kill-switch: `heald policy --consent log --cloud-off` | still log / cloud false | |
| 8 | No outbound | no HEALD_API push (cloud off) | |
| 9 | `./uninstall.sh` | daemon stopped, binary gone | |
| 10 | Data optional purge | `HEALD_PURGE_DATA=1 ./uninstall.sh` | |

## Pass criteria

- All automated checks PASS  
- Zero unexpected remediation in bank mode  
- Uninstall leaves machine without daemon  

## Lab vs Bank

| | Lab | Bank |
|--|-----|------|
| preset | lab | bank |
| consent | auto | log |
| cloud | may on | **off** |
| auto-update | may on | **off** |
| install | `install.sh` / brew | `install-bank.sh` / bank pkg |
