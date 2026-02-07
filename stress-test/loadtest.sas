/* loadtest.sas (small) : run a simple proc on sashelp.cars, then sleep 20 mins */
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