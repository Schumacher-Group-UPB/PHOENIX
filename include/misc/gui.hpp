#pragma once

#include <iostream>
#include <sstream>
#include <iomanip>
#include <deque>
#include <vector>
#include <memory>
#include <string>
#include "solver/solver.hpp"
#include "misc/commandline_io.hpp"
#include "misc/solver_thread.hpp"
#include "cuda/cuda_matrix.cuh"

#ifdef SFML_RENDER
    #include <SFML/Graphics.hpp>
    #include <SFML/Window.hpp>
    #include "misc/sfml_window.hpp"
    #include "imgui.h"
    #include "imgui-SFML.h"
    #include "implot3d.h"
#endif

#include "misc/colormap.hpp"
#include "resources/vik.hpp"
#include "resources/viko.hpp"
#include "resources/viridis.hpp"
#include "resources/plasma.hpp"
#include "resources/inferno.hpp"
#include "resources/magma.hpp"
#include "resources/hot.hpp"
#include "resources/turbo_cmap.hpp"
#include "resources/grayscale.hpp"

namespace PHOENIX {

class PhoenixGUI {
public:
    explicit PhoenixGUI( Solver& solver );
    ~PhoenixGUI();
    void init();
    bool update( double simulation_time, double elapsed_time, size_t iterations, SolverThreadState& st );
    bool is_paused() const { return paused_; }

private:
    Solver& solver_;
    bool paused_ = false;
    SolverThreadState* st_ = nullptr;

#ifdef SFML_RENDER
    // ---- Window & colormaps ----
    BasicWindow  window_;
    struct ColormapEntry { std::string name; ColorPalette palette; };
    std::vector<ColormapEntry> colormaps_;
    void buildColormaps();

    // ---------------------------------------------------------------
    // Registry: one entry for every matrix the GUI can display
    // ---------------------------------------------------------------
    struct MatrixDescriptor {
        std::string label;
        CUDAMatrix<Type::complex>* complex_mat = nullptr;
        CUDAMatrix<Type::real>*    real_mat    = nullptr;
        bool is_phase  = false;
        bool available = true;   // false → greyed out / skipped
    };
    std::vector<MatrixDescriptor> matrix_registry_;

    // ---------------------------------------------------------------
    // Panel: one independent ImGui viewer window
    // ---------------------------------------------------------------
    struct MatrixPanel {
        int      selected    = 0;                      // index into matrix_registry_
        int      panel_id   = 0;                      // stable unique ID (never changes)
        ImGuiID  saved_dock_id = 0;                   // last known dock node - restored on title change
        std::unique_ptr<sf::RenderTexture> tex;
        std::vector<sf::Vertex>  pix;
        int  tex_w = 0, tex_h = 0;
        bool open  = true;
        std::string title;                            // ImGui window ID: "Label##view_N"
        // min/max history for the embedded mini-plot
        std::deque<float> hist_max, hist_min;
        static constexpr int kMaxHist = 512;
        // optional fixed colormap range
        bool   use_manual_range = false;
        double manual_min = 0.0, manual_max = 1.0;
        // logarithmic display
        bool log_scale = false;
        // view mode: 2D heatmap, 1D line cut, or 3D surface
        enum class ViewMode { Image2D = 0, LineCut, Surface3D };
        ViewMode view_mode   = ViewMode::Image2D;
        int  slice_axis  = 0;     // 0 = X (select column, plot along Y), 1 = Y (select row, plot along X)
        int  slice_index = 0;     // which column/row index
        // 3D surface plot options
        int  subsample_3d = 4;    // render every Nth point per axis (stride)
        // per-panel download cadence
        int download_every   = 1;   // blit every N updatePanel calls
        int download_counter = 0;
        // per-panel colormap: -1 = auto (viko for phase, vik for amplitude)
        int colormap_idx = -1;
        // display mode for complex matrices
        enum class DisplayMode { Abs2 = 0, Abs, Real, Imag, Phase };
        DisplayMode display_mode = DisplayMode::Abs2;
        // line-cut component visibility (only relevant when show_matrix == false)
        bool show_abs_curve = true;
        bool show_re_curve  = true;
        bool show_im_curve  = true;
        bool show_arg_curve = false;  // arg(Z) hidden by default
        // ---- Zoom & pan state for 2D image view ----
        float zoom_scale = 1.0f;   // 1.0 = fully zoomed out; max 64.0
        float pan_u      = 0.0f;   // horizontal pan in logical UV space [0, 1 - 1/zoom]
        float pan_v      = 0.0f;   // vertical   pan in logical UV space [0, 1 - 1/zoom]
        bool  square_aspect = false; // letterbox so grid pixels appear square
        // fftshift: remap indices so DC (k=0) is at the centre instead of the corners
        bool  fft_shift = false;
    };
    std::vector<MatrixPanel> panels_;
    int next_panel_id_ = 1;

