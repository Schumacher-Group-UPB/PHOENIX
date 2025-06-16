#include "misc/gui.hpp"
#include <cmath>
#include <sstream>
#include <iomanip>

namespace PHOENIX {

PhoenixGUI::PhoenixGUI(Solver& solver)
    : solver_(solver) {
        init();
    }

#ifdef SFML_RENDER

void PhoenixGUI::init() {
    if (solver_.system.disableRender) {
        std::cout << CLIO::prettyPrint("SFML Renderer disabled", CLIO::Control::Warning) << std::endl;
        return;
    }

    int width = solver_.system.use_twin_mode ? 1920 : 1920;
    int height = solver_.system.use_twin_mode ? 1080 : 540;
    int cols = solver_.system.p.N_c * 3;
    int rows = solver_.system.p.N_r * (solver_.system.use_twin_mode ? 2 : 1);

    window_.construct(width, height, cols, rows, "PHOENIX_ v0.3.0-alpha");

    color_amp_.readColorPaletteFromMemory(Misc::Resources::cmap_vik);
    color_phase_.readColorPaletteFromMemory(Misc::Resources::cmap_viko);
    color_amp_.initColors();
    color_phase_.initColors();
    window_.init();

    setupGUI();
}

void PhoenixGUI::setupGUI() {
    cb_toggle_fft_ = CheckBox(10, 50, "Toggle FFT Plot", false);
    cb_min_and_max_ = CheckBox(10, 80, "Toggle Min/Max", false);
    b_add_outevery_ = Button(10, 150, "Increase");
    b_sub_outevery_ = Button(10, 180, "Decrease");
    b_add_dt_ = Button(10, 250, "Increase dt");
    b_sub_dt_ = Button(10, 280, "Decrease dt");
    b_snapshot_ = Button(10, 380, "Snapshot");
    b_reset_to_snapshot_ = Button(10, 410, "Reset to Snapshot");
    b_reset_to_initial_ = Button(10, 440, "Reset to Initial");
    b_cycle_subplot_ = Button(10, 480, "Cycle Subplot");

    window_.addObject(&cb_toggle_fft_);
    window_.addObject(&cb_min_and_max_);
    window_.addObject(&b_add_outevery_);
    window_.addObject(&b_sub_outevery_);
    window_.addObject(&b_add_dt_);
    window_.addObject(&b_sub_dt_);
    window_.addObject(&b_snapshot_);
    window_.addObject(&b_reset_to_snapshot_);
    window_.addObject(&b_reset_to_initial_);
    window_.addObject(&b_cycle_subplot_);
}

bool PhoenixGUI::update(double simulation_time, double elapsed_time, size_t iterations) {
    if (solver_.system.disableRender) return true;

    bool running = window_.run();

    inset_mode_ = cb_toggle_fft_.isChecked() ? 1 : 0;
    bool plot_min_max = cb_min_and_max_.isChecked();

    auto& sys = solver_.system;
    auto& mat = solver_.matrix;

    plot(mat.wavefunction_plus, false, sys.p.N_c, sys.p.N_r, sys.p.N_c, 0, 1, color_amp_, "Psi+ ", plot_min_max);
    plot(mat.wavefunction_plus, true, sys.p.N_c, sys.p.N_r, 0, 0, 1, color_phase_, "ang(Psi+) ", plot_min_max);
    if (sys.use_reservoir)
        plot(mat.reservoir_plus, false, sys.p.N_c, sys.p.N_r, 2 * sys.p.N_c, 0, 1, color_amp_, "n+ ", plot_min_max);

    if (sys.use_twin_mode) {
        plot(mat.wavefunction_minus, false, sys.p.N_c, sys.p.N_r, sys.p.N_c, sys.p.N_r, 1, color_amp_, "Psi- ", plot_min_max);
        plot(mat.wavefunction_minus, true, sys.p.N_c, sys.p.N_r, 0, sys.p.N_r, 1, color_phase_, "ang(Psi-) ", plot_min_max);
        if (sys.use_reservoir)
            plot(mat.reservoir_minus, false, sys.p.N_c, sys.p.N_r, 2 * sys.p.N_c, sys.p.N_r, 1, color_amp_, "n- ", plot_min_max);
    }

    handleGUIEvents();
    handleSnapshots();
    drawGUI();

    const auto ps_per_sec = simulation_time / elapsed_time;
    const auto it_per_sec = iterations / elapsed_time;
    window_.print(5, 5, "t = " + std::to_string(int(sys.p.t)) +
        ", FPS: " + std::to_string(int(window_.fps)) +
        ", ps/s: " + std::to_string(int(ps_per_sec)) +
        ", it/s: " + std::to_string(int(it_per_sec)), sf::Color::White);

    window_.drawObjects();
    window_.flipscreen();

    return running;
}

void PhoenixGUI::handleGUIEvents() {
    auto& sys = solver_.system;

    if (b_add_outevery_.isToggled()) {
        if (sys.output_every == 0.0)
            sys.output_every = sys.p.dt;
        sys.output_every *= 2;
    }

    if (b_sub_outevery_.isToggled())
        sys.output_every /= 2;

    if (b_add_dt_.isToggled())
        sys.p.dt *= 1.1;

    if (b_sub_dt_.isToggled())
        sys.p.dt /= 1.1;

    if (b_cycle_subplot_.isToggled())
        current_subplot_ = (current_subplot_ + 1) % 12; // Update if subplot list changes
}

void PhoenixGUI::handleSnapshots() {
    auto& sys = solver_.system;
    auto& mat = solver_.matrix;

    if (b_snapshot_.isToggled()) {
        snapshot_wavefunction_plus_ = mat.wavefunction_plus.toFull().getFullMatrix();
        snapshot_reservoir_plus_ = mat.reservoir_plus.toFull().getFullMatrix();
        if (sys.use_twin_mode) {
            snapshot_wavefunction_minus_ = mat.wavefunction_minus.toFull().getFullMatrix();
            snapshot_reservoir_minus_ = mat.reservoir_minus.toFull().getFullMatrix();
        }
        snapshot_time_ = sys.p.t;
        std::cout << CLIO::prettyPrint("Snapshot taken!", CLIO::Control::Info) << std::endl;
    }

    if (b_reset_to_snapshot_.isToggled()) {
        mat.wavefunction_plus.setTo(snapshot_wavefunction_plus_).hostToDeviceSync();
        mat.reservoir_plus.setTo(snapshot_reservoir_plus_).hostToDeviceSync();
        if (sys.use_twin_mode) {
            mat.wavefunction_minus.setTo(snapshot_wavefunction_minus_).hostToDeviceSync();
            mat.reservoir_minus.setTo(snapshot_reservoir_minus_).hostToDeviceSync();
        }
        sys.p.t = snapshot_time_;
        std::cout << CLIO::prettyPrint("Reset to Snapshot!", CLIO::Control::Info) << std::endl;
    }

    if (b_reset_to_initial_.isToggled()) {
        mat.wavefunction_plus.setTo(mat.initial_state_plus).hostToDeviceSync();
        mat.reservoir_plus.setTo(mat.initial_reservoir_plus).hostToDeviceSync();
        if (sys.use_twin_mode) {
            mat.wavefunction_minus.setTo(mat.initial_state_minus).hostToDeviceSync();
            mat.reservoir_minus.setTo(mat.initial_reservoir_minus).hostToDeviceSync();
        }
        sys.p.t = 0.0;
        std::cout << CLIO::prettyPrint("Reset to Initial!", CLIO::Control::Info) << std::endl;
    }
}

void PhoenixGUI::drawGUI() {
    if (window_.MouseX() < 200) {
        window_.drawRect(0, 300, 0, window_.height, sf::Color(0, 0, 0, 180), true);
        for (auto& obj : window_.objects)
            obj->visible = true;

        window_.print(10, 120, "Out Every: " + std::to_string(solver_.system.output_every) + "ps");
        window_.print(10, 220, "dt: " + std::to_string(solver_.system.p.dt) + "ps");

        double progress = solver_.system.p.t / solver_.system.t_max;
        window_.drawRect(10, 180, 310, 335, sf::Color(50, 50, 50), true);
        window_.drawRect(13, 13 + 164 * progress, 313, 332, sf::Color(36, 114, 234, 255), true);
    } else {
        for (auto& obj : window_.objects)
            obj->visible = false;
    }
}

#else

void PhoenixGUI::init() {}
bool PhoenixGUI::update(double, double, size_t) {return true;}
void PhoenixGUI::setupGUI() {}
void PhoenixGUI::handleGUIEvents() {}
void PhoenixGUI::drawGUI() {}
void PhoenixGUI::handleSnapshots() {}

#endif 

std::string PhoenixGUI::toScientific(Type::real in) {
    std::stringstream ss;
    ss << std::scientific << std::setprecision(2) << in;
    return ss.str();
}

} // namespace PHOENIX
