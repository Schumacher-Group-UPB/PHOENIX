clear;    
%--------------------------------Misc---------------------------------%
optimizer = 0;        %find the exceptional point using a optimizer algorythm

%--------------------------------time evolution settings---------------------------------%
dt=0.02;
tmax=1500;
lambda_min=2;
lambda_max=6;
FFT_sample_rate=1;
sample_t0=500;

%----------------------------------system discretisation---------------------------------%
N=200;  dxy=0.1;  L=N*dxy;
x=sparse(dxy*(-N/2+1:N/2)).';
y=sparse(dxy*(-N/2+1:N/2)).';
kx=(2*pi*(-N/2+1:N/2)/L).';
ky=(2*pi*(-N/2+1:N/2)/L).';

%--------------------------------GP - parameter definition-------------------------------%
hbar = 6.582119569E-1;  
mc = 0.5*5.864E-1;      %effective polariton mass (0.5E-4*me)
gammaC = 0.16;          %polariton loss rate
gammaR = 1.5*gammaC;    %reservoir loss rate    
R = 0.01;               %condensation rate 
gc = 6E-3;              %polariton-polariton interaction strength
gr = 2*gc;              %polariton-reservoir interaction strength      

%----------------------------------shape external potential------------------------------%
V=zeros(N,N);
V1 = -2.2;              %potential depth 1
v1w=1.5;                %potential width 1
V2 = -2;                %potential depth 2
v2w=v1w;                %potential width 2
vpow=2;                 %potential well steepnes
dis=4;                  %potential well separation

P1 =12;                 %pump intensity 1
p1w=1.0;                %pump width 1
p2w=p1w;                %pump width 2

for i=1:N
    for j=1:N
        V(i,j) = V1*(exp(-((x(i)^2+(y(j)+dis/2)^2)/v1w^2)^vpow))+V2*(exp(-((x(i)^2+(y(j)-dis/2)^2)/v2w^2)^vpow));
    end
end

potential(1:N,1:N) = real(V);
potential(N+1:2*N,1:N) = imag(V);

%----- create 2D Hamiltonian with periodisc boundary conditions -----%
a=hbar^2/(2*mc)*4/(dxy)^2;
b=hbar^2/(2*mc)*(-1/(dxy)^2);
a1=sptoeplitz( [a b zeros(1,N-3) b],[a b zeros(1,N-3) b]);
b1=b*speye(N);
H=TriDiagonalMatrix(a1,b1,b1);
H(1:N,N^2-N+1:N^2)=b1;
H(N^2-N+1:N^2,1:N)=b1;
M=H+speye(N^2,N^2).*reshape(V,N^2,1);

%--- solve eigenvalue problem of H+V to generate intial condition ---%
[Evec,Eval]=eigs(M,12,'sa','Tolerance',1e-6);
psi=75*reshape(Evec(:,2),N,N);   n=zeros(N,N);

wavefunction(1:N,1:N) = real(psi);
wavefunction(N+1:2*N,1:N) = imag(psi);
reservoir(1:N,1:N) = real(n);
reservoir(N+1:2*N,1:N) = imag(n);

header = {'#' 'SIZE' num2str(N) num2str(N) num2str(L) num2str(L) num2str(dxy) num2str(dxy)};
writecell(header,'data/load/potential_plus.txt','Delimiter',' ');
writecell(header,'data/load/wavefunction_plus.txt','Delimiter',' ');
writecell(header,'data/load/reservoir_plus.txt','Delimiter',' ');

%writematrix(potential,'data/load/potential_plus.txt','Delimiter',' ','WriteMode','append');
writematrix(wavefunction,'data/load/wavefunction_plus.txt','Delimiter',' ','WriteMode','append');
writematrix(reservoir,'data/load/reservoir_plus.txt','Delimiter',' ','WriteMode','append');

integrated_densities=zeros(lambda_max-lambda_min+1,1);
pump_intensitys_scaned=zeros(lambda_max-lambda_min+1,1);
E1 = zeros(lambda_max-lambda_min+1,1);
E2 = zeros(lambda_max-lambda_min+1,1);

fileID = fopen('data/load/potential_plus.txt', 'a'); % Open the file in append mode
% Write the data with space delimiter
for row = 1:size(potential, 1)
    fprintf(fileID, '%.5f ', potential(row, :)); % Use %g for formatting
    fprintf(fileID, '\n'); % New line after each row
end
fclose(fileID); % Close the file

