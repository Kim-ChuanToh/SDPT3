%%*****************************************************************************
%% sqlp: solve an semidefinite-quadratic-linear program 
%%       by infeasible path-following method. 
%%
%%  [obj,X,y,Z,info,runhist] = sqlp(blk,At,C,b,OPTIONS,X0,y0,Z0);
%%
%%  Input: blk: a cell array describing the block diagonal structure of SQL data.
%%          At: a cell array with At{p} = [svec(Ap1) ... svec(Apm)] 
%%         b,C: data for the SQL instance.
%%  (X0,y0,Z0): an initial iterate (if it is not given, the default is used).
%%     OPTIONS: a structure that specifies parameters required in sqlp.m,
%%              (if it is not given, the default in sqlparameters.m is used). 
%%
%%  Output: obj  = [<C,X> <b,y>].
%%          (X,y,Z): an approximately optimal solution or a primal or dual
%%                   infeasibility certificate. 
%%          info.termcode = termination-code  
%%          info.iter     = number of iterations
%%          info.obj      = [primal-obj, dual-obj]
%%          info.cputime  = total-time
%%          info.gap      = gap
%%          info.pinfeas  = primal_infeas
%%          info.dinfeas  = dual_infeas  
%%          runhist.pobj    = history of primal objective value. 
%%          runhist.dobj    = history of dual   objective value.
%%          runhist.gap     = history of <X,Z>. 
%%          runhist.pinfeas = history of primal infeasibility. 
%%          runhist.dinfeas = history of dual   infeasibility. 
%%          runhist.cputime = history of cputime spent.
%%----------------------------------------------------------------------------
%%  The OPTIONS structure specifies the required parameters: 
%%      vers  gam  predcorr  expon  gaptol  inftol  steptol  
%%      maxit  printlevel  ...
%%      (all have default values set in sqlparameters.m).
%%
%%*************************************************************************
%% SDPT3: version 3.1
%% Copyright (c) 1997 by
%% K.C. Toh, M.J. Todd, R.H. Tutuncu
%% Last Modified: 16 Sep 2004
%%*************************************************************************

  function [obj,X,y,Z,info,runhist] = sqlp(blk,At,C,b,OPTIONS,X0,y0,Z0);
%%                                      
%%-----------------------------------------
%% get parameters from the OPTIONS structure. 
%%-----------------------------------------
%%
   global matlabversion ispc_hp_ibm
   global spdensity  iter  solve_ok  switch2LU  depconstr
   global cachesize  smallblkdim  printlevel 
   global schurfun   schurfun_par permZ

   warning off; 
   matlabversion = sscanf(version,'%f');
   matlabversion = matlabversion(1);
   ispc_hp_ibm = strncmp(computer,'PC',2) | strncmp(computer,'HP',2) | ...
                 strncmp(computer,'IBM',3); 

   vers        = 1; 
   predcorr    = 1; 
   gam         = 0; 
   expon       = 1; 
   gaptol      = 1e-8;
   inftol      = 1e-8;
   steptol     = 1e-6;
   maxit       = 100;
   printlevel  = 3;
   stoplevel   = 1; 
   spdensity   = 0.4; 
   rmdepconstr = 0; 
   cachesize   = 256; 
   smallblkdim = 15; 
   schurfun     = cell(size(blk,1),1);
   schurfun_par = cell(size(blk,1),1); 
   if exist('OPTIONS')
      if isfield(OPTIONS,'vers');        vers     = OPTIONS.vers; end
      if isfield(OPTIONS,'predcorr');    predcorr = OPTIONS.predcorr; end 
      if isfield(OPTIONS,'gam');         gam      = OPTIONS.gam; end
      if isfield(OPTIONS,'expon');       expon    = OPTIONS.expon; end
      if isfield(OPTIONS,'gaptol');      gaptol   = OPTIONS.gaptol; end
      if isfield(OPTIONS,'inftol');      inftol   = OPTIONS.inftol; end
      if isfield(OPTIONS,'steptol');     steptol  = OPTIONS.steptol; end
      if isfield(OPTIONS,'maxit');       maxit    = OPTIONS.maxit; end
      if isfield(OPTIONS,'printlevel');  printlevel  = OPTIONS.printlevel; end 
      if isfield(OPTIONS,'stoplevel');   stoplevel   = OPTIONS.stoplevel; end 
      if isfield(OPTIONS,'spdensity');   spdensity   = OPTIONS.spdensity; end
      if isfield(OPTIONS,'rmdepconstr'); rmdepconstr = OPTIONS.rmdepconstr; end
      if isfield(OPTIONS,'cachesize');   cachesize   = OPTIONS.cachesize; end
      if isfield(OPTIONS,'smallblkdim'); smallblkdim = OPTIONS.smallblkdim; end
      if isfield(OPTIONS,'schurfun');    schurfun = OPTIONS.schurfun; end
      if isfield(OPTIONS,'schurfun_par'); schurfun_par = OPTIONS.schurfun_par; end
      if isempty(schurfun); schurfun = cell(size(blk,1),1); end
      if isempty(schurfun_par); schurfun_par = cell(size(blk,1),1); end
   end
