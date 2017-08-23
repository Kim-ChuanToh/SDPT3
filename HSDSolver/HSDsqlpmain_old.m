%%*****************************************************************************
%% HSDsqlp: solve an semidefinite-quadratic-linear program 
%%   by infeasible path-following method on the homogeneous self-dual model.
%%
%%  [obj,X,y,Z,info,runhist] = 
%%      HSDsqlp(blk,At,C,b,OPTIONS,X0,y0,Z0,kap0,tau0,theta0);
%%
%%  Input: blk: a cell array describing the block diagonal structure of SQL data.
%%          At: a cell array with At{p} = [svec(Ap1) ... svec(Apm)] 
%%         b,C: data for the SQL instance.
%%     OPTIONS: a structure that specifies parameters required in HSDsqlp.m,
%%              (if it is not given, the default in sqlparameters.m is used). 
%%
%%  (X0,y0,Z0): an initial iterate (if it is not given, the default is used).
%%  (kap0,tau0,theta0): initial parameters (if not given, the default is used).
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

  function [obj,X,y,Z,info,runhist] = ...
            HSDsqlpmain(blk,At,C,b,par,X0,y0,Z0,kap0,tau0,theta0);

%%                                      
%%-----------------------------------------
%% get parameters from the OPTIONS structure. 
%%-----------------------------------------
%%
   global spdensity  solve_ok  printlevel 
   global schurfun   schurfun_par 
%%
   randstate = rand('state');  randnstate = randn('state');
   rand('state',0);   randn('state',0);
%%
   matlabversion = par.matlabversion;
   vers          = par.vers;
   predcorr      = par.predcorr;
   gam           = par.gam; 
   expon         = par.expon;
   gaptol        = par.gaptol;
   inftol        = par.inftol;
   steptol       = par.steptol;
   maxit         = par.maxit;
   printlevel    = par.printlevel;
   stoplevel     = par.stoplevel;
   scale_data    = par.scale_data;
   spdensity     = par.spdensity;
   rmdepconstr   = par.rmdepconstr;
   cachesize     = par.cachesize; 
   smallblkdim   = par.smallblkdim;
   schurfun      = par.schurfun;
   schurfun_par  = par.schurfun_par;
   ublksize      = par.ublksize;
%%
   tstart = cputime; 
   X = X0; y = y0; Z = Z0; 
   for p = 1:size(blk,1)
      if strcmp(blk{p,1},'u'); Z{p} = zeros(blk{p,2},1); end
   end
%%
%%-----------------------------------------
%% convert unrestricted blk to linear blk. 
%%-----------------------------------------
%%
   ublkidx = zeros(size(blk,1),1); 
   Cpert = zeros(size(blk,1),1); Cnew = C; 
   perturb_C = 1;
   for p = 1:size(blk,1) 
      pblk = blk(p,:); 
      n = sum(pblk{2}); 
      tmp = max(1,norm(C{p},'fro'))/sqrt(n); 
      if strcmp(pblk{1},'u') 
         if (printlevel); fprintf(' *** convert ublk to linear blk'); end
         ublkidx(p) = 1; 
         n = 2*pblk{2}; 
         blk{p,1} = 'l'; blk{p,2} = n;
         if (perturb_C); Cpert(p) = 1e-2*tmp; end
         C{p}  = [C{p}; -C{p}];
         At{p} = [At{p}; -At{p}];
         Cnew{p} = C{p} + Cpert(p)*ones(n,1); 
         X{p}  = 1+rand(n,1); %% do not add a factor of n
         Z{p}  = 1+rand(n,1); %%
      elseif strcmp(pblk{1},'s') 
         if (perturb_C); Cpert(p) = 1e-3*tmp; end
         Cnew{p} = C{p} + Cpert(p)*speye(n); 
      else
         if (perturb_C); Cpert(p) = 1e-3*tmp; end
         Cnew{p} = C{p} + Cpert(p)*ones(n,1); 
      end
   end