for lambda=lambda_min:lambda_max
    writecell(header,'data/load/pump_plus.txt','Delimiter',' ');
    P=zeros(N,N);
    P2 =lambda;  
    for i=1:N
        for j=1:N
            P(i,j) = P1*exp(-sqrt(x(i)^2+(y(j)+dis/2)^2)/p1w^2)+P2*exp(-sqrt(x(i)^2+(y(j)-dis/2)^2)/p2w^2);
        end
    end

    pump(1:N,1:N) = real(P);
    pump(N+1:2*N,1:N) = imag(P);

    writematrix(pump,'data/load/pump_plus.txt','Delimiter',' ','WriteMode','append')

    %-----------------------------------call-PHOENIX-------------------------------------------%
    str1 = 'phoenix_gpu_fp32.exe ';                                                                                                 
    str2 = ['--N ',num2str(N),' ',num2str(N),' --L ',num2str(L),' ',num2str(L),' --boundary periodic periodic '];
    str3 = ['--tmax ',num2str(tmax),' --tstep ',num2str(dt),' --outEvery 1 --fftMask 1.0 add 0.2 0.2 0 0 both 6 none gauss+noDivide+local --fftEvery ',num2str(dt),' '];  
    str4 = ['--historyMatrix 0 ',num2str(N),' 0 ',num2str(N),' 1 --output wavefunction --outEvery ',num2str(FFT_sample_rate),' ']; 
    str5 = '--potential load data/load/potential_plus.txt 1 add both --initialState load data/load/wavefunction_plus.txt 1 add both --pump load data/load/pump_plus.txt 1 add both ';                                                                            
    str6 = ['--gammaC ',num2str(gammaC),' --gammaR ',num2str(gammaR),' --gc ',num2str(gc),' --gr ',num2str(gr),' --meff ',num2str(mc),' --hbarscaled ',num2str(hbar),' --R ',num2str(R),' '];                            
    str7 = '--path data/results/'; 
    inputstr = [str1,str2,str3,str4,str5,str6,str7];
    [~,cmdout] = system(inputstr,'CUDA_VISIBLE_DEVICES','0');

    htmlString = removeAnsiCodes(cmdout);
    disp(htmlString(end-2630:end));    
    %----------------------------------post-processing---------------------------------------%

    psi = readmatrix('data/results/wavefunction_plus.txt');
    psi=psi(1:N,1:N)+1i*psi(N+1:2*N,1:N);
    Y1 = abs(reshape(psi,N,N)).^2;
    %integrated_densities(lambda+1,1)=max(max(Y1));
    pump_intensitys_scaned(lambda+1,1)=P2;

    projectdir = 'data/results/timeoutput/';
    dinfo = dir( fullfile(projectdir, '*.txt'));
    nfiles = length(dinfo);
    filenames = fullfile(projectdir, {dinfo.name});
    y1_centralcut_x_t = zeros(nfiles-sample_t0, N);
    y1sum=zeros(N,N);
    for K = 0 : nfiles-1-sample_t0
        thisfile = ['data/results/timeoutput/wavefunction_plus_',num2str(K+sample_t0),'.000000.txt'];
        thisdata = readmatrix(thisfile);
        %y1_centralcut_x_t(K+1, :) = thisdata(1,:)+1i*thisdata(2,:);
        y1_centralcut_x_t(K+1, :) = thisdata(N/2,:)+1i*thisdata(3*N/2,:);
        Y1 = abs(thisdata(1:N,:)+1i*thisdata(N+1:2*N,:)).^2;
        y1sum = y1sum + Y1;
    end
    [rows, columns]= size(y1_centralcut_x_t);
    W=2*pi*((-rows/2):(rows/2-1))/(FFT_sample_rate*rows);
    y1_iFFT = abs(fftshift(ifft((y1_centralcut_x_t),[],1),1));
    [Energy1, E_index1]=max(y1_iFFT(:,x==-dis/2),[],1);
    [Energy2, E_index2]=max(y1_iFFT(:,x==dis/2),[],1);

    if W(E_index1)*hbar < 0 && max(max(Y1)) > 1
        E1(lambda+1)=W(E_index1)*hbar;
    else
        E1(lambda+1)=NaN;
    end
    if W(E_index2)*hbar < 0 && max(max(Y1)) > 1
        E2(lambda+1)=W(E_index2)*hbar;
    else
        E2(lambda+1)=NaN;
    end
    integrated_densities(lambda+1)=max(max(y1sum));
end
E2(E2==E1)=NaN;

