# SAS Viya Cluster Stress Test Guide

## Overview

This guide explains how to perform a stress test on a SAS Viya deployment running on Kubernetes. The test submits multiple concurrent batch jobs to the cluster using the `sas-viya` CLI from a Windows machine, allowing you to observe how the environment handles increasing workloads — including compute pod scaling, memory consumption, and scheduling behavior.

The stress test consists of two components:

1. **`loadtest.sas`** — A lightweight SAS program that runs basic analytics on `sashelp.cars` and then holds a compute session open for 20 minutes.
2. **`stress_test.bat`** — A Windows batch script that submits multiple instances of the SAS program as batch jobs via the `sas-viya` CLI.

---

## Prerequisites

- **SAS Viya CLI (`sas-viya`)** installed and authenticated on your Windows machine.
- **Batch plugin** enabled in the CLI (`sas-viya batch jobs list` should work).
- The SAS program (`.sas` file) must be accessible from the machine running the batch script.
- A valid compute context (default: `"default"`) configured in your SAS Viya environment.

---

## Component 1: The SAS Program (`loadtest.sas`)

This program acts as the workload unit. Each submitted job will:

1. Log the start time, hostname, user ID, and WORK library path.
2. Run `PROC MEANS` and `PROC FREQ` on `sashelp.cars` to simulate light analytical work.
3. Sleep for **20 minutes** (`1200` seconds) to keep the compute pod alive, simulating a long-running session.
4. Log the end time and terminate.

```sas
options fullstimer;

%let SLEEP_SEC = 1200;   /* 20 minutes */
%let TAG       = loadtest;

%put NOTE: [&TAG] START %sysfunc(datetime(), e8601dt19.) Host=&SYSHOSTNAME User=&SYSUSERID Work=%sysfunc(pathname(work));

proc means data=sashelp.cars n mean min max;
  var msrp horsepower weight;
run;

proc freq data=sashelp.cars;
  tables make*type / norow nocol nopercent;
run;

%put NOTE: [&TAG] Sleeping for &SLEEP_SEC seconds...;

data _null_;
  call sleep(&SLEEP_SEC, 1);
run;

%put NOTE: [&TAG] END   %sysfunc(datetime(), e8601dt19.) Host=&SYSHOSTNAME;
endsas;
```

### Tuning the SAS Program

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SLEEP_SEC` | `1200` | Duration (in seconds) the session stays alive. Increase to hold pods longer; decrease for quicker tests. |

> **Tip:** The `fullstimer` option provides detailed resource usage in the SAS log, which is helpful for analyzing memory and CPU consumption per session.

---

## Component 2: The Batch Script (`stress_test.bat`)

This Windows batch script automates submitting multiple batch jobs to SAS Viya using the `sas-viya batch jobs submit-pgm` command.

```bat
@echo off
setlocal enabledelayedexpansion

:: Enhanced SAS Viya Batch Job Stress Test
:: Usage: stress_test.bat <number_of_jobs> <sas_program_path> [delay_seconds]

if "%~1"=="" goto :usage
if "%~2"=="" goto :usage

set NUM_JOBS=%~1
set SAS_PROGRAM=%~2
set DELAY=%~3
if "%DELAY%"=="" set DELAY=0

:: Create log directory
set LOG_DIR=%TEMP%\sas_stress_test_%date:~-4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set LOG_DIR=%LOG_DIR: =0%
mkdir "%LOG_DIR%" 2>nul

echo ============================================
echo SAS Viya Batch Job Stress Test
echo ============================================
echo Jobs to submit: %NUM_JOBS%
echo SAS Program: %SAS_PROGRAM%
echo Delay between jobs: %DELAY% seconds
echo Log directory: %LOG_DIR%
echo Start Time: %date% %time%
echo ============================================
echo.

:: Submit jobs and capture output
for /l %%i in (1,1,%NUM_JOBS%) do (
    echo [%%i/%NUM_JOBS%] Submitting job at %time%...
    sas-viya batch jobs submit-pgm --context "default" --pgm-path "%SAS_PROGRAM%" > "%LOG_DIR%\job_%%i.log" 2>&1
    if !errorlevel!==0 (
        echo          Success - see job_%%i.log for details
    ) else (
        echo          Warning - check job_%%i.log for errors
    )

    :: Optional delay between submissions
    if %DELAY% gtr 0 (
        if %%i lss %NUM_JOBS% (
            timeout /t %DELAY% /nobreak >nul
        )
    )
)

