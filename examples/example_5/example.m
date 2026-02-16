%% ========================================================================
%  PHOENIX Linear Response Simulation for Non-Hermitian Polariton Systems
%  ========================================================================
%
%  PURPOSE:
%    - Run the Paderborn open-access GPU solver PHOENIX twice (ψ₊ and ψ₋ probe)
%    - Extract the momentum- and frequency-resolved linear susceptibility χ(k,ω)
%    - Compare the numerical absorption spectrum to a 2×2 non-Hermitian model
%    - Demonstrate perfect agreement between simulation and analytic theory
%
%  PHYSICAL CONTEXT:
%    - Two-component exciton-polaritons (circular polarizations) in a planar cavity
%    - Non-Hermiticity from:
%         (i) intrinsic dichroism: γ₊ ≠ γ₋ (requires PHOENIX source modification)
%         (ii) induced by off-resonant, polarized pumping below threshold
%    - CW pumping creates steady-state asymmetry in losses
%    - Weak Gaussian pulse probes linear optical response
%
%  WORKFLOW:
%    1. Clean previous output files
%    2. Set physical and numerical parameters
%    3. Prepare PHOENIX potential and input arguments
%    4. Run PHOENIX for ψ₊ probe, compute χ₊(k,ω)
%    5. Run PHOENIX for ψ₋ probe, compute χ₋(k,ω)
%    6. Compute analytic eigenvalues of 2×2 model
%    7. Normalize and align spectra
%    8. Plot and save figures
%
%  DEPENDENCIES:
%    - PHOENIX GPU solver executable (e.g., main_v03_10_6.exe)
%    - npy-matlab package for reading NumPy arrays
%
%  AUTHOR:
%    Jan Wingenbach (Universität Paderborn)
% ========================================================================

%% ------------------------------------------------------------------------
%  1) HOUSEKEEPING: clear workspace, delete previous outputs
% -------------------------------------------------------------------------

clear;set(0, 'DefaultFigureColor', 'w');
delete([pwd,'\output_git_minus\timeoutput\*.npy']);
delete([pwd,'\output_git_plus\timeoutput\*.npy']);

delete([pwd,'\output_git_minus\*.txt']);
delete([pwd,'\output_git_plus\*.txt']);
pyenv
addpath([pwd,'\npy-matlab\npy-matlab'])
savepath

%% ------------------------------------------------------------------------
%  2) PHYSICAL AND NUMERICAL PARAMETERS
% -------------------------------------------------------------------------
% Time evolution
tmax = 250.1;            % Total time range [ps]
dt   = 0.001;            % Time step [ps]
FFT_sample_rate = dt*100; % Sampling rate for FFT output

% Spatial grid
N   = 1000;               % Grid size (N × N points)
dxy = 0.1;                % Spatial step [µm]
L   = N*dxy;              % Real space grid length [µm]
x   = dxy*(-N/2+1:N/2).'; % Real-space coordinates [µm]
y   = x;                  % y-coordinates
kx  = (2*pi*(-N/2+1:N/2)/L).'; % Momentum grid [µm⁻¹]
ky  = kx;

% Physical constants
hbar = 6.582119569E-1;  % Planck's constant [meV·ps]
mc = 5.684E-1;          % Effective mass [meV·ps²/µm²]

% here: we excite the plus component with cw pump to create the gamma difference
% Dissipation and interaction parameters
gamma_C = 0.4/hbar;          % Cavity loss rate [meV]
gamma_R = 1.5*gamma_C;  % Reservoir decay rate [meV]
R = 0.01;               % Condensation rate

Gamma_plus_soll = -0.2/hbar; % Target γ₊ loss rate
p0 = gamma_R*(gamma_C+Gamma_plus_soll)/R;  % Required pump amplitude
gc = 0;  gr = 0;        % Interaction constants
delta = 0.1;            % LT splitting coefficient [meV·µm²]
omega = 0.025132741228718;    % Probe frequency [meV/ħ]
E0 = 5E-6;              % Pulse amplitude
p_xw = 1;               % Spatial width [µm]
p_tw = 0.5;             % Temporal width [ps]
t0 = 50;                % Pulse center time [ps]

%% ------------------------------------------------------------------------
%  3) PREPARE PHOENIX INPUT FILES
% -------------------------------------------------------------------------
outputfiletype = 'npy';   % Output format from PHOENIX

