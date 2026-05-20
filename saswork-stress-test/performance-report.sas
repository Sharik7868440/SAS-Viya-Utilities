/*****************************************************************************
* Program  : saswork_stress_report.sas  (FIXED v2)
* Purpose  : Build an HTML report comparing BEFORE vs AFTER SASWORK metrics.
*****************************************************************************/
 
%let METRICS_DIR = /data_unix/insight/insight/saswork-nvme-bench;
 
libname bench "&METRICS_DIR";
 
proc sql noprint;
    select count(distinct run_label) into :n_runs trimmed from bench.results;
    select distinct run_label into :run_list separated by ', ' from bench.results;
quit;
 
%put NOTE: Found &n_runs run(s): &run_list;
 
%if &n_runs lt 2 %then %do;
    %put ERROR: Need both BEFORE and AFTER runs. Found: &run_list;
%end;
 
/* Build comparison dataset */
proc sql;
    create table work.compare as
        select  b.test_name,
                b.total_sec   as before_total_sec   format=10.2,
                a.total_sec   as after_total_sec    format=10.2,
                b.mean_sec    as before_mean_sec    format=10.2,
                a.mean_sec    as after_mean_sec     format=10.2,
                (b.total_sec - a.total_sec)                       as diff_sec         format=10.2,
                ((b.total_sec - a.total_sec) / b.total_sec * 100) as improvement_pct  format=8.1,
                (b.total_sec / a.total_sec)                       as speedup_factor   format=6.2
        from        bench.results (where=(run_label='BEFORE')) b
        inner join  bench.results (where=(run_label='AFTER'))  a
            on b.test_name = a.test_name
        order by b.test_name;
quit;
 
/* Overall totals */
proc sql;
    create table work.overall as
        select  sum(before_total_sec)                                 as before_total format=10.2,
                sum(after_total_sec)                                  as after_total  format=10.2,
                (sum(before_total_sec) - sum(after_total_sec))        as diff_total   format=10.2,
                ((sum(before_total_sec) - sum(after_total_sec))
                    / sum(before_total_sec) * 100)                    as improvement  format=8.1,
                (sum(before_total_sec) / sum(after_total_sec))        as speedup      format=6.2
        from work.compare;
quit;
 
data _null_;
    set work.overall;
    call symputx('overall_before', put(before_total, 10.2));
    call symputx('overall_after',  put(after_total,  10.2));
    call symputx('overall_improvement', put(improvement, 8.1));
    call symputx('overall_speedup', put(speedup, 6.2));
run;
 
proc sql noprint;
    select distinct work_path into :work_before trimmed
        from bench.results where run_label='BEFORE';
    select distinct work_path into :work_after  trimmed
        from bench.results where run_label='AFTER';
quit;
 
/* Reshape to long form for grouped bar charts */
data work.compare_long;
    set work.compare;
    length run_label $10;
    run_label = 'BEFORE'; total_sec = before_total_sec; mean_sec = before_mean_sec; output;
    run_label = 'AFTER';  total_sec = after_total_sec;  mean_sec = after_mean_sec;  output;
    keep test_name run_label total_sec mean_sec;
run;
 
data work.overall_long;
    length run_label $10;
    run_label = 'BEFORE'; total_sec = &overall_before; output;
    run_label = 'AFTER';  total_sec = &overall_after;  output;
run;
 
/* Build the HTML report */
ods _all_ close;
ods graphics on / width=900px height=500px imagefmt=svg;
ods escapechar='^';
 
ods html5 path="&METRICS_DIR" (url=none)
         file="saswork_benchmark_report.html"
         style=htmlblue
         options(svg_mode='inline' bitmap_mode='inline');
 
title;
footnote;
 
ods text="^S={font_size=18pt font_weight=bold color=cx0B5394}
         SASWORK Storage Migration Benchmark Report";
ods text="^S={font_size=11pt color=cx666666}
         SAS Viya 4 LTS 2025.09  |  EBS root FS to NVMe RAID-0 /saswork";
ods text=" ";
 
/* Configuration table */
data work.config;
    length Setting $25 Value $200;
    Setting='BEFORE run WORK path'; Value="&work_before"; output;
    Setting='AFTER  run WORK path'; Value="&work_after";  output;
    Setting='Overall BEFORE total'; Value="&overall_before seconds"; output;
    Setting='Overall AFTER  total'; Value="&overall_after seconds";  output;
    Setting='Overall improvement';  Value="&overall_improvement %";  output;
    Setting='Overall speedup';      Value="&overall_speedup x faster"; output;