    // ---------------------------------------------------------------
    // Temporal envelope history for the Envelopes window
    // ---------------------------------------------------------------
    struct EnvelopeHistory {
        std::string label;
        std::deque<float> times;
        std::deque<float> values;     // |temporal_envelope| (abs) summed over groups
        std::deque<float> values_re;  // Re(temporal_envelope) summed over groups
        std::deque<float> values_im;  // Im(temporal_envelope) summed over groups
        static constexpr int kMaxHist = 1024;
    };
    std::vector<EnvelopeHistory> env_histories_;
    bool show_env_window_  = false;
    bool show_plot_window_ = false;

    // ---- Snapshot data ----
    struct Snapshot {
        std::string label;
        double      time = 0.0;
        Type::host_vector<Type::complex> wf_plus, wf_minus;
        Type::host_vector<Type::complex> rv_plus, rv_minus;
    };
    std::vector<Snapshot> snapshots_;
    int snapshot_selected_ = -1;

    // ---- Parameter panel ----
    SystemParameters::KernelParameters params_saved_;
    bool params_show_panel_ = false;

    // ---- ETA rolling-average state ----
    struct RateSample { double sim_t; double elapsed; };
    std::deque<RateSample> rate_history_;
    static constexpr int kRateHistMax = 100;

    // ---- Layout state ----
    bool     layout_initialized_      = false;
    ImGuiID  default_dock_id_         = 0;    // right-side dock node; new panels auto-dock here
    int      implot3d_colormap_base_  = -1;   // index of first registered custom colormap in implot3d

    // ---- Internal helpers ----
    void buildRegistry();
    void addPanel( int initial_selected = 0 );
    void updatePanel( MatrixPanel& p );
    void updateEnvelopeHistories();

    void renderMenuBar();
    void renderMatrixPanel( MatrixPanel& p );
    void renderMatrixPanel3D( MatrixPanel& p );
    void renderControlWindow( double sim_t, double elapsed, size_t iter );
    void renderParametersPanel();
    void renderPlotsPanel();
    void renderEnvelopePlotWindow();
    void tileViews();
    void doHandleSnapshots( bool take, bool restore_snap, bool restore_initial, bool delete_snap );

    template <typename T>
    void blitPanel( MatrixPanel& p, const MatrixDescriptor& desc, ColorPalette& cp );

public:
    // ---------------------------------------------------------------
    // Envelope Editor (public so anonymous-namespace helpers in gui.cu can use them)
    // ---------------------------------------------------------------

    // Per-component spatial editing state
    struct SpatialComponentEdit {
        float amp = 1.f, width_x = 1.f, width_y = 1.f;
        float x = 0.f, y = 0.f, exponent = 1.f;
        float k0_x = 0.f, k0_y = 0.f;
        int   m = 0;               // topological charge (0 = none)
        // Type flags
        bool  flag_gauss    = true;
        bool  flag_ring     = false;
        bool  flag_noDivide = true;
        bool  flag_outerExp = false;
        bool  flag_local    = false;
        // 0=plus, 1=minus, 2=both
        int   polarization_idx = 2;
        // 0=add, 1=multiply, 2=replace, 3=adaptive, 4=complex
        int   behavior_idx     = 0;
    };

    // Single temporal group editing state
    struct TemporalComponentEdit {
        int   type_idx = 0;   // 0=constant, 1=gauss, 2=iexp, 3=cos
        float t0 = 0.f, sigma = 1.f, freq = 0.f;
    };

