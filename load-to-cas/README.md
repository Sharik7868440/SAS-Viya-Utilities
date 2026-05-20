# CAS Health Check Utility

A simple SAS script that loads a sample table into **SAS Cloud Analytic Services (CAS)** and keeps it there for inspection. Useful for verifying that a CAS session is healthy, that the `casuser` caslib is writable, and that promoted tables are visible across sessions.

## What it does

1. Starts (or attaches to) a CAS session named `check` with a 600-second timeout.
2. Assigns all available caslibs so they're usable as SAS librefs.
3. Generates a synthetic in-memory table `healthcheck` in the `casuser` caslib with 100,000 rows of randomly generated sales-like data.
4. Promotes the table to global scope so other sessions/users can see it.
5. Lists the tables in `casuser` to confirm the table is loaded.
6. Provides a cleanup block (commented usage) to drop the table and terminate the session when you're done.

## Generated table schema

| Column   | Type      | Description                                    |
|----------|-----------|------------------------------------------------|
| region   | char(4)   | One of `NW`, `NE`, `SW`, `SE`                  |
| product  | char(10)  | One of `Widget`, `Gadget`, `Gizmo`, `Sprocket`, `Flange` |
| amount   | numeric   | Random value 0–1000, rounded to 2 decimals     |
| quantity | numeric   | Random integer 1–100                           |

Row count: **100,000**. Random seed is fixed at `42` so results are reproducible.

## Prerequisites

- SAS Viya environment with CAS available.
- An active user account with permission to write to the `casuser` caslib.
- SAS client (SAS Studio, Enterprise Guide, or batch) connected to the Viya server.

## How to run

Open the script in SAS Studio (or your preferred SAS client) and submit it. The script is divided into two logical sections:

### 1. Load & inspect

Run everything from the top down to the `table.tableInfo` block. After this completes, the `healthcheck` table will be loaded and promoted in CAS. You can browse it from any session connected to the same CAS server.

```sas
cas check sessopts=(caslib=casuser timeout=600);
caslib _all_ assign;
/* ... data generation and promote ... */
proc cas;
   table.tableInfo / caslib="casuser";
quit;
```

> **Do not** run `cas check terminate;` at this point — that drops the session and unloads non-promoted resources.

### 2. Cleanup (run separately when done)

When you're finished inspecting, run the cleanup block to drop the table and terminate the session:

```sas
cas cleanup;
proc cas;
   table.dropTable /
      caslib="casuser",
      name="healthcheck",
      quiet=true;
quit;
cas cleanup terminate;
```

## Notes

- The table is created via `dataStep.runCode` inside `proc cas`, so the DATA step executes **in CAS**, not on the SAS compute server.
- `table.promote` makes the table globally visible. Without it, the table would only exist for the session that created it.
- The `quiet=true` option on `dropTable` suppresses the error if the table doesn't exist — handy for re-running cleanup safely.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `ERROR: Connection refused` | CAS server not running or hostname/port misconfigured. |
| `ERROR: ... access denied ... casuser` | Account lacks write permission on the `casuser` caslib. |
| Table not visible from another session | `table.promote` was skipped — table is session-scoped only. |
| `ERROR: The action stopped due to errors` on re-run | Table already exists; drop it first or use `replace=true` on promote. |

## License

Internal utility — adapt as needed.
