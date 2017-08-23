## SDPT3 version 4.0 -- a MATLAB software for semidefinite-quadratic-linear programming

### [Kim-Chuan Toh](www.math.nus.edu.sg/~mattohkc/index.html), [ Michael J. Todd](https://people.orie.cornell.edu/miketodd/todd.html),  [Reha H. Tutuncu](http://www.math.cmu.edu/users/reha/home.html)

The last major update on the software was in <font color = blue>Feb 2009</font>. It implemented an infeasible path-following algorithm (sqlp.m) for solving SQLP -- conic optimization problems involving semidefinite, second-order and linear cone constraints. It also has a path-following algorithm (HSDsqlp.m) for solving a 3-parameter homogeneous self-dual reformulation of SQLP. <font color=red>Note: though this software is fairly well tested, but minor refinement or fix may still be needed from time to time.</font>

<font color=blue>New features that SDPT3 can now handle:</font>

- free variables;
- determinant maximization problems; 
- SDP with complex data; 
- Matlab 7.3 on 64-bit machine; 
- 3-parameter homogeneous self-dual model of SQLP (in HSDsqlp.m); 

### Citation

- **K.C. Toh, M.J. Todd, and R.H. Tutuncu**, SDPT3 --- a Matlab software package for semidefinite programming, Optimization Methods and Software, 11 (1999), pp. 545--581. 
- **R.H Tutuncu, K.C. Toh, and M.J. Todd**, Solving semidefinite-quadratic-linear programs using SDPT3, Mathematical Programming Ser. B, 95 (2003), pp. 189--217. 

------

- **Copyright**:  This version of SDPT3 is distributed under the **GNU General Public License 2.0**. For commercial applications that may be incompatible with this license, please contact the authors to discuss alternatives. 
- <font color=blue>SDPT3 is currently used as one of the main computational engines in optimization modeling languages such as</font> [CVX](http://cvxr.com/cvx/) <font color=blue>and</font> [YALMIP](https://yalmip.github.io/) .

-----

- <font color=red>Please read.</font>. <font color=blue> Welcome to SDPT3-4.0! The software is built for MATLAB version 7.4 or later releases, it may not work for earlier versions</font>. The software requires a few Mex files for execution. You can generate the Mex files as follows: 

  - Firstly, clone the package via
    ```github
    git clone (The URL pending)
    ```
  - Run Matlab in the directory SDPT3-4.0 
  - In Matlab command window, type: 
    ```matlab
    >>installmex(1)
    ```
  - After that, to see whether you have installed SDPT3 correctly, type: 
    ```matlab
    >> startup
    >> sqlpdemo
    ```
  - <font color=blue>By now, SDPT3 is ready for you to use</font>.

- **User's guide**([PDF](http://www.math.nus.edu.sg/~mattohkc/sdpt3/guide4-0-draft.pdf))(Draft)

-----

- The following example shows how SDPT3 call a data file that is stored in **SDPA format**:
  ```matlab
  >> [blk,At,C,b] = read_sdpa('/sdplib/theta3.dat-s'); 
  >> [obj,X,y,Z] = sdpt3(blk,At,C,b); 
  ```

  The following example shows how SDPT3 call a data file that is stored in **SeDuMi format**:
  ```matlab
  >> [blk,At,C,b] = read_sedumi(AA,bb,cc,K); or [blk,At,C,b] = read_sedumi('/dimacs/hamming_7_5_6.mat');
  >> [obj,X,y,Z] = sdpt3(blk,At,C,b); 
  ```

- [Simple examples to illustrate the usage of the software](http://www.math.nus.edu.sg/~mattohkc/sdpt3/sdpexample.html)
- Special thanks go to [Hans Mittelmann](http://plato.la.asu.edu/)  for his effort in benchmarking several SDP software packages on the following [test problems](http://plato.asu.edu/sub/testcases.html):
  [benchmark](http://plato.asu.edu/ftp/sparse_sdp.html)on some large sparse SDPs;
  [benchmark](http://plato.asu.edu/ftp/sdp_free.html) on SDPs with free variables;

------

### Bugs corrected

- 2017/08/23: fixed a bug (reported by Johan Lofberg) due to mex-function incompatibility with MatlabR2016 
- 2017/05/06: fixed a bug reported by [Johan Lofberg](https://github.com/sqlp/sdpt3/issues/2)
- 2017/05/06: fixed mex-function incompatibility with MatlabR2016a 
- 2016/10/26: fixed mex-function incompatibility with MatlabR2015b 

### Acknowledgements

We thank those who had made suggestions and reported bugs to make SDPT3 better. In particular, we thank **Johan Lofberg** for bug reports while incorporating SDPT3 into YALMIP. Thanks also go to **Michael Grant** for bug reports while testing SDPT3 as an engine for CVX. 





