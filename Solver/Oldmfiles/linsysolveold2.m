%%***************************************************************
%% linsysolve: solve linear system to get dy, and direction
%%             corresponding to unrestricted variables. 
%%
%% [xx,coeff,L,resnrm] = linsysolve(schur,UU,Afree,EE,rhs); 
%%
%% child functions: symqmr.m, mybicgstable.m, linsysolvefun.m
%%
%% SDPT3: version 3.1
%% Copyright (c) 1997 by
%% K.C. Toh, M.J. Todd, R.H. Tutuncu
%% Last Modified: 16 Sep 2004
%%***************************************************************
   
   function [xx,coeff,L,resnrm] = linsysolve(par,schur,UU,Afree,EE,rhs); 
   
    global solve_ok existspcholsymb exist_analytic_term
    global nnzmat nnzmatold matfct_options matfct_options_old use_LU
    global Lsymb msg diagR diagRold perturb_opt

    spdensity  = par.spdensity;
    printlevel = par.printlevel; 
    iter       = par.iter; 

    m = length(schur); 
    if (iter==1); 
       use_LU = 0; matfct_options_old = ''; 
       diagR = ones(m,1); perturb_opt = 1; 
    end
    if isempty(nnzmatold); nnzmatold = 0; end
    diagRold = diagR; 
%%
%% schur = schur + rho*diagschur + lam*AAt
%%
    diagschur = full(abs(diag(schur)));
    if (min(diagR) < 1e-6) & (max(diagR) > 1e-2); 
       perturb_opt = 2; 
    end
    if (perturb_opt == 2) & (iter > 10)
       pertdiag = min(1e-2,1e-15*max(1,diagschur)./max(1e-12,diagR)); 
       idx = find(diagschur < 1e-6); 
       if (norm(rhs(idx)) < 1e-6) & (max(diagschur) > 1e-2)
          pertdiag(idx) = 1e6*ones(length(idx),1);         
       end
       mexschurfun(schur,pertdiag); 
       if (printlevel); fprintf('*'); end
    else
       diagschur = max(0,full(diag(schur))); 
       minrho(1) = max(1e-15, 1e-6/3.0^iter); 
       minlam(1) = max(1e-10, 1e-4/2.0^iter); 
       minrho(2) = max(1e-04, 1/1.5^iter);
       rho = min(minrho(1),minrho(2)*(1+norm(rhs))/(1+norm(diagschur.*par.y)));
       lam = min(minlam(1),0.1*rho*norm(diagschur)/par.normAAt);
       if (exist_analytic_term); rho = 0; end
       mexschurfun(schur,rho*diagschur); 
       mexschurfun(schur,lam*par.AAt); 
       %%if (printlevel); fprintf(' %2.1e %2.1e ',rho,lam); end
    end
%%
%% assemble coefficient matrix
%% 
    len = size(Afree,2);
    if ~isempty(EE)
       EE(:,[1 2]) = len + EE(:,[1 2]); %% adjust for ublk
    end
    EE = [(1:len)' (1:len)' zeros(len,1); EE]; 
    if isempty(EE)
       coeff.mat22 = []; 
    else
       coeff.mat22 = spconvert(EE);
    end
    coeff.mat12 = [Afree, UU]; 
    coeff.mat11 = schur; %% important to use perturbed schur matrix
    ncolU = size(coeff.mat12,2); 
%%
%% pad rhs with zero vector
%% decide which solution methods to use
%%
    rhs = [rhs; zeros(m+ncolU-length(rhs),1)]; 
    if (ncolU > 300); use_LU = 1; end