    // Registry entry for a targetable matrix slot
    struct EnvelopeDescriptor {
        std::string                label;
        Envelope*                  source_env   = nullptr;
        CUDAMatrix<Type::real>*    real_target  = nullptr;   // pump+/-, potential+/-
        CUDAMatrix<Type::complex>* cmplx_target = nullptr;   // pulse+/-, psi+/-, n+/-
        Type::host_vector<Type::complex>* host_target = nullptr; // initial_state+/- (host only)
        bool                       is_complex   = false;
        Envelope::Polarization     polarization = Envelope::Polarization::Plus;
        bool                       available    = true;
        std::string                unavail_reason;
    };

    // Full envelope editor panel state
    struct EnvelopeEditorPanel {
        int         panel_id = 0;
        bool        open     = true;
        std::string title;
        ImGuiID     saved_dock_id = 0;

        int selected_target = 0;   // index into envelope_registry_

        std::vector<SpatialComponentEdit> components;
        int  selected_component = -1;
        TemporalComponentEdit temporal;

        // Preview texture (CPU-computed via Envelope::calculate)
        std::unique_ptr<sf::RenderTexture> preview_tex;
        std::vector<sf::Vertex>            preview_pix;
        int  preview_w = 0, preview_h = 0;
        bool preview_dirty = true;

        // Preview display options (mirrors MatrixPanel)
        enum class PreviewMode { Abs2 = 0, Abs, Real, Imag, Phase };
        PreviewMode preview_mode    = PreviewMode::Abs2;
        int         colormap_idx    = -1;
        bool        use_manual_range = false;
        double      manual_min = 0.0, manual_max = 1.0;
        bool        log_scale  = false;

        // Zoom/pan (same logic as MatrixPanel)
        float zoom_scale = 1.f, pan_u = 0.f, pan_v = 0.f;
        bool  square_aspect = false; // letterbox so grid pixels appear square

        // Interactive drag state
        enum class DragMode { None, Move, ResizeX, ResizeY };
        DragMode drag_mode        = DragMode::None;
        int      drag_component   = -1;
        ImVec2   drag_start_mouse = {};
        float    drag_start_x = 0.f, drag_start_y = 0.f;
        float    drag_start_wx = 0.f, drag_start_wy = 0.f;

        std::string last_apply_status;

        // Live apply - every preview rebuild is immediately pushed to the GPU matrix
        bool live_apply = false;

        // ---- Noise overlay (applied on top of envelope in preview & apply) ----
        struct NoiseState {
            bool     enabled            = false; // include noise in preview & apply
            float    amplitude          = 0.1f;
            int      type_idx           = 0;     // 0=Uniform, 1=Gaussian, 2=Correlated
            float    correlation_length = 1.0f;  // same units as L_x / L_y
            int      seed               = 0;     // 0 = new random each rebuild
            uint32_t last_used_seed     = 0;     // stored after each preview; apply reuses it
        };
        NoiseState noise;

        // ---- Matrix snapshot (current device data, loaded when no source envelope) ----
        std::vector<Type::complex> matrix_snapshot;
        bool                       matrix_snapshot_is_real = false;

        // ---- Revision history (one entry per Apply) ----
        struct Revision {
            std::string                       label;       // "Rev N  (t=X ps)"
            std::vector<SpatialComponentEdit> components;
            TemporalComponentEdit             temporal;
        };
        std::vector<Revision> revisions;
        int selected_revision = -1;
    };

    std::vector<EnvelopeDescriptor>  envelope_registry_;
    std::vector<EnvelopeEditorPanel> env_editor_panels_;
    int next_env_editor_id_ = 1;

    void buildEnvelopeRegistry();
    void addEnvelopeEditorPanel();
    void renderEnvelopeEditorPanel( EnvelopeEditorPanel& p );
    void rebuildPreview( EnvelopeEditorPanel& p );
    void applyEnvelopeToMatrix( EnvelopeEditorPanel& p, bool push_revision = true );
#endif

    static std::string toScientific( Type::real in );

    // Legacy stubs - defined in the #else branch of gui.cu
    void setupGUI();
    void handleGUIEvents();
    void drawGUI();
    void handleSnapshots();
};

} // namespace PHOENIX