%%
   if all(vers-[1 2]); error('*** vers must be 1 or 2 ***'); end; 
%%
%%-----------------------------------------
%% convert matrices to cell arrays. 
%%-----------------------------------------
%%
   if ~iscell(At); At = {At}; end;
   if ~iscell(C);  C = {C}; end;
   m = length(b);       
   if all(size(At) == [size(blk,1), m]); 
      convertyes = zeros(size(blk,1),1); 
      for p = 1:size(blk,1)
         if strcmp(blk{p,1},'s') & all(size(At{p,1}) == sum(blk{p,2}))
            convertyes(p) = 1;    
         end
      end
      if any(convertyes)
         if (printlevel); fprintf('\n sqlp: converting At into required format'); end
         At = svec(blk,At,ones(size(blk,1),1));
      end
   end 
   if (nargin <= 5) | (isempty(X0) | isempty(y0) | isempty(Z0)); 
      [X0,y0,Z0] = infeaspt(blk,At,C,b); 
   end
   X = X0; y = y0; Z = Z0;  
   if ~iscell(X);  X = {X}; end;
   if ~iscell(Z);  Z = {Z}; end;
%%
%%-----------------------------------------
%% validate SQLP data. 
%%-----------------------------------------
%%
   tstart = cputime; 
   [blk,At,C,b,dim,numblk,X,Z] = validate(blk,At,C,b,X,y,Z);
   if (printlevel>=2)
      fprintf('\n num. of constraints = %2.0d',length(b));      
      if dim(1); 
         fprintf('\n dim. of sdp    var  = %2.0d,',dim(1)); 
         fprintf('   num. of sdp  blk  = %2.0d',numblk(1)); 
      end
      if dim(2); 
         fprintf('\n dim. of socp   var  = %2.0d,',dim(2)); 
         fprintf('   num. of socp blk  = %2.0d',numblk(2)); 
      end
      if dim(3); fprintf('\n dim. of linear var  = %2.0d',dim(3)); end
      if dim(4); fprintf('\n dim. of free   var  = %2.0d',dim(4)); end
   end
   if (vers == 0); 
      if dim(1); vers = 1; else; vers = 2; end
   end
