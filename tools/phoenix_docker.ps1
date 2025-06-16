[PowerTypeDictionary]@{
    Keys        = @("phoenix", "phoenix-cpu", "phoenix-gpu");
    Name        = "PHOENIX";
    Description = "A high-performance solver for the 2D nonlinear Schroedinger equation.";
    Platforms   = [Platforms]::All;
    State       = [DictionaryState]::Experimental -bor [DictionaryState]::Incomplete;
    Source      = "PHOENIX: A High-Performance Solver for the Gross-Pitaevskii Equation";
    Url         = "https://github.com/Schumacher-Group-UPB/PHOENIX";
    Parameters  = @(
        [CommandParameter]@{
            Name        = "cpu/gpu";
            Keys        = @("cpu", "gpu");
            Description = "Run a simulation using PHOENIX with the specified parameters.";
            Parameters  = @(

                # Path and Configuration
                [ValueParameter]@{ 
                    Keys = @("--path"); 
                    Name = "path"; 
                    Description = "Output directory for simulation data."; 
                },
                [ValueParameter]@{ 
                    Keys = @("--config"); 
                    Name = "config"; 
                    Description = "Configuration file(s) to load.";
                },

                # Output
                [ValueParameter]@{ 
                    Keys = @("--output"); 
                    Name = "output"; 
                    Description = "Comma-separated list of output keys.";
                },
                [ValueParameter]@{ 
                    Keys = @("--outEvery"); 
                    Name = "outEvery"; 
                    Description = "Interval (ps) between outputs.";
                },
                [ValueParameter]@{ 
                    Keys = @("--outputFileType"); 
                    Name = "outputFileType"; 
                    Description = "Format of output files, e.g., 'npy'.";
                    Source = [StaticSource]@{
                        Name = "File mode";
                        Description = "";
                        Items = @(
                            [SourceItem]@{
                                Name = "txt";
                                Description = "Uses human readable .txt format. Slow."
                            },
                            [SourceItem]@{
                                Name = "npy";
                                Description = "Uses binary numpy format."
                            },
                            [SourceItem]@{
                                Name = "ash";
                                Description = "Similar to npy, but stores aligned instead of interleaved real and imaginary parts."
                            }
                        )
                    }
                },

                # Grid and Time Settings
                [ValueParameter]@{ 
                    Keys = @("--N", "--gridsize"); 
                    Name = "grid size"; 
                    Description = "Spatial grid dimensions.";
                },
                [ValueParameter]@{ 
                    Keys = @("--subgrids", "--sg"); 
                    Name = "subgrids"; 
                    Description = "Subgrid layout for parallelization.";
                },
                [ValueParameter]@{ 
                    Keys = @("--L", "--gridlength", "--xmax"); 
                    Name = "system size"; 
                    Description = "Physical dimensions of the system.";
                },
                [ValueParameter]@{ 
                    Keys = @("--tmax", "--tend"); 
                    Name = "tmax"; 
                    Description = "Maximum simulation time (ps).";
                },
                [ValueParameter]@{ 
                    Keys = @("--tstep", "--dt"); 
                    Name = "timestep"; 
                    Description = "Simulation timestep (ps).";
                },
                [FlagParameter]@{ 
                    Keys = @("-adaptive", "-adaptiveTimestep"); 
                    Name = "adaptive timestep"; 
                    Description = "Enable adaptive timestep if available.";
                },
                [ValueParameter]@{ 
                    Keys = @("--rkvdt"); 
                    Name = "rkvdt"; 
                    Description = "Minimum and maximum timestep for adaptive iterator.";
                },
                [ValueParameter]@{ 
                    Keys = @("--tol"); 
                    Name = "tolerance"; 
                    Description = "Tolerance for adaptive timestep.";
                },

                # Iteration
                [ValueParameter]@{ 
                    Keys = @("--iterator"); 
                    Name = "iterator"; 
                    Description = "Integration method for time evolution.";
                },

                # History
                [ValueParameter]@{ 
                    Keys = @("--historyMatrix"); 
                    Name = "historyMatrix"; 
                    Description = "Matrix history output settings.";
                },
                [ValueParameter]@{ 
                    Keys = @("--historyTime"); 
                    Name = "historyTime"; 
                    Description = "Time-based matrix output control.";
                },

                # Physics Parameters
                [ValueParameter]@{ 
                    Keys = @("--gammaC", "--gamma_C", "--gammac", "--gamma_c"); 
                    Name = "gammaC"; 
                    Description = "Wavefunction damping coefficient.";
                },
                [ValueParameter]@{ 
                    Keys = @("--gammaR", "--gamma_R", "--gamma_r", "--gammar"); 
                    Name = "gammaR"; 
                    Description = "Reservoir damping coefficient.";
                },
                [ValueParameter]@{ 
                    Keys = @("--gc", "--g_c"); 
                    Name = "gc"; 
                    Description = "Nonlinear interaction coefficient (wavefunction).";
                },
                [ValueParameter]@{ 
                    Keys = @("--gr", "--g_r"); 
                    Name = "gr"; 
                    Description = "Nonlinear interaction coefficient (reservoir).";
                },
                [ValueParameter]@{ 
                    Keys = @("--R"); 
                    Name = "R"; 
                    Description = "Relaxation rate for the wavefunction.";
                },
                [ValueParameter]@{ 
                    Keys = @("--g_pm", "--g_PM", "--gpm"); 
                    Name = "g_pm"; 
                    Description = "TE/TM splitting coefficient.";
                },
                [ValueParameter]@{ 
                    Keys = @("--deltaLT", "--delta_LT", "--deltalt", "--dlt"); 
                    Name = "deltaLT"; 
                    Description = "TE/TM splitting energy difference.";
                },
                [FlagParameter]@{ 
                    Keys = @("-tetm"); 
                    Name = "tetm"; 
                    Description = "Enable TE/TM splitting.";
                },

                # Initial State
                [ValueParameter]@{ 
                    Keys = @("--initRandom", "--iR"); 
                    Name = "initRandom"; 
                    Description = "Randomly initialize Psi with amplitude and seed.";
                },
                [ValueParameter]@{ 
                    Keys = @("--fftEvery"); 
                    Name = "fftEvery"; 
                    Description = "FFT mask application frequency.";
                },

                # SI and Scaled Constants
                [ValueParameter]@{ 
                    Keys = @("--hbar"); 
                    Name = "hbar"; 
                    Description = "Planck constant (SI units).";
                },
                [ValueParameter]@{ 
                    Keys = @("--e", "--electron_charge"); 
                    Name = "e"; 
                    Description = "Electron charge (SI units).";
                },
                [ValueParameter]@{ 
                    Keys = @("--m_e", "--me", "--electron_mass"); 
                    Name = "m_e"; 
                    Description = "Electron mass (SI units).";
                },
                [ValueParameter]@{ 
                    Keys = @("--m_eff", "--meff"); 
                    Name = "m_eff"; 
                    Description = "Effective mass (scaled).";
                },
                [ValueParameter]@{ 
                    Keys = @("--hbar_scaled", "--hbarscaled", "--hbars"); 
                    Name = "hbar_scaled"; 
                    Description = "Scaled Planck constant.";
                },

                # Boundary
                [ValueParameter]@{ 
                    Keys = @("--boundary"); 
                    Name = "boundary"; 
                    Description = "Boundary conditions for x and y directions.";
                },

                # Time Control
                [ValueParameter]@{ 
                    Keys = @("--imagTime"); 
                    Name = "imagTime"; 
                    Description = "Use imaginary time propagation with normalization.";
                },
                [ValueParameter]@{ 
                    Keys = @("--t0"); 
                    Name = "t0"; 
                    Description = "Initial time of simulation.";
                },

                # Envelopes
                [CommandParameter]@{ 
                    Keys = @("--pump"); 
                    Name = "pump"; 
                    Description = "Define pump envelope (supports spatial and temporal forms).";
                },
                [CommandParameter]@{ 
                    Keys = @("--pulse"); 
                    Name = "pulse"; 
                    Description = "Define pulse envelope (spatial and temporal).";
                },
                [CommandParameter]@{ 
                    Keys = @("--potential"); 
                    Name = "potential"; 
                    Description = "Define potential envelope (spatial and temporal).";
                },
                [CommandParameter]@{ 
                    Keys = @("--fftMask"); 
                    Name = "fftMask"; 
                    Description = "Define FFT mask envelope (spatial only).";
                },
                [CommandParameter]@{ 
                    Keys = @("--initialState", "--initState", "--iS"); 
                    Name = "initialState"; 
                    Description = "Define initial state envelope.";
                },
                [CommandParameter]@{ 
                    Keys = @("--initialReservoir", "--initReservoir"); 
                    Name = "initialReservoir"; 
                    Description = "Define initial reservoir envelope.";
                },

                # Stochastic
                [ValueParameter]@{ 
                    Keys = @("--dw"); 
                    Name = "dw"; 
                    Description = "Stochastic noise amplitude.";
                },

                # Render / Visual
                [FlagParameter]@{ 
                    Keys = @("-nosfml", "-norender"); 
                    Name = "disable rendering"; 
                    Description = "Disable SFML visualization.";
                },

                # Threading
                [ValueParameter]@{ 
                    Keys = @("--threads"); 
                    Name = "threads"; 
                    Description = "Number of OpenMP threads to use.";
                },
                [ValueParameter]@{ 
                    Keys = @("--blocksize"); 
                    Name = "blocksize"; 
                    Description = "Block size for computation.";
                },

                # Reservoir Control
                [FlagParameter]@{ 
                    Keys = @("-noReservoir"); 
                    Name = "noReservoir"; 
                    Description = "Disable reservoir usage.";
                 }
            );
        }
    )
}