#include "misc/gui.hpp"
#ifdef SFML_RENDER
#include "imgui_internal.h"
#endif
#include <cmath>
#include <numbers>
#include <algorithm>
#include <limits>
#include <sstream>
#include <iomanip>

namespace PHOENIX {

PhoenixGUI::PhoenixGUI( Solver& solver )
    : solver_( solver ) {
    init();
}

#ifdef SFML_RENDER

// ============================================================
// init / destroy
// ============================================================

void PhoenixGUI::init() {
    if ( solver_.system.disableRender ) {
        std::cout << CLIO::prettyPrint( "SFML Renderer disabled", CLIO::Control::Warning ) << std::endl;
        return;
    }

    window_.construct( 1920, 1080, 1920, 1080, "PHOENIX" );
    window_.init();

    buildColormaps();

    ImGui::SFML::Init( window_.window );
    ImGui::GetIO().ConfigFlags |= ImGuiConfigFlags_DockingEnable;

    // --- Modern dark IDE theme ---
    {
        ImGuiStyle& style = ImGui::GetStyle();
        ImVec4*     c     = style.Colors;
        const ImVec4 accent{ 0.537f, 0.706f, 0.980f, 1.0f }; // #89B4FA sky-blue

        c[ImGuiCol_WindowBg]             = { 0.118f, 0.118f, 0.180f, 1.0f }; // #1E1E2E
        c[ImGuiCol_ChildBg]              = { 0.098f, 0.098f, 0.157f, 1.0f };
        c[ImGuiCol_PopupBg]              = { 0.118f, 0.118f, 0.180f, 1.0f };
        c[ImGuiCol_Text]                 = { 0.804f, 0.839f, 0.957f, 1.0f }; // #CDD6F4
        c[ImGuiCol_TextDisabled]         = { 0.459f, 0.471f, 0.573f, 1.0f };
        c[ImGuiCol_FrameBg]              = { 0.157f, 0.157f, 0.235f, 1.0f };
        c[ImGuiCol_FrameBgHovered]       = { 0.220f, 0.220f, 0.314f, 1.0f };
        c[ImGuiCol_FrameBgActive]        = { 0.271f, 0.271f, 0.380f, 1.0f };
        c[ImGuiCol_TitleBg]              = { 0.098f, 0.098f, 0.157f, 1.0f };
        c[ImGuiCol_TitleBgActive]        = { 0.157f, 0.157f, 0.243f, 1.0f };
        c[ImGuiCol_MenuBarBg]            = { 0.098f, 0.098f, 0.157f, 1.0f };
        c[ImGuiCol_Header]               = { accent.x, accent.y, accent.z, 0.31f };
        c[ImGuiCol_HeaderHovered]        = { accent.x, accent.y, accent.z, 0.50f };
        c[ImGuiCol_HeaderActive]         = { accent.x, accent.y, accent.z, 0.70f };
        c[ImGuiCol_Button]               = { accent.x, accent.y, accent.z, 0.25f };
        c[ImGuiCol_ButtonHovered]        = { accent.x, accent.y, accent.z, 0.45f };
        c[ImGuiCol_ButtonActive]         = { accent.x, accent.y, accent.z, 0.65f };
        c[ImGuiCol_CheckMark]            = accent;
        c[ImGuiCol_SliderGrab]           = { accent.x, accent.y, accent.z, 0.75f };
        c[ImGuiCol_SliderGrabActive]     = accent;
        c[ImGuiCol_Separator]            = { 0.220f, 0.220f, 0.314f, 1.0f };
        c[ImGuiCol_SeparatorHovered]     = { accent.x, accent.y, accent.z, 0.50f };
        c[ImGuiCol_SeparatorActive]      = { accent.x, accent.y, accent.z, 0.80f };
        c[ImGuiCol_Tab]                  = { 0.118f, 0.118f, 0.180f, 1.0f };
        c[ImGuiCol_TabHovered]           = { accent.x, accent.y, accent.z, 0.50f };
        c[ImGuiCol_TabActive]            = { 0.314f, 0.459f, 0.671f, 1.0f };
        c[ImGuiCol_TabUnfocused]         = { 0.098f, 0.098f, 0.157f, 1.0f };
        c[ImGuiCol_TabUnfocusedActive]   = { 0.220f, 0.290f, 0.420f, 1.0f };
        c[ImGuiCol_ScrollbarBg]          = { 0.098f, 0.098f, 0.157f, 1.0f };
        c[ImGuiCol_ScrollbarGrab]        = { 0.314f, 0.314f, 0.459f, 1.0f };
        c[ImGuiCol_ScrollbarGrabHovered] = { 0.400f, 0.400f, 0.560f, 1.0f };
        c[ImGuiCol_ScrollbarGrabActive]  = accent;
        c[ImGuiCol_PlotLines]            = { accent.x, accent.y, accent.z, 0.90f };
        c[ImGuiCol_PlotHistogram]        = { accent.x, accent.y, accent.z, 0.90f };
        c[ImGuiCol_DockingPreview]       = { accent.x, accent.y, accent.z, 0.50f };
        c[ImGuiCol_ResizeGrip]           = { accent.x, accent.y, accent.z, 0.25f };
        c[ImGuiCol_ResizeGripHovered]    = { accent.x, accent.y, accent.z, 0.50f };
        c[ImGuiCol_ResizeGripActive]     = { accent.x, accent.y, accent.z, 0.80f };

        style.WindowRounding = 4.0f;
        style.FrameRounding  = 3.0f;
        style.GrabRounding   = 3.0f;
        style.TabRounding    = 4.0f;
        style.FramePadding   = { 6.0f, 4.0f };
        style.ItemSpacing    = { 8.0f, 5.0f };
        style.WindowPadding  = { 8.0f, 8.0f };
    }

    buildRegistry();
    params_saved_ = solver_.system.kernel_parameters;
}

PhoenixGUI::~PhoenixGUI() {
    ImGui::SFML::Shutdown();
}

// ============================================================
// buildColormaps — populate colormaps_ from compiled-in resources
// ============================================================

void PhoenixGUI::buildColormaps() {
    auto add = [&]( const char* name, const auto& data ) {
        ColormapEntry e;
        e.name = name;
        e.palette.readColorPaletteFromMemory( data );
        e.palette.initColors();
        colormaps_.push_back( std::move( e ) );
    };
    add( "vik",       Misc::Resources::cmap_vik );       // index 0 — default amplitude
    add( "viko",      Misc::Resources::cmap_viko );      // index 1 — default phase
    add( "viridis",   Misc::Resources::cmap_viridis );
    add( "plasma",    Misc::Resources::cmap_plasma );
    add( "inferno",   Misc::Resources::cmap_inferno );
    add( "magma",     Misc::Resources::cmap_magma );
    add( "hot",       Misc::Resources::cmap_hot );
    add( "turbo",     Misc::Resources::cmap_turbo );
    add( "grayscale", Misc::Resources::cmap_grayscale );
}

// ============================================================
// buildRegistry — populate matrix_registry_ from all available matrices
// ============================================================

void PhoenixGUI::buildRegistry() {
    matrix_registry_.clear();
    panels_.clear();
    env_histories_.clear();
    next_panel_id_ = 1;

    auto& sys = solver_.system;
    auto& mat = solver_.matrix;

    auto add = [&]( const char* label,
                    CUDAMatrix<Type::complex>* cm,
                    CUDAMatrix<Type::real>*    rm,
                    bool phase,
                    bool avail = true ) {
        MatrixDescriptor d;
        d.label       = label;
        d.complex_mat = cm;
        d.real_mat    = rm;
        d.is_phase    = phase;
        d.available   = avail;
        matrix_registry_.push_back( std::move( d ) );
    };

    // --- Plus components (always present) ---
    add( "Psi+",            &mat.wavefunction_plus,  nullptr,              false );
    add( "n+",              &mat.reservoir_plus,     nullptr,              false, sys.use_reservoir  );
    add( "pump+",           nullptr,                 &mat.pump_plus,       false, sys.use_pumps      );
    add( "potential+",      nullptr,                 &mat.potential_plus,  false, sys.use_potentials );
    add( "pulse+",          &mat.pulse_plus,         nullptr,              false, sys.use_pulses     );

    // --- Minus components (twin mode only) ---
    if ( sys.use_twin_mode ) {
        add( "Psi-",            &mat.wavefunction_minus, nullptr,              false );
        add( "n-",              &mat.reservoir_minus,    nullptr,              false, sys.use_reservoir  );
        add( "pump-",           nullptr,                 &mat.pump_minus,      false, sys.use_pumps      );
        add( "potential-",      nullptr,                 &mat.potential_minus, false, sys.use_potentials );
        add( "pulse-",          &mat.pulse_minus,        nullptr,              false, sys.use_pulses     );
    }

    // --- Debug / diagnostic ---
    add( "Debug: RK error", nullptr, &mat.rk_error, false );

    // --- Temporal envelope history entries ---
    if ( sys.use_pumps )
        env_histories_.push_back( { "pump",      {}, {} } );
    if ( sys.use_pulses )
        env_histories_.push_back( { "pulse",     {}, {} } );
    if ( sys.use_potentials )
        env_histories_.push_back( { "potential", {}, {} } );

    // Create the initial viewer panel
    addPanel( 0 );
}

// ============================================================
// addPanel — create and append a new viewer window
// ============================================================

void PhoenixGUI::addPanel( int initial_selected ) {
    const int W = (int)solver_.system.p.N_c;
    const int H = (int)solver_.system.p.N_r;

    const int id = next_panel_id_++;
    const std::string label = ( initial_selected >= 0
                                && initial_selected < (int)matrix_registry_.size() )
                              ? matrix_registry_[initial_selected].label
                              : "View " + std::to_string( id );

    MatrixPanel p;
    p.selected       = initial_selected;
    p.panel_id       = id;
    p.tex_w          = W;
    p.tex_h          = H;
    p.open           = true;
    p.title          = label + "##view_" + std::to_string( id );
    p.saved_dock_id  = default_dock_id_;   // auto-dock into the right-side node
    p.tex      = std::make_unique<sf::RenderTexture>();
    p.tex->create( W, H );
    p.pix.resize( W * H );
    for ( int r = 0; r < H; r++ )
        for ( int c = 0; c < W; c++ )
            p.pix[r * W + c] = sf::Vertex( sf::Vector2f( c + 0.5f, r + 0.5f ), sf::Color::Black );

    panels_.push_back( std::move( p ) );
}

// ============================================================
// blitPanel<T> — compute pixels and upload to the panel texture
// ============================================================

template <typename T>
void PhoenixGUI::blitPanel( MatrixPanel& p, const MatrixDescriptor& desc, ColorPalette& cp ) {
    const int W = p.tex_w, H = p.tex_h;
    if ( W == 0 || H == 0 ) return;

    const T* data = nullptr;
    if constexpr ( std::is_same_v<T, Type::complex> ) {
        if ( !desc.complex_mat ) return;
        desc.complex_mat->deviceToHostSync();
        data = desc.complex_mat->getHostPtr();
    } else {
        if ( !desc.real_mat ) return;
        desc.real_mat->deviceToHostSync();
        data = desc.real_mat->getHostPtr();
    }
    if ( !data ) return;

    const int N = W * H;

    // Raw display value based on per-panel display mode
    const bool is_phase_mode = ( p.display_mode == MatrixPanel::DisplayMode::Phase );
    auto rawVal = [&]( int i ) -> double {
        if constexpr ( std::is_same_v<T, Type::complex> ) {
            switch ( p.display_mode ) {
                case MatrixPanel::DisplayMode::Abs:   return (double)CUDA::sqrt( CUDA::abs2( data[i] ) );
                case MatrixPanel::DisplayMode::Real:  return (double)CUDA::real( data[i] );
                case MatrixPanel::DisplayMode::Imag:  return (double)CUDA::imag( data[i] );
                case MatrixPanel::DisplayMode::Phase: return (double)CUDA::arg( data[i] );
                default:                              return (double)CUDA::abs2( data[i] );
            }
        } else {
            return (double)data[i];
        }
    };

    // Display value with optional log transform
    auto displayVal = [&]( int i ) -> double {
        double v = rawVal( i );
        if ( p.log_scale && !is_phase_mode )
            v = std::log10( std::max( v, 1e-30 ) );
        return v;
    };

    // Determine colormap range
    double vmin, vmax;
    if ( is_phase_mode ) {
        vmin = -std::numbers::pi;
        vmax =  std::numbers::pi;
    } else if ( p.use_manual_range ) {
        vmin = p.manual_min;
        vmax = p.manual_max;
        if ( p.log_scale ) {
            vmin = std::log10( std::max( vmin, 1e-30 ) );
            vmax = std::log10( std::max( vmax, 1e-30 ) );
        }
    } else {
        vmin =  std::numeric_limits<double>::max();
        vmax = -std::numeric_limits<double>::max();
        for ( int i = 0; i < N; i++ ) {
            double v = displayVal( i );
            if ( v < vmin ) vmin = v;
            if ( v > vmax ) vmax = v;
        }
        if ( vmax - vmin < 1e-30 ) vmax = vmin + 1e-30;
    }

    // Update history with raw (non-log) values
    {
        double hmax = -std::numeric_limits<double>::max();
        double hmin =  std::numeric_limits<double>::max();
        for ( int i = 0; i < N; i++ ) {
            double v = rawVal( i );
            if ( v > hmax ) hmax = v;
            if ( v < hmin ) hmin = v;
        }
        p.hist_max.push_back( (float)hmax );
        p.hist_min.push_back( (float)hmin );
        while ( (int)p.hist_max.size() > MatrixPanel::kMaxHist ) p.hist_max.pop_front();
        while ( (int)p.hist_min.size() > MatrixPanel::kMaxHist ) p.hist_min.pop_front();
    }

    // Write colormap pixels
    for ( int r = 0; r < H; r++ ) {
        for ( int c = 0; c < W; c++ ) {
            double v = displayVal( r * W + c );
            double t = ( v - vmin ) / ( vmax - vmin );
            t = std::max( 0.0, std::min( 1.0, t ) );
            auto& col = cp.getColor( t );
            p.pix[r * W + c].color = sf::Color( col.r, col.g, col.b );
        }
    }

    p.tex->clear( sf::Color::Black );
    p.tex->draw( p.pix.data(), N, sf::Points );
    p.tex->display();
}

// ============================================================
// updatePanel — dispatch blitPanel for the selected matrix
// ============================================================

void PhoenixGUI::updatePanel( MatrixPanel& p ) {
    if ( p.selected < 0 || p.selected >= (int)matrix_registry_.size() ) return;
    const auto& desc = matrix_registry_[p.selected];
    if ( !desc.available ) return;

    // Download cadence: skip unless counter hits the threshold
    if ( p.download_counter++ % p.download_every != 0 ) return;

    // Colormap: -1 = auto (viko for phase, vik for amplitude), else explicit index
    int idx = p.colormap_idx;
    ColorPalette* cp;
    if ( idx < 0 || idx >= (int)colormaps_.size() ) {
        const bool is_phase_mode = ( p.display_mode == MatrixPanel::DisplayMode::Phase );
        cp = is_phase_mode ? &colormaps_[1].palette : &colormaps_[0].palette;
    } else {
        cp = &colormaps_[idx].palette;
    }

    if ( desc.complex_mat )
        blitPanel<Type::complex>( p, desc, *cp );
    else if ( desc.real_mat )
        blitPanel<Type::real>( p, desc, *cp );
}

// ============================================================
// updateEnvelopeHistories — record temporal amplitude each frame
// ============================================================

void PhoenixGUI::updateEnvelopeHistories() {
    auto& sys = solver_.system;
    const float t = (float)sys.p.t;

    auto record = [&]( EnvelopeHistory& h, const Envelope& env ) {
        if ( env.temporal_envelope.empty() ) return;
        float val_abs = 0.0f, val_re = 0.0f, val_im = 0.0f;
        for ( const auto& v : env.temporal_envelope ) {
            val_abs += (float)std::sqrt( (double)CUDA::abs2( v ) );
            val_re  += (float)CUDA::real( v );
            val_im  += (float)CUDA::imag( v );
        }
        h.times.push_back( t );
        h.values.push_back( val_abs );
        h.values_re.push_back( val_re );
        h.values_im.push_back( val_im );
        while ( (int)h.times.size()     > EnvelopeHistory::kMaxHist ) h.times.pop_front();
        while ( (int)h.values.size()    > EnvelopeHistory::kMaxHist ) h.values.pop_front();
        while ( (int)h.values_re.size() > EnvelopeHistory::kMaxHist ) h.values_re.pop_front();
        while ( (int)h.values_im.size() > EnvelopeHistory::kMaxHist ) h.values_im.pop_front();
    };

    for ( auto& h : env_histories_ ) {
        if      ( h.label == "pump"      ) record( h, sys.pump );
        else if ( h.label == "pulse"     ) record( h, sys.pulse );
        else if ( h.label == "potential" ) record( h, sys.potential );
    }
}

// ============================================================
// renderMatrixPanel — one ImGui viewer window per panel
// ============================================================

void PhoenixGUI::renderMatrixPanel( MatrixPanel& p ) {
    if ( !p.open ) return;

    auto& sys = solver_.system;

    ImGui::SetNextWindowSize( ImVec2( 600, 640 ), ImGuiCond_FirstUseEver );
    if ( p.saved_dock_id != 0 )
        ImGui::SetNextWindowDockID( p.saved_dock_id, ImGuiCond_Appearing );
    ImGui::Begin( p.title.c_str(), &p.open );
    p.saved_dock_id = ImGui::GetWindowDockID();

    // ---- Toolbar Row 1: matrix selector | display mode | view toggle | save ----
    ImGui::SetNextItemWidth( 200.f );
    const char* combo_preview = ( p.selected >= 0 && p.selected < (int)matrix_registry_.size() )
        ? matrix_registry_[p.selected].label.c_str()
        : "---";

    if ( ImGui::BeginCombo( "##matsel", combo_preview ) ) {
        for ( int i = 0; i < (int)matrix_registry_.size(); i++ ) {
            const auto& d = matrix_registry_[i];
            if ( !d.available ) continue;
            bool sel = ( p.selected == i );
            if ( ImGui::Selectable( d.label.c_str(), sel ) ) {
                p.selected = i;
                p.title = d.label + "##view_" + std::to_string( p.panel_id );
            }
            if ( sel ) ImGui::SetItemDefaultFocus();
        }
        ImGui::EndCombo();
    }

    // Display mode selector (complex matrices only) — Row 1
    if ( p.selected >= 0 && p.selected < (int)matrix_registry_.size()
         && matrix_registry_[p.selected].complex_mat != nullptr ) {
        ImGui::SameLine();
        ImGui::SetNextItemWidth( 80.f );
        static const char* mode_names[] = { "|psi|^2", "|psi|", "Re", "Im", "arg" };
        int mode_int = (int)p.display_mode;
        if ( ImGui::BeginCombo( "##dmode", mode_names[mode_int] ) ) {
            for ( int m = 0; m < 5; m++ ) {
                bool sel = ( mode_int == m );
                if ( ImGui::Selectable( mode_names[m], sel ) )
                    p.display_mode = (MatrixPanel::DisplayMode)m;
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "How to visualize the complex matrix" );
    }

    ImGui::SameLine();
    ImGui::Checkbox( "Matrix##matview", &p.show_matrix );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Toggle between 2D image and 1D line-cut view" );

    ImGui::SameLine();
    if ( ImGui::Button( "Save##ss" ) && p.tex ) {
        sf::Image img = p.tex->getTexture().copyToImage();
        std::string fname = "phoenix_";
        {
            auto sep = p.title.find( "##" );
            fname += ( sep != std::string::npos ) ? p.title.substr( 0, sep ) : p.title;
        }
        fname += "_t" + std::to_string( (int)sys.p.t ) + ".png";
        img.saveToFile( fname );
    }
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Save panel image to PNG" );

    // ---- Line-cut component visibility / legend (only in 1D mode, complex matrices) ----
    if ( !p.show_matrix
         && p.selected >= 0 && p.selected < (int)matrix_registry_.size()
         && matrix_registry_[p.selected].complex_mat != nullptr ) {
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 1.f, 1.f, 1.f, 1.f ) );
        ImGui::Checkbox( "abs##slck", &p.show_abs_curve );
        ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 0.3f, 1.f, 0.3f, 1.f ) );
        ImGui::Checkbox( "re##slck", &p.show_re_curve );
        ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 1.f, 0.5f, 0.1f, 1.f ) );
        ImGui::Checkbox( "im##slck", &p.show_im_curve );
        ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 0.4f, 0.8f, 1.f, 1.f ) );
        ImGui::Checkbox( "arg##slck", &p.show_arg_curve );
        ImGui::PopStyleColor();
    }

    // ---- Toolbar Row 2: log scale | fix range | skip | colormap ----
    ImGui::Checkbox( "Log##log", &p.log_scale );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Display values on a log10 scale" );

    ImGui::SameLine();
    ImGui::Checkbox( "Fix range##fr", &p.use_manual_range );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Lock colormap to a fixed min/max instead of auto-scaling" );

    ImGui::SameLine();
    ImGui::SetNextItemWidth( 55.f );
    ImGui::InputInt( "Skip##dl", &p.download_every, 0, 0 );
    p.download_every = std::max( 1, p.download_every );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Download every N-th frame (1 = every frame).\nIncrease to reduce GPU-CPU transfer overhead." );

    ImGui::SameLine();
    ImGui::SetNextItemWidth( 100.f );
    {
        const char* cmap_preview = ( p.colormap_idx < 0 || p.colormap_idx >= (int)colormaps_.size() )
            ? "auto" : colormaps_[p.colormap_idx].name.c_str();
        if ( ImGui::BeginCombo( "##cmap", cmap_preview ) ) {
            if ( ImGui::Selectable( "auto", p.colormap_idx < 0 ) )
                p.colormap_idx = -1;
            if ( p.colormap_idx < 0 ) ImGui::SetItemDefaultFocus();
            for ( int i = 0; i < (int)colormaps_.size(); i++ ) {
                bool sel = ( p.colormap_idx == i );
                if ( ImGui::Selectable( colormaps_[i].name.c_str(), sel ) )
                    p.colormap_idx = i;
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Select colormap. 'auto' picks vik for amplitude, viko for phase" );
    }

    // ---- Manual range inputs (Row 3, only when Fix range is active) ----
    if ( p.use_manual_range ) {
        ImGui::SetNextItemWidth( 130.f );
        ImGui::InputDouble( "Min##mn", &p.manual_min, 0, 0, "%.4e" );
        ImGui::SameLine();
        ImGui::SetNextItemWidth( 130.f );
        ImGui::InputDouble( "Max##mx", &p.manual_max, 0, 0, "%.4e" );
    }

    // ---- Range info (always visible when data is available) ----
    if ( !p.hist_min.empty() )
        ImGui::TextDisabled( "range: %.3e  \xe2\x80\x94  %.3e", p.hist_min.back(), p.hist_max.back() );

    // ---- Matrix image OR line cut ----
    ImVec2 avail      = ImGui::GetContentRegionAvail();
    const float plot_h = p.hist_max.empty() ? 0.f : 65.f;

    if ( p.show_matrix ) {
        // --- 2D colormap image ---
        ImVec2 img_size( avail.x, std::max( 10.f, avail.y - plot_h ) );

        if ( p.tex ) {
            // UV viewport with SFML Y-flip (SFML textures have origin at bottom-left)
            // pan_v=0 → top of image → SFML UV v=1; pan_v=1 → bottom → SFML UV v=0
            const float  uv_size = 1.0f / p.zoom_scale;
            const ImVec2 uv0( p.pan_u,            1.0f - p.pan_v            );
            const ImVec2 uv1( p.pan_u + uv_size,  1.0f - p.pan_v - uv_size );

            // ImTextureID encoding matches imgui-SFML's internal memcpy technique
            const unsigned int gl_handle = p.tex->getTexture().getNativeHandle();
            ImTextureID tex_id = nullptr;
            std::memcpy( &tex_id, &gl_handle, sizeof(unsigned int) );

            // InvisibleButton reserves layout space and provides hover/active state
            ImVec2 img_cursor = ImGui::GetCursorScreenPos();
            ImVec2 img_p1( img_cursor.x + img_size.x, img_cursor.y + img_size.y );
            ImGui::InvisibleButton( "##canvas", img_size );
            const bool is_hovered = ImGui::IsItemHovered();
            const bool is_active  = ImGui::IsItemActive();

            ImDrawList* dl = ImGui::GetWindowDrawList();
            dl->AddImage( tex_id, img_cursor, img_p1, uv0, uv1 );

            // ---- Scroll-wheel zoom (zoom toward cursor) ----
            if ( is_hovered ) {
                const float wheel = ImGui::GetIO().MouseWheel;
                if ( wheel != 0.0f ) {
                    const ImVec2 mouse  = ImGui::GetIO().MousePos;
                    const float  frac_c = ( mouse.x - img_cursor.x ) / img_size.x;
                    const float  frac_r = ( mouse.y - img_cursor.y ) / img_size.y;

                    // Texture point under cursor in logical UV space
                    const float tex_u_under = p.pan_u + frac_c * uv_size;
                    const float tex_v_under = p.pan_v + frac_r * uv_size;

                    const float factor = ( wheel > 0.f ) ? 1.15f : ( 1.0f / 1.15f );
                    p.zoom_scale = std::clamp( p.zoom_scale * factor, 1.0f, 64.0f );

                    const float new_uv = 1.0f / p.zoom_scale;
                    p.pan_u = std::clamp( tex_u_under - frac_c * new_uv, 0.0f, 1.0f - new_uv );
                    p.pan_v = std::clamp( tex_v_under - frac_r * new_uv, 0.0f, 1.0f - new_uv );
                }
            }

            // ---- Left-click drag to pan ----
            if ( is_active && p.zoom_scale > 1.001f ) {
                const ImVec2 delta   = ImGui::GetIO().MouseDelta;
                const float  cur_uv  = 1.0f / p.zoom_scale;
                p.pan_u = std::clamp( p.pan_u - ( delta.x / img_size.x ) * cur_uv, 0.0f, 1.0f - cur_uv );
                p.pan_v = std::clamp( p.pan_v - ( delta.y / img_size.y ) * cur_uv, 0.0f, 1.0f - cur_uv );
            }

            // ---- Double-click to reset zoom & pan ----
            if ( is_hovered && ImGui::IsMouseDoubleClicked( ImGuiMouseButton_Left ) ) {
                p.zoom_scale = 1.0f;
                p.pan_u = p.pan_v = 0.0f;
            }

            // ---- Cursor hint ----
            if ( is_hovered )
                ImGui::SetMouseCursor( p.zoom_scale > 1.001f
                                       ? ImGuiMouseCursor_ResizeAll
                                       : ImGuiMouseCursor_Arrow );

            // ---- Hover readout (coordinate mapping through zoom/pan) ----
            if ( is_hovered
                 && p.selected >= 0
                 && p.selected < (int)matrix_registry_.size() ) {

                const auto& desc      = matrix_registry_[p.selected];
                const void* raw       = nullptr;
                const bool  is_complex = ( desc.complex_mat != nullptr );

                if ( is_complex && desc.complex_mat )
                    raw = (const void*)desc.complex_mat->getHostPtr();
                else if ( desc.real_mat )
                    raw = (const void*)desc.real_mat->getHostPtr();

                if ( raw ) {
                    const ImVec2 mouse  = ImGui::GetMousePos();
                    const float  frac_c = ( mouse.x - img_cursor.x ) / img_size.x;
                    const float  frac_r = ( mouse.y - img_cursor.y ) / img_size.y;
                    const float  cur_uv = 1.0f / p.zoom_scale;
                    const float  tex_u  = p.pan_u + frac_c * cur_uv;
                    const float  tex_v  = p.pan_v + frac_r * cur_uv;
                    const int    ci     = std::max( 0, std::min( p.tex_w - 1, (int)( tex_u * p.tex_w ) ) );
                    const int    ri     = std::max( 0, std::min( p.tex_h - 1, (int)( tex_v * p.tex_h ) ) );

                    const double x_phys = ( ci + 0.5 ) * (double)sys.p.dx - 0.5 * (double)sys.p.L_x;
                    const double y_phys = ( ri + 0.5 ) * (double)sys.p.dy - 0.5 * (double)sys.p.L_y;

                    double val    = 0.0;
                    const int idx_px = ri * p.tex_w + ci;
                    if ( is_complex ) {
                        const auto* cd = (const Type::complex*)raw;
                        switch ( p.display_mode ) {
                            case MatrixPanel::DisplayMode::Abs:   val = (double)CUDA::sqrt( CUDA::abs2( cd[idx_px] ) ); break;
                            case MatrixPanel::DisplayMode::Real:  val = (double)CUDA::real( cd[idx_px] ); break;
                            case MatrixPanel::DisplayMode::Imag:  val = (double)CUDA::imag( cd[idx_px] ); break;
                            case MatrixPanel::DisplayMode::Phase: val = (double)CUDA::arg( cd[idx_px] ); break;
                            default:                              val = (double)CUDA::abs2( cd[idx_px] ); break;
                        }
                    } else {
                        val = (double)( (const Type::real*)raw )[idx_px];
                    }

                    ImGui::SetTooltip( "x = %.3f\ny = %.3f\nval = %.4e", x_phys, y_phys, val );
                }
            }

            // ---- Minimap overlay (visible only when zoomed in) ----
            if ( p.zoom_scale > 1.01f ) {
                const float cur_uv   = 1.0f / p.zoom_scale;
                const float mini_dim = std::max( 40.0f, std::min( img_size.x, img_size.y ) * 0.20f );
                const float margin   = 8.0f;
                const ImVec2 mini_p0( img_p1.x - mini_dim - margin, img_cursor.y + margin );
                const ImVec2 mini_p1( mini_p0.x + mini_dim,         mini_p0.y + mini_dim );

                dl->AddRectFilled( mini_p0, mini_p1, IM_COL32( 0, 0, 0, 160 ) );
                // Full-texture thumbnail (Y-flipped to match main view orientation)
                dl->AddImage( tex_id, mini_p0, mini_p1, ImVec2(0,1), ImVec2(1,0) );
                dl->AddRect( mini_p0, mini_p1, IM_COL32(180, 180, 180, 200) );

                // Viewport rectangle showing the currently visible region
                const ImVec2 vp_p0( mini_p0.x + p.pan_u * mini_dim,
                                    mini_p0.y + p.pan_v * mini_dim );
                const ImVec2 vp_p1( mini_p0.x + ( p.pan_u + cur_uv ) * mini_dim,
                                    mini_p0.y + ( p.pan_v + cur_uv ) * mini_dim );
                dl->AddRect( vp_p0, vp_p1, IM_COL32(255, 255, 255, 220), 0.f, 0, 1.5f );
            }
        }
    } else {
        // --- 1D line cut ---
        const int N_c = (int)sys.p.N_c;
        const int N_r = (int)sys.p.N_r;

        // Axis selector + index slider
        ImGui::RadioButton( "X##slax", &p.slice_axis, 0 );
        ImGui::SameLine();
        ImGui::RadioButton( "Y##slax", &p.slice_axis, 1 );
        ImGui::SameLine();
        const int max_idx = ( p.slice_axis == 0 ) ? std::max( 0, N_c - 1 )
                                                   : std::max( 0, N_r - 1 );
        p.slice_index = std::clamp( p.slice_index, 0, max_idx );
        ImGui::SetNextItemWidth( -1.f );
        ImGui::SliderInt( "##sliceidx", &p.slice_index, 0, max_idx );

        // Build slice arrays from already-synced host data
        if ( p.selected >= 0 && p.selected < (int)matrix_registry_.size() ) {
            const auto& desc    = matrix_registry_[p.selected];
            const bool is_cmplx = ( desc.complex_mat != nullptr );
            const Type::complex* cdata = is_cmplx ? desc.complex_mat->getHostPtr() : nullptr;
            const Type::real*    rdata = ( !is_cmplx && desc.real_mat ) ? desc.real_mat->getHostPtr() : nullptr;

            if ( cdata || rdata ) {
                const int slice_len = ( p.slice_axis == 0 ) ? N_r : N_c;
                std::vector<float> abs_v( slice_len ), re_v( slice_len ), im_v( slice_len ), arg_v( slice_len );

                for ( int i = 0; i < slice_len; i++ ) {
                    // axis==0: fixed column (X), vary row  → data[row * N_c + col]
                    // axis==1: fixed row   (Y), vary col  → data[row * N_c + col]
                    const int didx = ( p.slice_axis == 0 )
                        ? ( i * N_c + p.slice_index )
                        : ( p.slice_index * N_c + i );
                    if ( cdata ) {
                        abs_v[i] = (float)CUDA::sqrt( CUDA::abs2( cdata[didx] ) );
                        re_v[i]  = (float)CUDA::real( cdata[didx] );
                        im_v[i]  = (float)CUDA::imag( cdata[didx] );
                        arg_v[i] = (float)CUDA::arg( cdata[didx] );
                    } else {
                        abs_v[i] = (float)rdata[didx];
                        re_v[i]  = (float)rdata[didx];
                        im_v[i]  = 0.f;
                        arg_v[i] = 0.f;
                    }
                }

                // Compute common y-range from visible curves only (respects Fix range)
                float gmin, gmax;
                if ( p.use_manual_range ) {
                    gmin = (float)p.manual_min;
                    gmax = (float)p.manual_max;
                } else {
                    gmin = FLT_MAX;  gmax = -FLT_MAX;
                    auto expand = [&]( const std::vector<float>& v ) {
                        gmin = std::min( gmin, *std::min_element( v.begin(), v.end() ) );
                        gmax = std::max( gmax, *std::max_element( v.begin(), v.end() ) );
                    };
                    if ( !is_cmplx || p.show_abs_curve ) expand( abs_v );
                    if ( is_cmplx && p.show_re_curve  ) expand( re_v  );
                    if ( is_cmplx && p.show_im_curve  ) expand( im_v  );
                    if ( is_cmplx && p.show_arg_curve ) expand( arg_v );
                    if ( gmin > gmax ) { gmin = 0.f; gmax = 1.f; }  // nothing visible fallback
                }
                if ( gmax - gmin < 1e-30f ) gmax = gmin + 1e-30f;

                // Overlay PlotLines in the same rect (cursor save/restore pattern)
                // abs always provides the frame; alpha=0 hides the line when unchecked
                avail = ImGui::GetContentRegionAvail();
                const ImVec2 plot_sz( -1.f, std::max( 10.f, avail.y - plot_h ) );
                ImVec2 saved_pos = ImGui::GetCursorPos();

                const double coord_min = -0.5 * (double)( p.slice_axis == 0 ? sys.p.L_y : sys.p.L_x );
                const double coord_max =  0.5 * (double)( p.slice_axis == 0 ? sys.p.L_y : sys.p.L_x );
                char overlay[128];
                snprintf( overlay, sizeof( overlay ), "abs=%.3e  [%.2f, %.2f]",
                          abs_v.back(), coord_min, coord_max );
                const float abs_a = p.show_abs_curve ? 1.f : 0.f;
                ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 1.f, 1.f, 1.f, abs_a ) );
                ImGui::PlotLines( "##sl_abs", abs_v.data(), slice_len, 0, overlay, gmin, gmax, plot_sz );
                ImGui::PopStyleColor();

                if ( is_cmplx ) {
                    const float re_a  = p.show_re_curve  ? 1.f : 0.f;
                    const float im_a  = p.show_im_curve  ? 1.f : 0.f;
                    const float arg_a = p.show_arg_curve ? 1.f : 0.f;

                    ImGui::SetCursorPos( saved_pos );
                    ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 0.3f, 1.f, 0.3f, re_a ) );
                    ImGui::PushStyleColor( ImGuiCol_FrameBg,   ImVec4( 0.f, 0.f, 0.f, 0.f ) );
                    ImGui::PlotLines( "##sl_re", re_v.data(), slice_len, 0, nullptr, gmin, gmax, plot_sz );
                    ImGui::PopStyleColor( 2 );

                    ImGui::SetCursorPos( saved_pos );
                    ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 1.f, 0.5f, 0.1f, im_a ) );
                    ImGui::PushStyleColor( ImGuiCol_FrameBg,   ImVec4( 0.f, 0.f, 0.f, 0.f ) );
                    ImGui::PlotLines( "##sl_im", im_v.data(), slice_len, 0, nullptr, gmin, gmax, plot_sz );
                    ImGui::PopStyleColor( 2 );

                    ImGui::SetCursorPos( saved_pos );
                    ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 0.4f, 0.8f, 1.f, arg_a ) );
                    ImGui::PushStyleColor( ImGuiCol_FrameBg,   ImVec4( 0.f, 0.f, 0.f, 0.f ) );
                    ImGui::PlotLines( "##sl_arg", arg_v.data(), slice_len, 0, nullptr, gmin, gmax, plot_sz );
                    ImGui::PopStyleColor( 2 );
                }
            }
        }
    }

    // ---- Embedded mini-plot ----
    if ( !p.hist_max.empty() ) {
        std::vector<float> maxv( p.hist_max.begin(), p.hist_max.end() );
        char overlay[64];
        snprintf( overlay, sizeof( overlay ), "max=%.3e", maxv.back() );
        ImGui::PlotLines( "##histmax",
                          maxv.data(), (int)maxv.size(),
                          0, overlay, FLT_MAX, FLT_MAX, ImVec2( -1, 55 ) );
    }

    ImGui::End();
}

