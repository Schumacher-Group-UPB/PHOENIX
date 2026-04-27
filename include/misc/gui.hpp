#pragma once

#include <iostream>
#include <sstream>
#include <iomanip>
#include <deque>
#include <vector>
#include <memory>
#include <string>
#include <cstring>
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
    #include "implot.h"
    #include "implot3d.h"
    #include <algorithm>
    #include <chrono>
    #include <thread>
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

// ============================================================
// Shared ImGui widget helpers (SFML_RENDER builds only)
// ============================================================
#ifdef SFML_RENDER

// Apply scroll-wheel zoom, left-drag pan, and double-click reset to a
// zoom/pan state.  img_cursor/img_size describe the drawn image region in
// screen space.  is_hovered / is_active / in_image come from the
// InvisibleButton that covers the canvas.
// allow_pan: set to false to suppress panning (e.g. when a component drag is active).
inline void applyZoomPanInteraction( float& zoom_scale, float& pan_u, float& pan_v,
                                      ImVec2 img_cursor, ImVec2 img_size,
                                      bool is_hovered, bool is_active, bool in_image,
                                      bool allow_pan = true ) {
    const float uv_size = 1.0f / zoom_scale;

    // Scroll-wheel zoom toward cursor
    if ( is_hovered && in_image ) {
        const float wheel = ImGui::GetIO().MouseWheel;
        if ( wheel != 0.0f ) {
            const ImVec2 mouse  = ImGui::GetIO().MousePos;
            const float  frac_c = ( mouse.x - img_cursor.x ) / img_size.x;
            const float  frac_r = ( mouse.y - img_cursor.y ) / img_size.y;
            const float  tex_u  = pan_u + frac_c * uv_size;
            const float  tex_v  = pan_v + frac_r * uv_size;
            const float  factor = ( wheel > 0.f ) ? 1.15f : ( 1.0f / 1.15f );
            zoom_scale = std::clamp( zoom_scale * factor, 1.0f, 64.0f );
            const float new_uv = 1.0f / zoom_scale;
            pan_u = std::clamp( tex_u - frac_c * new_uv, 0.0f, 1.0f - new_uv );
            pan_v = std::clamp( tex_v - frac_r * new_uv, 0.0f, 1.0f - new_uv );
        }
    }

    // Left-drag pan (skip on the initial click frame to avoid conflict with click handlers;
    // also suppressed when allow_pan=false, e.g. while a component drag is active)
    if ( allow_pan && is_active && in_image && zoom_scale > 1.001f && !ImGui::IsMouseClicked( ImGuiMouseButton_Left ) ) {
        const ImVec2 delta  = ImGui::GetIO().MouseDelta;
        const float  cur_uv = 1.0f / zoom_scale;
        pan_u = std::clamp( pan_u - ( delta.x / img_size.x ) * cur_uv, 0.0f, 1.0f - cur_uv );
        pan_v = std::clamp( pan_v - ( delta.y / img_size.y ) * cur_uv, 0.0f, 1.0f - cur_uv );
    }

    // Double-click to reset
    if ( is_hovered && in_image && ImGui::IsMouseDoubleClicked( ImGuiMouseButton_Left ) ) {
        zoom_scale = 1.0f;
        pan_u = pan_v = 0.0f;
    }
}

// Draw a compact polyline mini-plot with a dark background rectangle and
// an overlay label in the top-left corner.  p0/p1 are screen-space corners.
inline void drawMiniHistPlot( ImDrawList* dl, ImVec2 p0, ImVec2 p1,
                               const float* data, int n, ImU32 line_col,
                               const char* overlay_text ) {
    if ( !dl || n < 2 ) return;
    dl->AddRectFilled( p0, p1, IM_COL32( 0, 0, 0, 80 ) );

    const float pw  = p1.x - p0.x;
    const float ph  = p1.y - p0.y - ImGui::GetTextLineHeightWithSpacing();
    float vmin = data[0], vmax = data[0];
    for ( int i = 1; i < n; ++i ) {
        if ( data[i] < vmin ) vmin = data[i];
        if ( data[i] > vmax ) vmax = data[i];
    }
    if ( vmax - vmin < 1e-30f ) vmax = vmin + 1.f;

    std::vector<ImVec2> pts( n );
    for ( int i = 0; i < n; ++i )
        pts[i] = ImVec2( p0.x + (float)i / (float)( n - 1 ) * pw,
                         p1.y - ImGui::GetTextLineHeightWithSpacing()
                             - ( data[i] - vmin ) / ( vmax - vmin ) * ph );
    dl->AddPolyline( pts.data(), n, line_col, 0, 1.5f );

    if ( overlay_text )
        dl->AddText( ImVec2( p0.x + 3.f, p0.y + 2.f ), IM_COL32( 200, 200, 200, 220 ), overlay_text );
}

