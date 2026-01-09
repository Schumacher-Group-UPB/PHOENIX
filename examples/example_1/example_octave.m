
clear; rng('shuffle');
%% Setting up the required directories and check for executable and GPU device (if required)
% Define the filename of your PHOENIX release
filename = '/bin/gpu/PHOENIX_gpu_fp64_sfml';

cd('~/yourpath/PHOENIX');
% Specify a custom directory
customDir = pwd;
disp(['customDir: "', customDir]);

if exist(fullfile(customDir, filename), 'file') == 2
    disp(['The file "', filename, '" is present in the directory.']);
else
    disp(['The file "', filename, '" is not found in the directory.']);
end

% Define loads directory path
directoryPath_load = 'data/loads/';

% Create loads directory
if ~exist(directoryPath_load, 'dir')
    % Create the directory
    mkdir(directoryPath_load);
    disp(['Directory "', directoryPath_load, '" has been created.']);
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
gpuTable = [];

% Check if the GPU device table is empty
if isempty(gpuTable)
    disp('No GPU device detected. Please use the CPU version of Phoenix.');
else
    disp('GPU device detected. Proceeding with GPU-based Phoenix.');
end
%% Set if you want to run the optimizer algorithm
optimizer = 0;      %find the resoance energy to the corner state

%% Setting up parameters and matrices
% time evolution settings
tmax = 5000;              %time-evolution range
dt = 0.006;               %time-step

% system discretisation
N = 600;                  %grid size
dxy = 0.1;                 %spatial discretization step
L = N*dxy;                 %real space grid length
x = sparse(dxy*(-N/2+1:N/2)).';   %x dimension discretization
y = sparse(dxy*(-N/2+1:N/2)).';   %y dimension discretization

% parameter definition
hbar = 6.582119569E-1;  %hbar in eVps^-1
mc = 5.684E-1;          %effective polariton mass
gammaC = 0.005;         %polariton loss rate in ps^-1
gc = 2E-3;              %polariton-polariton interaction strength in eVum^2

% create potential and initial condition
load([pwd '/examples/example_1/potential_N600.mat']);
pot=vpotmatrix;
I_Noise = 1E-1; psi=I_Noise*(-1+2*rand(N,N)-1i+2*1i*rand(N,N));

psi(1:N,1:N) = real(psi);
psi(N+1:2*N,1:N) = imag(psi);

fid = fopen(fullfile(directoryPath_load,'wavefunction_plus.txt'), 'w');
fprintf(fid, '# SIZE %d %d %f %f %f %f\n', N, N, L, L, dxy, dxy);
fclose(fid);

dlmwrite(fullfile(directoryPath_load,'wavefunction_plus.txt'), psi, '-append', 'delimiter', ' ');

potential(1:N,1:N) = real(pot*1e3);
potential(N+1:2*N,1:N) = imag(pot);

fid = fopen(fullfile(directoryPath_load,'potential_plus.txt'), 'w');
fprintf(fid, '# SIZE %d %d %f %f %f %f\n', N, N, L, L, dxy, dxy);
fclose(fid);

dlmwrite(fullfile(directoryPath_load,'potential_plus.txt'), potential, '-append', 'delimiter', ' ');

% pulse parameters
omega = -5.68828730684262;
E0 = 5.6856E-3;

%% Execute PHOENIX
str1 = [fullfile(customDir, filename), ' '];                                                                                                    %call main.exe
str2 = ['--N ',num2str(N),' ',num2str(N),' --L ',num2str(L),' ',num2str(L),' --boundary zero zero '];                      %define the real-space grid
str3 = ['--tmax ',num2str(tmax),' --tstep ',num2str(dt),' --outEvery 1 --fftEvery 1000 '];                                 %time discretization
str4 = ['--pulse ',num2str(E0),' add 1E12 1E12 0 0 plus 10 0 gauss+noDivide time iexp 0 1E12 ',num2str(omega),' '];        %define resonant pump
str5 = ['--potential load ',directoryPath_load,'potential_plus.txt 1 add plus --wavefunction load ',directoryPath_load,'wavefunction_plus.txt 1 add plus '];      %load initial condition and potential
str6 = ['--gammaC ',num2str(gammaC),' --gc ',num2str(gc),' --meff ',num2str(mc),' --hbarscaled ',num2str(hbar),' '];                            %set GP-Parameters
str7 = ['--path ',directoryPath_result];                                                                                                        %set output directory

