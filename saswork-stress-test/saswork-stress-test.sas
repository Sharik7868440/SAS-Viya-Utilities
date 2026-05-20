/*****************************************************************************
* Program  : saswork_stress_test.sas (FIXED - macro quoting corrected)
* Purpose  : Stress-test SASWORK by writing/reading/sorting/joining ~100 GB
*            of data and measuring I/O performance.
* Platform : SAS Viya 4 LTS 2025.09 (Compute Server / SPRE)
*****************************************************************************/
 
/*========================= USER PARAMETERS =================================*/
%let RUN_LABEL   = BEFORE;                     /* BEFORE or AFTER           */
%let METRICS_DIR = <location_to_save_files>; /* Persistent (NOT in WORK)  */
%let NUM_TABLES  = 10;                         /* Total tables to process   */
%let NUM_OBS     = 50000000;                   /* Obs per table             */
%let SAFETY_GB   = 50;                         /* Abort if free < this GB   */
/*===========================================================================*/
 
options fullstimer compress=no msglevel=i;
options nosource2;
 
/* Create persistent metrics directory if missing */
%macro ensure_dir(p);
    %if %sysfunc(fileexist(&p)) = 0 %then %do;
        %local parent leaf;
        %let leaf   = %scan(&p,-1,/);
        %let parent = %substr(&p,1,%length(&p)-%length(&leaf)-1);
        %let rc = %sysfunc(dcreate(&leaf,&parent));
    %end;
%mend;
%ensure_dir(&METRICS_DIR);
 
libname bench "&METRICS_DIR";
 
%let saswork_path = %sysfunc(pathname(work));
 
%put;
%put NOTE: ===============================================================;
%put NOTE: SASWORK STRESS TEST  -  run label: &RUN_LABEL;
%put NOTE: WORK is physically at: &saswork_path;
%put NOTE: Tables: &NUM_TABLES   Obs/table: &NUM_OBS;
%put NOTE: ===============================================================;
%put;
 
/* Pre-flight free-space check */
filename dfout pipe "df -B1 --output=avail '&saswork_path' 2>/dev/null | tail -n 1";
data _null_;
    infile dfout truncover;
    input avail_bytes : best32.;
    if not missing(avail_bytes) then do;
        avail_gb = avail_bytes / 1024**3;
        put "NOTE: Free space on WORK FS: " avail_gb 10.2 " GB";
        if avail_gb < &SAFETY_GB then do;
            put "ERROR: Free space below safety threshold &SAFETY_GB GB. Aborting.";
            abort cancel;
        end;
    end;
    else put "WARNING: Could not determine free space on WORK FS; proceeding anyway.";
run;
filename dfout clear;
 
/* ------------------------------------------------------------------------ *
*  START_TIMER / STOP_TIMER macros
*  Instead of wrapping code blocks inside a macro parameter (which causes
*  the macro-quoting problem), we just bracket each step with these calls.
* ------------------------------------------------------------------------ */
%global _t0;
%macro start_timer;
    %let _t0 = %sysfunc(datetime());
%mend;
 
%macro stop_timer(test_name=, table_idx=);
    %local t1 elapsed;
    %let t1 = %sysfunc(datetime());
    %let elapsed = %sysevalf(&t1 - &_t0);
 
    proc sql noprint;
        insert into work._timings
            set test_name = "&test_name",
                table_idx = &table_idx,
                elapsed_sec = &elapsed,
                ts = &t1;
    quit;
 
    %put NOTE: [TIMING] &test_name  table=&table_idx  elapsed=&elapsed sec;
%mend;
 
proc sql;
    create table work._timings (
        test_name   char(40),
        table_idx   num,
        elapsed_sec num,
        ts          num format=datetime20.
    );
quit;
 
%let bench_start = %sysfunc(datetime());
 
