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