%%
%%-----------------------------------------
%% convert unrestricted blk to linear blk. 
%%-----------------------------------------
%%
   ublkidx = zeros(size(blk,1),1); 
   for p = 1:size(blk,1) 
       if strcmp(blk{p,1},'u') 
         ublkidx(p) = 1; 
         n = 2*blk{p,2}; 
         blk{p,1} = 'l'; 
         blk{p,2} = n;
         At{p} = [At{p}; -At{p}];       
         C{p} = [C{p}; -C{p}];
         b2 = 1 + abs(b');  
         normC = 1+norm(C{p});
         normA = 1+sqrt(sum(At{p}.*At{p}));
         %%X{p} = max(1,max(b2./normA)) *ones(n,1);
         %%Z{p} = max(1,max([normA,normC])/sqrt(n)) *ones(n,1);
         X{p} = n* ones(n,1); Z{p} = n* ones(n,1);
      end
   end
%%
%%-----------------------------------------
%% check if the matrices Ak are 
%% linearly independent. 
%%-----------------------------------------
%%
   m0 = length(b); 
   [At,b,y,indeprows,depconstr,feasible] = checkdepconstr(blk,At,b,y,rmdepconstr);
   if (~feasible)
      fprintf('\n sqlp: SQLP is not feasible'); return; 
   end
%%
%%-----------------------------------------
%% find the combined list of non-zero 
%% elements of Aj, j = 1:k, for each k. 
%%-----------------------------------------
%% 
   m = length(b); 
   [At,C,X,Z,par.permA,par.permZ] = sortA(blk,At,C,b,X,Z);
   [par.isspA,par.nzlistA,par.nzlistAsum,par.isspAy,par.nzlistAy] = nzlist(blk,At,m);
%%
%%-----------------------------------------
%% initialization
%%-----------------------------------------
%%
   [Xchol,indef(1)] = blkcholfun(blk,X); 
   [Zchol,indef(2)] = blkcholfun(blk,Z); 
   if any(indef)
      if (printlevel); fprintf('\n Stop: X, Z are not both positive definite'); end
      termcode = -3;
      return;
   end 
   normC = zeros(length(C),1); 
   for p = 1:length(C); normC(p) = max(max(abs(C{p}))); end
   normC = 1+max(normC); 
   normb = 1+max(abs(b)); 
   normX0 = 1+ops(X0,'norm'); normZ0 = 1+ops(Z0,'norm'); 
   E = cell(size(blk,1),1);
   for p = 1:size(blk,1)
      pblk = blk(p,:);
      if strcmp(pblk{1},'s')
         E{p} = speye(sum(pblk{2})); 
      elseif strcmp(pblk{1},'q')
         s = 1+[0,cumsum(pblk{2})]; len = length(pblk{2}); 
         tmp = zeros(sum(pblk{2}),1); tmp(s(1:len)) = ones(len,1); 
         E{p} = tmp; 
      elseif strcmp(pblk{1},'l')
         E{p} = ones(pblk{2},1);
      elseif strcmp(pblk{1},'u') 
         E{p} = zeros(pblk{2},1); 
      end
   end
   AE = AXfun(blk,At,par.permA,E); 
   AE = AE*norm(b)/(1+norm(AE)); E = ops(E,'*',ops(C,'norm')/(1+ops(E,'norm'))); 
   n = ops(C,'getM'); 
   trXZ = blktrace(blk,X,Z); 
   gap = trXZ; 
   mu  = trXZ/n;  
   ptau = 1e-4;
   dtau = 1e-4*ops(X,'norm');
   AX = AXfun(blk,At,par.permA,X);
   rp = b + ptau*AE - AX;
   ZpATy = ops(Z,'+',Atyfun(blk,At,par.permA,par.isspAy,y));
   ZpATynorm = ops(ZpATy,'norm');
   Rd = ops(ops(C,'+',E,dtau),'-',ZpATy);
   obj = [blktrace(blk,C,X), b'*y];
   rel_gap = gap/(1+sum(abs(obj)));
   prim_infeas = norm(b-AX)/normb;
   dual_infeas = ops(ops(C,'-',ZpATy),'norm')/normC;
   infeas_meas = max(prim_infeas,dual_infeas); 
   pstep = 0; dstep = 0; pred_convg_rate = 1; corr_convg_rate = 1;
   prim_infeas_bad = 0; 
   termcode  = -6; 
   runhist.pobj = obj(1);
   runhist.dobj = obj(2); 
   runhist.gap  = gap;
   runhist.relgap  = rel_gap;
   runhist.pinfeas = prim_infeas;
   runhist.dinfeas = dual_infeas;
   runhist.infeas  = infeas_meas;  
   runhist.step    = 0; 
   runhist.cputime = cputime-tstart; 
   ttime.preproc   = runhist.cputime; 
   ttime.pred = 0; ttime.pred_pstep = 0; ttime.pred_dstep = 0; 
   ttime.corr = 0; ttime.corr_pstep = 0; ttime.corr_dstep = 0; 
   ttime.pchol = 0; ttime.dchol = 0; ttime.misc = 0; 
%%
%%-----------------------------------------
%% display parameters, and initial info
%%-----------------------------------------
%%
   if (printlevel >= 2)
      fprintf('\n********************************************');
      fprintf('***********************\n');
      fprintf('   SDPT3: Infeasible path-following algorithms'); 
      fprintf('\n********************************************');
      fprintf('***********************\n');
      [hh,mm,ss] = mytimed(ttime.preproc); 
      if (printlevel>=3)       
         fprintf(' version  predcorr  gam  expon\n');
         if (vers == 1); fprintf('   HKM '); elseif (vers == 2); fprintf('    NT '); end
         fprintf('     %1.0f      %4.3f   %1.0f\n',predcorr,gam,expon);
         fprintf('\nit  pstep dstep p_infeas d_infeas  gap')
         fprintf('     mean(obj)    cputime\n');
         fprintf('------------------------------------------------');
         fprintf('-------------------\n');
         fprintf('%2.0f  %4.3f %4.3f %2.1e %2.1e',0,0,0,prim_infeas,dual_infeas);
         fprintf('  %2.1e %- 7.6e  %d:%d:%d',gap,mean(obj),hh,mm,ss);
      end
   end
%%
%%---------------------------------------------------------------
%% start main loop
%%---------------------------------------------------------------
%%
    param.printlevel  = printlevel;    
    param.gaptol      = gaptol; 
    param.inftol      = inftol;
    param.m0          = m0;
    param.indeprows   = indeprows;
    param.scale_data  = 0;
    param.normX0      = normX0; 
    param.normZ0      = normZ0; 
%%
   for iter = 1:maxit;  

       update_iter = 0; breakyes = 0; pred_slow = 0; corr_slow = 0; step_short = 0; 
       tstart = cputime;  
       time = zeros(1,11); 
       time(1) = cputime;
%%
%%---------------------------------------------------------------
%% predictor step.
%%---------------------------------------------------------------
%%
       if (predcorr)
          sigma = 0; 
       else 
          sigma = 1-0.9*min(pstep,dstep); 
          if (iter == 1); sigma = 0.5; end; 
       end
       sigmu = sigma*mu; 

       invXchol = cell(size(blk,1),1); 
       invZchol = ops(Zchol,'inv'); 
       if (vers == 1);
          [par,dX,dy,dZ,coeff,L,hRd] = ...
           HKMpred(blk,At,par,rp,Rd,sigmu,X,Z,invZchol);
       elseif (vers == 2);
          [par,dX,dy,dZ,coeff,L,hRd] = ...
           NTpred(blk,At,par,rp,Rd,sigmu,X,Z,Zchol,invZchol);
       end
       if (solve_ok <= 0)
          fprintf('\n Stop: difficulty in computing predictor directions');  
          runhist.cputime(iter+1) = cputime-tstart; 
          termcode = -4;
          break;
       end
       time(2) = cputime;
       ttime.pred = ttime.pred + time(2)-time(1);
%%
%%-----------------------------------------
%% step-lengths for predictor step
%%-----------------------------------------
%%
      if (gam == 0) 
         gamused = 0.9 + 0.09*min(pstep,dstep); 
      else
         gamused = gam;
      end 
      [Xstep,invXchol] = steplength(blk,X,dX,Xchol,invXchol); 
      time(3) = cputime; 
      if (Xstep > .99e12) & (blktrace(blk,C,dX) < -1e-3) & (prim_infeas < 1e-3)
         if (printlevel); fprintf('\n Predictor: dual seems infeasible.'); end
      end
      pstep = min(1,gamused*Xstep);
      Zstep = steplength(blk,Z,dZ,Zchol,invZchol); 
      time(4) = cputime;        
      if (Zstep > .99e12) & (b'*dy > 1e-3) & (dual_infeas < 1e-3)
         if (printlevel); fprintf('\n Predictor: primal seems infeasible.'); end
      end
      dstep = min(1,gamused*Zstep);
      trXZpred = trXZ + pstep*blktrace(blk,dX,Z) + dstep*blktrace(blk,X,dZ) ...
                 + pstep*dstep*blktrace(blk,dX,dZ); 
      gappred = trXZpred; 
      mupred  = trXZpred/n; 
      mupredhist(iter) = mupred; 
      ttime.pred_pstep = ttime.pred_pstep + time(3)-time(2);
      ttime.pred_dstep = ttime.pred_dstep + time(4)-time(3);  
%%
%%-----------------------------------------
%%  stopping criteria for predictor step.
%%-----------------------------------------
%%
      if (min(pstep,dstep) < steptol) & (stoplevel)
         if (printlevel) 
            fprintf('\n Stop: steps in predictor too short:');
            fprintf(' pstep = %3.2e,  dstep = %3.2e\n',pstep,dstep);
         end
         runhist.cputime(iter+1) = cputime-tstart; 
         termcode = -2; 
         breakyes = 1; 
      end
      if (iter >= 2) 
         idx = [max(2,iter-2) : iter];
         pred_slow = all(mupredhist(idx)./mupredhist(idx-1) > 0.4);
         idx = [max(2,iter-5) : iter];
         pred_convg_rate = mean(mupredhist(idx)./mupredhist(idx-1));
         pred_slow = pred_slow + (mupred/mu > 5*pred_convg_rate);
      end 
      if (~predcorr)
         if (max(mu,infeas_meas) < 1e-6) & (pred_slow) & (stoplevel)
            if (printlevel) 
               fprintf('\n  Stop: lack of progress in predictor:');
               fprintf(' mupred/mu = %3.2f, pred_convg_rate = %3.2f.',...
                         mupred/mu,pred_convg_rate);
            end
            runhist.cputime(iter+1) = cputime-tstart; 
            termcode = -1; 
            breakyes = 1;
         else 
            update_iter = 1; 
         end
      end
%%
%%---------------------------------------------------------------
%% corrector step.
%%---------------------------------------------------------------
%%
      if (predcorr) & (~breakyes)
         step_pred = min(pstep,dstep);
         if (mu > 1e-6)
            if (step_pred < 1/sqrt(3)); 
               expon_used = 1; 
            else
               expon_used = max(expon,3*step_pred^2); 
            end
         else 
            expon_used = max(1,min(expon,3*step_pred^2)); 
         end 
         sigma = min( 1, (mupred/mu)^expon_used );
         sigmu = sigma*mu; 
%%
         if (vers == 1)
            [dX,dy,dZ] = HKMcorr(blk,At,par,rp,Rd,sigmu,hRd,...
             dX,dZ,coeff,L,X,Z);
         elseif (vers == 2)
            [dX,dy,dZ] = NTcorr(blk,At,par,rp,Rd,sigmu,hRd,...
             dX,dZ,coeff,L,X,Z); 
         end
         if (solve_ok <= 0)
            fprintf('\n Stop: difficulty in computing corrector directions');
            runhist.cputime(iter+1) = cputime-tstart; 
            termcode = -4;
            break;
         end
         time(5) = cputime;
         ttime.corr = ttime.corr + time(5)-time(4);
%%
%%-----------------------------------
%% step-lengths for corrector step
%%-----------------------------------
%%
         if (gam == 0) 
            gamused = 0.9 + 0.09*min(pstep,dstep); 
         else
            gamused = gam;
         end            
         Xstep = steplength(blk,X,dX,Xchol,invXchol);
         time(6) = cputime;
         if (Xstep > .99e12) & (blktrace(blk,C,dX) < -1e-3) & (prim_infeas < 1e-3)
            pstep = Xstep;
            if (printlevel); fprintf('\n Corrector: dual seems infeasible.'); end
         else
            pstep = min(1,gamused*Xstep);
         end
         Zstep = steplength(blk,Z,dZ,Zchol,invZchol);
         time(7) = cputime;
         if (Zstep > .99e12) & (b'*dy > 1e-3) & (dual_infeas < 1e-3)
            dstep = Zstep;
            if (printlevel); fprintf('\n Corrector: primal seems infeasible.'); end
         else
            dstep = min(1,gamused*Zstep);
         end     
         trXZcorr = trXZ + pstep*blktrace(blk,dX,Z) + dstep*blktrace(blk,X,dZ)...
                    + pstep*dstep*blktrace(blk,dX,dZ); 
         gapcorr = trXZcorr;
         mucorr  = trXZcorr/n;
         ttime.corr_pstep = ttime.corr_pstep + time(6)-time(5);
         ttime.corr_dstep = ttime.corr_dstep + time(7)-time(6);
%%
%%-----------------------------------------
%%  stopping criteria for corrector step
%%-----------------------------------------
%%
         if (iter >= 2) 
            idx = [max(2,iter-2) : iter];
            corr_slow = all(runhist.gap(idx)./runhist.gap(idx-1) > 0.8); 
            idx = [max(2,iter-5) : iter];
            corr_convg_rate = mean(runhist.gap(idx)./runhist.gap(idx-1));
            corr_slow = corr_slow + (mucorr/mu > max(min(1,5*corr_convg_rate),0.8)); 
         end 
	 if (max(mu,infeas_meas) < 1e-6) & (iter > 10) & (corr_slow) & (stoplevel)
   	    if (printlevel) 
               fprintf('\n  Stop: lack of progress in corrector:');
               fprintf(' mucorr/mu = %3.2f, corr_convg_rate = %3.2f',...
                         mucorr/mu,corr_convg_rate); 
            end
            runhist.cputime(iter+1) = cputime-tstart; 
            termcode = -1; 
            breakyes = 1;
         else
            update_iter = 1;
         end
      end 
%%
%%---------------------------------------------------------------
%% udpate iterate
%%---------------------------------------------------------------
%%
      indef = [1 1]; 
      if (update_iter)
         for t = 1:5
            [Xchol,indef(1)] = blkcholfun(blk,ops(X,'+',dX,pstep)); time(8) = cputime;
            if (predcorr); ttime.pchol = ttime.pchol + time(8)-time(7); 
            else;          ttime.pchol = ttime.pchol + time(8)-time(4); 
            end 
            if (indef(1)); pstep = 0.8*pstep; else; break; end            
         end
	     if (t > 1); pstep = gamused*pstep; end
	     for t = 1:5
            [Zchol,indef(2)] = blkcholfun(blk,ops(Z,'+',dZ,dstep)); time(9) = cputime; 
            if (predcorr); ttime.dchol = ttime.dchol + time(9)-time(8); 
            else;          ttime.dchol = ttime.dchol + time(9)-time(4); 
            end 
            if (indef(2)); dstep = 0.8*dstep; else; break; end             
         end
	     if (t > 1); dstep = gamused*dstep; end
         AXtmp = AX + pstep*AXfun(blk,At,par.permA,dX);
         prim_infeasnew = norm(b-AXtmp)/normb;
         if any(indef)
            if (printlevel); fprintf('\n Stop: X, Z not both positive definite'); end
            termcode = -3;
            breakyes = 1;         
         elseif (prim_infeasnew > max([rel_gap,20*prim_infeas,1e-8])) ...  	    
	      | (prim_infeasnew > max([1e-4,20*prim_infeas]) & (switch2LU))
            if (stoplevel) & (max(pstep,dstep)<=1)
               if (printlevel)
                  fprintf('\n Stop: primal infeas has deteriorated too much, %2.1e',prim_infeasnew);
               end
               termcode = -7; 
               breakyes = 1; 
            end
         else
            X = ops(X,'+',dX,pstep);  
            y = y+dstep*dy;           
            Z = ops(Z,'+',dZ,dstep);
         end
      end
%%---------------------------------------------------------------
%% adjust linear blk arising from unrestricted blk
%%---------------------------------------------------------------
%%
      for p = 1:size(blk,1)
         if (ublkidx(p) == 1)
            len = blk{p,2}/2;
            alpha = 0.8;
            xtmp = min(X{p}([1:len]),X{p}(len+[1:len])); 
            X{p}([1:len]) = X{p}([1:len]) - alpha*xtmp;
            X{p}(len+[1:len]) = X{p}(len+[1:len]) - alpha*xtmp;
            if (mu < 1e-8)
               Z{p} = 0.5*mu./max(1,X{p});
	    else
               ztmp = min(1,max(Z{p}([1:len]),Z{p}(len+[1:len]))); 
               beta1 = xtmp'*(Z{p}([1:len])+Z{p}(len+[1:len]));
               beta2 = (X{p}([1:len])+X{p}(len+[1:len])-2*xtmp)'*ztmp;
               beta = max(0.1,min(beta1/beta2,0.5));
               Z{p}([1:len]) = Z{p}([1:len]) + beta*ztmp;
               Z{p}(len+[1:len]) = Z{p}(len+[1:len]) + beta*ztmp;
            end
         end
      end
%%
%%---------------------------------------------------------------
%% compute rp, Rd, infeasibities, etc.
%%---------------------------------------------------------------
%%
      trXZ = blktrace(blk,X,Z); 
      gap = trXZ;
      mu  = trXZ/n;
      AX  = AXfun(blk,At,par.permA,X);  
      ZpATy = ops(Z,'+',Atyfun(blk,At,par.permA,par.isspAy,y));
      ZpATynorm = ops(ZpATy,'norm');
      obj = [blktrace(blk,C,X),  b'*y]; 
      rel_gap = gap/(1+sum(abs(obj))); 
      prim_infeas  = norm(b-AX)/normb;
      dual_infeas = ops(ops(C,'-',ZpATy),'norm')/normC;
      infeas_meas = max(prim_infeas,dual_infeas); 
      if (max([prim_infeas,dual_infeas,rel_gap]) > 1e-4)
         beta = 1e-4;
      elseif (max([prim_infeas,dual_infeas,rel_gap]) > 1e-6)
         beta = 1e-6;
      else 
         beta = 1e-8; 
      end
      ptau = min([1e-4,beta*norm(y)/iter^4]); 
      dtau = min([1e-4,beta*ops(X,'norm')/(iter^4)]); 
      rp = b + ptau*AE -AX;
      Rd  = ops(ops(C,'+',E,dtau),'-',ZpATy); 
      if (obj(2) > 0); homRd = ZpATynorm/(obj(2)); else; homRd = inf; end
      if (obj(1) < 0); homrp = norm(AX)/(-obj(1)); else; homrp = inf; end
      runhist.pobj(iter+1) = obj(1); 
      runhist.dobj(iter+1) = obj(2); 
      runhist.gap(iter+1)  = gap;
      runhist.relgap(iter+1)  = rel_gap;
      runhist.pinfeas(iter+1) = prim_infeas;
      runhist.dinfeas(iter+1) = dual_infeas;
      runhist.infeas(iter+1)  = infeas_meas;
      runhist.step(iter+1)    = min(pstep,dstep); 
      runhist.cputime(iter+1) = cputime-tstart; 
      time(10) = cputime;
      ttime.misc = ttime.misc + time(10)-time(9); 

      [hh,mm,ss] = mytimed(sum(runhist.cputime)); 
      if (printlevel>=3)
         fprintf('\n%2.0f  %4.3f %4.3f',iter,pstep,dstep);
         fprintf(' %2.1e %2.1e  %2.1e',prim_infeas,dual_infeas,gap);
         fprintf(' %- 7.6e  %d:%d:%d',mean(obj),hh,mm,ss);
      end
%%
%%--------------------------------------------------
%% check convergence.
%%--------------------------------------------------
%%
      param.iter        = iter; 
      param.obj         = obj;
      param.rel_gap     = rel_gap; 
      param.gap         = gap; 
      param.mu          = mu; 
      param.prim_infeas = prim_infeas;
      param.dual_infeas = dual_infeas;      
      param.ZpATynorm   = ZpATynorm;
      param.homRd       = homRd; 
      param.homrp       = homrp; 
      param.AX          = AX; 
      param.ZpATynorm   = ZpATynorm;
      param.normX       = ops(X,'norm'); 
      param.normZ       = ops(Z,'norm'); 
      param.termcode    = termcode;
      param.stoplevel   = stoplevel; 
      param.prim_infeas_bad = prim_infeas_bad; 
      [termcode,breakyes,prim_infeas_bad,restart] = sqlpcheckconvg(param,runhist); 
      if (breakyes); break; end
   end
%%---------------------------------------------------------------
%% end of main loop
%%---------------------------------------------------------------
%%
%%---------------------------------------------------------------
%% produce infeasibility certificates if appropriate
%%---------------------------------------------------------------
%%
   if (iter >= 1) 
      param.termcode = termcode; 
      [X,y,Z,termcode,resid,reldist] = sqlpmisc(blk,At,C,b,X,y,Z,par.permZ,param); 
   end   
%%
%%---------------------------------------------------------------
%% recover unrestricted blk from linear blk
%%---------------------------------------------------------------
%% 
   for p = 1:size(blk,1)
      if (ublkidx(p) == 1)
         n = blk{p,2}/2; 
         X{p} = X{p}(1:n)-X{p}(n+[1:n]); 
         Z{p} = Z{p}(1:n); 
      end
   end
%%
%%---------------------------------------------------------------
%%  print summary
%%---------------------------------------------------------------
%%
   dimacs = [prim_infeas; 0; dual_infeas; 0];
   dimacs = [dimacs; [-diff(obj); gap]/(1+sum(abs(obj)))];
   info.dimacs   = dimacs; 
   info.termcode = termcode;
   info.iter     = iter; 
   info.obj      = obj; 
   info.gap      = gap; 
   info.relgap   = rel_gap;
   info.pinfeas  = prim_infeas;
   info.dinfeas  = dual_infeas;
   info.cputime  = sum(runhist.cputime); 
   info.resid    = resid;
   info.reldist  = reldist; 
   info.normX    =  ops(X,'norm'); 
   info.normy    = norm(y); 
   info.normZ    = ops(Z,'norm'); 
   info.normb    = norm(b); 
   info.normC    = ops(C,'norm'); 
   info.normA    = ops(At,'norm'); 
   sqlpsummary(info,ttime,[],printlevel);
%%*****************************************************************************