#endif // SFML_RENDER

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
        int hist_window = kMaxHist;  // how many samples to show (slider-controlled)
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
        // ---- Freeze: stop updating this panel while others continue ----
        bool  frozen = false;
        // ---- Linked zoom/pan: propagate view changes to other linked panels ----
        bool  linked_zoom = false;
        // ---- Optional overlays ----
        bool  show_colorbar   = true;   // draw a thin colorbar on the right edge
        bool  show_axis_ticks = false;  // draw physical coordinate tick marks
        // ---- Save-to-PNG status feedback (shown as tooltip on the Save button) ----
        std::string save_status_msg;
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
        int hist_window = kMaxHist;   // how many samples to show (slider-controlled)
    };
    std::vector<EnvelopeHistory> env_histories_;
    bool show_env_window_       = false;
    bool show_plot_window_      = false;
    bool show_benchmark_window_ = false;
    int  bench_hist_window_     = 256;
    int  bench_selected_key_    = 0;
    bool bench_overlay_all_     = false;

    // ---------------------------------------------------------------
    // TrackedPoint: time-series of a single pixel across matrices
    // ---------------------------------------------------------------
    struct TrackedPoint {
        int         matrix_idx = 0;  // index into matrix_registry_
        int         col = 0, row = 0;  // pixel coords in original matrix (ci, ri)
        float       x_phys = 0.f, y_phys = 0.f;  // physical coordinates at time of creation
        std::string label;           // e.g. "Psi+ @ (100, 50)  t₀=5.2 ps"
        bool        enabled    = true;
        bool        is_complex = false;
        std::deque<float> times;
        std::deque<float> values_abs, values_re, values_im, values_arg;
        static constexpr int kMaxHist = 8192;
        // Which components to show in the time-evolution plot
        bool show_abs  = true;
        bool show_abs2 = false;
        bool show_re   = false;
        bool show_im   = false;
        bool show_arg  = false;
        // Which components to show in the FFT sub-plot (independent of time series)
        bool fft_show_abs  = true;
        bool fft_show_abs2 = false;
        bool fft_show_z    = false;  // complex FFT: |FFT(Re + i·Im)|
        bool fft_show_re   = false;
        bool fft_show_im   = false;
        bool fft_show_arg  = false;
        ImVec4 color = { 1.f, 1.f, 1.f, 1.f };  // per-point display color (overlay mode); auto-assigned, user-editable
    };
    std::vector<TrackedPoint> tracked_points_;
    bool  show_tracked_window_     = false;
    bool  tracked_overlay_mode_    = true;    // true = all in one graph, false = individual
    int   tracked_hist_window_     = 1024;    // how many samples to show and FFT
    bool  tracked_show_fft_        = false;
    int   tracked_max_hist_        = 1024;    // FIFO depth, user-settable
    bool  tracked_autoscale_ts_    = true;
    bool  tracked_autoscale_fft_   = true;
    bool  tracked_ts_hovered_      = false;
    bool  tracked_fft_hovered_     = false;
    bool  tracked_show_window_fn_  = false;   // show the window-function panel
    bool  tracked_apply_smoothing_ = false;   // apply custom window to FFT
    bool  tracked_smooth_preview_  = false;   // also apply window to time-series line plots
    int   tracked_window_fn_type_  = 3;       // 0=Gaussian 1=Hann 2=Blackman 3=Flat
    float tracked_window_fn_sigma_ = 0.4f;    // Gaussian sigma (fraction of half-window)
    int   tracked_window_fn_power_ = 1;       // super-Gaussian exponent N in exp(-(x²)^N)

    // ---------------------------------------------------------------
    // TrackedCut: kymograph (space-time) accumulation of a line cut
    // ---------------------------------------------------------------
    struct TrackedCut {
        int         matrix_idx  = 0;
        int         slice_axis  = 0;   // 0 = fixed col (vary Y), 1 = fixed row (vary X)
        int         slice_index = 0;   // column or row index in original matrix
        int         slice_len   = 0;   // spatial width of the cut (N_r or N_c)
        std::string label;
        bool        enabled    = true;
        bool        is_complex = false;

        std::deque<float>              times;
        std::deque<std::vector<float>> frames_abs;
        std::deque<std::vector<float>> frames_re;
        std::deque<std::vector<float>> frames_im;
        std::deque<std::vector<float>> frames_arg;

        static constexpr int kMaxHist = 1024;

        enum class DisplayComp { Abs = 0, Abs2, Re, Im, Arg } display_comp = DisplayComp::Abs;

        bool   use_manual_range = false;
        double manual_min = 0.0, manual_max = 1.0;
        int    colormap_idx = -1;   // -1 = auto

        bool show_spatial_fft  = false;
        bool show_temporal_fft = false;

        // ---- FFT cache (rebuilt at most once per cut_fft_interval_s_) ----
        std::chrono::steady_clock::time_point last_fft_time {};  // default = epoch (triggers first compute)
        // Spatial FFT cache
        std::vector<float> sfft_flat;
        int                sfft_half_s   = 0;
        double             sfft_vmin = 0.0, sfft_vmax = 1.0;
        double             sfft_k_max = 1.0;
        // Temporal FFT cache
        std::vector<float> tfft_flat;
        int                tfft_half_t   = 0;
        int                tfft_n_cols   = 0;
        double             tfft_vmin = 0.0, tfft_vmax = 1.0;
        double             tfft_f_max = 1.0;
        // Remember which data window the caches were built from (to detect stale caches)
        int  fft_cache_frame_offset = -1;
        int  fft_cache_n_frames     = -1;
    };
    std::vector<TrackedCut> tracked_cuts_;
    bool  show_tracked_cuts_window_ = false;
    int   cut_hist_window_          = 256;
    int   cut_max_hist_             = TrackedCut::kMaxHist;
    float cut_fft_interval_s_       = 1.0f;  // wall-clock seconds between FFT recomputes
    int   implot_colormap_base_     = -1;  // index of first custom colormap in ImPlot (2D)

    // ---- History-window sizes for other graphs ----
    int plots_hist_window_ = MatrixPanel::kMaxHist;  // Plots panel

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

    // ---- dt history for the control window mini-plot ----
    std::deque<float> dt_history_;
    static constexpr int kDtHistMax = 256;

    // ---- Layout state ----
    bool     layout_initialized_      = false;
    ImGuiID  default_dock_id_         = 0;    // right-side dock node; new panels auto-dock here
    int      implot3d_colormap_base_  = -1;   // index of first registered custom colormap in implot3d
    bool     first_frame_             = true;  // used to apply startup-paused logic once

    // ---- Runstring viewer ----
    bool              show_runstring_window_ = false;
    std::string       runstring_cache_;
    std::vector<char> runstring_buf_;   // ImGui requires a writable buffer even for read-only text

    // ---- Config save/load dialogs ----
    struct ConfigSaveState {
        bool open             = false;
        char filepath[512];
        bool include_matrices = false;
        std::string status_msg;
        ConfigSaveState() { std::fill( std::begin( filepath ), std::end( filepath ), '\0' );
                            std::strncpy( filepath, "config.txt", sizeof( filepath ) - 1 ); }
    } config_save_;

    struct ConfigLoadState {
        bool open          = false;
        char filepath[512];
        std::string status_msg;
        ConfigLoadState() { std::fill( std::begin( filepath ), std::end( filepath ), '\0' );
                            std::strncpy( filepath, "config.txt", sizeof( filepath ) - 1 ); }
    } config_load_;

    // ---- Shared widget helpers (close over colormaps_) ----
    // Renders the "auto / vik / viko / …" colormap selector combo.
    // Returns true when the selection changed.  Width must be set by caller.
    bool colormapCombo_( const char* id, int& colormap_idx );
    // Renders the "|.|^2 / |.| / Re / Im / arg" display-mode combo.
    // Returns true when the selection changed.  Width must be set by caller.
    bool displayModeCombo_( const char* id, int& mode_int );

    // ---- Internal helpers ----
    void buildRegistry();
    void addPanel( int initial_selected = 0 );
    void updatePanel( MatrixPanel& p );
    void updateEnvelopeHistories();

    // ---- Runstring / Config helpers ----
    void renderRunstringWindow();
    void renderConfigSaveDialog();
    void renderConfigLoadDialog();
    void renderBenchmarkWindow();
    void applyUpdatableParamsFromFile( const char* filepath );

    // ---- Solver pause/resume for safe parameter/matrix updates ----
    // pauseSolverForUpdate: if the solver thread is running, request a pause and spin until
    // it confirms it is idle (solver_actually_paused). Returns true when it auto-paused so
    // the caller can pass the result straight into resumeSolverAfterUpdate().
    // No-op (returns false) when already paused or no solver thread is attached.
    [[nodiscard]] bool pauseSolverForUpdate();
    // resumeSolverAfterUpdate: iff auto_paused is true, clears paused_ and wakes the solver.
    void resumeSolverAfterUpdate( bool auto_paused );

    void renderMenuBar();
    void renderMatrixPanel( MatrixPanel& p );
    void renderMatrixPanel3D( MatrixPanel& p );
    void renderControlWindow( double sim_t, double elapsed, size_t iter );
    void renderParametersPanel();
    void renderPlotsPanel();
    void renderEnvelopePlotWindow();
    void renderTrackedPointsWindow();
    void updateTrackedPoints();
    void renderTrackedCutsWindow();
    void updateTrackedCuts();
    void tileViews();
    void doHandleSnapshots( bool take, bool restore_snap, bool restore_initial, bool delete_snap );

    template <typename T>
    void blitPanel( MatrixPanel& p, const MatrixDescriptor& desc, ColorPalette& cp );

