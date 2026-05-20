# SAS Viya 4 — SASWORK Storage Migration Benchmark

Benchmark suite to measure SAS WORK performance before and after migrating the WORK location to faster storage (e.g. EBS root filesystem → NVMe RAID-0). Produces a self-contained HTML report with bar charts comparing the two runs.

Built and tested on **SAS Viya 4 LTS 2025.09** (Compute Server / SPRE).

---

## What it does

The suite consists of two SAS programs:

1. **`saswork_stress_test.sas`** — generates ~100 GB of synthetic data and times five common SASWORK operations (write, read, sort, SQL join, delete). Run this **twice**: once before the storage migration and once after.
2. **`saswork_stress_report.sas`** — reads both sets of timings and builds an HTML comparison report with bar charts, speedup factors, and a per-iteration variability box plot. Run this **once** after both stress test runs are complete.

### Workflow

```
                Run 1 (BEFORE)               Run 2 (AFTER)
                EBS root FS                  NVMe RAID-0
                      │                            │
                      └────────────┬───────────────┘
                                   ▼
                          METRICS_DIR
                  results.sas7bdat + timings.sas7bdat
                                   │
                                   ▼
                     saswork_stress_report.sas
                                   │
                                   ▼
                  saswork_benchmark_report.html
```

---

## What gets tested

For each of 10 tables (configurable), five operations are timed:

| Test               | What it does                                    | Why it matters                                   |
| ------------------ | ----------------------------------------------- | ------------------------------------------------ |
| `WRITE_DATA_STEP`  | Creates a ~10 GB table with 50M rows            | Pure sequential write throughput                 |
| `READ_PROC_MEANS`  | Full sequential scan via PROC MEANS             | Sequential read throughput                       |
| `SORT`             | PROC SORT by two columns                        | Heavy disk use — sort utility files              |
| `SQL_JOIN`         | PROC SQL self-join, filtered output             | Mixed read/write pattern                         |
| `DELETE`           | PROC DATASETS DELETE                            | Filesystem unlink throughput                     |

Result: **50 timed measurements per run**, 100 across BEFORE + AFTER.

---

## Disk safety

A naive 100 GB stress test that creates ten 10 GB tables and then sorts/joins them all can peak at **~240 GB on disk** (original + sorted + join utility files held simultaneously). That would fill a 200 GB root filesystem during the BEFORE run.

This program is **rolling**: it processes one table at a time end-to-end (write → read → sort → join → delete) and cleans up before the next. Peak SASWORK footprint stays around **25–35 GB** regardless of `NUM_TABLES`. A pre-flight `df` check aborts if free space is below `SAFETY_GB` (default 50 GB).

---

## Requirements

- SAS Viya 4 (Compute Server) — should also work on SAS 9.4 with minor adjustments
- A persistent path for `METRICS_DIR` that survives the WORK cutover (see "Important" below)
- Approximately 35 GB of free space on the WORK filesystem at runtime
- Permission to shell out via `filename pipe` for the pre-flight disk check (optional — warns and continues if unavailable)

---

## Usage

### 1. Before migration — BEFORE run

Edit `saswork_stress_test.sas`, set the parameters at the top:

```sas
%let RUN_LABEL   = BEFORE;
%let METRICS_DIR = /tmp/saswork_bench;   /* See "Important" below */
%let NUM_TABLES  = 10;
%let NUM_OBS     = 50000000;
%let SAFETY_GB   = 50;
```

Submit the program. Expected runtime on EBS root FS: **45–90 minutes**, depending on throughput limits.

### 2. Migrate WORK to the new storage

Update your `sas-launcher` ConfigMap (or equivalent) so the `-WORK` option points to the new NVMe mount (e.g. `/saswork`). Recycle the Compute Server pod so the change takes effect.

**Before recycling**, back up the BEFORE metrics:

```bash
cp /tmp/saswork_bench/*.sas7bdat ~/saswork_bench_backup/
```

If `/tmp` is ephemeral in your pod (it usually is on K8s-managed Viya 4 unless `/tmp` is backed by a PVC), the BEFORE results will vanish on pod restart and you'll need to redo the BEFORE run.

### 3. After migration — AFTER run

Open a new SAS session on the recycled pod. **Verify** the new WORK path:

```sas
%put NOTE: WORK is at: %sysfunc(pathname(work));
```

Should show `/saswork/...` (or wherever you mounted the NVMe). If it still shows the old path, the launcher config change didn't take effect.

Edit `saswork_stress_test.sas`, change just one line:

```sas
%let RUN_LABEL = AFTER;
```

Submit. Expected runtime: **significantly less** than the BEFORE run.

### 4. Generate the report

Run `saswork_stress_report.sas`. Output lands at `&METRICS_DIR/saswork_benchmark_report.html`.