// ============================================================
// renderControlWindow — floating simulation control window
// ============================================================

static void tileHelper( ImGuiID node, std::vector<std::string>& titles,
                         int start, int count, bool horiz ) {
    if ( count == 1 ) {
        ImGui::DockBuilderDockWindow( titles[start].c_str(), node );
        return;
    }
    int a = count / 2, b = count - a;
    ImGuiID a_id, b_id;
    ImGui::DockBuilderSplitNode( node, horiz ? ImGuiDir_Left : ImGuiDir_Up,
                                  0.5f, &a_id, &b_id );
    tileHelper( a_id, titles, start,     a, !horiz );
    tileHelper( b_id, titles, start + a, b, !horiz );
}

void PhoenixGUI::tileViews() {
    std::vector<std::string> titles;
    for ( auto& p : panels_ )
        if ( p.open ) titles.push_back( p.title );
    if ( titles.empty() ) return;

    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGuiID dock_id   = ImGui::GetID( "PhoenixDock" );

    ImGui::DockBuilderRemoveNode( dock_id );
    ImGui::DockBuilderAddNode( dock_id, ImGuiDockNodeFlags_DockSpace );
    ImGui::DockBuilderSetNodeSize( dock_id, vp->Size );

    ImGuiID left_id, right_id;
    ImGui::DockBuilderSplitNode( dock_id, ImGuiDir_Left, 0.22f, &left_id, &right_id );
    ImGui::DockBuilderDockWindow( "Control##ctrl", left_id );

    tileHelper( right_id, titles, 0, (int)titles.size(), true );
    ImGui::DockBuilderFinish( dock_id );
}