%% ------------------------------------------------------------------------
%  4) PHOENIX COMMAND TEMPLATE
% -------------------------------------------------------------------------
% Base executable
str1 = 'main_v03_10_6.exe -tetm --subgrids 2 2 ';
%str1_inherent = 'phoenix_32_2gammac.exe -tetm --subgrids 2 2 ';

% Geometry and boundary conditions
str2 = ['--N ',num2str(N),' ',num2str(N),' --L ',num2str(L),' ',num2str(L),' --boundary periodic periodic '];                

% Time evolution settings
str3 = ['--tmax ',num2str(tmax),' --tstep ',num2str(dt),' --fftMask 1.0 add 0.2 0.2 0 0 both 6 none gauss+noDivide+local --fftEvery ',num2str(dt),' '];  
           
% Initial condition
str4 = ['--initRandom 0 1 --pump ',num2str(p0),' add 1e12 1e12 0 0 plus 1 none gauss+noDivide '];  
%str4_inherent = '--initRandom 0 1 --initialReservoir 0 add 1 1 0 0 both 1 none gauss+noDivide ';      %load initial condition and potential

% Physical parameters
str5 = ['--gammaC ',num2str(gamma_C),' --gammaR ',num2str(gamma_R),' --R ',num2str(R),' --gc ',num2str(gc),' --gr ',num2str(gr),' --meff ',num2str(mc),' --hbarscaled ',num2str(hbar),' --deltaLT ',num2str(delta),' --g_pm 0 '];   

% Output settings
str6_plus = ['--historyMatrix 0 ',num2str(N),' ', num2str(N/2),' ',num2str(N/2+1),' 1 --output wavefunction,scalar,pulse --outEvery ',num2str(FFT_sample_rate),' --outputFileType ', outputfiletype,' --path output_git_plus\ ']; %--outputFileType ', outputfiletype,'
str6_minus = ['--historyMatrix 0 ',num2str(N),' ', num2str(N/2),' ',num2str(N/2+1),' 1 --output wavefunction,scalar,pulse --outEvery ',num2str(FFT_sample_rate),' --outputFileType ', outputfiletype,' --path output_git_minus\ ']; %--outputFileType ', outputfiletype,'

% Probe pulse strings (ψ₊ and ψ₋)
pstr_plus = ['--pulse ', num2str(E0),'i add ', num2str(p_xw), ' ', num2str(p_xw),' 0 0 plus 1 0 gauss+noDivide time iexp ', num2str(t0), ' ',num2str(p_tw), ' ', num2str(omega),' '];
pstr_minus = ['--pulse ', num2str(E0), ' add ', num2str(p_xw), ' ', num2str(p_xw),' 0 0 minus 1 0 gauss+noDivide time iexp ', num2str(t0), ' ',num2str(p_tw), ' ', num2str(omega),' '];

%% ------------------------------------------------------------------------
%  5) RUN PHOENIX FOR ψ₊ PROBE AND COMPUTE χ₊(k,ω)
% -------------------------------------------------------------------------
inputstr = [str1,str2,str3,pstr_plus,str4,str5,str6_plus];    %cw pumping to create gamma diff.

% Run PHOENIX solver with GPU environment variable set
[~,cmdout] = system(inputstr,'CUDA_VISIBLE_DEVICES','0');

% Clean ANSI escape codes from PHOENIX output for readability
htmlString = removeAnsiCodes(cmdout);
disp(htmlString(end-2630:end));

% Compute susceptibility χ₊ from simulation output
CHIp = response(N,FFT_sample_rate,'plus',outputfiletype);

%% ------------------------------------------------------------------------
%  6) RUN PHOENIX FOR ψ₋ PROBE AND COMPUTE χ₋(k,ω)
% -------------------------------------------------------------------------

inputstr = [str1,str2,str3,pstr_minus,str4,str5,str6_minus];    %cw pumping to create gamma diff.
[~,cmdout] = system(inputstr,'CUDA_VISIBLE_DEVICES','0');
htmlString = removeAnsiCodes(cmdout);
disp(htmlString(end-2630:end));

% Compute susceptibility χ₋ from simulation output
CHIm = response(N,FFT_sample_rate,'minus',outputfiletype);

%% ------------------------------------------------------------------------
%  7) COMPUTE ANALYTIC NON-HERMITIAN MODEL EIGENVALUES
% -------------------------------------------------------------------------
[rows, ~]= size(CHIm);
W=-2*pi*((-rows/2):(rows/2-1))/(FFT_sample_rate*rows);

gamma1 = abs(Gamma_plus_soll);
gamma2 = gamma_C;

