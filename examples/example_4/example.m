clear; rng('shuffle');
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

% Define post-processing directory path
directoryPath_postprocess = 'BroadEx/Psi/';

% Create results directory
if ~exist(directoryPath_postprocess, 'dir')
    % Create the directory
    mkdir(directoryPath_postprocess);
    disp(['Directory "', directoryPath_postprocess, '" has been created.']);
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
N = 256;                   %grid size
L = 230.4;                 %real space grid length
dxy = L/N;                 %spatial discretization step
x = sparse(dxy*(-N/2+1:N/2)).';   %x dimension discretization
y = sparse(dxy*(-N/2+1:N/2)).';   %y dimension discretization

% set Wigner Noise and sampling
dV = L^2/N^2;
MultP = 1:0.25:8;
Nj=150; 

% time evolution settings
tsave = 5;
tav=0;
dt = 0.04;
tend = 2000;

% parameter definition
hbar = 6.582119569E-1;  %hbar in eVps^-1
mc = 5.684E-1;          %effective polariton mass
gammaC = 0.2;           %polariton loss rate
gammaR = 1.5*gammaC;    %reservoir loss rate    
R = 0.015;              %condensation rate 
gc = 6E-3;              %polariton-polariton interaction strength
gr = 2*gc;              %polariton-reservoir interaction strength      

header = {'#' 'SIZE' num2str(N) num2str(N) num2str(L) num2str(L) num2str(dxy) num2str(dxy)};

% create pump profile and initial condition
Pthr = gammaC*gammaR/R;
wp = 65; %mum
p = zeros(N,N);

mask = zeros(N,N);
sx = 0.325*L;
sy = 0.325*L;
Px = 15;
Py = 15;
x0 = 0;
y0 = 0;

for i=1:N
    for j=1:N
        r = sqrt(x(i)^2+y(j)^2);
        p(i,j) = Pthr*exp(-r^4/wp^4);
    end
end

psi=1/sqrt(4*dV)*(normrnd(0,1,N,N)+1i*normrnd(0,1,N,N));
res=normrnd(0,1,N,N);

wavefunction(1:N,1:N) = real(psi);
wavefunction(N+1:2*N,1:N) = imag(psi);

reservoir(1:N,1:N) = real(res);
reservoir(N+1:2*N,1:N) = imag(res);

writecell(header,[directoryPath_load,'wavefunction_plus.txt'],'Delimiter',' ');
writecell(header,[directoryPath_load,'reservoir_plus.txt'],'Delimiter',' ');

writematrix(wavefunction,[directoryPath_load,'wavefunction_plus.txt'],'Delimiter',' ','WriteMode','append');
writematrix(reservoir,[directoryPath_load,'reservoir_plus.txt'],'Delimiter',' ','WriteMode','append');

for j=1:length(MultP)
    disp(['Amplitude multiplier = ',num2str(MultP(j))]);
    for k=1:Nj
        pump_new = MultP(j)*p;
        pump(1:N,1:N) = real(pump_new);
        pump(N+1:2*N,1:N) = imag(pump_new);
  
        writecell(header,[directoryPath_load,'pump_plus.txt'],'Delimiter',' ');
        writematrix(pump,[directoryPath_load,'pump_plus.txt'],'Delimiter',' ','WriteMode','append');

        %% Execute PHOENIX
        str1 = [filename, ' --dw 1 --threads 2 '];  
        str2 = ['--N ',num2str(N),' ',num2str(N),' --L ',num2str(L),' ',num2str(L),' --boundary periodic periodic ']; 
        str3 = ['--tmax ',num2str(tend),' --tstep ',num2str(dt),' '];                                                 
        str4 = ['--pump load ',directoryPath_load,'pump_plus.txt 1 add plus --reservoir load ',directoryPath_load,'reservoir_plus.txt 1 add plus --initialState load ',directoryPath_load,'wavefunction_plus.txt 1 add plus ']; 
        str5 = ['--gammaC ',num2str(gammaC),' --gammaR ',num2str(gammaR),' --gc ',num2str(gc),' --gr ',num2str(gr),' --meff ',num2str(mc),' --hbarscaled ',num2str(hbar),' --R ',num2str(R),' '];
        str6 = ['--historyMatrix 0 ',num2str(N),' 0 ',num2str(N),' 1 --output wavefunction --outEvery ',num2str(tsave),' --path ',directoryPath_result];

        % execute PHOENIX
        inputstr = [str1,str2,str3,str4,str5,str6];
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
        % post-processing: save data for evaluation of the quantum coherence, the correlation function and mean and variance of averaged polariton excitation number 
        projectdir = [directoryPath_result,'timeoutput/'];
        dinfo = dir( fullfile(projectdir, 'wavefunction*.txt'));
        nfiles = length(dinfo); 
        filenames = fullfile(projectdir, {dinfo.name});
        navPsi = zeros(N^2, nfiles-tav/tsave+1);        

        thisdata = readmatrix([directoryPath_load,'wavefunction_plus.txt']);
        psi_k = reshape(thisdata(1:N,:)+1i*thisdata(N+1:2*N,:),N^2,1);
        navPsi(:,1) = psi_k; 

        for K =1 : nfiles-tav/tsave
            thisfile = [directoryPath_result,'timeoutput/wavefunction_plus_',num2str((K+tav/tsave)*tsave),'.000000.txt'];
            thisdata = readmatrix(thisfile);
            psi_k = reshape(thisdata(1:N,:)+1i*thisdata(N+1:2*N,:),N^2,1);
            navPsi(:,K+1) = psi_k; 
            maxn(K) = max(max(abs(psi_k).^2));
        end

        name = strcat('Broad',string(k),'_Pump',string(MultP(1,j)));
        save(strcat(directoryPath_postprocess,name,'.mat'),'-v7.3',"navPsi","N","L","tend","dt","tsave","tav","gammaR","gammaC","R","gc","gr");

    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Post-processing
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% this part of the code determines the quantum coherence, the correlation function and mean and variance of averaged polariton excitation number 