// ============================================================

void PhoenixGUI::renderControlWindow( double sim_t, double elapsed, size_t iter ) {
    auto& sys = solver_.system;

    ImGui::SetNextWindowSize( ImVec2( 290, 520 ), ImGuiCond_FirstUseEver );
    ImGui::SetNextWindowPos( ImVec2( 10, 10 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Control##ctrl" );

    // ---- Simulation stats ----
    if ( ImGui::CollapsingHeader( "Simulation", ImGuiTreeNodeFlags_DefaultOpen ) ) {
        ImGui::Text( "t     = %.4f ps", (double)sys.p.t );
        ImGui::Text( "t_max = %.4f ps", (double)sys.t_max );
        ImGui::PushStyleColor( ImGuiCol_PlotHistogram, ImVec4( 0.537f, 0.706f, 0.980f, 0.85f ) );
        ImGui::ProgressBar( (float)( sys.p.t / sys.t_max ), ImVec2( -1, 0 ) );
        ImGui::PopStyleColor();
        if ( elapsed > 0.0 ) {
            ImGui::Text( "ps/s : %.1f",  sim_t / elapsed );
            ImGui::Text( "it/s : %.0f",  (double)iter / elapsed );
            ImGui::Text( "FPS  : %d",    window_.fps );
        }
    }

    // ---- Simulation controls ----
    if ( ImGui::CollapsingHeader( "Control", ImGuiTreeNodeFlags_DefaultOpen ) ) {
        if ( !paused_ ) {
            ImGui::PushStyleColor( ImGuiCol_Button,        ImVec4( 0.20f, 0.55f, 0.35f, 0.8f ) );
            ImGui::PushStyleColor( ImGuiCol_ButtonHovered, ImVec4( 0.20f, 0.65f, 0.40f, 0.9f ) );
            ImGui::PushStyleColor( ImGuiCol_ButtonActive,  ImVec4( 0.15f, 0.45f, 0.30f, 1.0f ) );
        } else {
            ImGui::PushStyleColor( ImGuiCol_Button,        ImVec4( 0.70f, 0.35f, 0.15f, 0.8f ) );
            ImGui::PushStyleColor( ImGuiCol_ButtonHovered, ImVec4( 0.80f, 0.40f, 0.15f, 0.9f ) );
            ImGui::PushStyleColor( ImGuiCol_ButtonActive,  ImVec4( 0.60f, 0.30f, 0.10f, 1.0f ) );
        }
        if ( ImGui::Button( paused_ ? "Resume##ctrl" : "Pause##ctrl" ) )
            paused_ = !paused_;
        ImGui::PopStyleColor( 3 );

        ImGui::Separator();

        ImGui::Text( "Snapshots" );
        if ( ImGui::BeginListBox( "##snaps", ImVec2( -1, 80 ) ) ) {
            for ( int i = 0; i < (int)snapshots_.size(); ++i ) {
                bool selected = ( i == snapshot_selected_ );
                if ( ImGui::Selectable( snapshots_[i].label.c_str(), selected ) )
                    snapshot_selected_ = i;
                if ( selected )
                    ImGui::SetItemDefaultFocus();
            }
            ImGui::EndListBox();
        }
        bool take_snap    = ImGui::Button( "Snapshot" );
        ImGui::SameLine();
        bool delete_snap  = ImGui::Button( "Delete" );
        bool restore_snap = ImGui::Button( "Restore Selected" );
        bool restore_initial = ImGui::Button( "Reset to Initial" );
        if ( snapshot_selected_ < 0 || snapshot_selected_ >= (int)snapshots_.size() ) {
            restore_snap = false;
            delete_snap  = false;
        }
        doHandleSnapshots( take_snap, restore_snap, restore_initial, delete_snap );

        ImGui::Separator();

        if ( ImGui::Button( "Save matrices now" ) )
            solver_.outputMatrices( 0, sys.p.N_c, 0, sys.p.N_r, 1, "_manual" );

        ImGui::Text( "Out every: %s ps", toScientific( sys.output_every ).c_str() );
        if ( ImGui::Button( "+##out" ) ) {
            if ( sys.output_every == 0.0 )
                sys.output_every = sys.p.dt;
            sys.output_every *= 2.0;
        }
        ImGui::SameLine();
        if ( ImGui::Button( "-##out" ) )
            sys.output_every /= 2.0;
    }

    // ---- Views management ----
    auto displayTitle = []( const std::string& t ) -> std::string {
        auto pos = t.find( "##" );
        return ( pos != std::string::npos ) ? t.substr( 0, pos ) : t;
    };
    if ( ImGui::CollapsingHeader( "Views", ImGuiTreeNodeFlags_DefaultOpen ) ) {
        if ( ImGui::Button( "Open new View" ) )
            addPanel( 0 );
        ImGui::SameLine();
        if ( ImGui::Button( "Tile##tile" ) )
            tileViews();
        ImGui::SameLine();
        if ( ImGui::Button( "Parameters..." ) )
            params_show_panel_ = !params_show_panel_;
        ImGui::Separator();
        for ( auto& p : panels_ ) {
            bool vis = p.open;
            if ( ImGui::Checkbox( displayTitle( p.title ).c_str(), &vis ) )
                p.open = vis;
        }
    }

    ImGui::Separator();
    ImGui::TextDisabled( "[Space] Pause    [S] Snapshot    [T] Tile    [N] New view" );

    ImGui::End();
}

// ============================================================
// renderMenuBar — top application menu bar
// ============================================================

void PhoenixGUI::renderMenuBar() {
    if ( ImGui::BeginMainMenuBar() ) {
        if ( ImGui::BeginMenu( "Windows" ) ) {
            if ( ImGui::MenuItem( "Parameters...", nullptr, params_show_panel_ ) )
                params_show_panel_ = !params_show_panel_;
            ImGui::MenuItem( "Plots",     nullptr, &show_plot_window_ );
            ImGui::MenuItem( "Envelopes", nullptr, &show_env_window_  );
            ImGui::EndMenu();
        }
        ImGui::EndMainMenuBar();
    }
}

// ============================================================
// renderParametersPanel
// ============================================================

void PhoenixGUI::renderParametersPanel() {
    if ( !params_show_panel_ ) return;

    auto& sys = solver_.system;
    auto& p   = sys.kernel_parameters;

    auto inputReal = [&]( const char* label, Type::real& v ) -> bool {
        double d = static_cast<double>( v );
        if ( ImGui::InputDouble( label, &d, 0.0, 0.0, "%.6g" ) ) {
            v = static_cast<Type::real>( d );
            return true;
        }
        return false;
    };

    ImGui::SetNextWindowSize( ImVec2( 300, 520 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Parameters", &params_show_panel_ );

    if ( ImGui::CollapsingHeader( "Time Control" ) ) {
        bool dirty = false;
        dirty |= inputReal( "dt", p.dt );
        { double d = sys.t_max;        if ( ImGui::InputDouble( "t_max",     &d, 0, 0, "%.4f" ) ) sys.t_max        = d; }
        { double d = sys.output_every; if ( ImGui::InputDouble( "out_every", &d, 0, 0, "%.6f" ) ) sys.output_every = d; }
        { double d = sys.fft_every;    if ( ImGui::InputDouble( "fft_every", &d, 0, 0, "%.6f" ) ) sys.fft_every    = d; }
        { double d = sys.dt_min;       if ( ImGui::InputDouble( "dt_min",    &d, 0, 0, "%.8f" ) ) sys.dt_min       = d; }
        { double d = sys.dt_max;       if ( ImGui::InputDouble( "dt_max",    &d, 0, 0, "%.6f" ) ) sys.dt_max       = d; }
        { double d = sys.tolerance;    if ( ImGui::InputDouble( "tolerance", &d, 0, 0, "%.2e" ) ) sys.tolerance    = d; }
        if ( dirty ) solver_.parameters_are_dirty = true;
    }

    if ( ImGui::CollapsingHeader( "Physics" ) ) {
        bool dirty = false;
        dirty |= inputReal( "gamma_c",  p.gamma_c );
        dirty |= inputReal( "gamma_r",  p.gamma_r );
        dirty |= inputReal( "g_c",      p.g_c );
        dirty |= inputReal( "g_r",      p.g_r );
        dirty |= inputReal( "R",        p.R );
        dirty |= inputReal( "g_pm",     p.g_pm );
        dirty |= inputReal( "delta_LT", p.delta_LT );
        if ( dirty ) solver_.parameters_are_dirty = true;
    }

    if ( ImGui::CollapsingHeader( "Effective Mass" ) ) {
        bool dirty = inputReal( "m_eff", p.m_eff );
        if ( dirty ) solver_.parameters_are_dirty = true;
    }

    if ( ImGui::CollapsingHeader( "Stochastic" ) ) {
        const bool disabled = ( params_saved_.stochastic_amplitude == 0 );
        if ( disabled ) ImGui::BeginDisabled();
        bool dirty = inputReal( "stochastic_amplitude", p.stochastic_amplitude );
        if ( disabled ) ImGui::EndDisabled();
        if ( dirty ) solver_.parameters_are_dirty = true;
    }

    ImGui::Separator();
    if ( ImGui::Button( "Save as Default" ) )
        params_saved_ = sys.kernel_parameters;
    ImGui::SameLine();
    if ( ImGui::Button( "Revert to Default" ) ) {
        sys.kernel_parameters = params_saved_;
        solver_.parameters_are_dirty = true;
    }

    ImGui::End();
}

// ============================================================
// renderPlotsPanel — max history for all open panels
// ============================================================

void PhoenixGUI::renderPlotsPanel() {
    if ( !show_plot_window_ ) return;

    ImGui::SetNextWindowSize( ImVec2( 420, 420 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Plots", &show_plot_window_ );

    auto displayTitle = []( const std::string& t ) -> std::string {
        auto pos = t.find( "##" );
        return ( pos != std::string::npos ) ? t.substr( 0, pos ) : t;
    };
    for ( auto& p : panels_ ) {
        if ( p.hist_max.empty() ) continue;
        std::vector<float> maxv( p.hist_max.begin(), p.hist_max.end() );
        char overlay[64];
        snprintf( overlay, sizeof( overlay ), "max=%.3e", maxv.back() );
        ImGui::Text( "%s", displayTitle( p.title ).c_str() );
        ImGui::PlotLines( ( "##plt_" + p.title ).c_str(),
                          maxv.data(), (int)maxv.size(),
                          0, overlay, FLT_MAX, FLT_MAX, ImVec2( -1, 55 ) );
        ImGui::Separator();
    }

    ImGui::End();
}

// ============================================================
// renderEnvelopePlotWindow — temporal envelope amplitudes
// ============================================================

void PhoenixGUI::renderEnvelopePlotWindow() {
    if ( !show_env_window_ ) return;

    ImGui::SetNextWindowSize( ImVec2( 500, 420 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Envelope Temporal", &show_env_window_ );

    if ( env_histories_.empty() )
        ImGui::TextDisabled( "No time-dependent envelopes detected." );

    for ( auto& h : env_histories_ ) {
        if ( h.values.empty() ) continue;

        std::vector<float> abs_v( h.values.begin(),    h.values.end()    );
        std::vector<float> re_v ( h.values_re.begin(), h.values_re.end() );
        std::vector<float> im_v ( h.values_im.begin(), h.values_im.end() );
        const int n = (int)abs_v.size();

        // Compute global min/max across all three series for consistent y axis
        float gmin = *std::min_element( abs_v.begin(), abs_v.end() );
        float gmax = *std::max_element( abs_v.begin(), abs_v.end() );
        if ( !re_v.empty() ) {
            gmin = std::min( gmin, *std::min_element( re_v.begin(), re_v.end() ) );
            gmax = std::max( gmax, *std::max_element( re_v.begin(), re_v.end() ) );
        }
        if ( !im_v.empty() ) {
            gmin = std::min( gmin, *std::min_element( im_v.begin(), im_v.end() ) );
            gmax = std::max( gmax, *std::max_element( im_v.begin(), im_v.end() ) );
        }
        if ( gmax - gmin < 1e-30f ) gmax = gmin + 1e-30f;

        // Legend
        ImGui::Text( "%s:", h.label.c_str() );
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 1.f, 1.f, 1.f, 1.f ) );
        ImGui::Text( "abs" );
        ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 0.3f, 1.f, 0.3f, 1.f ) );
        ImGui::Text( "re" );
        ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 1.f, 0.5f, 0.1f, 1.f ) );
        ImGui::Text( "im" );
        ImGui::PopStyleColor();

        // Overlay three PlotLines in the same rect using cursor save/restore
        const ImVec2 plot_size( -1, 80 );
        char overlay[64];
        snprintf( overlay, sizeof( overlay ), "abs=%.3e", abs_v.back() );

        ImVec2 saved_pos = ImGui::GetCursorPos();

        ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 1.f, 1.f, 1.f, 1.f ) );
        ImGui::PlotLines( ( "##env_abs_" + h.label ).c_str(),
                          abs_v.data(), n, 0, overlay, gmin, gmax, plot_size );
        ImGui::PopStyleColor();

        if ( !re_v.empty() ) {
            ImGui::SetCursorPos( saved_pos );
            ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 0.3f, 1.f, 0.3f, 1.f ) );
            ImGui::PushStyleColor( ImGuiCol_FrameBg,   ImVec4( 0.f, 0.f, 0.f, 0.f ) );
            ImGui::PlotLines( ( "##env_re_" + h.label ).c_str(),
                              re_v.data(), n, 0, nullptr, gmin, gmax, plot_size );
            ImGui::PopStyleColor( 2 );
        }

        if ( !im_v.empty() ) {
            ImGui::SetCursorPos( saved_pos );
            ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 1.f, 0.5f, 0.1f, 1.f ) );
            ImGui::PushStyleColor( ImGuiCol_FrameBg,   ImVec4( 0.f, 0.f, 0.f, 0.f ) );
            ImGui::PlotLines( ( "##env_im_" + h.label ).c_str(),
                              im_v.data(), n, 0, nullptr, gmin, gmax, plot_size );
            ImGui::PopStyleColor( 2 );
        }

        ImGui::Separator();
    }

    ImGui::End();
}

