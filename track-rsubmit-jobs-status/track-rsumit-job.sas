signoff _all_;
 
options msglevel=i;
 
%let start1 = %sysfunc(datetime());
 
signon sess1 sascmd="!sascmd";
 
rsubmit sess1 wait=no;
 
    proc means data=sashelp.cars; var msrp; run;
 
    %sysrput rc1 = &syscc;
 
endrsubmit;
 
%let start2 = %sysfunc(datetime());
 
signon sess2 sascmd="!sascmd";
 
rsubmit sess2 wait=no;
 
    proc freq data=sashelp.cars1; tables origin; run;  /* Wrong table to test */
 
    %sysrput rc2 = &syscc;
 
endrsubmit;
 
%let start3 = %sysfunc(datetime());
 
signon sess3 sascmd="!sascmd";
 
rsubmit sess3 wait=no;
 
    proc print data=sashelp.class; run;
 
    %sysrput rc3 = &syscc;
 
endrsubmit;
 
waitfor _all_ sess1 sess2 sess3;
 
%let endall = %sysfunc(datetime());
 
rget sess1;
 
rget sess2;
 
rget sess3;
 
signoff sess1;
 
signoff sess2;
 
signoff sess3;
 
%put NOTE: rc1=&rc1 rc2=&rc2 rc3=&rc3;
 
/* Build tracking table */
 
data work.job_tracker;
 
    length Session $10 SAS_Program $50 Job_Status $10 Duration $20;
 
    format Start_Time End_Time datetime20.;
 
    Session='sess1'; SAS_Program='PROC MEANS - sashelp.cars';
 
    Start_Time=&start1; End_Time=&endall;
 
    if &rc1 = 0 then Job_Status='Success'; else Job_Status='FAILED';
 
    output;
 
    Session='sess2'; SAS_Program='PROC FREQ - sashelp.cars1';
 
    Start_Time=&start2; End_Time=&endall;
 
    if &rc2 = 0 then Job_Status='Success'; else Job_Status='FAILED';
 
    output;
 
    Session='sess3'; SAS_Program='PROC PRINT - sashelp.class';
 
    Start_Time=&start3; End_Time=&endall;
 
    if &rc3 = 0 then Job_Status='Success'; else Job_Status='FAILED';
 
    output;
 
run;
 
/* Add duration */
 
data work.job_tracker;
 
    set work.job_tracker;
 
    dur_secs = intck('second', Start_Time, End_Time);
 
    if dur_secs >= 60 then
 
        Duration = catx(' ', put(int(dur_secs/60), best3.), 'min',
 
                             put(mod(dur_secs, 60), best2.), 'sec');
 
    else
 
        Duration = catx(' ', put(dur_secs, best4.), 'sec');
 
    drop dur_secs;
 
run;
 
/* Report */
 
title "RSUBMIT Job Status Report";
 
title2 "Generated: %sysfunc(datetime(), datetime20.)";
 
proc report data=work.job_tracker nowd
 
    style(header)=[background=#4472C4 color=white font_weight=bold];
 
    columns Session SAS_Program Job_Status Start_Time End_Time Duration;
 
    define Session     / display 'Session'     width=10;
 
    define SAS_Program / display 'SAS Program' width=40;
 
    define Job_Status  / display 'Status'      width=10;
 
    define Start_Time  / display 'Start Time'  width=22;
 
    define End_Time    / display 'End Time'    width=22;
 
    define Duration    / display 'Duration'    width=15;
 
    compute Job_Status;
 
        if Job_Status = 'FAILED' then
 
            call define(_row_, "style",
 
                "style=[background=#FFE0E0 font_weight=bold color=#CC0000]");
 
        else if Job_Status = 'Success' then
 
            call define(_row_, "style",
 
                "style=[background=#E0FFE0 color=#006400]");
 
    endcomp;
 
run;
 
title;