kx = -2*pi/(2*dxy):2*pi/L:2*pi/(2*dxy);
                                          
DirName=directoryPath_postprocess;                                                       
PsiName="navPsi";

QCplt=zeros(1,length(MultP));                                              
g2plt=zeros(1,length(MultP));
g2anplt=zeros(1,length(MultP));
ncplt=zeros(1,length(MultP));
dnc2plt=zeros(1,length(MultP));

for m=1:length(MultP)                                                       
    %% Average berechnen
    AvPsi=zeros(N^2,tend/tsave+1);                                      
    Avk2=zeros(N^2,tend/tsave+1);                                       
    Avk4=zeros(N^2,tend/tsave+1);
    for j=1:Nj
        DataName=strcat('Broad',string(j),'_Pump',string(MultP(1,m)),'.mat');  
        load(strcat(DirName,DataName),PsiName);                              
        Psi=eval(PsiName);
        AvPsi = AvPsi+abs(Psi).^2;                                         
        temp=zeros(N^2,tend/tsave+1);
        for i=1:tend/tsave+1
            temp(:,i)=reshape(abs(fftshift(fft2(reshape(Psi(:,i),N,N)))*dV/L-0.5).^2,N^2,1);    
        end
        Avk2 = Avk2+temp;                                                   
        Avk4 = Avk4+temp.^2;
     
    end
    AvPsi=sum(AvPsi(:,tav/tsave+1:end),2)/(Nj*((tend-tav)/tsave+1));    
    Avk2=sum(Avk2(:,tav/tsave+1:end),2)/(Nj*((tend-tav)/tsave+1));
    Avk4=sum(Avk4(:,tav/tsave+1:end),2)/(Nj*((tend-tav)/tsave+1));
    save(strcat(DirName,'AvData_Pump',string(MultP(1,m)),'.mat'),"Avk4","AvPsi","Avk2");

    %% Quatum Coherence berechnen
    load(strcat(DirName,'AvData_Pump',string(MultP(1,m)),'.mat'),"Avk4","Avk2");
    
    if mod(N,2)==0                                                     
        middle=N/2;
    else
        middle=floor(N/2)+1;
    end
    
    temp=reshape(Avk2,N,N);                                             
    for i=middle+1:N
        if temp(i,middle)<250
            rk=kx(1,i+1);
            break
        end
    end

    Np=0;                                                               
    for i=1:N^2
        if sqrt(kx(1,getx(i,N))^2+kx(1,gety(i,N))^2)<=rk
            Np=Np+1;
        end
    end
    
    k2=zeros(Np,1);                                                    
    k4=zeros(Np,1);
    countk=1;
    for i=1:N^2
        if sqrt(kx(1,getx(i,N))^2+kx(1,gety(i,N))^2)<=rk
            k2(countk,1)=Avk2(i,1);
            k4(countk,1)=Avk4(i,1);
            countk=countk+1;
        end
    end

    nc=sum(k2-0.5)/Np;                                                 
    dnc2=(sum(k4-k2)-sum((k2-0.5).^2))/Np;
    alpha02=sqrt(nc^2+nc-dnc2);
    nbar=nc-alpha02;
    besen=besseli(0,(2*alpha02)/((nbar+1)^2-nbar^2));
    g2=1+(dnc2-nc)/(nc^2);
    g2an=2-(1+(nbar/alpha02))^(-2);
    Qc=(1-exp(-(2*alpha02)/((nbar+1)^2-nbar^2))*besen)/((nbar+1)^2-nbar^2);
    
    save(strcat(DirName,'AvData_Pump',string(MultP(1,m)),'.mat'),"Qc","g2","g2an","nc","dnc2","alpha02","nbar",'-append');

    QCplt(1,m)=Qc;
    g2plt(1,m)=g2; 
    g2anplt(1,m)=g2an;
    ncplt(1,m)=nc;
    dnc2plt(1,m)=dnc2;