val1nh = zeros(N,1);
val2nh = zeros(N,1);
Sz1 = zeros(N,1);
Sz2= zeros(N,1);

k0_index = find(kx==0);
k01_index = k0_index + 10 +7;
k1_index = k0_index + 32;

for i=k0_index-40:k0_index+40
    k2 = abs(kx(i))^2;
    beta = -delta*k2;

    Ekx =hbar^2*k2/2/mc;
    Eky =hbar^2*k2/2/mc;

    Hnonherm = [Ekx-1i*gamma1*hbar, beta;           
                beta,       Eky-1i*gamma2*hbar];          
    [V,D,~] = eig(Hnonherm);
    val1nh(i,1) = D(1,1);
    val2nh(i,1) = D(2,2);

    Sz1(i,1) = (abs(V(1,1))^2-abs(V(2,1))^2)/(abs(V(1,1))^2+abs(V(2,1))^2);
    Sz2(i,1) = (abs(V(1,2))^2-abs(V(2,2))^2)/(abs(V(1,2))^2+abs(V(2,2))^2);
end

%% ------------------------------------------------------------------------
%  8) NORMALIZE AND ALIGN SIMULATION SPECTRA
% -------------------------------------------------------------------------
% Extract absorption (imag part of χ) for chosen momenta

epsilon_cc_k0_p = imag(CHIp(:,k0_index));
epsilon_cc_k0_m = imag(CHIm(:,k0_index));

epsilon_cc_k1_p = imag(CHIp(:,k1_index));
epsilon_cc_k1_m = imag(CHIm(:,k1_index));

epsilon_cc_k01_p = imag(CHIp(:,k01_index));
epsilon_cc_k01_m = imag(CHIm(:,k01_index));

epsilon_cc_k0_p = epsilon_cc_k0_p./min(epsilon_cc_k0_p);
epsilon_cc_k0_m = epsilon_cc_k0_m./min(epsilon_cc_k0_m);

epsilon_cc_k1_p = epsilon_cc_k1_p./min(epsilon_cc_k1_p);
epsilon_cc_k1_m = epsilon_cc_k1_m./min(epsilon_cc_k1_m);

epsilon_cc_k01_p = epsilon_cc_k01_p./min(epsilon_cc_k01_p);
epsilon_cc_k01_m = epsilon_cc_k01_m./min(epsilon_cc_k01_m);

Zp = -imag(CHIp(:,3:N));
Zm = -imag(CHIm(:,3:N));

Zp = Zp./max(Zp(:));
Zm = Zm./max(Zm(:));

[~,offsetp] = max(-imag(CHIp(:,k0_index))); %offset due potential must be shifted
[~,offsetm] = max(-imag(CHIm(:,k0_index))); %offset due potential must be shifted

%% ------------------------------------------------------------------------
%  9) PLOT RESULTS: DISPERSION AND SPECTRAL CUTS
% -------------------------------------------------------------------------
figure(4);clf;
subplot(1,5,1);
surf(kx(2:N-1), W*hbar-W(offsetp)*hbar, Zp);title('dispersion');
shading interp;view(2);colormap('hot')
axis tight;xlim([-2 2]);ylim([-0.5 2]);
xlabel('k [1/µm]');ylabel('energy [meV]');set(gca,'fontsize',18);colorbar;
hold on; 
scatter3(kx, real(val1nh), 100*ones(N,1), 'k', 'LineWidth', 2);
scatter3(kx, real(val2nh), 100*ones(N,1), 'k', 'LineWidth', 2);
hold off;pbaspect([1 2 1])

subplot(1,5,2);
surf(kx(2:N-1), W*hbar-W(offsetm)*hbar, Zm);title('dispersion');
shading interp;view(2);colormap('hot')
axis tight;xlim([-2 2]);ylim([-0.5 2]);
xlabel('k [1/µm]');ylabel('energy [meV]');set(gca,'fontsize',18);colorbar;
hold on; 
scatter3(kx, real(val1nh), 100*ones(N,1), 'k', 'LineWidth', 2);
scatter3(kx, real(val2nh), 100*ones(N,1), 'k', 'LineWidth', 2);
hold off;pbaspect([1 2 1])

subplot(1,5,3);hold on;title(['k=',num2str(kx(k0_index))])
plot(W*hbar-W(offsetp)*hbar,epsilon_cc_k0_p,'LineWidth',2,'DisplayName','ψ_+ response ');
plot(W*hbar-W(offsetm)*hbar,epsilon_cc_k0_m,'LineWidth',2,'DisplayName','ψ_- respons ');
%plot(W(1:nfiles)*hbar,lorentz,'LineWidth',2,'DisplayName','Lorentz')
hold off;xlabel('energy [meV]');ylabel('response');legend('Location','northeast');xlim([-2 4]);box on;grid on;set(gca,'fontsize',18);set(gca,'LineWidth',2);pbaspect([1 2 1])

