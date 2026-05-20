/*Check work space usage */
 
%put WORK path: %sysfunc(pathname(work));
filename wrkdir pipe "df -h %sysfunc(pathname(work))";
data _null_;
   infile wrkdir;
   input;
   put _infile_;
run;
 
/*
   Create a ~300 GB SAS dataset in SASWORK
   with periodic size reporting every 10 minutes
   and total runtime summary at the end
*/
 
%let nobs = 322122547;   /* ~300 GB at ~1000 bytes/obs */
%let report_interval = 600;  /* seconds between size reports (600 = 10 min) */
 
/* Capture WORK path and dataset file path as macro vars */
%let work_path = %sysfunc(pathname(work));
%let dsfile = &work_path/big_dataset.sas7bdat;
 
%put NOTE: ====================================================;
%put NOTE: WORK path  = &work_path;
%put NOTE: Target file = &dsfile;
%put NOTE: Target obs  = &nobs;
%put NOTE: Report every &report_interval seconds;
%put NOTE: ====================================================;
 
/* Capture overall start time in a macro var so we can use it after the step */
%let job_start = %sysfunc(datetime());
%put NOTE: Job started at %sysfunc(datetime(), datetime20.);
 
data work.big_dataset (compress=no);
   length
      char_var1 - char_var10 $100
   ;
   retain filler '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
   /* Tracking vars - retained but not output */
   retain _start_time _last_report _report_num 0;
   drop _start_time _last_report _report_num _now _elapsed
        _rc _fid _size_bytes _size_gb _pct _eta_sec _eta_min filler i;
   if _n_ = 1 then do;
      _start_time  = datetime();
      _last_report = _start_time;
      put "NOTE: ==== Dataset build started at " _start_time datetime20. " ====";
   end;
   do i = 1 to &nobs;
      char_var1  = filler;
      char_var2  = filler;
      char_var3  = filler;
      char_var4  = filler;
      char_var5  = filler;
      char_var6  = filler;
      char_var7  = filler;
      char_var8  = filler;
      char_var9  = filler;
      char_var10 = filler;
      output;
      /* Every 100,000 obs, check the clock (cheap check) */
      if mod(i, 100000) = 0 then do;
         _now = datetime();
         if (_now - _last_report) >= &report_interval then do;
            _report_num + 1;
            _elapsed = _now - _start_time;
            _pct = (i / &nobs) * 100;
            /* Get current file size on disk */
            _rc = filename('dsmon', "&dsfile");
            _fid = fopen('dsmon','I');
            if _fid > 0 then do;
               _size_bytes = input(finfo(_fid, 'File Size (bytes)'), best32.);
               _size_gb = _size_bytes / (1024**3);
               _rc = fclose(_fid);
            end;
            else _size_gb = .;
            _rc = filename('dsmon','');
            /* Estimate time remaining */
            if _pct > 0 then _eta_sec = (_elapsed / _pct) * (100 - _pct);
            _eta_min = _eta_sec / 60;
            put "NOTE: ---- Progress report #" _report_num " ----";
            put "NOTE:   Time         : " _now datetime20.;
            put "NOTE:   Elapsed (min): " _elapsed time8. " (" _elapsed comma12.0 " sec)";
            put "NOTE:   Obs written  : " i comma15.0 " of &nobs (" _pct 6.2 "%)";
            put "NOTE:   File size    : " _size_gb 10.3 " GB on disk";
            put "NOTE:   ETA remaining: " _eta_min 8.1 " minutes";
            put "NOTE: -----------------------------------";
            _last_report = _now;
         end;
      end;
   end;
   /* End-of-step report */
   _now = datetime();
   _elapsed = _now - _start_time;
   put "NOTE: ==== DATA step write phase complete ====";
   put "NOTE: DATA step elapsed: " _elapsed time8.;
run;
 
/* ===== FINAL SUMMARY ===== */
%let job_end = %sysfunc(datetime());
%let total_sec = %sysevalf(&job_end - &job_start);
 
data _null_;
   /* Get final file size */
   rc = filename('ds', "&dsfile");
   fid = fopen('ds','I');
   if fid > 0 then do;
      size_bytes = input(finfo(fid, 'File Size (bytes)'), best32.);
      size_gb = size_bytes / (1024**3);
      rc = fclose(fid);
   end;
   rc = filename('ds','');
   /* Total runtime breakdown */
   total_sec = &total_sec;
   hours   = floor(total_sec / 3600);
   minutes = floor(mod(total_sec, 3600) / 60);
   seconds = round(mod(total_sec, 60), 1);
   /* Throughput */
   if total_sec > 0 then do;
      gb_per_min = size_gb / (total_sec / 60);
      obs_per_sec = &nobs / total_sec;
   end;
   put " ";
   put "NOTE: ============================================================";
   put "NOTE: =============== FINAL RUNTIME SUMMARY ======================";
   put "NOTE: ============================================================";
   put "NOTE:   Start time     : %sysfunc(putn(&job_start, datetime20.))";
   put "NOTE:   End time       : %sysfunc(putn(&job_end,   datetime20.))";
   put "NOTE:   Total elapsed  : " hours z2. ":" minutes z2. ":" seconds z2.
       "  (" total_sec comma14.1 " seconds)";
   put "NOTE:   Total elapsed  : " total_sec time10. " (hh:mm:ss)";
   put " ";
   put "NOTE:   Observations   : &nobs";
   put "NOTE:   Final size     : " size_bytes comma24. " bytes";
   put "NOTE:   Final size     : " size_gb 12.3 " GB";
   put " ";
   put "NOTE:   Throughput     : " gb_per_min 10.2 " GB/min";
   put "NOTE:   Throughput     : " obs_per_sec comma12.0 " obs/sec";
   put "NOTE: ============================================================";
   put " ";
run;
 
proc contents data=work.big_dataset; run;