%%
%%-----------------------------------------
%% check if the matrices Ak are 
%% linearly independent. 
%%-----------------------------------------
%%
   m0 = length(b); 
   [At,b,y,indeprows,depconstr,feasible,AAt] = ...
   checkdepconstr(blk,At,b,y,rmdepconstr);
   if (~feasible)
      msg = 'SQLP is not feasible'; 
      if (printlevel); fprintf('\n %s',msg); end
      return; 
   end
   par.depconstr = depconstr; 
%%
   normC = zeros(length(C),1); 
   for p = 1:length(C); normC(p) = max(max(abs(C{p}))); end
   normC = 1+max(normC); 
   normb = 1+max(abs(b)); 
   nn = ops(C,'getM'); 
   m = length(b); 
   if (nargin <= 8) | (isempty(kap0) | isempty(tau0) | isempty(theta0)) 
      if (max([ops(At,'norm'),ops(C,'norm'),norm(b)]) > 1e6)
         kap0 = 10*blktrace(blk,X,Z); 
      else
         kap0 = blktrace(blk,X,Z);  
      end
      tau0 = 1; theta0 = 1; 
   end
   kap = kap0; tau = tau0; theta = theta0; 
%%
   normX0 = ops(X0,'norm')/tau; normZ0 = ops(Z0,'norm')/tau; 
   bbar  = (tau*b-AXfun(blk,At,[],X))/theta;
   ZpATy = ops(Z,'+',Atyfun(blk,At,[],[],y)); 
   Cbar = ops(ops(ops(tau,'*',C),'-',ZpATy),'/',theta);
   gbar = (blktrace(blk,C,X)-b'*y+kap)/theta; 
   abar = (blktrace(blk,X,Z)+tau*kap)/theta;
   for p = 1:size(blk,1); 
      pblk = blk(p,:); 
      if strcmp(pblk{1},'s')
         At{p} = [At{p}, -svec(pblk,Cnew{p},1), svec(pblk,Cbar{p},1)]; 
      else
         At{p} = [At{p}, -Cnew{p}, Cbar{p}]; 
      end
   end
   Bmat = [sparse(m,m), -b, bbar; b', 0, gbar; -bbar', -gbar, 0];   
   em1 = zeros(m+2,1); em1(m+1) = 1;
   em2 = zeros(m+2,1); em2(m+2) = 1;
   par.Umat = [[b;0;0], [bbar;gbar;0], em1, em2];
   par.m = m;
   par.diagAAt = [full(diag(AAt)); 1; 1];
%%
%%-----------------------------------------
%% find the combined list of non-zero 
%% elements of Aj, j = 1:k, for each k. 
%%-----------------------------------------
%% 
   par.numcolAt = length(b)+2;
   [At,C,Cnew,X,Z,par.permA,par.invpermA,par.permZ] = ...
    HSDsortA(blk,At,C,Cnew,[b;0;0],X,Z);
   [par.isspA,par.nzlistA,par.nzlistAsum,par.isspAy,par.nzlistAy] = ...
    nzlist(blk,At,par); 
%%
%%-----------------------------------------
%% initialization
%%-----------------------------------------
%%
   y2 = [y; tau; theta]; 
   AX = AXfun(blk,At,par.permA,X); 
   rp = [zeros(m,1); kap; -abar] - AX - Bmat*y2;
   Rd = ops(Atyfun(blk,At,par.permA,par.isspAy,-y2),'-',Z);
   trXZ = blktrace(blk,X,Z); 
   mu  = (trXZ+kap*tau)/(nn+1);   
   obj = [blktrace(blk,C,X), b'*y]/tau;
   gap = trXZ/tau^2;  
   relgap = gap/(1+mean(abs(obj)));
   ZpATy = ops(Z,'+',Atyfun(blk,At,par.permA,par.isspAy,[y;0;0]));
   ZpATynorm = ops(ZpATy,'norm');
   prim_infeas = norm(b - AX(1:m)/tau)/normb;
   dual_infeas = ops(ops(C,'-',ops(ZpATy,'/',tau)),'norm')/normC;
   infeas = max(prim_infeas,dual_infeas); 
   pstep = 0; dstep = 0; pred_convg_rate = 1; corr_convg_rate = 1;
   prim_infeas_bad = 0;
   termcode  = -6; 
   msg = []; 
   runhist.pobj    = obj(1);
   runhist.dobj    = obj(2); 
   runhist.gap     = gap;
   runhist.relgap  = relgap;
   runhist.pinfeas = prim_infeas;
   runhist.dinfeas = dual_infeas;
   runhist.infeas  = infeas;  
   runhist.cputime = cputime-tstart; 
   runhist.step    = 0; 
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
      fprintf('   SDPT3: homogeneous self-dual path-following algorithms'); 
      fprintf('\n********************************************');
      fprintf('***********************\n');
      [hh,mm,ss] = mytime(ttime.preproc); 
      if (printlevel>=3)       
         fprintf(' version  predcorr  gam  expon\n');
         if (vers == 1); fprintf('   HKM '); elseif (vers == 2); fprintf('    NT '); end
         fprintf('     %1.0f      %4.3f   %1.0f\n',predcorr,gam,expon);
         fprintf('it  pstep dstep p_infeas d_infeas  gap')
         fprintf('     mean(obj)    cputime\n');
         fprintf('------------------------------------------------');
         fprintf('-------------------\n');
         fprintf('%2.0f  %4.3f %4.3f %2.1e %2.1e',0,0,0,prim_infeas,dual_infeas);
         fprintf('  %2.1e %- 7.6e  %s:%s:%s',gap,mean(obj),hh,mm,ss);
         fprintf(' %2.1e %2.1e %2.1e',kap,tau,theta); 
      end
   end
%%
%%---------------------------------------------------------------
%% start main loop
%%---------------------------------------------------------------
%%
   EE = ops(blk,'identity');
   normE = ops(EE,'norm'); Zpertold = 1; 
   [Xchol,indef(1)] = blkcholfun(blk,X); 
   [Zchol,indef(2)] = blkcholfun(blk,Z); 
   if any(indef)
      msg = 'Stop: X, Z are not both positive definite'; 
      if (printlevel); fprintf('\n  %s\n',msg); end
      info.termcode = -3;      
      info.msg1 = msg; 
      return;
   end 
%%
   breakyes = 0; dy = zeros(length(b),1); dtau = 0; dtheta = 0;  
   for iter = 1:maxit;  

       update_iter = 0; pred_slow = 0; corr_slow = 0; step_short = 0; 
       tstart = cputime;  
       time = zeros(1,11); 
       time(1) = cputime;
       par.tau = tau; 
       par.kap = kap; 
       par.theta = theta; 
       par.mu   = mu;
       par.iter = iter; 
       par.y    = y; 
       par.dy2  = [dy; dtau; dtheta]; 
       par.rp   = rp; 
       par.ZpATynorm = ZpATynorm; 
%%
%%--------------------------------------------------
%% perturb C associated with ublk
%%--------------------------------------------------
%%
       if (perturb_C) 
          Cpertold = Cpert; 
          for p = 1:size(blk,1) 
             pblk = blk(p,:); 
             n = sum(pblk{2}); 
             tmp = max(1,norm(C{p},'fro'))/sqrt(n);
             if (max(relgap,infeas) < 1e-6)
                if (norm(X{p},'fro') < 1e2); const=0.2; else; const=0.3; end 
                Cpert(p) = max(const*Cpert(p),1e-10*tmp);  
             elseif (max(relgap,infeas) < 1e-2) 
                if (norm(X{p},'fro') < 1e2); const=0.4; else; const=0.5; end 
                Cpert(p) = max(const*Cpert(p),1e-8*tmp); 
   	     else
	        Cpert(p) = max(0.9*Cpert(p),1e-6*tmp); 
             end
             Cpert = min(Cpert,Cpertold); 
             if (prim_infeas < min([0.1*dual_infeas, 1e-7*runhist.pinfeas(1)])) ...
      	        & (iter > 1 & dual_infeas > 0.8*runhist.dinfeas(iter-1) & relgap < 1e-4)
                Cpert(p) = 0.5*Cpert(p); 
             end
             if (dual_infeas < min([0.1*prim_infeas, 1e-7*runhist.dinfeas(1)])) ...
   	        & (iter > 1 & prim_infeas > 0.8*runhist.pinfeas(iter-1) & relgap < 1e-4)
                Cpert(p) = 0.5*Cpert(p);
             end
	     if (max(relgap,1e-2*infeas) < 1e-6 & relgap < 0.1*infeas) 
                Cpert(p) = 0.5*Cpert(p);
             end
             if (prim_infeas < min([1e-4*dual_infeas,1e-7]) & theta < 1e-6) ...
	        | (prim_infeas < 1e-4 & theta < 1e-10) 
                Cpert(p) = 0.1*Cpert(p); 0; 
             end
             if (dual_infeas < min([1e-4*prim_infeas,1e-7]) & theta < 1e-6) ...
	        | (dual_infeas < 1e-4 & theta < 1e-10) 
                Cpert(p) = 0.1*Cpert(p); 0; 
             end
             if strcmp(pblk{1},'s')
                Cnew{p} = C{p} + Cpert(p)*speye(n); 
                At{p}(:,par.invpermA(p,end-1)) = -svec(pblk,Cnew{p},1); 
             else
                Cnew{p} = C{p} + Cpert(p)*ones(n,1); 
                At{p}(:,par.invpermA(p,end-1)) = -Cnew{p}; 
             end
          end
          maxCpert(iter) = max(Cpert); 
          fprintf(' %2.1e',max(Cpert)); 
          if (iter > 10 & norm(diff(maxCpert([iter-3,iter]))) < 1e-13)
             Cpert = 0.5*Cpert; 
             maxCpert(iter) = max(Cpert); 
          end
          AX = AXfun(blk,At,par.permA,X); 
          rp = [zeros(m,1); kap; -abar] - AX - Bmat*y2;
          Rd = ops(Atyfun(blk,At,par.permA,par.isspAy,-y2),'-',Z);  
       end
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
           HSDHKMpred(blk,At,par,rp,Rd,sigmu,X,Z,invZchol);
       elseif (vers == 2);
          [par,dX,dy,dZ,coeff,L,hRd] = ...
           HSDNTpred(blk,At,par,rp,Rd,sigmu,X,Z,Zchol,invZchol);
       end
       if (solve_ok <= 0)
          msg = 'Stop: difficulty in computing predictor directions';
          if (printlevel); fprintf('\n  %s',msg); end
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
      kapstep = max( (par.dkap<0)*(-kap/(par.dkap-eps)), (par.dkap>=0)*1e6 ); 
      taustep = max( (par.dtau<0)*(-tau/(par.dtau-eps)), (par.dtau>=0)*1e6 ); 
      [Xstep,invXchol] = steplength(blk,X,dX,Xchol,invXchol); 
      time(3) = cputime; 
      Zstep = steplength(blk,Z,dZ,Zchol,invZchol); 
      time(4) = cputime;        
      pstep = min(1,gamused*min([Xstep,Zstep,kapstep,taustep]));
      dstep = pstep; 
      kappred = kap + pstep*par.dkap; 
      taupred = tau + pstep*par.dtau; 
      trXZpred = trXZ + pstep*blktrace(blk,dX,Z) + dstep*blktrace(blk,X,dZ) ...
                 + pstep*dstep*blktrace(blk,dX,dZ); 
      mupred  = (trXZpred + kappred*taupred)/(nn+1); 
      mupredhist(iter) = mupred; 
      ttime.pred_pstep = ttime.pred_pstep + time(3)-time(2);
      ttime.pred_dstep = ttime.pred_dstep + time(4)-time(3);  
%%
%%-----------------------------------------
%%  stopping criteria for predictor step.
%%-----------------------------------------
%%
      if (min(pstep,dstep) < steptol) & (stoplevel)
         msg = 'Stop: steps in predictor too short';
         if (printlevel) 
            fprintf('\n  %s',msg);
            fprintf(': pstep = %3.2e,  dstep = %3.2e',pstep,dstep);
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
         if (max(mu,infeas) < 1e-6) & (pred_slow) & (stoplevel)
            msg = 'Stop: lack of progress in predictor'; 
            if (printlevel) 
               fprintf('\n  %s',msg);
               fprintf(': mupred/mu = %3.2f, pred_convg_rate = %3.2f.',...
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
            [par,dX,dy,dZ] = HSDHKMcorr(blk,At,par,rp,Rd,sigmu,hRd,...
             dX,dZ,coeff,L,X,Z);
         elseif (vers == 2)
            [par,dX,dy,dZ] = HSDNTcorr(blk,At,par,rp,Rd,sigmu,hRd,...
             dX,dZ,coeff,L,X,Z); 
         end
         if (solve_ok <= 0)
            msg = 'Stop: difficulty in computing corrector directions'; 
            if (printlevel); fprintf('\n  %s',msg); end
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
         kapstep = max( (par.dkap<0)*(-kap/(par.dkap-eps)), (par.dkap>=0)*1e6 ); 
         taustep = max( (par.dtau<0)*(-tau/(par.dtau-eps)), (par.dtau>=0)*1e6 ); 
         Xstep = steplength(blk,X,dX,Xchol,invXchol);
         time(6) = cputime;
         Zstep = steplength(blk,Z,dZ,Zchol,invZchol);
         time(7) = cputime;
         pstep = min(1,gamused*min([Xstep,Zstep,kapstep,taustep]));
         dstep = pstep; 
         kapcorr = kap + pstep*par.dkap; 
         taucorr = tau + pstep*par.dtau; 
         trXZcorr = trXZ + pstep*blktrace(blk,dX,Z) + dstep*blktrace(blk,X,dZ)...
                    + pstep*dstep*blktrace(blk,dX,dZ); 
         mucorr = (trXZcorr+kapcorr*taucorr)/(nn+1);
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
	 if (max(mu,infeas) < 1e-6) & (iter > 10) & (stoplevel) ...
            & (corr_slow & mucorr/mu > 1.0) 
            msg = 'Stop: lack of progress in corrector'; 
   	    if (printlevel) 
               fprintf('\n  %s',msg);
               fprintf(': mucorr/mu = %3.2f, corr_convg_rate = %3.2f',...
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
         AdX = AXfun(blk,At,par.permA,dX);
         AXtmp = AX(1:m) + pstep*AdX(1:m); tautmp = par.tau+pstep*par.dtau; 
         prim_infeasnew = norm(b-AXtmp/tautmp)/normb;
         if any(indef)
            msg = 'Stop: X, Z not both positive definite';
            if (printlevel); fprintf('\n  %s',msg); end
   	    termcode = -3; 
            breakyes = 1;         
         elseif (prim_infeasnew > max([1e-8,relgap,10*infeas])) ... 
	    | (prim_infeasnew > max([1e-4,20*prim_infeas]) & (infeas < 1e-2)) ...
            | (prim_infeasnew > max([1e-6,3*prim_infeas,10*dual_infeas]) ...
            & max([relgap,dual_infeas]) < 1e-5)
            if (stoplevel) & (max(pstep,dstep)<=1) & (kap < 1e-3)
               msg = 'Stop: primal infeas has deteriorated too much'; 
               if (printlevel); fprintf('\n  %s, %2.1e',msg,prim_infeasnew); end
               termcode = -7; 
               breakyes = 1; 
            end
	 end
         if (~breakyes)
            X = ops(X,'+',dX,pstep);  
            y = y + dstep*dy;  Z = ops(Z,'+',dZ,dstep);
            theta = max(0, theta + pstep*par.dtheta); 
            kap = kap + pstep*par.dkap; 
            if (tau + pstep*par.dtau > theta)
               tau = tau + pstep*par.dtau; 
            end
         end
      end
%%
%%--------------------------------------------------
%% perturb Z: do this step before checking for break
%%--------------------------------------------------
      perturb_Z = 1;
      if (~breakyes) & (perturb_Z)
         trXZtmp = blktrace(blk,X,Z);
         trXE  = blktrace(blk,X,EE);
         Zpert = max(1e-12,0.2*min(relgap,prim_infeas)).*normC./normE;
         Zpert = min(Zpert,0.1*trXZtmp./trXE);
         Zpert = min([1,Zpert,1.5*Zpertold]); 
         if (infeas < 1e-2) 
            Z = ops(Z,'+',EE,Zpert); 
            [Zchol,indef(2)] = blkcholfun(blk,Z);
            if any(indef(2))
               msg = 'HSDsqlp stop: Z not positive definite';      
               if (printlevel); fprintf('\n  %s',msg); end
               termcode = -3;
               breakyes = 1; 
            end
         end
         Zpertold = Zpert;        
      end
%%
%%---------------------------------------------------------------
%% compute rp, Rd, infeasibities, etc.
%%---------------------------------------------------------------
%%
      y2 = [y; tau; theta]; 
      AX = AXfun(blk,At,par.permA,X); 
      rp = [zeros(m,1); kap; -abar] - AX - Bmat*y2;
      Rd = ops(Atyfun(blk,At,par.permA,par.isspAy,-y2),'-',Z);
      trXZ = blktrace(blk,X,Z); 
      mu  = (trXZ+kap*tau)/(nn+1); 
      obj = [blktrace(blk,C,X), b'*y]/tau;
      gap = trXZ/tau^2;  
      relgap = gap/(1+mean(abs(obj)));
      ZpATy = ops(Z,'+',Atyfun(blk,At,par.permA,par.isspAy,[y;0;0]));
      prim_infeas = norm(b-AX(1:m)/tau)/normb;
      dual_infeas = ops(ops(C,'-',ops(ZpATy,'/',tau)),'norm')/normC;
      infeas = max(prim_infeas,dual_infeas);
      runhist.pobj(iter+1)    = obj(1); 
      runhist.dobj(iter+1)    = obj(2); 
      runhist.gap(iter+1)     = gap;
      runhist.relgap(iter+1)  = relgap;
      runhist.pinfeas(iter+1) = prim_infeas;
      runhist.dinfeas(iter+1) = dual_infeas;
      runhist.infeas(iter+1)  = infeas;
      runhist.cputime(iter+1) = cputime-tstart; 
      runhist.step(iter+1)    = min(pstep,dstep); 
      time(10) = cputime;
      ttime.misc = ttime.misc + time(10)-time(9); 
      [hh,mm,ss] = mytime(sum(runhist.cputime)); 
      if (printlevel>=3)
         fprintf('\n%2.0f  %4.3f %4.3f',iter,pstep,dstep);
         fprintf(' %2.1e %2.1e  %2.1e',prim_infeas,dual_infeas,gap);
         fprintf(' %- 7.6e  %s:%s:%s',mean(obj),hh,mm,ss);
         fprintf(' %2.1e %2.1e %2.1e',kap,tau,theta); 
      end
%%
%%--------------------------------------------------
%% check convergence.
%%--------------------------------------------------
%%
      ZpATynorm = ops(ZpATy,'norm');
      if (obj(2) > 0); homRd = (ZpATynorm/tau)/obj(2);   else; homRd = inf; end
      if (obj(1) < 0); homrp = (norm(AX(1:m))/tau)/(-obj(1)); else; homrp = inf; end
      if (ops(X,'norm')/tau > 1e15*normX0 | ops(Z,'norm')/tau > 1e15*normZ0)
         termcode = 3;
         breakyes = 1; 
      end
      if (homRd < min(1e-6,1e-2*sqrt(max([infeas,relgap]*inftol)))) ...
         | (homRd < 10*tau & tau < 1e-7)
         termcode = 1;
         breakyes = 1;
      end
      if (homrp < min(1e-6,1e-2*sqrt(max([infeas,relgap]*inftol)))) ...
         | (homrp < 10*tau & tau < 1e-7)
         termcode = 2;
         breakyes = 1;
      end
      if (max(relgap,infeas) < gaptol)
         msg = sprintf('Stop: max(relative gap, infeasibilities) < %3.2e',gaptol);
         if (printlevel); fprintf('\n  %s',msg); end
         termcode = 0;
         breakyes = 1;
      end
      if (stoplevel)
         min_prim_infeas = min(runhist.pinfeas(1:iter)); 
         prim_infeas_bad = prim_infeas_bad + (prim_infeas > ...
            max(1e-10,5*min_prim_infeas) & (min_prim_infeas < 1e-2));
         if (mu < 1e-6)
            idx = [max(1,iter-1): iter];
         elseif (mu < 1e-3);
            idx = [max(1,iter-2): iter]; 
         else
            idx = [max(1,iter-3): iter];
         end
         idx2 = [max(1,iter-4): iter]; 
         gap_ratio2 = runhist.gap(idx2+1)./runhist.gap(idx2);
         gap_slowrate = min(0.8,max(0.6,2*mean(gap_ratio2)));
         gap_ratio = runhist.gap(idx+1)./runhist.gap(idx); 
         if (infeas < 1e-4 | prim_infeas_bad) & (relgap < 1e-3) ...
            & (iter > 5) & (prim_infeas > (1-pstep/2)*runhist.pinfeas(iter)) 
            gap_slow = all(gap_ratio > gap_slowrate) & (relgap < 1e-3);
            min_pinfeas = min(runhist.pinfeas); 
            const = 0.1;
            if (relgap < const*max(prim_infeas,dual_infeas)) ...
               & ((runhist.step(iter+1) < 0.5) | ...
                  (prim_infeas > 10*min_pinfeas & min_pinfeas < 1e-6)) ...
               & (dual_infeas > 0.8*runhist.dinfeas(iter) | (dual_infeas < 1e-2*gaptol))
               msg = 'Stop: relative gap < infeasibility'; 
               if (printlevel); fprintf('\n  %s',msg); end
               termcode = -1;
               breakyes = 1;           
            elseif (gap_slow) & (infeas > 0.8*runhist.infeas(iter)) ...
               & (theta < 1e-8)
               msg = 'Stop: progress is too slow'; 
               if (printlevel); fprintf('\n  %s',msg); end
               termcode = -5; 
               breakyes = 1;
            end  
         elseif (prim_infeas_bad) & (iter >50) & all(gap_ratio > gap_slowrate)
            msg = 'Stop: progress is bad';
            if (printlevel); fprintf('\n  %s',msg); end
            termcode = -5;
            breakyes = 1; 
         elseif (infeas < 1e-8) & (gap > 1.2*mean(runhist.gap(idx)))
            msg = 'Stop: progress is bad*'; 
            if (printlevel); fprintf('\n  %s',msg); end
            termcode = -5;
            breakyes = 1;  
         end
         if (max([relgap,infeas]) < 1e-3) & (iter > 10) ...
            & (runhist.pinfeas(iter+1) > 0.9*runhist.pinfeas(max(1,iter-5))) ...
            & (runhist.dinfeas(iter+1) > 0.9*runhist.dinfeas(max(1,iter-5)))
            msg = 'Stop: progress is bad**';
            if (printlevel); fprintf('\n  %s',msg); end
            termcode = -5;
            breakyes = 1;  
         end
         if (min(runhist.infeas) < 1e-4 | prim_infeas_bad) ...
            & (max(runhist.infeas) > 1e-4) & (iter > 5)
            relgap2 = abs(diff(obj))/(1+mean(abs(obj))); 
            if (relgap2 < 1e-3); 
               step_short = all(runhist.step([iter:iter+1]) < 0.1) ;
            elseif (relgap2 < 1) 
               idx = [max(1,iter-3): iter+1];
               step_short = all(runhist.step(idx) < 0.05); 
            else
               step_short = 0; 
            end
            if (step_short) 
               msg = 'Stop: steps too short consecutively'; 
               if (printlevel); fprintf('\n  %s',msg); end
               termcode = -5; 
               breakyes = 1;      
            end
         end
	 if (infeas > 100*max(1e-12,min(runhist.infeas)) & relgap < 1e-4)
            msg = 'Stop: infeas has deteriorated too much'; 
            if (printlevel); fprintf('\n  %s, %3.1e',msg,infeas); end
            X = ops(X,'-',dX,pstep);  
            y = y - dstep*dy;  Z = ops(Z,'-',dZ,dstep);  
            kap = kap - pstep*par.dkap; tau = tau - pstep*par.dtau; 
            theta = theta - pstep*par.dtheta; 
            prim_infeas = runhist.pinfeas(iter); dual_infeas = runhist.dinfeas(iter); 
            gap = runhist.gap(iter); relgap = runhist.relgap(iter); 
            obj = [runhist.pobj(iter), runhist.dobj(iter)];
            termcode = -7; 
            breakyes = 1; 
         end
         if (iter > 3 & iter < 20) & (max(runhist.step(max(1,iter-3):iter+1)) < 1e-3) ...
            & (infeas > 1) & (min(homrp,homRd) > 1000*inftol) 
            if (stoplevel >= 2)
               msg = 'Stop: steps too short consecutively'; 
               if (printlevel); fprintf('\n  %s',msg); end
               termcode = -5;
               breakyes = 1;              
            end
         end
      end
      if (breakyes > 0.5); break; end
   end
%%---------------------------------------------------------------
%% end of main loop
%%---------------------------------------------------------------
%%
   if (termcode == -6) 
      msg = 'Stop: maximum number of iterations reached'; 
      if (printlevel); fprintf('\n  %s',msg); end
   end
%%
%%---------------------------------------------------------------
%% produce infeasibility certificates if appropriate
%%---------------------------------------------------------------
%%
   X = ops(X,'/',tau); y = y/tau; Z = ops(Z,'/',tau); 
   if (iter >= 1) 
      param.obj         = obj;
      param.relgap      = relgap; 
      param.prim_infeas = prim_infeas;
      param.dual_infeas = dual_infeas;
      param.ZpATynorm   = ZpATynorm/tau;
      param.inftol      = inftol;
      param.m0          = m0;
      param.indeprows   = indeprows;
      param.termcode    = termcode;
      param.AX          = AX(1:m)/tau; 
      param.normX0      = normX0; 
      param.normZ0      = normZ0;
      param.printlevel  = printlevel; 
      [X,y,Z,resid,reldist,param,msg2] = ...
      HSDsqlpmisc(blk,At,C,b,X,y,Z,par.permZ,param); 
      termcode = param.termcode;
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
   info.relgap   = relgap;
   info.pinfeas  = prim_infeas;
   info.dinfeas  = dual_infeas;
   info.cputime  = sum(runhist.cputime); 
   info.resid    = resid; 
   info.reldist  = reldist; 
   info.normX    = ops(X,'norm'); 
   info.normy    = norm(y); 
   info.normZ    = ops(Z,'norm'); 
   info.normA    = ops(At,'norm'); 
   info.normb    = norm(b); 
   info.normC    = ops(C,'norm'); 
   info.msg1     = msg; 
   info.msg2     = msg2; 
%%
   sqlpsummary(info,ttime,[],printlevel);
   rand('state',randstate); 
%%*****************************************************************************
