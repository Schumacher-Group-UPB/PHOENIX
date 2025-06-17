#pragma once

#include <iostream>
#include <sstream>
#include <iomanip>
#include <complex>
#include "solver/solver.hpp"
#include "misc/commandline_io.hpp"
#include "cuda/cuda_matrix.cuh"

#ifdef SFML_RENDER
    #include <SFML/Graphics.hpp>
    #include <SFML/Window.hpp>
    #include "misc/sfml_window.hpp"
    #include "misc/colormap.hpp"
    #include "resources/vik.hpp"
    #include "resources/viko.hpp"
#endif

namespace PHOENIX {

class PhoenixGUI {
public:
    explicit PhoenixGUI(Solver& solver);
    void init();
    bool update(double simulation_time, double elapsed_time, size_t iterations);

private:
    Solver& solver_;
    #ifdef SFML_RENDER
    BasicWindow window_;
    ColorPalette color_phase_, color_amp_;

    // GUI Controls
    CheckBox cb_toggle_fft_, cb_min_and_max_;
    Button b_add_outevery_, b_sub_outevery_;
    Button b_add_dt_, b_sub_dt_;
    Button b_snapshot_, b_reset_to_snapshot_;
    Button b_reset_to_initial_, b_cycle_subplot_;
    
    // Snapshot data
    double snapshot_time_ = 0.0;
    Type::host_vector<Type::complex> snapshot_wavefunction_plus_, snapshot_wavefunction_minus_;
    Type::host_vector<Type::complex> snapshot_reservoir_plus_, snapshot_reservoir_minus_;
    
    // Internal state
    int inset_mode_ = 0;
    size_t current_subplot_ = 0;
    Type::host_vector<Type::complex> plot_array_;
    #endif

    static std::string toScientific(Type::real in);
    #ifdef SFML_RENDER
    template <typename T>
    void plot(CUDAMatrix<T>& matrix, bool angle, int N_cols, int N_rows, int posX, int posY, int skip, ColorPalette& cp, const std::string& title, bool plot_min_max) {
        T min, max;
        if (angle) {
            plot_array_ = matrix.staticAngle(true).getFullMatrix();
            min = -3.1415926535;
            max = 3.1415926535;
        } else {
            std::tie(min, max) = matrix.extrema();
            min = CUDA::abs2(min);
            max = CUDA::abs2(max);
            plot_array_ = matrix.staticCWiseAbs2(true).getFullMatrix();
        }
        window_.blitMatrixPtr(plot_array_.data(), min, max, cp, N_cols, N_rows, posX, posY, 1, skip);

        if (plot_min_max) {
            int cols = N_cols / skip;
            int rows = N_rows / skip;
            int text_height = window_.textheight / skip;
            window_.scaledPrint(posX + 5, posY + rows - text_height - 5, text_height,
                title + "Min: " + toScientific(std::sqrt(CUDA::abs(min))) +
                " Max: " + toScientific(std::sqrt(CUDA::abs(max))), sf::Color::White);
        }
    }
    #else
    template <typename T>
    void plot(CUDAMatrix<T>& matrix, bool angle, int N_cols, int N_rows, int posX, int posY, int skip, ColorPalette& cp, const std::string& title, bool plot_min_max) {}
    #endif
    void setupGUI();
    void handleGUIEvents();
    void drawGUI();
    void handleSnapshots();
};

} // namespace PHOENIX