// ============================================================
// doHandleSnapshots
// ============================================================

void PhoenixGUI::doHandleSnapshots( bool take, bool restore_snap, bool restore_initial, bool delete_snap ) {
    auto& sys = solver_.system;
    auto& mat = solver_.matrix;

    if ( take ) {
        Snapshot s;
        s.time    = sys.p.t;
        s.label   = "t = " + std::to_string( sys.p.t ) + " ps";
        s.wf_plus = mat.wavefunction_plus.getHostVector();
        s.rv_plus = sys.use_reservoir
            ? mat.reservoir_plus.getHostVector()
            : Type::host_vector<Type::complex>{};
        if ( sys.use_twin_mode ) {
            s.wf_minus = mat.wavefunction_minus.getHostVector();
            s.rv_minus = sys.use_reservoir
                ? mat.reservoir_minus.getHostVector()
                : Type::host_vector<Type::complex>{};
        }
        snapshots_.push_back( std::move( s ) );
        snapshot_selected_ = (int)snapshots_.size() - 1;
        std::cout << CLIO::prettyPrint( "Snapshot taken!", CLIO::Control::Info ) << std::endl;
    }

    if ( delete_snap && snapshot_selected_ >= 0 && snapshot_selected_ < (int)snapshots_.size() ) {
        snapshots_.erase( snapshots_.begin() + snapshot_selected_ );
        if ( snapshot_selected_ >= (int)snapshots_.size() )
            snapshot_selected_ = (int)snapshots_.size() - 1;
        std::cout << CLIO::prettyPrint( "Snapshot deleted.", CLIO::Control::Info ) << std::endl;
    }

    if ( restore_snap && snapshot_selected_ >= 0 ) {
        const auto& s = snapshots_[snapshot_selected_];
        mat.wavefunction_plus.setTo( s.wf_plus ).hostToDeviceSync();
        if ( sys.use_reservoir && !s.rv_plus.empty() )
            mat.reservoir_plus.setTo( s.rv_plus ).hostToDeviceSync();
        if ( sys.use_twin_mode ) {
            if ( !s.wf_minus.empty() )
                mat.wavefunction_minus.setTo( s.wf_minus ).hostToDeviceSync();
            if ( sys.use_reservoir && !s.rv_minus.empty() )
                mat.reservoir_minus.setTo( s.rv_minus ).hostToDeviceSync();
        }
        sys.p.t = s.time;
        std::cout << CLIO::prettyPrint( "Restored snapshot: " + s.label, CLIO::Control::Info ) << std::endl;
    }

    if ( restore_initial ) {
        mat.wavefunction_plus.setTo( mat.initial_state_plus ).hostToDeviceSync();
        if ( sys.use_reservoir )
            mat.reservoir_plus.setTo( mat.initial_reservoir_plus ).hostToDeviceSync();
        if ( sys.use_twin_mode ) {
            mat.wavefunction_minus.setTo( mat.initial_state_minus ).hostToDeviceSync();
            if ( sys.use_reservoir )
                mat.reservoir_minus.setTo( mat.initial_reservoir_minus ).hostToDeviceSync();
        }
        sys.p.t = 0.0;
        std::cout << CLIO::prettyPrint( "Reset to Initial!", CLIO::Control::Info ) << std::endl;
    }
}

