#include "misc/gui.hpp"
#ifdef SFML_RENDER
#include "imgui_internal.h"
#endif
#include <cmath>
#include <numbers>
#include <algorithm>
#include <limits>
#include <random>
#include <sstream>
#include <iomanip>
#include "system/noise.hpp"

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

    ImPlot3D::CreateContext();

    // Register our ColorPalette colormaps with implot3d so the per-panel
    // colormap selector works in 3D surface mode.
    {
        implot3d_colormap_base_ = ImPlot3D::GetColormapCount();
        std::vector<ImVec4> cols;
        constexpr int kSamples = 256;
        cols.reserve( kSamples );
        for ( const auto& e : colormaps_ ) {
            cols.clear();
            const int n = (int)e.palette.output_colors.size();
            for ( int k = 0; k < kSamples; k++ ) {
                const int idx = std::clamp(
                    (int)std::round( (double)k / (kSamples - 1) * (n - 1) ),
                    0, n - 1 );
                const auto& c = e.palette.output_colors[idx];
                cols.push_back( { c.r / 255.f, c.g / 255.f, c.b / 255.f, 1.f } );
            }
            ImPlot3D::AddColormap( e.name.c_str(), cols.data(), kSamples, false );
        }
    }

    buildRegistry();
    params_saved_ = solver_.system.kernel_parameters;
}

PhoenixGUI::~PhoenixGUI() {
    ImPlot3D::DestroyContext();
    ImGui::SFML::Shutdown();
}

// ============================================================
// buildColormaps - populate colormaps_ from compiled-in resources
// ============================================================

void PhoenixGUI::buildColormaps() {
    auto add = [&]( const char* name, const auto& data ) {
        ColormapEntry e;
        e.name = name;
        e.palette.readColorPaletteFromMemory( data );
        e.palette.initColors();
        colormaps_.push_back( std::move( e ) );
    };
    add( "vik",       Misc::Resources::cmap_vik );       // index 0 - default amplitude
    add( "viko",      Misc::Resources::cmap_viko );      // index 1 - default phase
    add( "viridis",   Misc::Resources::cmap_viridis );
    add( "plasma",    Misc::Resources::cmap_plasma );
    add( "inferno",   Misc::Resources::cmap_inferno );
    add( "magma",     Misc::Resources::cmap_magma );
    add( "hot",       Misc::Resources::cmap_hot );
    add( "turbo",     Misc::Resources::cmap_turbo );
    add( "grayscale", Misc::Resources::cmap_grayscale );
}

// ============================================================
// buildRegistry - populate matrix_registry_ from all available matrices
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
    if ( sys.use_fft_mask ) {
        add( "FFT+",      &mat.fft_display_plus,      nullptr,                    false );
        add( "FFT mask+", nullptr,                     &mat.fft_mask_display_plus, false );
    }

    // --- Minus components (twin mode only) ---
    if ( sys.use_twin_mode ) {
        add( "Psi-",            &mat.wavefunction_minus, nullptr,              false );
        add( "n-",              &mat.reservoir_minus,    nullptr,              false, sys.use_reservoir  );
        add( "pump-",           nullptr,                 &mat.pump_minus,      false, sys.use_pumps      );
        add( "potential-",      nullptr,                 &mat.potential_minus, false, sys.use_potentials );
        add( "pulse-",          &mat.pulse_minus,        nullptr,              false, sys.use_pulses     );
        if ( sys.use_fft_mask ) {
            add( "FFT-",      &mat.fft_display_minus,      nullptr,                     false );
            add( "FFT mask-", nullptr,                      &mat.fft_mask_display_minus, false );
        }
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

    // Build envelope editor registry
    buildEnvelopeRegistry();
}

// ============================================================
// update - main per-frame entry point
// ============================================================

bool PhoenixGUI::update( double simulation_time, double elapsed_time, size_t iterations, SolverThreadState& st ) {
    st_ = &st;
    if ( solver_.system.disableRender ) return true;

    auto doFrame = [&]() -> bool {
        // --- Event handling ---
        window_.updateMouseState();
        bool kb_snapshot = false, kb_tile = false, kb_new_panel = false, kb_env_editor = false;
        sf::Event event;
        while ( window_.window.pollEvent( event ) ) {
            ImGui::SFML::ProcessEvent( event );
            if ( event.type == sf::Event::Closed )
                window_.window.close();
            if ( event.type == sf::Event::KeyPressed
                 && !ImGui::GetIO().WantCaptureKeyboard ) {
                switch ( event.key.code ) {
                    case sf::Keyboard::Space:
                        paused_ = !paused_;
                        st.paused.store( paused_ );
                        if ( !paused_ ) st.pause_cv.notify_all();
                        break;
                    case sf::Keyboard::S:     kb_snapshot    = true;     break;
                    case sf::Keyboard::T:     kb_tile        = true;     break;
                    case sf::Keyboard::N:     kb_new_panel   = true;     break;
                    case sf::Keyboard::E:     kb_env_editor  = true;     break;
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
        if ( kb_snapshot )   doHandleSnapshots( true, false, false, false );
        if ( kb_tile )       tileViews();
        if ( kb_new_panel )  addPanel( 0 );
        if ( kb_env_editor ) addEnvelopeEditorPanel();

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
        env_editor_panels_.erase(
            std::remove_if( env_editor_panels_.begin(), env_editor_panels_.end(),
                            []( const EnvelopeEditorPanel& p ) { return !p.open; } ),
            env_editor_panels_.end() );

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
        for ( auto& p : env_editor_panels_ ) renderEnvelopeEditorPanel( p );
        renderParametersPanel();
        renderPlotsPanel();
        renderEnvelopePlotWindow();

        ImGui::SFML::Render( window_.window );
        window_.window.display();
        return true;
    };

    bool alive = doFrame();
    if ( !alive ) return false;

    // Keep UI responsive while paused (solver is blocked on pause_cv)
    while ( paused_ && window_.window.isOpen() ) {
        doFrame();
        sf::sleep( sf::milliseconds( 16 ) );
    }
    // Unblock solver on resume (handles resume via the pause loop's doFrame() toggling paused_)
    st.paused.store( false );
    st.pause_cv.notify_all();

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
bool PhoenixGUI::update( double, double, size_t, SolverThreadState& ) { return true; }
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
