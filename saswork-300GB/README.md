# SAS WORK Storage Stress Test — 300 GB Dataset Generator

A SAS program for **SAS Viya (tested on LTS 2025.09)** that creates a large dataset (~300 GB by default) in the `SASWORK` location. It is designed for **storage benchmarking**, **disk-space testing**, and **performance validation** of the underlying compute node storage (PVC, ephemeral disk, NVMe, NFS, etc.).

The script reports progress periodically during the build and prints a final runtime summary with throughput statistics.

---

## Features

- Generates a configurable-size SAS dataset directly in `SASWORK`
- Progress reports every 10 minutes (configurable) showing:
  - Elapsed time
  - Observations written and % complete
  - Actual on-disk file size in GB
  - Estimated time remaining (ETA)
- Final summary including total runtime (hh:mm:ss), final file size, and throughput in **GB/min** and **obs/sec**
- Pre-run check of the `SASWORK` filesystem to confirm available space
- Pure DATA step — no external dependencies, no PROC SQL, no CAS

---

## Requirements

- SAS Viya 2025.09 LTS (or compatible Viya release)
- SAS Studio access on a compute server with sufficient free space in `SASWORK`
- Recommended free space: **at least 320 GB** for the default 300 GB target

> The script writes uncompressed data (`COMPRESS=NO`) so that the resulting `.sas7bdat` file accurately reflects the target size on disk.

---

## Usage

1. Open **SAS Studio** in your Viya environment.
2. Open or paste the contents of `create_large_saswork_dataset.sas` into a new program tab.
3. (Optional) Adjust the parameters at the top of the script (see [Configuration](#configuration)).
4. Submit the program.
5. Watch the log for progress reports and the final summary.

### Quick run with defaults

```sas
/* Default: ~300 GB, progress every 10 minutes */
%let nobs            = 322122547;
%let report_interval = 600;
```

---

## Configuration

| Macro variable     | Default       | Description                                                                                  |
| ------------------ | ------------- | -------------------------------------------------------------------------------------------- |
| `nobs`             | `322122547`   | Number of observations to write. Each obs is ~1,000 bytes, so default ≈ 300 GB.              |
| `report_interval`  | `600`         | Seconds between progress reports in the log (600 = 10 minutes).                              |

### Sizing guide

The dataset uses 10 character variables of length 100, producing roughly 1,000 bytes per observation. Approximate `nobs` values:

| Target size | `nobs` value     |
| ----------- | ---------------- |
| 10 GB       | `10737418`       |
| 50 GB       | `53687091`       |
| 100 GB      | `107374182`      |
| 300 GB      | `322122547`      |
| 500 GB      | `536870912`      |
| 1 TB        | `1073741824`     |

> SAS adds a small amount of page and header overhead, so the final `.sas7bdat` will be marginally larger than the logical size. Reduce `nobs` slightly if you need to stay strictly under a limit.

---

## Sample Log Output

### Progress reports (every 10 minutes)

```
NOTE: ---- Progress report #1 ----
NOTE:   Time         : 18MAY2026:14:32:15
NOTE:   Elapsed (min): 0:10:02 (         602 sec)
NOTE:   Obs written  :      38,500,000 of 322122547 ( 11.95%)
NOTE:   File size    :     35.842 GB on disk
NOTE:   ETA remaining:     73.8 minutes
NOTE: -----------------------------------
```

### Final runtime summary

```
NOTE: ============================================================
NOTE: =============== FINAL RUNTIME SUMMARY ======================
NOTE: ============================================================
NOTE:   Start time     : 18MAY2026:14:22:13
NOTE:   End time       : 18MAY2026:14:30:17
NOTE:   Total elapsed  : 00:08:04  (         484.0 seconds)
NOTE:   Total elapsed  : 0:08:04 (hh:mm:ss)

NOTE:   Observations   : 322122547
NOTE:   Final size     :    322,156,789,248 bytes
NOTE:   Final size     :      300.124 GB

NOTE:   Throughput     :      37.20 GB/min
NOTE:   Throughput     :     665,542 obs/sec
NOTE: ============================================================
```

---

## How It Works

1. **Pre-flight check** — Resolves the `SASWORK` path and runs `df -h` to confirm available disk space.
2. **DATA step build** — Writes `nobs` observations, each composed of 10 character variables filled with a fixed 100-byte string.
3. **In-step monitoring** — Every 100,000 observations, the step checks the wall clock. If at least `report_interval` seconds have passed since the last report, it queries the on-disk file size via the `fopen`/`finfo` SAS file functions and logs a progress note.
4. **Final summary** — After the DATA step finishes, a `_NULL_` DATA step computes total runtime, final size, and throughput metrics and writes them to the log.
5. **PROC CONTENTS** — Confirms the dataset structure and observation count.

---

## Important Notes

### SASWORK is ephemeral

Data in `SASWORK` is deleted when the SAS session ends. If you need to keep the dataset for later use, copy it to a permanent library or CAS caslib before logging off:

```sas
proc copy in=work out=mylib;
   select big_dataset;
run;
```

### Log buffering in SAS Studio

In Viya, SAS Studio may not stream the log in real time during a long-running DATA step. Progress reports will appear when the log refreshes (often at step end). For true real-time monitoring, check the file from a separate session using shell tools:

```bash
ls -lh /path/to/SAS_work*/big_dataset.sas7bdat
```

### Throughput interpretation

The reported `GB/min` is a useful indicator of sequential write throughput on the underlying `SASWORK` storage. Typical values:

| Storage type                | Expected GB/min |
| --------------------------- | --------------- |
| Network-attached (NFS/SMB)  | 1–5             |
| Standard SSD PVC            | 5–15            |
| High-performance SSD/NVMe   | 20–50+          |

---

## Repository Contents

```
.
├── create_large_saswork_dataset.sas   # Main SAS program
└── README.md                          # This file
```

---

## Use Cases

- Benchmarking `SASWORK` storage performance on new Viya environments
- Validating PVC sizing for compute node pools
- Stress-testing disk capacity and alerting thresholds
- Producing reproducible large datasets for downstream PROC performance tests (SORT, SQL joins, CAS load times)

---

## Caveats

- This script intentionally generates highly repetitive data. **Do not enable compression** (`COMPRESS=YES`) unless you want a much smaller on-disk footprint — the repeated filler string compresses to near nothing.
- Running this on a shared compute node may impact other users. Coordinate with your SAS administrator before running on production environments.
- Confirm available `SASWORK` space before running. If the disk fills up mid-step, the DATA step will fail and the partial dataset will still occupy space until the session ends or you explicitly delete it.

---

## License

Provided as-is for internal benchmarking and educational use. Adapt freely for your environment.

---

## Author / Maintainer

_Add your name, team, or contact info here._