% execute PHOENIX
inputstr = [str1,str2,str3,str4,str5,str6,str7];
[~,cmdout] = system(inputstr);


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
%post-processing: visualize results
psi = dlmread(fullfile(directoryPath_result,'wavefunction_plus.txt'));
psi=psi(1:N,1:N)+1i*psi(N+1:2*N,1:N);
Y1 = abs(reshape(psi,N,N)).^2;

pump = dlmread(fullfile(directoryPath_result,'pulse_plus.txt'));
pump=pump(1:N,1:N)+1i*pump(N+1:2*N,1:N);

pot = dlmread(fullfile(directoryPath_result,'potential_plus.txt'));
pot=pot(1:N,1:N);

figure(1);
ax(1)=subplot(2,2,1);surf(x,y,pot);shading interp;view(2);colorbar;colormap(ax(1),'jet');
pbaspect([1 1 1]);axis tight;xlabel('x (µm)');ylabel('y (µm)');shading interp;set(gca, 'Fontsize',20);
ax(2)=subplot(2,2,2);surf(x,y,pump);colorbar;shading interp;view(2);colormap(ax(2),'jet');clim([max(max(pump)-1E-7) max(max(pump)+1E-7)])
pbaspect([1 1 1]);axis tight;set(gca,'YTickLabel',[]);xlabel('x (µm)');shading interp;set(gca, 'Fontsize',20);
ax(3)=subplot(2,2,3);surf(x,y,Y1);shading interp;view(2);colorbar;colormap(ax(3),'jet');
pbaspect([1 1 1]);axis tight;xlabel('x (µm)');ylabel('y (µm)');shading interp;set(gca, 'Fontsize',20);
ax(4)=subplot(2,2,4);surf(x,y,angle(reshape(psi,N,N)));colorbar;shading interp;view(2);colormap(ax(4),'jet');
pbaspect([1 1 1]);axis tight;set(gca,'YTickLabel',[]);xlabel('x (µm)');shading interp;set(gca, 'Fontsize',20);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Optimizer
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%this part of the code uses an local optimizer algorithm to optimize the resonance of the pulse-frequency with  the corner state
if optimizer == 1
    %options = optimset('Display','iter','PlotFcns',@optimplotfval,'TolX',1E-1);
    %resonance = fminbnd(@costfunction,0,1,options);
    options = optimset('Display','iter','TolX',1E-1);
    resonance = fminbnd(@costfunction,0,1,options);
end
function cost = costfunction(X)
% Define the filename of your PHOENIX release
filename = '/bin/gpu/PHOENIX_gpu_fp64_sfml';
% Define the directory path
directoryPath_load = 'data/loads/';
% Define the directory path
directoryPath_result = 'data/results/';

% time evolution settings
tmax = 100;              %time-evolution range
dt = 0.006;               %time-step

% system discretisation
N = 600;                   %grid size
dxy = 0.1;                 %spatial discretization step
L = N*dxy;                 %real space grid length
x = sparse(dxy*(-N/2+1:N/2)).';   %x dimension discretization
y = sparse(dxy*(-N/2+1:N/2)).';   %y dimension discretization

% parameter definition
hbar = 6.582119569E-1;  %hbar in eVps^-1
mc = 5.684E-1;          %effective polariton mass
gammaC = 0.005;         %polariton loss rate in ps^-1
gc = 2E-3;              %polariton-polariton interaction strength in eVum^2

% create potential and initial condition
load([pwd '/examples/example_1/potential_N600.mat']);
pot=vpotmatrix;

I_Noise = 1E-1; psi=I_Noise*(-1+2*rand(N,N)-1i+2*1i*rand(N,N));

psi(1:N,1:N) = real(psi);
psi(N+1:2*N,1:N) = imag(psi);

fid = fopen(fullfile(directoryPath_load,'wavefunction_plus.txt'), 'w');
fprintf(fid, '# SIZE %d %d %f %f %f %f\n', N, N, L, L, dxy, dxy);
fclose(fid);

dlmwrite(fullfile(directoryPath_load,'wavefunction_plus.txt'), psi, '-append', 'delimiter', ' ');

potential(1:N,1:N) = real(pot*1e3);
potential(N+1:2*N,1:N) = imag(pot);