end

F1=figure;
set(gcf,'Position',[100 300 1500 1500],'Color','w');

figure(F1);
subplot(2,2,3);
plot(MultP,QCplt(1,:),'Color','b','LineWidth',2.5);
ylabel('Quantum Coherence $\mathcal{C}$','Interpreter','latex','FontSize',20); xlabel('$P_0 [P_{thr}]$','Interpreter','latex','FontSize',20);
subplot(2,2,4);
plot(MultP,g2plt(1,:),'Color','b','LineWidth',2.5); hold on;
plot(MultP,g2anplt(1,:),'Color','r','LineStyle','--','LineWidth',2.5); hold off;
ylabel('$g^{(2)}$-Function','Interpreter','latex','FontSize',20); xlabel('$P_0 [P_{thr}]$','Interpreter','latex','FontSize',20); legend('$g^{(2)}$ aus $\langle n_c\rangle, \langle(\Delta n_c)^2\rangle$','$g^{(2)}$ aus $\overline{n}, |\alpha_0|^2$','Interpreter','latex','FontSize',20)
subplot(2,2,2);
semilogy(MultP,ncplt(1,:),'Color','b','LineWidth',2.5); hold on;
semilogy(MultP,dnc2plt(1,:),'Color','r','LineWidth',2.5); hold off;
xlabel('$P_0 [P_{thr}]$','Interpreter','latex','FontSize',20); legend('$\langle n_c\rangle$','$\langle(\Delta n_c)^2\rangle$','Interpreter','latex','FontSize',20)

for m=1:length(MultP)
    load(strcat(DirName,'AvData_Pump',string(MultP(1,m)),'.mat'),"AvPsi","Avk2");
    figure(F1);
    subplot(2,2,1);
    surf(x,x,reshape(AvPsi,N,N)); colormap(flipud(gray)); shading interp; pbaspect([1 1 1]); axis([x(1,1) x(1,end) x(1,1) x(1,end)]); view([0 90]); CO=colorbar; box on;
    ylabel('$y [\mu m]$','Interpreter','latex','FontSize',20); xlabel('$x [\mu m]$','Interpreter','latex','FontSize',20); ylabel(CO,'$\overline{|\Psi|^2} [\mu m^{-2}]$','Interpreter','latex','FontSize',20,'Rotation',270); title('$\overline{|\Psi|^2}$ in Real-Space','Interpreter','latex','FontSize',20);
    subplot(2,2,3);
    plot(MultP,QCplt(1,:),'Color','b','LineWidth',2.5); hold on;
    scatter(MultP(1,m),QCplt(1,m),125,'red','x','LineWidth',1.5); hold off;
    ylabel('Quantum Coherence $\mathcal{C}$','Interpreter','latex','FontSize',20); xlabel('$P_0 [P_{thr}]$','Interpreter','latex','FontSize',20); legend('$\mathcal{C}$','current Data-Set','Interpreter','latex','FontSize',20,'Location','southeast')
    saveas(F1,strcat(DirName,'Bilder/Skala_MultP',string(MultP(1,m)),'.png'));
    subplot(2,2,1);
    surf(kx,kx,reshape(Avk2,N,N)); colormap(flipud(gray)); shading interp; pbaspect([1 1 1]); axis([-1 1 -1 1]); view([0 90]); CO=colorbar; box on; %axis([kx(1,1) kx(1,end) kx(1,1) kx(1,end)]);
    ylabel('$k_y [\frac{1}{\mu m}]$','Interpreter','latex','FontSize',20); xlabel('$k_x [\frac{1}{\mu m}]$','Interpreter','latex','FontSize',20); title('$\overline{|\Psi|^2}$ in k-Space','Interpreter','latex','FontSize',20); %ylabel(CO,'$\overline{|\Psi|^2} [\mu m^{-2}]$','Interpreter','latex','FontSize',20,'Rotation',270);
    saveas(F1,strcat(DirName,'Bilder/Skala_kS_MultP',string(MultP(1,m)),'.png'));
end

function cleanedString = removeAnsiCodes(inputString)
% Use regexprep to remove ANSI escape codes
cleanedString = strrep(inputString, '[90m#[0m', ' ');
cleanedString = regexprep(cleanedString, '\[0m|\[1m|\[2m|\[3m|\[4m|\[30m|\[31m|\[32m|\[33m|\[34m|\[35m|\[36m|\[37m|[93m|\[94m|\[?25h|\[2K|\[?25l|\[90m|\[A', '');
end

function ret=gety(i,N)
    ret = floor((i-1)/N)+1;
end
function ret=getx(i,N)
    ret = mod(i-1,N)+1;
end        