dim=[0.841333333333333,0.822916666666671,0.055333333333333,0.048333333333333];
x0=10; y0=10; width=1500; height=1100;
figure(3);
linecolors = copper(3);
hold on;
plot(pump_intensitys_scaned(:,1),integrated_densities(:,1)/max(integrated_densities),'linewidth',3,'color',linecolors(1,:),'marker','o','MarkerSize',8,'MarkerFaceColor',linecolors(1,:));
plot(pump_intensitys_scaned(:,1),E1(:,1)+1,'color',linecolors(2,:),'marker','^','MarkerSize',8,'MarkerFaceColor',linecolors(2,:),'linewidth',3);
plot(pump_intensitys_scaned(:,1),E2(:,1)+1,'color',linecolors(3,:),'marker','^','MarkerSize',8,'MarkerFaceColor',linecolors(3,:),'linewidth',3);
hold off;
set(gca,'linewidth',1);set(gca,'fontsize',15);pbaspect([1 1 1]);
set(gcf,'position',get(0, 'Screensize'));box on;set(gca,'linewidth',2);
set(gca,'XLim',[0 max(pump_intensitys_scaned)]);set(gca,'fontsize',24);
set(gcf,'position',[x0,y0,width,height]);

%----------------------------------Optimizer----------------------------------%
options = optimset('Display','iter','PlotFcns',@optimplotfval,'TolX',1E-1);
EP_loc = fminbnd(@costfunction,0,20,options);

%----------------------------------String handeling functions----------------------------------%
function cleanedString = removeAnsiCodes(inputString)
    % Use regexprep to remove ANSI escape codes
    cleanedString = strrep(inputString, '[90m#[0m', ' ');
    cleanedString = regexprep(cleanedString, '\[0m|\[1m|\[2m|\[3m|\[4m|\[30m|\[31m|\[32m|\[33m|\[34m|\[35m|\[36m|\[37m|[93m|\[94m|\[?25h|\[2K|\[?25l|\[90m|\[A', '');
end
%----------------------------------Matrix handeling functions----------------------------------%
function A = MatrixInsert(A,B,at)
[w,h] = size(B);
A(at(1):at(1)+w-1, at(2):at(2)+h-1) = B;
end
function ret = TriDiagonalMatrix(A,B,C,sp)
if nargin == 3
    sp = "full";
    if issparse(A)
        sp = "sparse";
    end
end
N = length(A);
if (2*N ~= length(B)+length(C))
    disp("Wrong matrix dimensions!"); return;
end
if (strcmp(sp,"sparse") == 1)
    fprintf("Creating %dx%d Sparsematrix... ",N^2,N^2);
    ret = sparse(N^2,N^2);
else if (strcmp(sp,"full") == 1)
        fprintf("Creating %dx%d Full-Matrix... ",N^2,N^2);
        ret = zeros(N^2,N^2);
    end
end
tic;
for i=1:N
    ret = MatrixInsert(ret,A,[N*(i-1)+1,N*(i-1)+1]);
    if i <= N-1
        ret = MatrixInsert(ret,B,[N*i+1,N*(i-1)+1]);
    end
    if i <= N-1
        ret = MatrixInsert(ret,C,[N*(i-1)+1,N*i+1]);
    end
end
toc;
end
function T = sptoeplitz(col,row)
if nargin < 2  % symmetric case
    col(1) = conj(col(1)); row = col; col = conj(col);
else
    if col(1)~=row(1)
        warning('MATLAB:sptoeplitz:DiagonalConflict',['First element of ' ...
            'input column does not match first element of input row. ' ...
            '\n         Column wins diagonal conflict.'])
    end