fid = fopen(fullfile(directoryPath_load,'potential_plus.txt'), 'w');
fprintf(fid, '# SIZE %d %d %f %f %f %f\n', N, N, L, L, dxy, dxy);
fclose(fid);

dlmwrite(fullfile(directoryPath_load,'potential_plus.txt'), potential, '-append', 'delimiter', ' ');

% pulse parameters
omega = -5.68178730684262-X*1e-2;
E0 = 5.6856E-3;

%create runstring
str1 = [fullfile(customDir, filename), ' '];                                                                                                    %call main.exe
str2 = ['--N ',num2str(N),' ',num2str(N),' --L ',num2str(L),' ',num2str(L),' --boundary zero zero '];                      %define the real-space grid
str3 = ['--tmax ',num2str(tmax),' --tstep ',num2str(dt),' --outEvery 1 --fftEvery 1000 '];                                 %time discretization
str4 = ['--pulse ',num2str(E0),' add 1E12 1E12 0 0 plus 10 0 gauss+noDivide time iexp 0 1E12 ',num2str(omega),' '];        %define resonant pump
str5 = ['--potential load ',directoryPath_load,'potential_plus.txt 1 add plus --wavefunction load ',directoryPath_load,'wavefunction_plus.txt 1 add plus '];      %load initial condition and potential
str6 = ['--gammaC ',num2str(gammaC),' --gc ',num2str(gc),' --meff ',num2str(mc),' --hbarscaled ',num2str(hbar),' '];                            %set GP-Parameters
str7 = ['--path ',directoryPath_result];                                                                                                        %set output directory

% execute PHOENIX
inputstr = [str1,str2,str3,str4,str5,str6,str7];
[~,cmdout] = system(inputstr);
phoenix_output = removeAnsiCodes(cmdout);
disp(phoenix_output);

%post-processing: visualize results and evaluate cost-function
psi = readmatrix([directoryPath_result,'wavefunction_plus.txt']);
psi=psi(1:N,1:N)+1i*psi(N+1:2*N,1:N);
Y1 = abs(reshape(psi,N,N)).^2;

pump = readmatrix([directoryPath_result,'pulse_plus.txt']);
pump=pump(1:N,1:N)+1i*pump(N+1:2*N,1:N);

pot = readmatrix([directoryPath_result,'potential_plus.txt']);
pot=pot(1:N,1:N);

argpsi=angle(reshape(psi,N,N));
xrange = N/2:N-1;
yrange = 1:N/2;
figure(1);
ax(1)=subplot(2,2,1);surf(x(xrange),y(yrange),pot(xrange,yrange));shading interp;view(2);colorbar;colormap(ax(1),'jet');
pbaspect([1 1 1]);axis tight;xlabel('x (µm)');ylabel('y (µm)');shading interp;set(gca, 'Fontsize',20);
ax(2)=subplot(2,2,2);surf(x(xrange),y(yrange),pump(xrange,yrange));colorbar;shading interp;view(2);colormap(ax(2),'jet');clim([max(max(pump)-1E-7) max(max(pump)+1E-7)])
pbaspect([1 1 1]);axis tight;set(gca,'YTickLabel',[]);xlabel('x (µm)');shading interp;set(gca, 'Fontsize',20);
ax(3)=subplot(2,2,3);surf(x(xrange),y(yrange),Y1(xrange,yrange));shading interp;view(2);colorbar;colormap(ax(3),'hot');
pbaspect([1 1 1]);axis tight;xlabel('x (µm)');ylabel('y (µm)');shading interp;set(gca, 'Fontsize',20);
ax(4)=subplot(2,2,4);surf(x(xrange),y(yrange),argpsi(xrange,yrange));colorbar;shading interp;view(2);colormap(ax(4),'jet');
pbaspect([1 1 1]);axis tight;set(gca,'YTickLabel',[]);xlabel('x (µm)');shading interp;set(gca, 'Fontsize',20);
cost = 1/max(max(Y1));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function cleanedString = removeAnsiCodes(inputString)
    % Use regexprep to remove ANSI escape codes
    cleanedString = strrep(inputString, '[90m#[0m', ' ');
    cleanedString = regexprep(cleanedString, '\[0m|\[1m|\[2m|\[3m|\[4m|\[30m|\[31m|\[32m|\[33m|\[34m|\[35m|\[36m|\[37m|[93m|\[94m|\[?25h|\[2K|\[?25l|\[90m|\[A', '');
endfunction