public:
    // ---------------------------------------------------------------
    // Envelope Editor (public so anonymous-namespace helpers in gui.cu can use them)
    // ---------------------------------------------------------------

    // Single temporal group editing state (defined first so it can be embedded per-component)
    struct TemporalComponentEdit {
        int   type_idx = 0;   // 0=constant, 1=gauss, 2=iexp, 3=cos
        float t0 = 0.f, sigma = 1.f, freq = 0.f;
    };

    // Noise overlay settings (defined before SpatialComponentEdit so it can be embedded per-component)
    struct NoiseState {
        bool     enabled            = false; // include noise in preview & apply
        float    amplitude          = 0.1f;
        int      type_idx           = 0;     // 0=Uniform, 1=Gaussian, 2=Correlated
        float    correlation_length = 1.0f;  // same units as L_x / L_y
        int      seed               = 0;     // 0 = new random each rebuild
        uint32_t last_used_seed     = 0;     // stored after each preview; apply reuses it
    };

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
        // Pseudo-adaptive timestep: 0=none, 1=auto, 2=value
        int   ads_idx   = 0;
        float ads_value = 0.0f;
        // Per-component temporal settings
        TemporalComponentEdit temporal;
        // Lock: prevent editing and dragging this component via the UI
        bool  locked = false;
        // Noise layer: static noise applied first (before envelope components)
        bool  is_noise_layer = false;
        // Per-component noise overlay
        NoiseState noise;
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

        // ---- Right-panel preview tab ----
        enum class PreviewTab { Spatial = 0, Temporal = 1 };
        PreviewTab active_preview_tab = PreviewTab::Spatial;
        // Temporal preview time-range controls
        bool  temporal_auto_range = true;
        float temporal_t_lo = 0.f;
        float temporal_t_hi = 10.f;
        // Temporal preview curve visibility toggles
        bool temporal_show_abs = true;
        bool temporal_show_re  = true;
        bool temporal_show_im  = true;
        // Number of sample points per curve in the temporal preview
        int  temporal_n_steps  = 200;

        // Interactive drag state
        enum class DragMode { None, Move, ResizeX, ResizeY };
        DragMode drag_mode        = DragMode::None;
        int      drag_component   = -1;
        ImVec2   drag_start_mouse = {};
        float    drag_start_x = 0.f, drag_start_y = 0.f;
        float    drag_start_wx = 0.f, drag_start_wy = 0.f;

        std::string last_apply_status;

        // Live apply - every preview rebuild is immediately pushed to the GPU matrix
        bool live_apply         = false;
        bool live_apply_warned_ = false;  // set after the user confirms the first-use warning

        // ---- Matrix snapshot (current device data, loaded when no source envelope) ----
        std::vector<Type::complex> matrix_snapshot;
        bool                       matrix_snapshot_is_real = false;

        // ---- Revision history (one entry per Apply) ----
        // temporal is stored per-component inside SpatialComponentEdit, so no separate temporal field needed.
        struct Revision {
            std::string                       label;       // "Rev N  (t=X ps)"
            std::vector<SpatialComponentEdit> components;
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