/* ------------------------------------------------------------------------ *
*  ROLLING TEST LOOP
*  Each table goes through: WRITE -> READ -> SORT -> JOIN -> DELETE
*  Peak concurrent on-disk size: ~25-35 GB (well under 200 GB).
* ------------------------------------------------------------------------ */
%macro run_rolling;
    %do i = 1 %to &NUM_TABLES;
 
        %put NOTE: ----- Table &i of &NUM_TABLES -----;
 
        /* --- WRITE --- */
        %start_timer;
        data work.big_&i;
            length id 8 grp 8 amt 8 qty 8 score 8
                   name $32 city $32 cat $16 status $8 note $64;
            do id = 1 to &NUM_OBS;
                grp    = mod(id, 1000);
                amt    = ranuni(12345) * 10000;
                qty    = int(ranuni(67890) * 500);
                score  = rannor(11111) * 50 + 500;
                name   = cats('CUST_', put(id, z10.));
                city   = cats('CITY_', put(mod(id, 5000), z5.));
                cat    = cats('CAT_',  put(mod(id, 50),  z3.));
                status = ifc(mod(id,7)=0, 'ACTIVE', 'INACT');
                note   = cats('Record-', put(id,z10.), '-payload-filler-text');
                output;
            end;
        run;
        %stop_timer(test_name=WRITE_DATA_STEP, table_idx=&i);
 
        /* --- READ (full sequential scan) --- */
        %start_timer;
        proc means data=work.big_&i noprint;
            var amt qty score;
            output out=work._stats (drop=_type_ _freq_)
                   mean=mean_amt mean_qty mean_score
                   sum=sum_amt  sum_qty  sum_score;
        run;
        %stop_timer(test_name=READ_PROC_MEANS, table_idx=&i);
 
        /* --- SORT --- */
        %start_timer;
        proc sort data=work.big_&i out=work.sorted_&i;
            by grp score;
        run;
        %stop_timer(test_name=SORT, table_idx=&i);
 
        /* Drop unsorted original to keep peak footprint bounded */
        proc datasets lib=work nolist nowarn;
            delete big_&i / memtype=data;
        quit;
 
        /* --- SQL JOIN (self-join filtered) --- */
        %start_timer;
        proc sql;
            create table work.joined_&i as
                select a.id, a.grp, a.amt, b.score as score_b, b.qty as qty_b
                from work.sorted_&i a
                inner join work.sorted_&i b
                    on a.id = b.id and a.grp = b.grp
                where a.grp < 200;
        quit;
        %stop_timer(test_name=SQL_JOIN, table_idx=&i);
 
        /* --- DELETE --- */
        %start_timer;
        proc datasets lib=work nolist nowarn;
            delete sorted_&i joined_&i _stats / memtype=data;
        quit;
        %stop_timer(test_name=DELETE, table_idx=&i);
 
    %end;
%mend;
%run_rolling;
 
%let bench_end = %sysfunc(datetime());
%let total_elapsed = %sysevalf(&bench_end - &bench_start);
 
/* Summarise and persist */
proc sql;
    create table work._summary as
        select  "&RUN_LABEL"            as run_label    length=10,
                "&saswork_path"         as work_path    length=256,
                test_name,
                count(*)                as n_iterations,
                sum(elapsed_sec)        as total_sec    format=10.2,
                mean(elapsed_sec)       as mean_sec     format=10.2,
                min(elapsed_sec)        as min_sec      format=10.2,
                max(elapsed_sec)        as max_sec      format=10.2,
&bench_start            as run_started  format=datetime20.,
&total_elapsed          as run_total_sec format=10.2
        from work._timings
        group by test_name
        order by test_name;
quit;
 
%macro persist_results;
    %if %sysfunc(exist(bench.results)) %then %do;
        data bench.results;
            set bench.results;
            where run_label ne "&RUN_LABEL";
        run;
        proc append base=bench.results data=work._summary force; run;
    %end;
    %else %do;
        data bench.results; set work._summary; run;
    %end;
 
    data work._timings_labeled;
        length run_label $10;
        set work._timings;
        run_label = "&RUN_LABEL";
    run;
 
    %if %sysfunc(exist(bench.timings)) %then %do;
        data bench.timings;
            set bench.timings;
            where run_label ne "&RUN_LABEL";
        run;
        proc append base=bench.timings data=work._timings_labeled force; run;
    %end;
    %else %do;
        data bench.timings; set work._timings_labeled; run;
    %end;
%mend;
%persist_results;
 
%put NOTE: STRESS TEST COMPLETE - &RUN_LABEL - Total: &total_elapsed sec;
 
proc print data=work._summary noobs;
    title "SASWORK Stress Test Summary - &RUN_LABEL";
    title2 "WORK path: &saswork_path";
run;
title;