end
% Size of result.
m = length(col(:));  n = length(row(:));
% Locate the nonzero diagonals.
[ic,jc,sc] = find(col(:));
row(1) = 0;  % not used
[ir,jr,sr] = find(row(:));
% Use spdiags for construction.
d = [ ir-1; 1-ic ];
B = repmat( [ sr; sc ].', min(m,n),1 );
T = spdiags( B,d,m,n );
end

function cost = costfunction(X)
N=200;                  %grid size
dxy=0.1;                %spatial discretization step
L=N*dxy;                %real space grid length
x=sparse(dxy*(-N/2+1:N/2)).';   %x dimension discretization
y=sparse(dxy*(-N/2+1:N/2)).';   %y dimension discretization

dt=0.02;                %time-evolution step
tmax=2000;              %time-evolution range
FFT_sample_rate=1;      %sample rate for wave-profile (affects the frequency range covered during the FFT)
sample_t0=1500;          %off-set for FFT-sampling to ensure convergence of the system before the sampling

%-------------------------------GP - parameter definition-------------------------------%
mc = 0.5*5.864E-4;      %effective polariton mass (0.5E-4*me)
gammaC = 0.16;          %polariton loss rate
gammaR = 1.5*gammaC;    %reservoir loss rate
R = 0.01;               %condensation rate
gc = 6E-6;              %polariton-polariton interaction strength
gr = 2*gc;              %polariton-reservoir interaction strength

dis=4;                  %potential well separation
P1 =12;                 %pump intensity 1
p1w=1.0;                %pump width 1
p2w=p1w;                %pump width 2

pump = writepump(X,N,L,dxy,x,y,dis,P1,p1w,p2w);
delete('output\timeoutput\*.txt');
%-----------------------------------call-PHOENIX-------------------------------------------%
str1 = 'phoenix_gpu_fp32.exe ';                                                                                                 
str2 = ['--N ',num2str(N),' ',num2str(N),' --L ',num2str(L),' ',num2str(L),' --boundary periodic periodic '];
str3 = ['--tmax ',num2str(tmax),' --tstep ',num2str(dt),' --outEvery 1 --fftMask 1.0 add 0.2 0.2 0 0 both 6 none gauss+noDivide+local --fftEvery ',num2str(dt),' '];  
str4 = ['--historyMatrix 0 ',num2str(N),' 0 ',num2str(N),' 1 --output wavefunction --outEvery ',num2str(FFT_sample_rate),' ']; 
str5 = '--potential load data/load/potential_plus.txt 1 add both --initialState load data/load/wavefunction_plus.txt 1 add both --pump load data/load/pump_plus.txt 1 add both ';                                                                            
str6 = ['--gammaC ',num2str(gammaC),' --gammaR ',num2str(gammaR),' --gc ',num2str(gc),' --gr ',num2str(gr),' --meff ',num2str(mc),' --hbarscaled ',num2str(hbar),' --R ',num2str(R),' '];                            
str7 = '--path data/results/'; 
inputstr = [str1,str2,str3,str4,str5,str6,str7];
[~,cmdout] = system(inputstr,'CUDA_VISIBLE_DEVICES','0');

projectdir = 'output\timeoutput\';
dinfo = dir( fullfile(projectdir, '*.txt'));
nfiles = length(dinfo);
filenames = fullfile(projectdir, {dinfo.name});
y1sum=zeros(N,N);
for K = 0 : nfiles-1-sample_t0
    thisfile = ['output\timeoutput\wavefunction_plus_',num2str(K+sample_t0),'.txt'];
    thisdata = readmatrix(thisfile);
    Y1 = abs(thisdata(1:N,:)+1i*thisdata(N+1:2*N,:)).^2;
    y1sum = y1sum + Y1;
end
psi = readmatrix('output\wavefunction_plus.txt');
psi=psi(1:N,1:N)+1i*psi(N+1:2*N,1:N);
Y1 = abs(reshape(psi,N,N)).^2;
figure(1);
ax(1)=subplot(1,2,1);surf(x,y,Y1);shading interp;view(2);colorbar;colormap(ax(1),'jet');
pbaspect([1 1 1]);axis tight;xlabel('x (µm)');ylabel('y (µm)');shading interp;set(gca, 'Fontsize',20);
ax(2)=subplot(1,2,2);surf(x,y,angle(reshape(psi,N,N)));colorbar;shading interp;view(2);colormap(ax(2),'jet');
pbaspect([1 1 1]);axis tight;set(gca,'YTickLabel',[]);xlabel('x (µm)');shading interp;set(gca, 'Fontsize',20);
cost = sum(sum(y1sum));
end
%----------------------------------Pump-Adaptation Function for Optimizer----------------------------------%
function P = writepump(lambda,N,L,dxy,x,y,dis,P1,p1w,p2w)
header = {'#' 'SIZE' num2str(N) num2str(N) num2str(L) num2str(L) num2str(dxy) num2str(dxy)};
writecell(header,'loads/pump_plus.txt','Delimiter',' ');
P=zeros(N,N);
P2 =lambda;
for i=1:N
    for j=1:N
        P(i,j) = P1*exp(-sqrt(x(i)^2+(y(j)+dis/2)^2)/p1w^2)+P2*exp(-sqrt(x(i)^2+(y(j)-dis/2)^2)/p2w^2);
    end
end
pump(1:N,1:N) = real(P);
pump(N+1:2*N,1:N) = imag(P);
writematrix(pump,'loads/pump_plus.txt','Delimiter',' ','WriteMode','append');
end