The HTML is self-contained (SVG charts inlined, no external image files) — you can email it, drop it in SharePoint, or commit it to a repo.

---

## Output

### `results.sas7bdat` — summary, one row per test per run

| run_label | work_path     | test_name        | n_iterations | total_sec | mean_sec | min_sec | max_sec |
| --------- | ------------- | ---------------- | ------------ | --------- | -------- | ------- | ------- |
| BEFORE    | /opt/sas/work | WRITE_DATA_STEP  | 10           | 423.50    | 42.35    | 40.1    | 45.8    |
| BEFORE    | /opt/sas/work | SORT             | 10           | 612.80    | 61.28    | 58.2    | 65.1    |
| AFTER     | /saswork      | WRITE_DATA_STEP  | 10           | 165.20    | 16.52    | 15.9    | 17.4    |
| AFTER     | /saswork      | SORT             | 10           | 195.40    | 19.54    | 18.8    | 20.7    |

### `timings.sas7bdat` — raw per-iteration data

One row per timed step (10 tables × 5 tests × 2 runs = 100 rows).

### `saswork_benchmark_report.html` — visual comparison

Contents:
- Configuration table (BEFORE vs AFTER WORK paths, overall totals, improvement %, speedup)
- Headline chart — total elapsed time, BEFORE vs AFTER
- Per-test grouped bar chart
- Improvement % bar chart per test
- Speedup factor bar chart per test
- Detailed comparison table
- Box plot showing per-iteration variability (NVMe is usually not just faster but more *consistent*)

---

## Configuration reference

| Parameter      | Default                 | Purpose                                                  |
| -------------- | ----------------------- | -------------------------------------------------------- |
| `RUN_LABEL`    | `BEFORE`                | Set to `BEFORE` or `AFTER`. Tags results in the dataset. |
| `METRICS_DIR`  | `/tmp/saswork_bench`    | Persistent directory for results files                   |
| `NUM_TABLES`   | `10`                    | Number of tables to cycle through                        |
| `NUM_OBS`      | `50000000`              | Rows per table (~10 GB each)                             |
| `SAFETY_GB`    | `50`                    | Abort if free space on WORK FS is below this             |

To scale the test up or down, change `NUM_TABLES` and/or `NUM_OBS`. Per-table size scales linearly with `NUM_OBS`.

---

## Important — pick `METRICS_DIR` carefully

The two metrics datasets must **survive between the BEFORE and AFTER runs**. On Kubernetes-managed Viya 4 deployments, the Compute Server pod is usually recycled when launcher config changes, and `/tmp` inside the pod is typically ephemeral.

**Recommended persistent locations** (in order of preference):

1. Your user home directory if backed by a PVC: `/home/<user>/saswork_bench`
2. A shared data mount: `/sasdata/saswork_bench`, `/data/saswork_bench`
3. As a fallback, `/tmp/saswork_bench` + manually copy the `.sas7bdat` files to your laptop or a safe location before the pod is recycled

Set `METRICS_DIR` to the **same path** in both programs.

---

## Troubleshooting

**"Free space below safety threshold, aborting"**
Free up space on the WORK filesystem, or lower `SAFETY_GB` if you're confident you have enough headroom for the rolling working set.

**Report says "Need both BEFORE and AFTER runs"**
The metrics dataset only contains one run label. Check `bench.results` with `proc print` and confirm both runs are present.

**AFTER run shows the old WORK path**
The launcher config / ConfigMap change didn't take effect. Verify the SAS Compute Server pod was actually recycled after the change. `%put %sysfunc(pathname(work));` should reflect the new mount.

**Charts not rendering when HTML is opened locally**
Make sure the report code uses `imagefmt=svg` and `options(svg_mode='inline' bitmap_mode='inline')` in the `ods html5` statement. This embeds all chart graphics into the HTML so there are no external image dependencies.

**SQL_JOIN runtime looks suspiciously short**
The join is filtered with `where a.grp < 200` so the output stays small (and so the test stays disk-safe). It still exercises significant read I/O. To stress harder, raise the filter threshold — but watch the disk budget.

---

## Files in this repo

```
saswork_stress_test.sas      Stress test - run twice (BEFORE and AFTER)
saswork_stress_report.sas    Report generator - run once
README.md                    This file
```

---

## Why this benchmark exists

PROC SORT, PROC SQL joins, and large DATA step outputs are among the most disk-bound operations in SAS. Moving WORK from a shared root filesystem to dedicated NVMe typically reduces these operations by 2–5×, and removes a noisy-neighbour bottleneck for analysts running heavy data preparation workloads. This benchmark quantifies the gain so you can justify the migration and set expectations with users.

---

## License

Use freely for internal benchmarking. No warranty — verify results in your own environment before making infrastructure decisions based on them.
