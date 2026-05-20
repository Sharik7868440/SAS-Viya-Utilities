/* =====================================================================
   Load a small table into CAS and leave it there for inspection
   ===================================================================== */
 
cas check sessopts=(caslib=casuser timeout=600);
caslib _all_ assign;
 
/* Create a small in-memory table */
proc cas;
   dataStep.runCode / code="
      data casuser.healthcheck;
         length region $4 product $10;
         array regions{4} $4 _temporary_ ('NW','NE','SW','SE');
         array prods{5}   $10 _temporary_ ('Widget','Gadget','Gizmo','Sprocket','Flange');
         call streaminit(42);
         do i = 1 to 100000;
            region   = regions{ceil(rand('uniform')*4)};
            product  = prods{ceil(rand('uniform')*5)};
            amount   = round(rand('uniform')*1000, 0.01);
            quantity = ceil(rand('uniform')*100);
            output;
         end;
         drop i;
      run;
   ";
 
   /* Promote it so it's visible globally, not just to this session */
   table.promote /
      caslib="casuser",
      name="healthcheck",
      target="healthcheck",
      targetCaslib="casuser";
quit;
 
/* Show it's there */
proc cas;
   table.tableInfo / caslib="casuser";
quit;
 
 
/* Keep the session alive so you can see the table */
/* DO NOT run "cas check terminate;" — that's what drops the session */
 
 
 
/*Drop CAS Table*/
 
cas cleanup;
proc cas;
   table.dropTable /
      caslib="casuser",
      name="healthcheck",
      quiet=true;
quit;
cas cleanup terminate;