// ============================================================
// update — main per-frame entry point
// ============================================================

bool PhoenixGUI::update( double simulation_time, double elapsed_time, size_t iterations ) {
    if ( solver_.system.disableRender ) return true;

    auto doFrame = [&]() -> bool {
        // --- Event handling ---
        window_.updateMouseState();
        bool kb_snapshot = false, kb_tile = false, kb_new_panel = false;
        sf::Event event;
        while ( window_.window.pollEvent( event ) ) {
            ImGui::SFML::ProcessEvent( event );
            if ( event.type == sf::Event::Closed )
                window_.window.close();
            if ( event.type == sf::Event::KeyPressed
                 && !ImGui::GetIO().WantCaptureKeyboard ) {
                switch ( event.key.code ) {
                    case sf::Keyboard::Space: paused_      = !paused_; break;
                    case sf::Keyboard::S:     kb_snapshot  = true;     break;
                    case sf::Keyboard::T:     kb_tile      = true;     break;
                    case sf::Keyboard::N:     kb_new_panel = true;     break;
                    default: break;
                }
            }
        }
        if ( !window_.window.isOpen() ) return false;

        sf::Time dt_sfml  = window_.clock.restart();
        window_.frametime = dt_sfml.asMilliseconds();
        window_.fps       = ( window_.frametime > 0 ) ? (int)( 1000.0 / window_.frametime ) : 0;

        ImGui::SFML::Update( window_.window, dt_sfml );

        // --- Handle keyboard shortcuts (require an active ImGui frame) ---
        if ( kb_snapshot )  doHandleSnapshots( true, false, false, false );
        if ( kb_tile )      tileViews();
        if ( kb_new_panel ) addPanel( 0 );

        // --- Update texture data (skip when paused) ---
        if ( !paused_ ) {
            for ( auto& p : panels_ ) updatePanel( p );
            updateEnvelopeHistories();
        }

        // --- Remove panels the user closed via the × button ---
        panels_.erase(
            std::remove_if( panels_.begin(), panels_.end(),
                            []( const MatrixPanel& p ) { return !p.open; } ),
            panels_.end() );

        // --- Fullscreen dockspace host (transparent central node) ---
        {
            ImGuiViewport* vp = ImGui::GetMainViewport();
            ImGui::SetNextWindowPos( vp->WorkPos );
            ImGui::SetNextWindowSize( vp->WorkSize );
            ImGui::SetNextWindowViewport( vp->ID );
            ImGui::PushStyleVar( ImGuiStyleVar_WindowPadding,    ImVec2( 0, 0 ) );
            ImGui::PushStyleVar( ImGuiStyleVar_WindowRounding,   0.0f );
            ImGui::PushStyleVar( ImGuiStyleVar_WindowBorderSize, 0.0f );
            ImGui::Begin( "DockSpace##host", nullptr,
                ImGuiWindowFlags_NoDocking             |
                ImGuiWindowFlags_NoTitleBar            |
                ImGuiWindowFlags_NoResize              |
                ImGuiWindowFlags_NoMove                |
                ImGuiWindowFlags_NoBringToFrontOnFocus |
                ImGuiWindowFlags_NoNavFocus            |
                ImGuiWindowFlags_NoBackground );
            ImGui::PopStyleVar( 3 );
            ImGuiID dock_id = ImGui::GetID( "PhoenixDock" );
            ImGui::DockSpace( dock_id, ImVec2( 0, 0 ), ImGuiDockNodeFlags_PassthruCentralNode );

            if ( !layout_initialized_ ) {
                layout_initialized_ = true;
                ImGuiDockNode* node = ImGui::DockBuilderGetNode( dock_id );
                if ( node == nullptr || node->IsLeafNode() ) {
                    ImGui::DockBuilderRemoveNode( dock_id );
                    ImGui::DockBuilderAddNode( dock_id, ImGuiDockNodeFlags_DockSpace );
                    ImGui::DockBuilderSetNodeSize( dock_id, vp->Size );
                    ImGuiID left_id, right_id;
                    ImGui::DockBuilderSplitNode( dock_id, ImGuiDir_Left, 0.22f, &left_id, &right_id );
                    ImGui::DockBuilderDockWindow( "Control##ctrl",               left_id );
                    ImGui::DockBuilderDockWindow( panels_[0].title.c_str(),      right_id );
                    ImGui::DockBuilderFinish( dock_id );
                    default_dock_id_ = right_id;
                }
            }

            ImGui::End();
        }

        // --- Update window title ---
        {
            auto& sys2 = solver_.system;
            char title_buf[80];
            snprintf( title_buf, sizeof( title_buf ), "PHOENIX  |  t = %.2f / %.2f ps",
                      (double)sys2.p.t, (double)sys2.t_max );
            window_.window.setTitle( title_buf );
        }

        // --- Clear & render ---
        window_.window.clear( sf::Color( 13, 13, 20 ) );

        renderMenuBar();
        renderControlWindow( simulation_time, elapsed_time, iterations );
        for ( auto& p : panels_ ) renderMatrixPanel( p );
        renderParametersPanel();
        renderPlotsPanel();
        renderEnvelopePlotWindow();

        ImGui::SFML::Render( window_.window );
        window_.window.display();
        return true;
    };

    bool alive = doFrame();
    if ( !alive ) return false;

    // Keep UI responsive while paused
    while ( paused_ && window_.window.isOpen() ) {
        doFrame();
        sf::sleep( sf::milliseconds( 16 ) );
    }

    return window_.window.isOpen();
}

// ============================================================
// Legacy stubs (unused in SFML_RENDER path, required by header)
// ============================================================

void PhoenixGUI::setupGUI()        {}
void PhoenixGUI::handleGUIEvents() {}
void PhoenixGUI::drawGUI()         {}
void PhoenixGUI::handleSnapshots() {}

#else  // !SFML_RENDER

void PhoenixGUI::init()                           {}
PhoenixGUI::~PhoenixGUI()                         {}
bool PhoenixGUI::update( double, double, size_t ) { return true; }
void PhoenixGUI::setupGUI()                       {}
void PhoenixGUI::handleGUIEvents()                {}
void PhoenixGUI::drawGUI()                        {}
void PhoenixGUI::handleSnapshots()                {}

#endif  // SFML_RENDER

// ============================================================
// Utilities
// ============================================================

std::string PhoenixGUI::toScientific( Type::real in ) {
    std::stringstream ss;
    ss << std::scientific << std::setprecision( 2 ) << in;
    return ss.str();
}

} // namespace PHOENIX
