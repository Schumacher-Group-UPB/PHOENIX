#pragma once

#include <iostream>
#include <sstream>
#include <iomanip>
#include "solver/gpu_solver.hpp"
#include "misc/commandline_io.hpp"
#include "cuda/cuda_matrix.cuh"

#ifdef SFML_RENDER
    #include <SFML/Graphics.hpp>
    #include <SFML/Window.hpp>
    #include "sfml_window.hpp"
    #include "colormap.hpp"
#endif

/*
 * The solver can be rendered using the SFML library, which is a very simple and easy to use library,
 * which we use to implement different methods to plot the solver in real time.
 *
 * The Plus and Minus Components are always plotted seperately in different rows.
 * Default: Plot Psi and Reservoir with inset
 * The inset can be switched by pressing 'i' in the SFML window.
 * The inset then cycles between the FFT, logscale FFT, Quantum Noise
 *
 * This plot "helper" is an abomination by itself and will probably be replaced by a more sophisticated
 * plotting library in the future such as QT.
 *
 * TODO: merke this header with the sfml_window class.
 */

namespace PHOENIX {

std::string toScientific( const Type::real in ) {
    std::stringstream ss;
    ss << std::scientific << std::setprecision( 2 ) << in;
    return ss.str();
}

#ifdef SFML_RENDER

BasicWindow& getWindow() {
    static BasicWindow window;
    return window;
}

PHOENIX::Type::host_vector<Type::complex> __plotarray;
PHOENIX::Type::host_vector<Type::complex> snapshot_wavefunction_plus, snapshot_wavefunction_minus, snapshot_reservoir_plus, snapshot_reservoir_minus;

template <typename T>
void plot( PHOENIX::CUDAMatrix<T>& matrix, bool angle, int N_cols, int N_rows, int posX, int posY, int skip, ColorPalette& cp, const std::string& title = "", bool plot_min_max = true ) {
    T min, max;
    if ( angle ) {
        __plotarray = matrix.staticAngle( true ).getFullMatrix();
        min = -3.1415926535;
        max = 3.1415926535;
    } else {
        std::tie( min, max ) = matrix.extrema();
        min = PHOENIX::CUDA::abs2( min );
        max = PHOENIX::CUDA::abs2( max );
        __plotarray = matrix.staticCWiseAbs2( true ).getFullMatrix();
    }
    getWindow().blitMatrixPtr( __plotarray.data(), min, max, cp, N_cols, N_rows, posX, posY, 1 /*border*/, skip );
    if ( !plot_min_max )
        return;
    N_cols = N_cols / skip;
    N_rows = N_rows / skip;
    auto text_height = getWindow().textheight / skip;
    getWindow().scaledPrint( posX + 5, posY + N_rows - text_height - 5, text_height, title + "Min: " + toScientific( std::sqrt( PHOENIX::CUDA::abs( min ) ) ) + " Max: " + toScientific( std::sqrt( PHOENIX::CUDA::abs( max ) ) ), sf::Color::White );
}

// Very bad practice, as this header can only be imported once without redefinitions.
// TODO: make this into a class like a normal friggin programmer.
ColorPalette __local_colorpalette_phase;
ColorPalette __local_colorpalette;

CheckBox cb_toggle_fft;
CheckBox cb_min_and_max;
Button b_add_outevery;
Button b_sub_outevery;
Button b_add_dt;
Button b_sub_dt;
Button b_snapshot;
Button b_reset_to_snapshot;
Button b_reset_to_initial;
Button b_cycle_subplot;
double snapshot_time = 0.0;
size_t current_subplot = 0;

void initSFMLWindow( PHOENIX::Solver& solver ) {
    if ( solver.system.disableRender ) {
        std::cout << PHOENIX::CLIO::prettyPrint( "Manually disabled SFML Renderer!", PHOENIX::CLIO::Control::Warning ) << std::endl;
        return;
    }
    if ( solver.system.use_twin_mode )
        getWindow().construct( 1920, 1080, solver.system.p.N_c * 3, solver.system.p.N_r * 2, "PHOENIX_ v0.3.0-alpha" );
    else
        getWindow().construct( 1920, 540, solver.system.p.N_c * 3, solver.system.p.N_r, "PHOENIX_ v0.3.0-alpha" );

    // if .pal in __local_colorpalette, read gnuplot __local_colorpalette, else read as .txt
    if ( solver.system.filehandler.color_palette.find( ".pal" ) != std::string::npos ) {
        __local_colorpalette.readColorPaletteFromGnuplotDOTPAL( solver.system.filehandler.color_palette );
        __local_colorpalette_phase.readColorPaletteFromGnuplotDOTPAL( solver.system.filehandler.color_palette_phase );
    } else if ( solver.system.filehandler.color_palette.find( ".txt" ) != std::string::npos ) {
        __local_colorpalette.readColorPaletteFromTXT( solver.system.filehandler.color_palette );
        __local_colorpalette_phase.readColorPaletteFromTXT( solver.system.filehandler.color_palette_phase );
    } else {
        __local_colorpalette.readColorPaletteFromTXT( "resources/" + solver.system.filehandler.color_palette + ".txt" );
        __local_colorpalette_phase.readColorPaletteFromTXT( "resources/" + solver.system.filehandler.color_palette_phase + ".txt" );
    }
    __local_colorpalette.initColors();
    __local_colorpalette_phase.initColors();
    getWindow().init();

    cb_toggle_fft = CheckBox( 10, 50, "Toggle FFT Plot", false );
    getWindow().addObject( &cb_toggle_fft );
    cb_min_and_max = CheckBox( 10, 80, "Toggle Min/Max", false );
    getWindow().addObject( &cb_min_and_max );
    b_add_outevery = Button( 10, 150, "Increase" );
    getWindow().addObject( &b_add_outevery );
    b_sub_outevery = Button( 10, 180, "Decrease" );
    getWindow().addObject( &b_sub_outevery );
    b_add_dt = Button( 10, 250, "Increase dt" );
    getWindow().addObject( &b_add_dt );
    b_sub_dt = Button( 10, 280, "Decrease dt" );
    getWindow().addObject( &b_sub_dt );
    b_snapshot = Button( 10, 380, "Snapshot" );
    getWindow().addObject( &b_snapshot );
    b_reset_to_snapshot = Button( 10, 410, "Reset to Snapshot" );
    getWindow().addObject( &b_reset_to_snapshot );
    b_reset_to_initial = Button( 10, 440, "Reset to Initial" );
    getWindow().addObject( &b_reset_to_initial );
    b_cycle_subplot = Button( 10, 480, "Cycle Subplot" );
    getWindow().addObject( &b_cycle_subplot );
}

int __local_inset = 0;

std::vector<std::string> subplot_names{ "FFT - ", "Wavefunction K1 - ", "Wavefunction K2 - ", "Wavefunction K3 - ", "Wavefunction K4 - ", "Reservoir K1 - ", "Reservoir K2 - ", "Reservoir K3 - ", "Reservoir K4 - ", "Pump - ", "Pulse - ", "Potential - ", "RandomNumber - " };

bool plotSFMLWindow( PHOENIX::Solver& solver, double simulation_time, double elapsed_time, size_t iterations ) {
    if ( solver.system.disableRender )
        return true;
    bool running = getWindow().run();

    //Type::complex *inset_plot_array_plus = nullptr, *inset_plot_array_minus = nullptr;
    //TODO: change to hold a raw pointer to the device memory
    //if ( __local_inset == 1 ) {
    //    std::vector<PHOENIX::CUDAMatrix<Type::complex>*> subplots{ &solver.matrix.fft_plus,
    //                                                            &solver.matrix.k1_wavefunction_plus, &solver.matrix.k2_wavefunction_plus, &solver.matrix.k3_wavefunction_plus, &solver.matrix.k4_wavefunction_plus,
    //                                                            &solver.matrix.k1_reservoir_plus, &solver.matrix.k2_reservoir_plus, &solver.matrix.k3_reservoir_plus, &solver.matrix.k4_reservoir_plus,
    //                                                            &solver.matrix.pump_plus, &solver.matrix.pulse_plus, &solver.matrix.potential_plus, &solver.matrix.random_number };
    //    inset_plot_array_plus = subplots[current_subplot]->deviceToHostSync().getHostPtr();
    //    if ( solver.system.use_twin_mode ) {
    //        std::vector<PHOENIX::CUDAMatrix<Type::complex>*> subplots{ &solver.matrix.fft_minus,
    //                                                                &solver.matrix.k1_wavefunction_minus, &solver.matrix.k2_wavefunction_minus, &solver.matrix.k3_wavefunction_minus, &solver.matrix.k4_wavefunction_minus,
    //                                                                &solver.matrix.k1_reservoir_minus, &solver.matrix.k2_reservoir_minus, &solver.matrix.k3_reservoir_minus, &solver.matrix.k4_reservoir_minus,
    //                                                                &solver.matrix.pump_minus, &solver.matrix.pulse_minus, &solver.matrix.potential_minus, &solver.matrix.random_number };
    //        inset_plot_array_minus = subplots[current_subplot]->deviceToHostSync().getHostPtr();
    //    }
    //}
    if ( getWindow().keyPressed( BasicWindow::KEY_i ) ) {
        __local_inset = ( __local_inset + 1 ) % 2;
    }

    if ( cb_toggle_fft.isChecked() )
        __local_inset = 1;
    else
        __local_inset = 0;

    bool plot_min_max = cb_min_and_max.isChecked();
    // Plot WF Plus
    plot( solver.matrix.wavefunction_plus, false, solver.system.p.N_c, solver.system.p.N_r /*size*/, solver.system.p.N_c, 0, 1, __local_colorpalette, "Psi+ ", plot_min_max );
    // Plot it again without static synchronization
    plot( solver.matrix.wavefunction_plus, true, solver.system.p.N_c, solver.system.p.N_r, 0, 0, 1, __local_colorpalette_phase, "ang(Psi+) ", plot_min_max );
    // Plot Reservoir Plus
    if ( solver.system.use_reservoir )
        plot( solver.matrix.reservoir_plus, false, solver.system.p.N_c, solver.system.p.N_r /*size*/, 2 * solver.system.p.N_c, 0, 1, __local_colorpalette, "n+ ", plot_min_max );

    // Plot Minus
    if ( solver.system.use_twin_mode ) {
        // Plot WF Minus
        plot( solver.matrix.wavefunction_minus, false, solver.system.p.N_c, solver.system.p.N_r /*size*/, solver.system.p.N_c, solver.system.p.N_r, 1, __local_colorpalette, "Psi+ ", plot_min_max );
        // Plot it again without static synchronization
        plot( solver.matrix.wavefunction_minus, true, solver.system.p.N_c, solver.system.p.N_r, 0, solver.system.p.N_r, 1, __local_colorpalette_phase, "ang(Psi+) ", plot_min_max );
        // Plot Reservoir Minus
        if ( solver.system.use_reservoir )
            plot( solver.matrix.reservoir_minus, false, solver.system.p.N_c, solver.system.p.N_r /*size*/, 2 * solver.system.p.N_c, solver.system.p.N_r, 1, __local_colorpalette, "n+ ", plot_min_max );
    }

    const auto ps_per_second = simulation_time / elapsed_time;
    const auto iterations_per_second = iterations / elapsed_time;

    // FPS and ps/s
    getWindow().print( 5, 5, "t = " + std::to_string( int( solver.system.p.t ) ) + ", FPS: " + std::to_string( int( getWindow().fps ) ) + ", ps/s: " + std::to_string( int( ps_per_second ) ) + ", it/s: " + std::to_string( int( iterations_per_second ) ), sf::Color::White );

    // If the mouse position is less than 200 on the x axis, draw the gui. else, set all gui components invisible
    if ( getWindow().MouseX() < 200 ) {
        getWindow().drawRect( 0, 300, 0, getWindow().height, sf::Color( 0, 0, 0, 180 ), true );
        for ( auto& obj : getWindow().objects ) {
            obj->visible = true;
        }
        getWindow().print( 10, 120, "Out Every: " + std::to_string( solver.system.output_every ) + "ps" );
        getWindow().print( 10, 220, "dt: " + std::to_string( solver.system.p.dt ) + "ps" );

        // Draw Quick and dirty progressbar because why not.
        double progress = solver.system.p.t / solver.system.t_max;
        getWindow().drawRect( 10, 180, 310, 335, sf::Color( 50, 50, 50 ), true );
        getWindow().drawRect( 13, 13 + 164 * progress, 313, 332, sf::Color( 36, 114, 234, 255 ), true );

    } else {
        for ( auto& obj : getWindow().objects ) {
            obj->visible = false;
        }
    }

    if ( b_add_outevery.isToggled() ) {
        if ( solver.system.output_every == 0.0 )
            solver.system.output_every = solver.system.p.dt;
        solver.system.output_every *= 2;
    }
    if ( b_sub_outevery.isToggled() ) {
        solver.system.output_every /= 2;
    }

    if ( b_add_dt.isToggled() ) {
        solver.system.p.dt *= 1.1;
    }
    if ( b_sub_dt.isToggled() ) {
        solver.system.p.dt /= 1.1;
    }

    if ( b_snapshot.isToggled() ) {
        // Copy the current state of the host wavefunction to the snapshot
        snapshot_wavefunction_plus = solver.matrix.wavefunction_plus.toFull().getFullMatrix();
        snapshot_reservoir_plus = solver.matrix.reservoir_plus.toFull().getFullMatrix();
        if ( solver.system.use_twin_mode ) {
            snapshot_wavefunction_minus = solver.matrix.wavefunction_minus.toFull().getFullMatrix();
            snapshot_reservoir_minus = solver.matrix.reservoir_minus.toFull().getFullMatrix();
        }
        snapshot_time = solver.system.p.t;

        std::cout << PHOENIX::CLIO::prettyPrint( "Snapshot taken!", PHOENIX::CLIO::Control::Info ) << std::endl;
    }

    if ( b_reset_to_snapshot.isToggled() ) {
        // Copy the contents of the snapshot back to the host wavefunction and sync the host matrix to the device.
        solver.matrix.wavefunction_plus.setTo( snapshot_wavefunction_plus ).hostToDeviceSync();
        solver.matrix.reservoir_plus.setTo( snapshot_reservoir_plus ).hostToDeviceSync();
        if ( solver.system.use_twin_mode ) {
            solver.matrix.wavefunction_minus.setTo( snapshot_wavefunction_minus ).hostToDeviceSync();
            solver.matrix.reservoir_minus.setTo( snapshot_reservoir_minus ).hostToDeviceSync();
        }
        solver.system.p.t = snapshot_time;
        std::cout << PHOENIX::CLIO::prettyPrint( "Reset to Snapshot!", PHOENIX::CLIO::Control::Info ) << std::endl;
    }

    if ( b_reset_to_initial.isToggled() ) {
        solver.matrix.wavefunction_plus.setTo( solver.matrix.initial_state_plus ).hostToDeviceSync();
        solver.matrix.reservoir_plus.setTo( solver.matrix.initial_reservoir_plus ).hostToDeviceSync();
        if ( solver.system.use_twin_mode ) {
            solver.matrix.wavefunction_minus.setTo( solver.matrix.initial_state_minus ).hostToDeviceSync();
            solver.matrix.reservoir_minus.setTo( solver.matrix.initial_reservoir_minus ).hostToDeviceSync();
        }
        solver.system.p.t = 0.0;
        std::cout << PHOENIX::CLIO::prettyPrint( "Reset to Initial!", PHOENIX::CLIO::Control::Info ) << std::endl;
    }

    if ( b_cycle_subplot.isToggled() ) {
        current_subplot = ( current_subplot + 1 ) % subplot_names.size();
    }

    getWindow().drawObjects();

    // Blit
    getWindow().flipscreen();
    return running;
}

#else
void initSFMLWindow( PHOENIX::Solver& solver ) {};
bool plotSFMLWindow( PHOENIX::Solver& solver, double simulation_time, double elapsed_time, size_t iterationsd ) {
    return true;
};
#endif

} // namespace PHOENIX