echo.
echo ============================================
echo Submission Complete!
echo End Time: %date% %time%
echo ============================================
echo.
echo Logs saved to: %LOG_DIR%
echo.
echo Monitor jobs with: sas-viya batch jobs list
echo.
exit /b 0

:usage
echo Usage: %~nx0 ^<number_of_jobs^> ^<sas_program_path^> [delay_seconds]
echo.
echo Arguments:
echo   number_of_jobs    - How many batch jobs to submit
echo   sas_program_path  - Full path to your .sas file
echo   delay_seconds     - Optional delay between submissions (default: 0)
echo.
echo Examples:
echo   %~nx0 10 C:\code\stress_test.sas
echo   %~nx0 50 C:\code\stress_test.sas 2
exit /b 1
```

### Script Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `number_of_jobs` | Yes | Total number of batch jobs to submit. |
| `sas_program_path` | Yes | Full path to the `.sas` file on your local machine. |
| `delay_seconds` | No | Optional delay (in seconds) between each job submission. Defaults to `0`. |

### Log Output

All job submission logs are saved to a timestamped directory under `%TEMP%`. Each job gets its own log file (`job_1.log`, `job_2.log`, etc.) containing the CLI output from `sas-viya batch jobs submit-pgm`.

---

## How to Run the Stress Test

### Step 1: Save the SAS Program

Save the `loadtest.sas` code to a location on your machine, for example:

```
C:\code\loadtest.sas
```

### Step 2: Run the Batch Script

Open a command prompt (or Git Bash) and run:

```bat
:: Submit 10 jobs with no delay
stress_test.bat 10 C:\code\loadtest.sas

:: Submit 25 jobs with a 2-second delay between each
stress_test.bat 25 C:\code\loadtest.sas 2

:: Submit 50 jobs with a 5-second stagger
stress_test.bat 50 C:\code\loadtest.sas 5
```

### Step 3: Monitor the Cluster

While jobs are running, monitor the environment:

```bash
# List all batch jobs and their status
sas-viya batch jobs list

# Watch compute pods spinning up in Kubernetes
kubectl get pods -n <namespace> -w | grep "sas-compute"

# Check node resource utilization
kubectl top nodes

# Check pod-level resource consumption
kubectl top pods -n <namespace> | grep "sas-compute"
```

### Step 4: Review Results

After the test completes (or while it's running), review the logs:

```bat
:: Navigate to the log directory printed by the script
cd %TEMP%\sas_stress_test_<timestamp>

:: Check individual job logs
type job_1.log
type job_10.log
```

---

## What to Look For

During and after the test, observe the following to understand your cluster's capacity:

- **Pod scheduling** — How many compute pods can the cluster run concurrently before jobs start queuing or failing?
- **Node autoscaling** — If autoscaling is enabled, do new nodes spin up to handle the load? How long does it take?
- **Resource limits** — Are pods hitting CPU or memory limits? Check for `OOMKilled` events in Kubernetes.
- **Job failures** — Do any jobs fail to submit or error out? Check the individual log files.
- **Recovery** — After pods terminate (post-sleep), does the cluster return to its baseline state cleanly?

---

## Recommended Test Plan

| Test | Jobs | Delay | Purpose |
|------|------|-------|---------|
| Baseline | 5 | 0 | Verify the setup works end-to-end. |
| Moderate load | 15–20 | 2s | Observe pod scaling and resource usage under moderate concurrency. |
| High load | 40–50 | 0 | Find the breaking point — where jobs start failing or queuing. |
| Sustained load | 20 | 5s | Simulate a realistic steady stream of user sessions over time. |

---

## Notes

- The `sas-viya` CLI must be authenticated before running the script. Run `sas-viya auth login` if your token has expired.
- Adjust `SLEEP_SEC` in the SAS program based on how long you want sessions to persist. Shorter sleep times free up resources faster for subsequent test iterations.
- Use a dedicated compute context for stress testing if you want to isolate the load from production users.