subplot(1,5,4);hold on;title(['k=',num2str(kx(k01_index))])
plot(W*hbar-W(offsetp)*hbar,epsilon_cc_k01_p,'LineWidth',2,'DisplayName','ψ_+ response ');
plot(W*hbar-W(offsetm)*hbar,epsilon_cc_k01_m,'LineWidth',2,'DisplayName','ψ_- respons ');
hold off;xlabel('energy [meV]');ylabel('response');legend('Location','northeast');xlim([-2 4]);box on;grid on;set(gca,'fontsize',18);set(gca,'LineWidth',2);pbaspect([1 2 1])

subplot(1,5,5);hold on;title(['k=',num2str(kx(k1_index))])
plot(W*hbar-W(offsetp)*hbar,epsilon_cc_k1_p,'LineWidth',2,'DisplayName','ψ_+ response ');
plot(W*hbar-W(offsetm)*hbar,epsilon_cc_k1_m,'LineWidth',2,'DisplayName','ψ_- respons ');
hold off;xlabel('energy [meV]');ylabel('response');legend('Location','northwest');xlim([-2 4]);box on;grid on;set(gca,'fontsize',18);set(gca,'LineWidth',2);pbaspect([1 2 1])

%% ------------------------------------------------------------------------
%  10) SAVE HIGH-RES DISPERSION PLOTS
% -------------------------------------------------------------------------
x0=10; y0=10; width=500; height=1000;
figure(5);clf;set(gcf, 'Color', 'w');
surf(kx(2:N-1), W*hbar-W(offsetp)*hbar, Zp);
shading interp;view(2);colormap('hot');%colorbar
axis tight;xlim([-2.5 2.5]);ylim([-0.5 2.2]);
set(gca,'fontsize',18);hold on; 
scatter3(kx, real(val1nh), ones(N,1), 'k', 'LineWidth', 4);
scatter3(kx, real(val2nh), ones(N,1), 'k', 'LineWidth', 4);
hold off;pbaspect([1 1 1]);set(gca,'XTickLabel',[]);set(gca,'YTickLabel',[]);
set(gcf,'position',[x0,y0,height,height]);

figure(6);clf;set(gcf, 'Color', 'w');
surf(kx(2:N-1), W*hbar-W(offsetm)*hbar, Zm);
shading interp;view(2);colormap('hot');%colorbar
axis tight;xlim([-2.5 2.5]);ylim([-0.5 2.2]);
set(gca,'fontsize',18);hold on; 
scatter3(kx, real(val1nh), ones(N,1), 'k', 'LineWidth', 4);
scatter3(kx, real(val2nh), ones(N,1), 'k', 'LineWidth', 4);
hold off;pbaspect([1 1 1]);set(gca,'XTickLabel',[]);set(gca,'YTickLabel',[]);
set(gcf,'position',[x0,y0,height,height]);

%% ------------------------------------------------------------------------
%  11) HELPER FUNCTION: RESPONSE
% -------------------------------------------------------------------------

function CHI = response(N,FFT_sample_rate,pulse_polarization,outputfiletype)
% RESPONSE - Compute susceptibility χ(k,ω) from PHOENIX outputs
%
% INPUTS:
%   N                  - Grid size
%   FFT_sample_rate    - Temporal sampling rate in PHOENIX output
%   pulse_polarization - 'plus' or 'minus'
%   outputfiletype     - 'npy' or 'txt'
%
% OUTPUT:
%   CHI - Complex susceptibility in (ω,k) space
projectdir     = ['output_git_', pulse_polarization, '\timeoutput\'];
dinfo          = dir(fullfile(projectdir, ['*wavefunction_', pulse_polarization, '*.', outputfiletype]));
nfiles         = numel(dinfo);
yp_t_x = zeros(nfiles,N);

% ——————————————
% 1) LOAD & STACK ψ(x,t) ALONG CENTRAL SPATIAL CUT
% ——————————————
for K = 1:nfiles
    % time-tag string (seconds)
    t_str = num2str(K*FFT_sample_rate, '%.2f');
    
    % find the file
    pattern = sprintf('wavefunction_%s_%s*.%s', pulse_polarization, t_str, outputfiletype);
    f = dir(fullfile(projectdir, pattern));

    if isempty(f)
        t_str = num2str(K*FFT_sample_rate-1e-2, '%.2f');
        % Check if files exist, otherwise try fallbacks
        pattern = sprintf('wavefunction_%s_%s*.%s', pulse_polarization, t_str, outputfiletype);
        f = dir(fullfile(projectdir, pattern));
    end

    % load numpy array and convert to MATLAB double
    if strcmp(outputfiletype, 'npy')
        raw    = py.numpy.load(fullfile(f(1).folder, f(1).name));
        psi    = double(raw);               
    elseif strcmp(outputfiletype, 'txt')
        thisfile = fullfile(f(1).folder, f(1).name);
        raw = readmatrix(thisfile); psi = raw(1,1:N) + 1i * raw(2,1:N);
    end

    yp_t_x(K,:) = psi;
