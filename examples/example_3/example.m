clear; rng('shuffle');
x0=10; y0=10;  width=1200; height=1000;
%% Setting up the required directories and check for executable and GPU device (if required)
% Define the filename of your PHOENIX release
filename = 'phoenix_64.exe';

% Specify a custom directory
customDir = pwd;

if exist(fullfile(customDir, filename), 'file') == 2
    disp(['The file "', filename, '" is present in the directory.']);
else
    disp(['The file "', filename, '" is not found in the directory.']);
end

% Define result directory path
directoryPath_result = 'data/results/';

% Create results directory
if ~exist(directoryPath_result, 'dir')
    % Create the directory
    mkdir(directoryPath_result);
    disp(['Directory "', directoryPath_result, '" has been created.']);
end

% Get GPU device table
gpuTable = gpuDeviceTable;

% Check if the GPU device table is empty
if isempty(gpuTable)
    disp('No GPU device detected. Please use the CPU version of Phoenix.');
else
    disp('GPU device detected. Proceeding with GPU-based Phoenix.');
end
%% Setting up parameters and matrices
% system discretisation
N = 500;                  %grid size
dxy = 0.4;                 %spatial discretization step
L = N*dxy;                 %real space grid length
x = sparse(dxy*(-N/2+1:N/2)).';   %x dimension discretization
y = sparse(dxy*(-N/2+1:N/2)).';   %y dimension discretization
kx = (2*pi*(-N/2+1:N/2)/L).';     %wavevector discretization
ky = (2*pi*(-N/2+1:N/2)/L).';     %wavevector discretization

% parameter definition
hbar = 6.582119569E-4;  %hbar in eVps^-1
mc = 5.684E-4;          %effective polariton mass
gammaC = 0.005;         %polariton loss rate in ps^-1
gc = 2E-6;              %polariton-polariton interaction strength in eVum^2

% run through combinations of topolgical charges
for sec = 1:3
if  sec == 1
    wp = 4.5;
    xres=30; 
    yres=30;
    marray = [-1 1; 0 0; 1 -1; 0 1; 1 0; 1 1; 0 -1; -1 0; -1 -1];
elseif sec == 2
    wp = 8;
    xres=50; 
    yres=50;
    marray = [-3 1; -3 0; -3 -1; -1 3; 0 3; 1 3; -3 -1; -3 0; -3 1; 3 1; 3 0; 3 -1];
elseif sec == 3
    wp = 12;
    xres=70; 
    yres=70;
    marray = [0 -4; -4 0; 4 0; 0 4];
end

[rows,~] = size(marray);

for mscan = 1:rows

mp = marray(mscan,1);
mm = marray(mscan,2);

%% Execute PHOENIX
str1 = [filename, ' -tetm '];                                        
str2 = '--N 500 500 --L 100 100 --boundary zero zero ';                 
str3 = '--tmax 10000 ';                                                 
str4 = ['--initialState 0.1 add 70 70 0 0 plus 1 ',num2str(mp),' gauss+noDivide --initialState 0.1 add 70 70 0 0 minus 1 ',num2str(mm),' gauss+noDivide '];  
str5 = '--g_pm 6E-7 --deltaLT 0.025E-3 ';                                                               
str6 = ['--pump 100 add ',num2str(wp),' ',num2str(wp),' 0 0 both 1 none gauss+noDivide+ring '];   
str7 = ['--outEvery 5 --path ',directoryPath_result];                        

% execute PHOENIX
inputstr = [str1,str2,str3,str4,str5,str6,str7];
[~,cmdout] = system(inputstr       );

% in cmdout you can view the output of PHOENIX
phoenix_output = removeAnsiCodes(cmdout);
disp(phoenix_output);

% Check if PHOENIX was completed successfully
if contains(phoenix_output, ' Runtime Statistics ')
    disp('PHOENIX ran successfully.');
else
    disp('PHOENIX did not run successfully.');
end

%% Post-processing
% post-processing: visualize results
psiiniplus = readmatrix([directoryPath_result,'initial_wavefunction_plus.txt']);
psiiniplus=psiiniplus(1:N,1:N)+1i*psiiniplus(N+1:2*N,1:N);
Y1iniplus = abs(reshape(psiiniplus,N,N)).^2;

psiiniminus = readmatrix([directoryPath_result,'initial_wavefunction_minus.txt']);
psiiniminus=psiiniminus(1:N,1:N)+1i*psiiniminus(N+1:2*N,1:N);
Y1iniminus = abs(reshape(psiiniminus,N,N)).^2;

pump = readmatrix([directoryPath_result,'pump_plus.txt']);
pump=pump(1:N,1:N);

psi = readmatrix([directoryPath_result,'wavefunction_plus.txt']);
psi=psi(1:N,1:N)+1i*psi(N+1:2*N,1:N);
Y1 = abs(reshape(psi,N,N)).^2;

psim = readmatrix([directoryPath_result,'wavefunction_minus.txt']);
psim=psim(1:N,1:N)+1i*psim(N+1:2*N,1:N);
Y1m = abs(reshape(psim,N,N)).^2;

figure(2);surf(x,y,Y1);shading interp;view(2);colormap('jet');pbaspect([1 1 1]);axis tight;set(gca,'XTickLabel',[]);set(gca,'YTickLabel',[]);shading interp;xlim([-xres xres]);ylim([-yres yres]);clim([0 160])
saveas(gca,['Figure_msum=',num2str(mp+mm),'_mdif=',num2str(mp-mm),'_psip_d.png']);
figure(3);surf(x,y,Y1m);shading interp;view(2);colormap('jet');pbaspect([1 1 1]);axis tight;set(gca,'XTickLabel',[]);set(gca,'YTickLabel',[]);shading interp;xlim([-xres xres]);ylim([-yres yres]);clim([0 160])
saveas(gca,['Figure_msum=',num2str(mp+mm),'_mdif=',num2str(mp-mm),'_psim_d.png']);
figure(4);surf(x,y,angle(reshape(psi,N,N)));shading interp;view(2);colormap('gray');pbaspect([1 1 1]);axis tight;set(gca,'XTickLabel',[]);set(gca,'YTickLabel',[]);shading interp;xlim([-xres xres]);ylim([-yres yres]);clim([-pi pi])
saveas(gca,['Figure_msum=',num2str(mp+mm),'_mdif=',num2str(mp-mm),'_psip_arg.png']);
figure(5);surf(x,y,angle(reshape(psim,N,N)));shading interp;view(2);colormap('gray');pbaspect([1 1 1]);axis tight;set(gca,'XTickLabel',[]);set(gca,'YTickLabel',[]);shading interp;xlim([-xres xres]);ylim([-yres yres]);clim([-pi pi])
saveas(gca,['Figure_msum=',num2str(mp+mm),'_mdif=',num2str(mp-mm),'_psim_arg.png']);

end
end
function cleanedString = removeAnsiCodes(inputString)
    % Use regexprep to remove ANSI escape codes
    cleanedString = strrep(inputString, '[90m#[0m', ' ');
    cleanedString = regexprep(cleanedString, '\[0m|\[1m|\[2m|\[3m|\[4m|\[30m|\[31m|\[32m|\[33m|\[34m|\[35m|\[36m|\[37m|[93m|\[94m|\[?25h|\[2K|\[?25l|\[90m|\[A', '');
end
