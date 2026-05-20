# Parallel RSUBMIT Job Tracker

A SAS utility that runs multiple jobs **in parallel** across separate SAS/CONNECT sessions, captures each job's return code, and produces a color-coded status report showing which jobs succeeded, which failed, and how long they took.

## What it does

1. Signs off any existing remote sessions to start clean.
2. Spawns three independent SAS sessions (`sess1`, `sess2`, `sess3`) using `signon ... sascmd="!sascmd"`.
3. Submits a different SAS program to each session **asynchronously** (`rsubmit ... wait=no`), so they all execute concurrently rather than one after another.
4. Captures each session's return code (`&syscc`) back to the parent session via `%sysrput`.
5. Waits for all three sessions to finish with `waitfor _all_`.
6. Builds a tracking dataset (`work.job_tracker`) with session name, program, status, start/end times, and human-readable duration.
7. Renders a styled `PROC REPORT` with green rows for successful jobs and red rows for failures.

## The three sample jobs

| Session | Program                         | Expected outcome |
|---------|---------------------------------|------------------|
| sess1   | `PROC MEANS` on `sashelp.cars`  | Success |
| sess2   | `PROC FREQ` on `sashelp.cars1`  | **FAILED** (table doesn't exist — included intentionally to demonstrate failure handling) |
| sess3   | `PROC PRINT` on `sashelp.class` | Success |

The deliberate failure in `sess2` is what makes the color-coded report meaningful — it shows the tracker correctly detects and highlights failed jobs.

## Prerequisites

- SAS environment with **SAS/CONNECT** licensed and available.
- The `!sascmd` spawning method enabled (default on most SAS Viya and SAS 9 deployments where local MP CONNECT is permitted).
- HTML or ODS output destination active so the styled `PROC REPORT` renders with colors.

## How to run

Open the script in SAS Studio (or any SAS client) and submit the entire file in one go. Once the three sessions finish, you'll see:

- A log message showing the three return codes: `NOTE: rc1=0 rc2=<non-zero> rc3=0`
- A status report titled **"RSUBMIT Job Status Report"** with rows highlighted by outcome.

## How it works under the hood

### Asynchronous submission

```sas
signon sess1 sascmd="!sascmd";
rsubmit sess1 wait=no;
    /* SAS code here */
endrsubmit;
```

`wait=no` tells the parent session to fire-and-continue instead of blocking. By repeating this for `sess2` and `sess3` before calling `waitfor`, all three jobs run in parallel.

### Return code propagation

```sas
%sysrput rc1 = &syscc;
```

`&syscc` is the cumulative session condition code inside the remote session. `%sysrput` pushes the value back up to the parent as a macro variable, where it's later compared to `0` to decide Success vs FAILED.

### Synchronization

```sas
waitfor _all_ sess1 sess2 sess3;
```

This blocks until every named session has finished, ensuring the tracking dataset is built only after all return codes are available.

### Duration formatting

The script converts elapsed seconds into a friendly string:
- Under 60 seconds → `"42 sec"`
- 60 seconds or more → `"2 min 15 sec"`

> **Note:** All three jobs share the same `End_Time` (the moment `waitfor` released). Because the script uses `&endall` for every row, the duration reflects total wall-clock time from each session's start to the point everything finished, not each job's individual runtime. If you need per-job runtimes, capture an end timestamp inside each `rsubmit` block via `%sysrput`.

## Customizing

- **Add more sessions:** copy a `signon` / `rsubmit` block, increment the session name, add a new `&rcN` capture, and include it in `waitfor` and the tracker dataset.
- **Change the jobs:** replace the `proc means` / `proc freq` / `proc print` calls with your real workload.
- **Tweak colors:** edit the hex codes in the `compute Job_Status` block — `#FFE0E0`/`#CC0000` for failures, `#E0FFE0`/`#006400` for success.
- **Persist results:** replace `work.job_tracker` with a permanent libref to keep an audit trail across runs.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `ERROR: No logical assign for name !SASCMD` | MP CONNECT spawning not configured; check `SASCMD` option or use a different signon method (TCP, spawner, etc.). |
| All jobs show `FAILED` even when log looks fine | `&syscc` may be inheriting a non-zero value from earlier code; reset with `%let syscc=0;` inside each `rsubmit` block. |
| Report shows no colors | Output destination is LISTING; switch to HTML/ODS (`ods html;`). |
| `waitfor` hangs indefinitely | One of the remote sessions is stuck; check each session's log via `rget`. |

## License

Internal utility — adapt as needed.