%%
%% Cholesky factorization
%%
    L = []; resnrm = []; xx = inf*ones(m,1);
    if (~use_LU)
       solve_ok = 1;  solvesys = 1;    
       nnzmat = mexnnz(coeff.mat11);
       nnzmatdiff = (nnzmat ~= nnzmatold);     
       if (nnzmat > spdensity*m^2) | (m < 500) 
          matfct_options = 'chol';
       else
          if (par.matlabversion < 7.3)
             matfct_options = 'spchol'; 
	  else
             matfct_options = 'spcholmatlab'; 
          end
       end
       if (printlevel>2); fprintf(' %s',matfct_options); end 
       if strcmp(matfct_options,'chol')
          if issparse(schur); schur = full(schur); end;
          if (iter<=5); %% to fix strange anonmaly in Matlab
             mexschurfun(schur,1e-20,2); 
          end 
          L.matfct_options = 'chol';
          L.perm = [1:m];
          [L.R,indef] = chol(schur); 
          diagR = diag(L.R).^2; 
          %%semilogy(diagschur,'*'); hold on;
          %%semilogy(diagR,'or'); hold off; pause(0.1); 
          if (indef)
             diagR = diagRold; 
 	     solve_ok = -2; solvesys = 0;
             msg = 'linsysolve: Schur complement matrix not pos. def.'; 
             if (printlevel); fprintf('\n  %s',msg); end
          end
       elseif strcmp(matfct_options,'spcholmatlab')
          if ~issparse(schur); schur = sparse(schur); end;
          L.matfct_options = 'spcholmatlab'; 
          [L.R,indef,L.perm] = chol(schur,'vector'); 
          L.Rt = L.R';
          %%diagR(L.perm(1:length(L.R)),1) = diag(L.R).^2; 
          if (indef)
             diagR = diagRold; 
 	     solve_ok = -2; solvesys = 0;
             msg = 'linsysolve: Schur complement matrix not pos. def.'; 
             if (printlevel); fprintf('\n  %s',msg); end
          end
       elseif strcmp(matfct_options,'spchol')
          if ~issparse(schur), schur = sparse(schur); end;
          if (nnzmatdiff | ~strcmp(matfct_options,matfct_options_old))
             [Lsymb,flag] = symbcholfun(schur,par.cachesize);
             if (flag) 
                solve_ok = -2;  solvesys = 0;
                existspcholsymb = 0;
                msg = 'linsysolve: symbolic factorization fails'; 
                if (printlevel); fprintf('\n  %s',msg); end
                use_LU = 1; 
             else 
                existspcholsymb = 1;
             end
          end 
          if (existspcholsymb)
             L = sparcholfun(Lsymb,schur);
             L.matfct_options  = 'spchol';  
             L.d(find(L.skip)) = 1e20;  
             if any(L.skip) & (ncolU)
                solve_ok = -3; solvesys = 0; 
                existspcholsymb = 0; 
                use_LU = 1; 
                if (printlevel)
                   fprintf('\n  L.skip exists but ncolU > 0.'); 
                   fprintf('\n  switch to LU factor.');
                end
             end          
          end
       end    
       if (solvesys)
          if (ncolU)
             tmp = coeff.mat12'*linsysolvefun(L,coeff.mat12)-coeff.mat22; 
	     if issparse(tmp); tmp = full(tmp); end
             tmp = 0.5*(tmp + tmp'); 
             [L.Ml,L.Mu,L.Mp] = lu(tmp);
             tol = 1e-16; 
             idx = find(abs(diag(L.Mu)) < tol);
             if ~isempty(idx) & (printlevel); fprintf('**'); end
          end
          [xx,resnrm,solve_ok] = symqmr(coeff,rhs,L);
          if (solve_ok<=0) & (printlevel)
             fprintf('\n  warning: symqmr fails: %3.1f.',solve_ok); 
          end
       end
       if (solve_ok < 0) 
          if (m < 5000 & strcmp(matfct_options,'chol')) | ...
             (m < 1e5 & strcmp(matfct_options,'spchol')) | ...
             (m < 1e5 & strcmp(matfct_options,'spcholmatlab'))
             use_LU = 1;
             if (printlevel); fprintf('\n  switch to LU factor.'); end
          end
       end
    end
%%
%% LU factorization
%%
    if (use_LU)
       nnzmat = mexnnz(coeff.mat11)+mexnnz(coeff.mat12); 
       nnzmatdiff = (nnzmat ~= nnzmatold);  
       solve_ok = 1; solvesys = 1; 
       if ~isempty(coeff.mat22)
          raugmat = [coeff.mat11, coeff.mat12; coeff.mat12', coeff.mat22]; 
       else
          raugmat = coeff.mat11; 
       end
       if (nnzmat > spdensity*m^2) | (m+ncolU < 500) 
          matfct_options = 'lu';     
       else
          matfct_options = 'splu';
       end
       if (printlevel > 2); fprintf(' %s ',matfct_options); end 
       if strcmp(matfct_options,'lu') 
          if issparse(raugmat); raugmat = full(raugmat); end
          [L.l,L.u,L.p] = lu(raugmat); 
          L.matfct_options = 'lu'; 
          L.p = sparse(L.p); 
          idx = find(abs(diag(L.u)) < 1e-20); 
          if ~isempty(idx)
             msg = 'linsysolve: matrix is singular'; 
             if (printlevel); fprintf('\n  %s',msg); end
             solvesys = 0; 
          end
          [ii,jj] = find(L.p); [dummy,idx] = sort(ii); L.perm = jj(idx); 
       end
       if strcmp(matfct_options,'splu') 
          if ~issparse(raugmat); raugmat = sparse(raugmat); end  
          if (nnzmatdiff | ~strcmp(matfct_options,matfct_options_old))
             Lsymb.perm = symamd(raugmat);
          end 
          L.perm = Lsymb.perm;     
          L.matfct_options = 'splu';  
          if (par.matlabversion >= 6.5)
             [L.l,L.u,L.p,L.q] = lu(raugmat(L.perm,L.perm));
          else
             [L.l,L.u,L.p] = lu(raugmat(L.perm,L.perm));
             L.q = speye(length(raugmat)); 
          end
       end
       if (solvesys)
          [xx,resnrm,solve_ok] = mybicgstab(coeff,rhs,L,[],[],printlevel);
          if (solve_ok<=0) & (printlevel)
             fprintf('\n  warning: bicgstab fails: %3.1f,',solve_ok); 
          end
       end
    end
    if (printlevel>=3); fprintf(' %2.0d',length(resnrm)-1); end
%%
    nnzmatold = nnzmat; matfct_options_old = matfct_options; 
%%***************************************************************