run;
 
proc report data=work.config nowd
            style(header)=[background=cx0B5394 color=white font_weight=bold]
            style(column)=[font_size=10pt];
    columns Setting Value;
    define Setting / display 'Setting' style(column)=[font_weight=bold background=cxE8F0FE];
    define Value   / display 'Value';
    title2 "Run Configuration";
run;
 
/* Headline - overall total elapsed */
proc sgplot data=work.overall_long noautolegend;
    title "Total Elapsed Time (all tests) - BEFORE vs AFTER";
    title2 "Lower is better";
    vbar run_label / response=total_sec
        datalabel datalabelattrs=(weight=bold size=14);
    yaxis label='Total elapsed (seconds)' grid;
    xaxis label='Run';
    styleattrs datacolors=(cxD32F2F cx388E3C);
run;
 
/* Per-test grouped bar chart */
proc sgplot data=work.compare_long;
    title "Total Elapsed by Test - BEFORE vs AFTER";
    title2 "Lower is better";
    vbar test_name / response=total_sec group=run_label groupdisplay=cluster
        datalabel datalabelattrs=(size=9);
    yaxis label='Total elapsed (seconds)' grid;
    xaxis label='Test' fitpolicy=rotate;
    keylegend / title='Run' location=outside position=bottom;
    styleattrs datacolors=(cxD32F2F cx388E3C);
run;
 
/* Improvement % */
proc sgplot data=work.compare;
    title "Improvement % by Test (AFTER vs BEFORE)";
    title2 "Higher is better - positive means AFTER was faster";
    vbar test_name / response=improvement_pct
        fillattrs=(color=cx388E3C)
        datalabel datalabelattrs=(weight=bold size=10);
    yaxis label='Improvement %' grid;
    xaxis label='Test' fitpolicy=rotate;
    refline 0 / axis=y lineattrs=(color=black thickness=1);
run;
 
/* Speedup factor */
proc sgplot data=work.compare;
    title "Speedup Factor by Test (BEFORE / AFTER)";
    title2 "Higher is better - 2.0 means twice as fast on NVMe";
    vbar test_name / response=speedup_factor
        fillattrs=(color=cx7B1FA2)
        datalabel datalabelattrs=(weight=bold size=10);
    yaxis label='Speedup (x)' grid;
    xaxis label='Test' fitpolicy=rotate;
    refline 1 / axis=y lineattrs=(color=red pattern=shortdash thickness=1)
        label='No change' labelloc=inside;
run;
 
/* Detailed comparison table */
ods text=" ";
ods text="^S={font_size=14pt font_weight=bold color=cx0B5394} Detailed Comparison Table";
 
proc report data=work.compare nowd
            style(header)=[background=cx0B5394 color=white font_weight=bold]
            style(column)=[font_size=10pt];
    columns test_name before_total_sec after_total_sec diff_sec improvement_pct speedup_factor;
    define test_name        / display 'Test'             style(column)=[font_weight=bold];
    define before_total_sec / display 'BEFORE (sec)'     format=10.2;
    define after_total_sec  / display 'AFTER (sec)'      format=10.2;
    define diff_sec         / display 'Saved (sec)'      format=10.2;
    define improvement_pct  / display 'Improvement %'    format=8.1
        style(column)=[background=cxE8F5E9 font_weight=bold];
    define speedup_factor   / display 'Speedup (x)'      format=6.2
        style(column)=[background=cxF3E5F5 font_weight=bold];
run;
 
/* Per-iteration variability */
/* ods text=" ";
ods text="^S={font_size=14pt font_weight=bold color=cx0B5394} Per-iteration Variability";
 
proc sgplot data=bench.timings;
    title "Elapsed Time Distribution by Test and Run";
    vbox elapsed_sec / category=test_name group=run_label groupdisplay=cluster;
    yaxis label='Elapsed per iteration (sec)' grid;
    xaxis label='Test' fitpolicy=rotate;
    keylegend / title='Run' location=outside position=bottom;
    styleattrs datacolors=(cxD32F2F cx388E3C);
run; */
 
ods html5 close;
ods listing;
 
%put NOTE: REPORT GENERATED: &METRICS_DIR/saswork_benchmark_report.html;