end

% ———————————————
% OPTIONAL: ZERO-PADDING IN TIME
% ———————————————
pad_factor = 1;  % e.g. 2x padding (can also try 4)
n_pad = pad_factor * nfiles;
pad_len = n_pad - nfiles;

% zero-pad time dimension (pad after)
yp_t_x = [yp_t_x; zeros(pad_len, N)];

[rows, ~]= size(yp_t_x);
W=-2*pi*((-rows/2):(rows/2-1))/(FFT_sample_rate*rows);

% ——————————————
% 2) FOURIER TRANSFORM ψ → ψ(k,ω)
% ——————————————
% First, shift the time-domain signal so the center (t0) is at the start
temp_psi = ifftshift(yp_t_x, 1); % Shift along time dimension (1)
% Then, shift the space-domain signal so the center (x=0) is at the start
temp_psi = ifftshift(temp_psi, 2); % Shift along space dimension (2)
YP_kw_uncentered = fft2(temp_psi);
% Finally, shift the zero-frequency component to the center for visualization
YP_kw = fftshift(YP_kw_uncentered);

% ——————————————
% 3) LOAD & FFT THE PULSE
% ——————————————
% time-profile
S = readmatrix(['output_git_',pulse_polarization,'/scalar.txt']);
pulse_time = S(:,7) + 1i*S(:,6);        % [n_t×1] complex

% spatial profile
if strcmp(outputfiletype, 'npy')
    Praw = ['output_git_',pulse_polarization,'\pulse_',pulse_polarization,'.',outputfiletype];
    Praw = py.numpy.load(Praw);
    Praw = double(Praw);
    P2D  = reshape(Praw, N, N);
elseif strcmp(outputfiletype, 'txt')
    thisfile = fullfile(['output_git_',pulse_polarization,'\pulse_',pulse_polarization,'.',outputfiletype]);
    Praw = readmatrix(thisfile);  
    P2D =  Praw(1:N,1:N) + 1i * Praw(N+1:2*N,1:N);
end

p_central = P2D(:,N/2).'; 

P_t_x((1:nfiles), :) = pulse_time((1:nfiles)) * p_central *exp(1i*pi/2);
% zero-pad time dimension (pad after)
P_t_x = [P_t_x; zeros(pad_len, N)];

% FFT → P(k,ω)
% Repeat the exact same robust procedure for the pulse
temp_pulse = ifftshift(P_t_x, 1);  % Shift time
temp_pulse = ifftshift(temp_pulse, 2);  % Shift space
P_KW_uncentered = fft2(temp_pulse);
P_KW = fftshift(P_KW_uncentered);

% ————————————————
% 4) Wiener deconvolution in (ω,k):
% ————————————————
noise_floor = 1e-8;    % try 1e-8 … 1e-5 for minimal bias
alpha       = noise_floor * max(abs(P_KW(:)).^2);          
H = conj(P_KW) ./ (abs(P_KW).^2 + alpha);

% apply filter
CHI = YP_kw .* H;
end

%% ------------------------------------------------------------------------
%  12) HELPER FUNCTION: REMOVE ANSI CODES
% -------------------------------------------------------------------------

function cleanedString = removeAnsiCodes(inputString)
    % REMOVEANSICODES - Strips ANSI escape sequences from PHOENIX log output
    cleanedString = strrep(inputString, '[90m#[0m', ' ');
    cleanedString = regexprep(cleanedString, '\[0m|\[1m|\[2m|\[3m|\[4m|\[30m|\[31m|\[32m|\[33m|\[34m|\[35m|\[36m|\[37m|[93m|\[94m|\[?25h|\[2K|\[?25l|\[90m|\[A', '');
end
