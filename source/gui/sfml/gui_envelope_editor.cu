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
#include <cstring>
#include "system/noise.hpp"

namespace PHOENIX {

#ifdef SFML_RENDER

// ============================================================
// Envelope Editor - helper string converters (internal linkage)
// ============================================================

namespace {

static const char* s_pol_names[]      = { "plus", "minus", "both" };
static const char* s_behavior_names[] = { "add", "multiply", "replace", "adaptive", "complex" };
static const char* s_temp_names[]     = { "constant", "gauss", "iexp", "cos" };
static const char* s_mode_names[]     = { "|.|^2", "|.|", "Re", "Im", "arg" };

std::string envTypeString( const PhoenixGUI::SpatialComponentEdit& c ) {
    std::string s;
    if ( c.flag_gauss )    s += ( s.empty() ? "" : "+" ) + std::string( "gauss" );
    if ( c.flag_ring )     s += ( s.empty() ? "" : "+" ) + std::string( "ring" );
    if ( c.flag_noDivide ) s += ( s.empty() ? "" : "+" ) + std::string( "noDivide" );
    if ( c.flag_outerExp ) s += ( s.empty() ? "" : "+" ) + std::string( "outerExponent" );
    if ( c.flag_local )    s += ( s.empty() ? "" : "+" ) + std::string( "local" );
    return s.empty() ? "gauss" : s;
}

Envelope buildEnvelopeFromPanel( const PhoenixGUI::EnvelopeEditorPanel& p ) {
    Envelope tmp;
    for ( const auto& comp : p.components ) {
        tmp.addSpacial(
            comp.amp, comp.width_x, comp.width_y, comp.x, comp.y, comp.exponent,
            envTypeString( comp ),
            s_pol_names[comp.polarization_idx],
            s_behavior_names[comp.behavior_idx],
            std::to_string( comp.m ),
            comp.k0_x, comp.k0_y
        );
        tmp.addTemporal( p.temporal.t0, p.temporal.sigma, p.temporal.freq, s_temp_names[p.temporal.type_idx] );
    }
    // Manually initialise cache vector with null pointers so calculate() doesn't go out-of-bounds
    tmp.cache.resize( tmp.amp.size() );
    return tmp;
}

// Populate an editor panel's components and temporal from the descriptor's source_env.
// Called when a panel is first created and when the user switches target.
static void populatePanelFromEnvelope( PhoenixGUI::EnvelopeEditorPanel& p,
                                        const PhoenixGUI::EnvelopeDescriptor& desc ) {
    const Envelope* env = desc.source_env;
    p.components.clear();
    if ( !env || env->amp.empty() ) {
        p.selected_component = -1;     // leave components empty; snapshot loaded by caller
        p.preview_dirty = true;
        return;
    }
    for ( int i = 0; i < (int)env->amp.size(); i++ ) {
        PhoenixGUI::SpatialComponentEdit c;
        c.amp        = (float)env->amp[i];
        c.width_x    = (float)env->width_x[i];
        c.width_y    = (float)env->width_y[i];
        c.x          = (float)env->x[i];
        c.y          = (float)env->y[i];
        c.exponent   = (float)env->exponent[i];
        c.k0_x       = (float)env->k0_x[i];
        c.k0_y       = (float)env->k0_y[i];
        c.m          = env->m[i];
        // Reverse-map EnvType bitmask to flag booleans
        c.flag_gauss    = (env->type[i] & Envelope::EnvType::Gauss);
        c.flag_ring     = (env->type[i] & Envelope::EnvType::Ring);
        c.flag_noDivide = (env->type[i] & Envelope::EnvType::NoDivide);
        c.flag_outerExp = (env->type[i] & Envelope::EnvType::OuterExponent);
        c.flag_local    = (env->type[i] & Envelope::EnvType::Local);
        // Reverse-map Polarization enum to idx (0=plus, 1=minus, 2=both)
        if      ( env->pol[i] == Envelope::Polarization::Plus  ) c.polarization_idx = 0;
        else if ( env->pol[i] == Envelope::Polarization::Minus ) c.polarization_idx = 1;
        else                                                       c.polarization_idx = 2;
        // Reverse-map Behavior enum to idx (0=add, 1=multiply, 2=replace, 3=adaptive, 4=complex)
        if      ( env->behavior[i] == Envelope::Behavior::Multiply ) c.behavior_idx = 1;
        else if ( env->behavior[i] == Envelope::Behavior::Replace  ) c.behavior_idx = 2;
        else if ( env->behavior[i] == Envelope::Behavior::Adaptive ) c.behavior_idx = 3;
        else if ( env->behavior[i] == Envelope::Behavior::Complex  ) c.behavior_idx = 4;
        else                                                           c.behavior_idx = 0; // Add
        p.components.push_back( c );
    }
    p.selected_component = p.components.empty() ? -1 : 0;
    // Temporal: read first group (group 0) - t0/sigma/freq are indexed by group
    if ( env->groupSize() > 0 ) {
        p.temporal.t0    = (float)env->t0[0];
        p.temporal.sigma = (float)env->sigma[0];
        p.temporal.freq  = (float)env->freq[0];
        if      ( env->temporal[0] & Envelope::Temporal::Gauss ) p.temporal.type_idx = 1;
        else if ( env->temporal[0] & Envelope::Temporal::IExp  ) p.temporal.type_idx = 2;
        else if ( env->temporal[0] & Envelope::Temporal::Cos   ) p.temporal.type_idx = 3;
        else                                                       p.temporal.type_idx = 0;
    }
    p.preview_dirty = true;
}

// Download the current matrix data for the selected target into p.matrix_snapshot.
// Called whenever the user switches target, so the preview can show the current state
// when no envelope components are defined.
static void loadMatrixSnapshot( PhoenixGUI::EnvelopeEditorPanel& p,
                                const PhoenixGUI::EnvelopeDescriptor& desc ) {
    p.matrix_snapshot.clear();
    p.matrix_snapshot_is_real = false;
    if ( desc.host_target ) {
        p.matrix_snapshot.assign( desc.host_target->begin(), desc.host_target->end() );
    } else if ( desc.cmplx_target ) {
        const auto& hv = desc.cmplx_target->getHostVector(); // auto-downloads from device
        p.matrix_snapshot.assign( hv.begin(), hv.end() );
    } else if ( desc.real_target ) {
        const auto& hv = desc.real_target->getHostVector();
        p.matrix_snapshot.resize( hv.size() );
        for ( size_t i = 0; i < hv.size(); ++i )
            p.matrix_snapshot[i] = Type::complex{ hv[i], 0 };
        p.matrix_snapshot_is_real = true;
    }
}

} // anonymous namespace

// ============================================================
// buildEnvelopeRegistry - populate envelope_registry_
// ============================================================

void PhoenixGUI::buildEnvelopeRegistry() {
    envelope_registry_.clear();
    auto& sys = solver_.system;
    auto& mat = solver_.matrix;

    const std::string tip = "Not allocated at startup. Re-run with -dense to enable.";

    auto add = [&]( const char* label,
                    Envelope* env,
                    CUDAMatrix<Type::real>*    rt,
                    CUDAMatrix<Type::complex>* ct,
                    bool is_complex,
                    Envelope::Polarization pol,
                    bool avail ) {
        EnvelopeDescriptor d;
        d.label        = label;
        d.source_env   = env;
        d.real_target  = rt;
        d.cmplx_target = ct;
        d.is_complex   = is_complex;
        d.polarization = pol;
        d.available    = avail;
        d.unavail_reason = avail ? "" : tip;
        envelope_registry_.push_back( std::move( d ) );
    };

    // Helper for initial-state entries: write to host_vector AND sync to CUDAMatrix
    auto add_init = [&]( const char* label,
                         Type::host_vector<Type::complex>* hv,
                         CUDAMatrix<Type::complex>* cm,
                         Envelope::Polarization pol ) {
        EnvelopeDescriptor d;
        d.label        = label;
        d.source_env   = nullptr;
        d.real_target  = nullptr;
        d.cmplx_target = cm;
        d.host_target  = hv;
        d.is_complex   = true;
        d.polarization = pol;
        d.available    = true;
        envelope_registry_.push_back( std::move( d ) );
    };

    // ---- Pump / potential / pulse ----
    add( "pump+",      &sys.pump,      &mat.pump_plus,       nullptr,             false, Envelope::Polarization::Plus,  sys.use_pumps      );
    add( "potential+", &sys.potential, &mat.potential_plus,  nullptr,             false, Envelope::Polarization::Plus,  sys.use_potentials );
    add( "pulse+",     &sys.pulse,     nullptr,              &mat.pulse_plus,     true,  Envelope::Polarization::Plus,  sys.use_pulses     );

    if ( sys.use_twin_mode ) {
        add( "pump-",      &sys.pump,      &mat.pump_minus,      nullptr,             false, Envelope::Polarization::Minus, sys.use_pumps      );
        add( "potential-", &sys.potential, &mat.potential_minus, nullptr,             false, Envelope::Polarization::Minus, sys.use_potentials );
        add( "pulse-",     &sys.pulse,     nullptr,              &mat.pulse_minus,    true,  Envelope::Polarization::Minus, sys.use_pulses     );
    }

    // ---- Live wavefunction (Psi) ----
    add( "Psi+", nullptr, nullptr, &mat.wavefunction_plus,  true, Envelope::Polarization::Plus,  true );
    if ( sys.use_twin_mode )
        add( "Psi-", nullptr, nullptr, &mat.wavefunction_minus, true, Envelope::Polarization::Minus, true );

    // ---- Reservoir (n) ----
    if ( sys.use_reservoir ) {
        add( "n+", nullptr, nullptr, &mat.reservoir_plus,  true, Envelope::Polarization::Plus,  true );
        if ( sys.use_twin_mode )
            add( "n-", nullptr, nullptr, &mat.reservoir_minus, true, Envelope::Polarization::Minus, true );
    }

    // ---- Initial state (writes host buffer AND re-seeds running wavefunction) ----
    add_init( "init+", &mat.initial_state_plus,  &mat.wavefunction_plus,  Envelope::Polarization::Plus  );
    if ( sys.use_twin_mode )
        add_init( "init-", &mat.initial_state_minus, &mat.wavefunction_minus, Envelope::Polarization::Minus );
}

// ============================================================
// addEnvelopeEditorPanel - open a new Envelope Editor panel
// ============================================================

void PhoenixGUI::addEnvelopeEditorPanel() {
    const int W = (int)solver_.system.p.N_c;
    const int H = (int)solver_.system.p.N_r;
    const int id = next_env_editor_id_++;

    EnvelopeEditorPanel p;
    p.panel_id      = id;
    p.open          = true;
    p.title         = "Envelope Editor##enved_" + std::to_string( id );
    p.saved_dock_id = default_dock_id_;
    p.preview_w     = W;
    p.preview_h     = H;
    p.preview_tex   = std::make_unique<sf::RenderTexture>();
    p.preview_tex->create( W, H );
    p.preview_pix.resize( W * H );
    for ( int r = 0; r < H; r++ )
        for ( int c = 0; c < W; c++ )
            p.preview_pix[r * W + c] = sf::Vertex( sf::Vector2f( c + 0.5f, r + 0.5f ), sf::Color::Black );

    // Select first available target
    p.selected_target = 0;
    for ( int i = 0; i < (int)envelope_registry_.size(); i++ ) {
        if ( envelope_registry_[i].available ) { p.selected_target = i; break; }
    }

    // Populate components from existing envelope (loads CLI-defined parameters)
    if ( p.selected_target >= 0 && p.selected_target < (int)envelope_registry_.size() ) {
        populatePanelFromEnvelope( p, envelope_registry_[p.selected_target] );
        loadMatrixSnapshot( p, envelope_registry_[p.selected_target] );
    }

    p.preview_dirty = true;
    env_editor_panels_.push_back( std::move( p ) );
}

// ============================================================
// rebuildPreview - CPU-side envelope calculate → SFML texture
// ============================================================

void PhoenixGUI::rebuildPreview( EnvelopeEditorPanel& p ) {
    if ( !p.preview_dirty ) return;
    p.preview_dirty = false;

    const int W = p.preview_w, H = p.preview_h;
    if ( W == 0 || H == 0 ) return;
    if ( p.selected_target < 0 || p.selected_target >= (int)envelope_registry_.size() ) return;

    const auto& desc = envelope_registry_[p.selected_target];

    auto& sys = solver_.system;
    Envelope::Dimensions dim{
        (Type::uint32)sys.p.N_c, (Type::uint32)sys.p.N_r,
        sys.p.L_x, sys.p.L_y, sys.p.dx, sys.p.dy
    };

    Envelope tmp = buildEnvelopeFromPanel( p );

    const int N = W * H;

    // Choose colormap
    int idx = p.colormap_idx;
    ColorPalette* cp;
    if ( idx < 0 || idx >= (int)colormaps_.size() ) {
        const bool is_phase = ( p.preview_mode == EnvelopeEditorPanel::PreviewMode::Phase );
        cp = is_phase ? &colormaps_[1].palette : &colormaps_[0].palette;
    } else {
        cp = &colormaps_[idx].palette;
    }

    // Resolve noise seed once per rebuild (so apply reuses the same pattern)
    if ( p.noise.enabled ) {
        if ( p.noise.seed != 0 )
            p.noise.last_used_seed = (uint32_t)p.noise.seed;
        else if ( p.noise.last_used_seed == 0 )
            p.noise.last_used_seed = (uint32_t)std::random_device{}();
        // seed=0 + last_used_seed!=0: keep reusing last_used_seed until Re-roll or seed changes
    }

    if ( desc.is_complex ) {
        // Complex target: calculate into complex buffer
        std::vector<Type::complex> buf( N, Type::complex{ 0.0, 0.0 } );
        if ( !p.components.empty() )
            tmp.calculate( buf.data(), Envelope::AllGroups, desc.polarization, dim );
        else if ( !p.matrix_snapshot.empty() && (int)p.matrix_snapshot.size() == N && !p.noise.enabled )
            buf = p.matrix_snapshot;  // show current device data when no components defined

        if ( p.noise.enabled ) {
            const uint32_t s    = p.noise.last_used_seed;
            const Type::real amp = (Type::real)p.noise.amplitude;
            switch ( p.noise.type_idx ) {
                case 1:  Noise::addGaussianNoise( buf.data(), N, amp, s ); break;
                case 2:  Noise::addCorrelatedNoise( buf.data(), (size_t)W, (size_t)H, amp, s,
                             (Type::real)p.noise.correlation_length, sys.p.dx, sys.p.dy ); break;
                default: Noise::addUniformNoise( buf.data(), N, amp, s ); break;
            }
        }

        const bool is_phase = ( p.preview_mode == EnvelopeEditorPanel::PreviewMode::Phase );
        auto rawVal = [&]( int i ) -> double {
            switch ( p.preview_mode ) {
                case EnvelopeEditorPanel::PreviewMode::Abs:   return (double)CUDA::sqrt( CUDA::abs2( buf[i] ) );
                case EnvelopeEditorPanel::PreviewMode::Real:  return (double)CUDA::real( buf[i] );
                case EnvelopeEditorPanel::PreviewMode::Imag:  return (double)CUDA::imag( buf[i] );
                case EnvelopeEditorPanel::PreviewMode::Phase: return (double)CUDA::arg( buf[i] );
                default:                                      return (double)CUDA::abs2( buf[i] );
            }
        };
        auto displayVal = [&]( int i ) -> double {
            double v = rawVal( i );
            if ( p.log_scale && !is_phase ) v = std::log10( std::max( v, 1e-30 ) );
            return v;
        };

        double vmin, vmax;
        if ( is_phase ) { vmin = -std::numbers::pi; vmax = std::numbers::pi; }
        else if ( p.use_manual_range ) {
            vmin = p.manual_min; vmax = p.manual_max;
            if ( p.log_scale ) { vmin = std::log10( std::max( vmin, 1e-30 ) ); vmax = std::log10( std::max( vmax, 1e-30 ) ); }
        } else {
            vmin =  std::numeric_limits<double>::max();
            vmax = -std::numeric_limits<double>::max();
            for ( int i = 0; i < N; i++ ) { double v = displayVal( i ); if ( v < vmin ) vmin = v; if ( v > vmax ) vmax = v; }
            if ( vmax - vmin < 1e-30 ) vmax = vmin + 1e-30;
        }
        for ( int i = 0; i < N; i++ ) {
            double t = ( displayVal( i ) - vmin ) / ( vmax - vmin );
            t = std::max( 0.0, std::min( 1.0, t ) );
            auto& col = cp->getColor( t );
            p.preview_pix[i].color = sf::Color( col.r, col.g, col.b );
        }
    } else {
        // Real target (pump, potential): calculate into real buffer
        std::vector<Type::real> buf( N, Type::real{ 0.0 } );
        if ( !p.components.empty() )
            tmp.calculate( buf.data(), Envelope::AllGroups, desc.polarization, dim );
        else if ( !p.matrix_snapshot.empty() && (int)p.matrix_snapshot.size() == N && !p.noise.enabled ) {
            for ( int i = 0; i < N; i++ ) buf[i] = CUDA::real( p.matrix_snapshot[i] );
        }

        if ( p.noise.enabled ) {
            const uint32_t s    = p.noise.last_used_seed;
            const Type::real amp = (Type::real)p.noise.amplitude;
            switch ( p.noise.type_idx ) {
                case 1:  Noise::addGaussianNoise( buf.data(), N, amp, s ); break;
                case 2:  Noise::addCorrelatedNoise( buf.data(), (size_t)W, (size_t)H, amp, s,
                             (Type::real)p.noise.correlation_length, sys.p.dx, sys.p.dy ); break;
                default: Noise::addUniformNoise( buf.data(), N, amp, s ); break;
            }
        }

        auto displayVal = [&]( int i ) -> double {
            double v = (double)buf[i];
            if ( p.log_scale ) v = std::log10( std::max( v, 1e-30 ) );
            return v;
        };

        double vmin, vmax;
        if ( p.use_manual_range ) {
            vmin = p.manual_min; vmax = p.manual_max;
            if ( p.log_scale ) { vmin = std::log10( std::max( vmin, 1e-30 ) ); vmax = std::log10( std::max( vmax, 1e-30 ) ); }
        } else {
            vmin =  std::numeric_limits<double>::max();
            vmax = -std::numeric_limits<double>::max();
            for ( int i = 0; i < N; i++ ) { double v = displayVal( i ); if ( v < vmin ) vmin = v; if ( v > vmax ) vmax = v; }
            if ( vmax - vmin < 1e-30 ) vmax = vmin + 1e-30;
        }
        for ( int i = 0; i < N; i++ ) {
            double t = ( displayVal( i ) - vmin ) / ( vmax - vmin );
            t = std::max( 0.0, std::min( 1.0, t ) );
            auto& col = cp->getColor( t );
            p.preview_pix[i].color = sf::Color( col.r, col.g, col.b );
        }
    }

    p.preview_tex->clear( sf::Color::Black );
    p.preview_tex->draw( p.preview_pix.data(), N, sf::Points );
    p.preview_tex->display();
}

// ============================================================
// applyEnvelopeToMatrix - write editor state into GPU matrix
// ============================================================

void PhoenixGUI::applyEnvelopeToMatrix( EnvelopeEditorPanel& p, bool push_revision ) {
    // Pause the solver while writing host matrices and uploading to GPU so that
    // syncDisplayMatrices() (device→host) cannot race with hostToDeviceSync() (host→device).
    const bool auto_paused = pauseSolverForUpdate();

    if ( p.selected_target < 0 || p.selected_target >= (int)envelope_registry_.size() ) {
        resumeSolverAfterUpdate( auto_paused );
        return;
    }
    auto& desc = envelope_registry_[p.selected_target];

    if ( !desc.available ) {
        p.last_apply_status = "Error: matrix not allocated (run with -dense)";
        resumeSolverAfterUpdate( auto_paused );
        return;
    }

    // Save current state as a revision before overwriting (skipped during live apply)
    if ( push_revision ) {
        EnvelopeEditorPanel::Revision rev;
        rev.label      = "Rev " + std::to_string( p.revisions.size() + 1 )
                       + "  (" + desc.label + ", t=" + toScientific( solver_.system.p.t ) + ")";
        rev.components = p.components;
        rev.temporal   = p.temporal;
        p.revisions.push_back( std::move( rev ) );
    }

    auto& sys = solver_.system;
    Envelope::Dimensions dim{
        (Type::uint32)sys.p.N_c, (Type::uint32)sys.p.N_r,
        sys.p.L_x, sys.p.L_y, sys.p.dx, sys.p.dy
    };

    Envelope tmp = buildEnvelopeFromPanel( p );

    const size_t N_apply = (size_t)sys.p.N_c * (size_t)sys.p.N_r;

    // Helper lambda to apply noise to a buffer after envelope calculation
    auto applyNoise = [&]( Type::complex* ptr ) {
        if ( !p.noise.enabled ) return;
        const uint32_t s    = p.noise.last_used_seed;
        const Type::real amp  = (Type::real)p.noise.amplitude;
        const Type::real corr = (Type::real)p.noise.correlation_length;
        switch ( p.noise.type_idx ) {
            case 1:  Noise::addGaussianNoise( ptr, N_apply, amp, s ); break;
            case 2:  Noise::addCorrelatedNoise( ptr, sys.p.N_c, sys.p.N_r, amp, s, corr, sys.p.dx, sys.p.dy ); break;
            default: Noise::addUniformNoise( ptr, N_apply, amp, s ); break;
        }
    };
    auto applyNoiseReal = [&]( Type::real* ptr ) {
        if ( !p.noise.enabled ) return;
        const uint32_t s    = p.noise.last_used_seed;
        const Type::real amp  = (Type::real)p.noise.amplitude;
        const Type::real corr = (Type::real)p.noise.correlation_length;
        switch ( p.noise.type_idx ) {
            case 1:  Noise::addGaussianNoise( ptr, N_apply, amp, s ); break;
            case 2:  Noise::addCorrelatedNoise( ptr, sys.p.N_c, sys.p.N_r, amp, s, corr, sys.p.dx, sys.p.dy ); break;
            default: Noise::addUniformNoise( ptr, N_apply, amp, s ); break;
        }
    };

    if ( desc.host_target ) {
        // Initial-state target: write into host_vector, then seed wavefunction from it
        tmp.calculate( desc.host_target->data(), Envelope::AllGroups, desc.polarization, dim );
        applyNoise( desc.host_target->data() );
        if ( desc.cmplx_target )
            desc.cmplx_target->setTo( *desc.host_target ).hostToDeviceSync();
    } else if ( desc.real_target ) {
        auto* ptr = desc.real_target->getHostPtr( 0 );
        if ( !ptr ) { p.last_apply_status = "Error: matrix slot 0 is null"; resumeSolverAfterUpdate( auto_paused ); return; }
        tmp.calculate( ptr, Envelope::AllGroups, desc.polarization, dim );
        applyNoiseReal( ptr );
        desc.real_target->hostToDeviceSync( 0 );
    } else if ( desc.cmplx_target ) {
        auto* ptr = desc.cmplx_target->getHostPtr( 0 );
        if ( !ptr ) { p.last_apply_status = "Error: matrix slot 0 is null"; resumeSolverAfterUpdate( auto_paused ); return; }
        tmp.calculate( ptr, Envelope::AllGroups, desc.polarization, dim );
        applyNoise( ptr );
        desc.cmplx_target->hostToDeviceSync( 0 );
    }

    // Update the SystemParameters envelope so temporal updates and file output reflect new state.
    // Rebuild rather than copy-assign (Envelope has non-copyable unique_ptr cache member).
    if ( desc.source_env ) {
        *desc.source_env = Envelope{};  // move-assign from temporary (clears all fields)
        for ( const auto& comp : p.components ) {
            desc.source_env->addSpacial(
                comp.amp, comp.width_x, comp.width_y, comp.x, comp.y, comp.exponent,
                envTypeString( comp ),
                s_pol_names[comp.polarization_idx],
                s_behavior_names[comp.behavior_idx],
                std::to_string( comp.m ),
                comp.k0_x, comp.k0_y
            );
            desc.source_env->addTemporal( p.temporal.t0, p.temporal.sigma, p.temporal.freq, s_temp_names[p.temporal.type_idx] );
        }
        desc.source_env->temporal_envelope.assign( 1, Type::complex{ 1.0, 0.0 } );
    }

    solver_.parameters_are_dirty = true;

    p.last_apply_status = "Applied at t=" + toScientific( sys.p.t ) + " ps";
    resumeSolverAfterUpdate( auto_paused );
}

// ============================================================
// renderEnvelopeEditorPanel - main editor window
// ============================================================

void PhoenixGUI::renderEnvelopeEditorPanel( EnvelopeEditorPanel& p ) {
    // Rebuild CPU preview if dirty; live-apply to GPU if enabled
    const bool was_dirty = p.preview_dirty;
    rebuildPreview( p );
    if ( p.live_apply && was_dirty )
        applyEnvelopeToMatrix( p, /*push_revision=*/false );

    if ( p.saved_dock_id != 0 )
        ImGui::SetNextWindowDockID( p.saved_dock_id, ImGuiCond_Appearing );
    ImGui::SetNextWindowSize( ImVec2( 900, 620 ), ImGuiCond_FirstUseEver );
    if ( !ImGui::Begin( p.title.c_str(), &p.open ) ) {
        ImGui::End();
        return;
    }
    p.saved_dock_id = ImGui::GetWindowDockID();

    auto& sys = solver_.system;
    const float avail_x = ImGui::GetContentRegionAvail().x;
    const float left_w  = avail_x * 0.38f;

    // ---- LEFT COLUMN ----
    ImGui::BeginChild( "##enved_left", ImVec2( left_w, 0 ), false );

    // -- Target dropdown --
    {
        ImGui::TextUnformatted( "Target matrix:" );
        ImGui::SameLine();
        ImGui::SetNextItemWidth( -1.f );
        const char* preview = envelope_registry_.empty() ? "---"
            : envelope_registry_[p.selected_target].label.c_str();
        if ( ImGui::BeginCombo( "##envtarget", preview ) ) {
            for ( int i = 0; i < (int)envelope_registry_.size(); i++ ) {
                const auto& d = envelope_registry_[i];
                if ( !d.available ) {
                    ImGui::BeginDisabled();
                    ImGui::Selectable( d.label.c_str(), false );
                    ImGui::EndDisabled();
                    if ( ImGui::IsItemHovered( ImGuiHoveredFlags_AllowWhenDisabled ) )
                        ImGui::SetTooltip( "%s", d.unavail_reason.c_str() );
                } else {
                    bool sel = ( p.selected_target == i );
                    if ( ImGui::Selectable( d.label.c_str(), sel ) ) {
                        p.selected_target = i;
                        populatePanelFromEnvelope( p, d );
                        loadMatrixSnapshot( p, d );
                    }
                    if ( sel ) ImGui::SetItemDefaultFocus();
                }
            }
            ImGui::EndCombo();
        }
    }

    ImGui::Separator();

    // -- Spatial component list --
    {
        ImGui::TextUnformatted( "Spatial components:" );
        const float list_h = 100.f;
        if ( ImGui::BeginListBox( "##complist", ImVec2( -1, list_h ) ) ) {
            for ( int i = 0; i < (int)p.components.size(); i++ ) {
                const auto& c = p.components[i];
                char buf[80];
                snprintf( buf, sizeof( buf ), "[%d] amp=%.2f  (%.1f,%.1f)  %.2f×%.2f", i, c.amp, c.x, c.y, c.width_x, c.width_y );
                bool sel = ( p.selected_component == i );
                if ( ImGui::Selectable( buf, sel ) )
                    p.selected_component = i;
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndListBox();
        }
        if ( ImGui::Button( "+ Add" ) ) {
            p.components.emplace_back();
            p.selected_component = (int)p.components.size() - 1;
            p.preview_dirty = true;
        }
        ImGui::SameLine();
        if ( ImGui::Button( "- Remove" ) && p.selected_component >= 0 && p.selected_component < (int)p.components.size() ) {
            p.components.erase( p.components.begin() + p.selected_component );
            p.selected_component = std::min( p.selected_component, (int)p.components.size() - 1 );
            p.preview_dirty = true;
        }
    }

    // -- Per-component parameter editor --
    if ( p.selected_component >= 0 && p.selected_component < (int)p.components.size() ) {
        auto& c = p.components[p.selected_component];
        ImGui::Separator();
        ImGui::TextUnformatted( "Component parameters:" );

        auto markDirty = [&]() { p.preview_dirty = true; };

        ImGui::TextUnformatted( "Amplitude" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##amp",  &c.amp,   0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "Width X" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##wx",   &c.width_x, 0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "Width Y" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##wy",   &c.width_y, 0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "Center X" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##cx",   &c.x,     0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "Center Y" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##cy",   &c.y,     0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "Exponent" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##exp",  &c.exponent, 0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "k0_x" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##k0x",  &c.k0_x,  0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "k0_y" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##k0y",  &c.k0_y,  0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "Charge m" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputInt(   "##m",    &c.m ) ) markDirty();

        ImGui::Spacing();
        ImGui::TextUnformatted( "Type flags:" );
        if ( ImGui::Checkbox( "Gauss##fg",        &c.flag_gauss    ) ) markDirty();  ImGui::SameLine();
        if ( ImGui::Checkbox( "Ring##fr",         &c.flag_ring     ) ) markDirty();  ImGui::SameLine();
        if ( ImGui::Checkbox( "NoDivide##fn",     &c.flag_noDivide ) ) markDirty();
        if ( ImGui::Checkbox( "OuterExp##fo",     &c.flag_outerExp ) ) markDirty();  ImGui::SameLine();
        if ( ImGui::Checkbox( "Local##fl",        &c.flag_local    ) ) markDirty();

        ImGui::Spacing();
        ImGui::TextUnformatted( "Polarization:" );
        for ( int pi = 0; pi < 3; pi++ ) {
            if ( pi > 0 ) ImGui::SameLine();
            if ( ImGui::RadioButton( s_pol_names[pi], c.polarization_idx == pi ) ) {
                c.polarization_idx = pi; markDirty();
            }
        }

        ImGui::TextUnformatted( "Behavior:" );
        // Disable "complex" behavior for real (pump/potential) targets
        bool is_complex_target = ( p.selected_target >= 0 && p.selected_target < (int)envelope_registry_.size() )
                                  ? envelope_registry_[p.selected_target].is_complex : true;
        for ( int bi = 0; bi < 5; bi++ ) {
            if ( bi > 0 ) ImGui::SameLine();
            const bool disabled = ( bi == 4 && !is_complex_target );
            if ( disabled ) ImGui::BeginDisabled();
            if ( ImGui::RadioButton( s_behavior_names[bi], c.behavior_idx == bi ) ) {
                c.behavior_idx = bi; markDirty();
            }
            if ( disabled ) ImGui::EndDisabled();
        }
    }

    // -- Noise overlay --
    ImGui::Separator();
    if ( ImGui::CollapsingHeader( "Noise##noise_hdr" ) ) {
        if ( ImGui::Checkbox( "Enable noise overlay##nen", &p.noise.enabled ) )
            p.preview_dirty = true;

        if ( !p.noise.enabled ) ImGui::BeginDisabled();

        static const char* noise_type_names[] = { "Uniform", "Gaussian", "Correlated" };
        ImGui::SetNextItemWidth( 120.f );
        if ( ImGui::Combo( "Type##ntype", &p.noise.type_idx, noise_type_names, 3 ) )
            p.preview_dirty = true;
        ImGui::SameLine();
        ImGui::SetNextItemWidth( 100.f );
        if ( ImGui::DragFloat( "Amplitude##namp", &p.noise.amplitude, 1e-4f, 0.f, 1e9f, "%.3e" ) )
            p.preview_dirty = true;
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Uniform: max absolute value; Gaussian/Correlated: std-dev." );

        if ( p.noise.type_idx == 2 ) {
            ImGui::SetNextItemWidth( 140.f );
            if ( ImGui::DragFloat( "Corr. length##ncorr", &p.noise.correlation_length,
                                   0.01f, 0.f, 1000.f, "%.2f" ) )
                p.preview_dirty = true;
            if ( ImGui::IsItemHovered() )
                ImGui::SetTooltip( "Spatial correlation length (same units as L_x / L_y).\n"
                                   "Separable real-space Gaussian convolution." );
        }

        ImGui::SetNextItemWidth( 120.f );
        if ( ImGui::InputInt( "Seed##nseed", &p.noise.seed ) ) {
            if ( p.noise.seed < 0 ) p.noise.seed = 0;
            p.noise.last_used_seed = 0;  // force new seed on next rebuild
            p.preview_dirty = true;
        }
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "0 = new random seed each preview rebuild.\n"
                               "Non-zero = reproducible; same seed used when applying." );
        ImGui::SameLine();
        if ( ImGui::Button( "Re-roll##nreroll" ) ) {
            p.noise.last_used_seed = 0;
            p.preview_dirty = true;
        }
        if ( p.noise.enabled && p.noise.last_used_seed != 0 )
            ImGui::TextDisabled( "active seed: %u", p.noise.last_used_seed );

        if ( !p.noise.enabled ) ImGui::EndDisabled();
    }

    // -- Temporal section --
    ImGui::Separator();
    if ( ImGui::CollapsingHeader( "Temporal" ) ) {
        auto& t = p.temporal;
        auto markDirty = [&]() { p.preview_dirty = true; };
        ImGui::TextUnformatted( "Type:" );
        for ( int ti = 0; ti < 4; ti++ ) {
            if ( ti > 0 ) ImGui::SameLine();
            if ( ImGui::RadioButton( s_temp_names[ti], t.type_idx == ti ) ) {
                t.type_idx = ti; markDirty();
            }
        }
        const bool is_const = ( t.type_idx == 0 );
        if ( is_const ) ImGui::BeginDisabled();
        ImGui::TextUnformatted( "t0" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##temp_t0",  &t.t0,    0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "sigma" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##temp_s",   &t.sigma, 0.f, 0.f, "%.4f" ) ) markDirty();
        ImGui::TextUnformatted( "freq" );
        ImGui::SetNextItemWidth( -1.f );
        if ( ImGui::InputFloat( "##temp_f",   &t.freq,  0.f, 0.f, "%.4f" ) ) markDirty();
        if ( is_const ) ImGui::EndDisabled();

        // Live plot for non-constant temporal types
        if ( !is_const ) {
            const int N_plot = 256;
            const float abs_sigma = std::abs( t.sigma ) < 1e-9f ? 1.f : std::abs( t.sigma );
            const float t_lo = t.t0 - 4.f * abs_sigma;
            const float t_hi = t.t0 + 4.f * abs_sigma;
            std::vector<float> vals_re( N_plot, 0.f ), vals_im( N_plot, 0.f ), vals_abs( N_plot, 0.f );
            for ( int k = 0; k < N_plot; k++ ) {
                float tk = t_lo + ( t_hi - t_lo ) * k / float( N_plot - 1 );
                if ( t.type_idx == 1 ) {
                    // gauss
                    float v = (float)gaussian_envelope( (Type::real)tk, (Type::real)t.t0, (Type::real)t.sigma, (Type::real)t.freq );
                    vals_re[k] = v; vals_abs[k] = std::abs( v );
                } else if ( t.type_idx == 2 ) {
                    // iexp
                    Type::complex v = gaussian_complex_oscillator( (Type::real)tk, (Type::real)t.t0, (Type::real)t.sigma, (Type::real)t.freq );
                    vals_re[k]  = (float)CUDA::real( v );
                    vals_im[k]  = (float)CUDA::imag( v );
                    vals_abs[k] = (float)CUDA::sqrt( CUDA::abs2( v ) );
                } else if ( t.type_idx == 3 ) {
                    // cos
                    float v = (float)gaussian_oscillator( (Type::real)tk, (Type::real)t.t0, (Type::real)t.sigma, (Type::real)t.freq );
                    vals_re[k] = v; vals_abs[k] = std::abs( v );
                }
            }
            // Draw abs magnitude first (provides the frame background)
            ImVec2 plot_cursor = ImGui::GetCursorPos();
            ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 0.9f, 0.9f, 0.9f, 0.9f ) );
            ImGui::PlotLines( "##tabs", vals_abs.data(), N_plot, 0, nullptr, -1.1f, 1.1f, ImVec2( -1, 60 ) );
            ImGui::PopStyleColor();
            // For iexp: overlay Re (green) and Im (orange) with transparent backgrounds
            if ( t.type_idx == 2 ) {
                ImGui::SetCursorPos( plot_cursor );
                ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 0.3f, 1.0f, 0.3f, 0.9f ) );
                ImGui::PushStyleColor( ImGuiCol_FrameBg,   ImVec4( 0.0f, 0.0f, 0.0f, 0.0f ) );
                ImGui::PlotLines( "##tre", vals_re.data(), N_plot, 0, nullptr, -1.1f, 1.1f, ImVec2( -1, 60 ) );
                ImGui::PopStyleColor( 2 );
                ImGui::SetCursorPos( plot_cursor );
                ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 1.0f, 0.6f, 0.1f, 0.9f ) );
                ImGui::PushStyleColor( ImGuiCol_FrameBg,   ImVec4( 0.0f, 0.0f, 0.0f, 0.0f ) );
                ImGui::PlotLines( "##tim", vals_im.data(), N_plot, 0, nullptr, -1.1f, 1.1f, ImVec2( -1, 60 ) );
                ImGui::PopStyleColor( 2 );
            }
        }
    }

    ImGui::Separator();

    // -- Apply button + live apply checkbox --
    {
        const float avail = ImGui::GetContentRegionAvail().x;
        const float btn_w = avail * 0.65f;
        if ( ImGui::Button( "Apply to Matrix", ImVec2( btn_w, 0 ) ) )
            applyEnvelopeToMatrix( p );
        ImGui::SameLine();
        ImGui::Checkbox( "Live##live_apply", &p.live_apply );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "When active, every parameter change is immediately applied to the GPU matrix (no revision saved)." );
    }
    if ( !p.last_apply_status.empty() )
        ImGui::TextDisabled( "%s", p.last_apply_status.c_str() );

    // -- Revision history --
    if ( ImGui::CollapsingHeader( "Revisions" ) ) {
        if ( ImGui::BeginListBox( "##revlist", ImVec2( -1, 80 ) ) ) {
            for ( int i = 0; i < (int)p.revisions.size(); i++ ) {
                bool sel = ( i == p.selected_revision );
                if ( ImGui::Selectable( p.revisions[i].label.c_str(), sel ) )
                    p.selected_revision = i;
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndListBox();
        }
        const bool has_sel = ( p.selected_revision >= 0
                             && p.selected_revision < (int)p.revisions.size() );
        if ( !has_sel ) ImGui::BeginDisabled();
        if ( ImGui::Button( "Restore##rev", ImVec2( -1, 0 ) ) && has_sel ) {
            const auto& rev      = p.revisions[p.selected_revision];
            p.components         = rev.components;
            p.temporal           = rev.temporal;
            p.selected_component = p.components.empty() ? -1 : 0;
            p.preview_dirty      = true;
        }
        if ( !has_sel ) ImGui::EndDisabled();
    }

    ImGui::EndChild(); // left column

    // ---- RIGHT COLUMN (preview) ----
    ImGui::SameLine();
    ImGui::BeginChild( "##enved_right", ImVec2( 0, 0 ), false );

    const bool is_complex_target = ( p.selected_target >= 0 && p.selected_target < (int)envelope_registry_.size() )
                                    ? envelope_registry_[p.selected_target].is_complex : false;

    // Controls row
    if ( is_complex_target ) {
        ImGui::SetNextItemWidth( 90.f );
        int mode_int = (int)p.preview_mode;
        if ( ImGui::BeginCombo( "##previewmode", s_mode_names[mode_int] ) ) {
            for ( int m = 0; m < 5; m++ ) {
                bool sel = ( mode_int == m );
                if ( ImGui::Selectable( s_mode_names[m], sel ) ) {
                    p.preview_mode  = (EnvelopeEditorPanel::PreviewMode)m;
                    p.preview_dirty = true;
                }
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        ImGui::SameLine();
    }

    // Colormap combo
    {
        ImGui::SetNextItemWidth( 90.f );
        const char* cmap_preview = ( p.colormap_idx < 0 || p.colormap_idx >= (int)colormaps_.size() )
            ? "auto" : colormaps_[p.colormap_idx].name.c_str();
        if ( ImGui::BeginCombo( "##envpcmap", cmap_preview ) ) {
            if ( ImGui::Selectable( "auto", p.colormap_idx < 0 ) ) { p.colormap_idx = -1; p.preview_dirty = true; }
            if ( p.colormap_idx < 0 ) ImGui::SetItemDefaultFocus();
            for ( int i = 0; i < (int)colormaps_.size(); i++ ) {
                bool sel = ( p.colormap_idx == i );
                if ( ImGui::Selectable( colormaps_[i].name.c_str(), sel ) ) { p.colormap_idx = i; p.preview_dirty = true; }
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        ImGui::SameLine();
    }

    // Log scale & manual range
    {
        if ( ImGui::Checkbox( "Log##envplog", &p.log_scale ) ) p.preview_dirty = true;
        ImGui::SameLine();
        if ( ImGui::Checkbox( "Fix range##envpfr", &p.use_manual_range ) ) p.preview_dirty = true;
        ImGui::SameLine();
        ImGui::Checkbox( "Sqare##envsq", &p.square_aspect );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Force square pixels (letterbox to N_c:N_r aspect ratio)" );
        if ( p.use_manual_range ) {
            ImGui::SameLine();
            ImGui::SetNextItemWidth( 70.f );
            if ( ImGui::InputDouble( "##envpmin", &p.manual_min, 0, 0, "%.2e" ) ) p.preview_dirty = true;
            ImGui::SameLine();
            ImGui::SetNextItemWidth( 70.f );
            if ( ImGui::InputDouble( "##envpmax", &p.manual_max, 0, 0, "%.2e" ) ) p.preview_dirty = true;
        }
    }

    // Preview image (same zoom/pan logic as MatrixPanel)
    {
        ImVec2 avail = ImGui::GetContentRegionAvail();
        const float full_w = std::max( 1.f, avail.x );
        const float full_h = std::max( 1.f, avail.y );
        float off_x = 0.f, off_y = 0.f;
        ImVec2 img_size( full_w, full_h );
        if ( p.square_aspect && p.preview_w > 0 && p.preview_h > 0 ) {
            const float aspect = (float)p.preview_w / (float)p.preview_h;
            const float fit_w  = full_h * aspect;
            if ( fit_w <= full_w ) {
                img_size = ImVec2( fit_w, full_h );
                off_x    = ( full_w - fit_w ) * 0.5f;
            } else {
                img_size = ImVec2( full_w, full_w / aspect );
                off_y    = ( full_h - img_size.y ) * 0.5f;
            }
        }

        const float uv_size = 1.0f / p.zoom_scale;
        // SFML Y-flip: pan_v=0 → top of image → SFML GL v=1; same as MatrixPanel
        const ImVec2 uv0( p.pan_u,            1.0f - p.pan_v            );
        const ImVec2 uv1( p.pan_u + uv_size,  1.0f - p.pan_v - uv_size );

        ImDrawList* dl = ImGui::GetWindowDrawList();
        ImVec2 pre_cursor = ImGui::GetCursorScreenPos();

        // Fill letterbox background when square aspect is active
        if ( p.square_aspect )
            dl->AddRectFilled( pre_cursor,
                               ImVec2( pre_cursor.x + full_w, pre_cursor.y + full_h ),
                               ImGui::GetColorU32( ImGuiCol_WindowBg ) );

        ImVec2 img_cursor( pre_cursor.x + off_x, pre_cursor.y + off_y );
        ImVec2 img_p1( img_cursor.x + img_size.x, img_cursor.y + img_size.y );

        ImTextureID tex_id = nullptr;
        if ( p.preview_tex ) {
            const unsigned int gl_handle = p.preview_tex->getTexture().getNativeHandle();
            std::memcpy( &tex_id, &gl_handle, sizeof( unsigned int ) );
            dl->AddImage( tex_id, img_cursor, img_p1, uv0, uv1 );
        } else {
            dl->AddRectFilled( img_cursor, img_p1, IM_COL32( 20, 20, 30, 255 ) );
        }

        // InvisibleButton covers full layout space; interaction restricted to image bounds
        ImGui::InvisibleButton( "##canvas", ImVec2( full_w, full_h ) );
        const bool canvas_hovered = ImGui::IsItemHovered();
        const bool canvas_active  = ImGui::IsItemActive();

        const ImVec2 mp      = ImGui::GetIO().MousePos;
        const bool   in_image = mp.x >= img_cursor.x && mp.x <= img_p1.x
                             && mp.y >= img_cursor.y && mp.y <= img_p1.y;

        // Scroll-wheel zoom (toward cursor)
        if ( canvas_hovered && in_image ) {
            const float wheel = ImGui::GetIO().MouseWheel;
            if ( wheel != 0.0f ) {
                const float frac_c = ( mp.x - img_cursor.x ) / img_size.x;
                const float frac_r = ( mp.y - img_cursor.y ) / img_size.y;
                const float tex_u_under = p.pan_u + frac_c * uv_size;
                const float tex_v_under = p.pan_v + frac_r * uv_size;
                const float factor = ( wheel > 0.f ) ? 1.15f : ( 1.f / 1.15f );
                p.zoom_scale = std::clamp( p.zoom_scale * factor, 1.0f, 64.0f );
                const float new_uv = 1.0f / p.zoom_scale;
                p.pan_u = std::clamp( tex_u_under - frac_c * new_uv, 0.0f, 1.0f - new_uv );
                p.pan_v = std::clamp( tex_v_under - frac_r * new_uv, 0.0f, 1.0f - new_uv );
            }
        }

        // Left-drag to pan (when zoomed)
        if ( canvas_active && in_image && p.zoom_scale > 1.001f && !ImGui::IsMouseClicked( ImGuiMouseButton_Left ) ) {
            const ImVec2 delta  = ImGui::GetIO().MouseDelta;
            const float  cur_uv = 1.0f / p.zoom_scale;
            p.pan_u = std::clamp( p.pan_u - ( delta.x / img_size.x ) * cur_uv, 0.0f, 1.0f - cur_uv );
            p.pan_v = std::clamp( p.pan_v - ( delta.y / img_size.y ) * cur_uv, 0.0f, 1.0f - cur_uv );
        }

        // Double-click to reset zoom
        if ( canvas_hovered && in_image && ImGui::IsMouseDoubleClicked( ImGuiMouseButton_Left ) ) {
            p.zoom_scale = 1.f; p.pan_u = 0.f; p.pan_v = 0.f;
        }

        // Coordinate helpers (V is screen-top=0, screen-bottom=1; py is physics up=positive)
        const float L_x = (float)sys.p.L_x, L_y = (float)sys.p.L_y;
        auto physToScreen = [&]( float phx, float phy ) -> ImVec2 {
            float u = ( phx + L_x * 0.5f ) / L_x;
            float v = ( phy + L_y * 0.5f ) / L_y;  // match data layout: row 0 = y=-L_y/2 at top
            return { img_cursor.x + ( u - p.pan_u ) * p.zoom_scale * img_size.x,
                     img_cursor.y + ( v - p.pan_v ) * p.zoom_scale * img_size.y };
        };
        auto screenToPhys = [&]( ImVec2 sc ) -> std::pair<float,float> {
            float u = p.pan_u + ( sc.x - img_cursor.x ) / ( p.zoom_scale * img_size.x );
            float v = p.pan_v + ( sc.y - img_cursor.y ) / ( p.zoom_scale * img_size.y );
            return { u * L_x - L_x * 0.5f, v * L_y - L_y * 0.5f };
        };

        // Drag mechanics (component interaction on canvas)
        {
            ImVec2 mouse = ImGui::GetIO().MousePos;

            // Drag start - only when clicking inside the image (not the letterbox)
            if ( canvas_hovered && in_image && ImGui::IsMouseClicked( ImGuiMouseButton_Left )
                 && p.drag_mode == EnvelopeEditorPanel::DragMode::None ) {
                const float hit_r = 10.f;
                auto dist = [&]( ImVec2 a, ImVec2 b ) {
                    float dx = a.x - b.x, dy = a.y - b.y;
                    return std::sqrt( dx*dx + dy*dy );
                };
                for ( int ci = (int)p.components.size() - 1; ci >= 0; ci-- ) {
                    auto& comp = p.components[ci];
                    ImVec2 center = physToScreen( comp.x, comp.y );
                    ImVec2 hx     = physToScreen( comp.x + comp.width_x, comp.y );
                    ImVec2 hy     = physToScreen( comp.x, comp.y + comp.width_y );

                    if ( dist( mouse, hx ) < hit_r ) {
                        p.drag_mode = EnvelopeEditorPanel::DragMode::ResizeX;
                        p.drag_component = ci; p.drag_start_mouse = mouse;
                        p.drag_start_wx = comp.width_x; p.selected_component = ci;
                        break;
                    }
                    if ( dist( mouse, hy ) < hit_r ) {
                        p.drag_mode = EnvelopeEditorPanel::DragMode::ResizeY;
                        p.drag_component = ci; p.drag_start_mouse = mouse;
                        p.drag_start_wy = comp.width_y; p.selected_component = ci;
                        break;
                    }
                    if ( dist( mouse, center ) < hit_r ) {
                        p.drag_mode = EnvelopeEditorPanel::DragMode::Move;
                        p.drag_component = ci; p.drag_start_mouse = mouse;
                        p.drag_start_x = comp.x; p.drag_start_y = comp.y;
                        p.selected_component = ci;
                        break;
                    }
                }
            }

            // During drag - Y-flip: moving screen-down = physical-y decrease
            if ( p.drag_mode != EnvelopeEditorPanel::DragMode::None
                 && p.drag_component >= 0 && p.drag_component < (int)p.components.size() ) {
                if ( ImGui::IsMouseDown( ImGuiMouseButton_Left ) ) {
                    auto& comp = p.components[p.drag_component];
                    // dx_phys: right=+, dy_phys: up=+ (screen down = physical down = negative)
                    float dx_phys = ( mouse.x - p.drag_start_mouse.x ) / ( p.zoom_scale * img_size.x ) * L_x;
                    float dy_phys = +( mouse.y - p.drag_start_mouse.y ) / ( p.zoom_scale * img_size.y ) * L_y;
                    if ( p.drag_mode == EnvelopeEditorPanel::DragMode::Move ) {
                        comp.x = p.drag_start_x + dx_phys;
                        comp.y = p.drag_start_y + dy_phys;
                    } else if ( p.drag_mode == EnvelopeEditorPanel::DragMode::ResizeX ) {
                        comp.width_x = std::max( 0.01f, p.drag_start_wx + dx_phys );
                    } else if ( p.drag_mode == EnvelopeEditorPanel::DragMode::ResizeY ) {
                        // Handle is at (x, y+wy); moving it up = increasing wy
                        comp.width_y = std::max( 0.01f, p.drag_start_wy + dy_phys );
                    }
                    p.preview_dirty = true;
                } else {
                    p.drag_mode = EnvelopeEditorPanel::DragMode::None;
                }
            }

            // Right-click to add component at cursor position
            if ( canvas_hovered && ImGui::IsMouseClicked( ImGuiMouseButton_Right )
                 && p.drag_mode == EnvelopeEditorPanel::DragMode::None ) {
                auto [phx, phy] = screenToPhys( mouse );
                SpatialComponentEdit nc;
                nc.x = phx; nc.y = phy;
                p.components.push_back( nc );
                p.selected_component = (int)p.components.size() - 1;
                p.preview_dirty = true;
            }
        }

        // End drag when mouse is released
        if ( !ImGui::IsMouseDown( ImGuiMouseButton_Left ) )
            p.drag_mode = EnvelopeEditorPanel::DragMode::None;

        // Draw component overlays (reuse dl from above)
        for ( int ci = 0; ci < (int)p.components.size(); ci++ ) {
            const auto& comp = p.components[ci];
            ImVec2 center = physToScreen( comp.x, comp.y );
            ImVec2 hx     = physToScreen( comp.x + comp.width_x, comp.y );
            ImVec2 hy     = physToScreen( comp.x, comp.y + comp.width_y );

            float r = std::min(
                std::abs( hx.x - center.x ),
                std::abs( hy.y - center.y )
            );
            r = std::max( 3.f, std::min( r, 80.f ) );

            const bool is_sel = ( ci == p.selected_component );
            ImU32 col_circle  = is_sel ? IM_COL32( 255, 220, 50, 200 ) : IM_COL32( 180, 180, 255, 140 );
            ImU32 col_handle  = is_sel ? IM_COL32( 255, 100, 100, 220 ) : IM_COL32( 150, 200, 150, 180 );

            dl->AddCircle( center, r, col_circle, 32, 1.5f );
            dl->AddLine( center, hx, col_circle, 1.0f );
            dl->AddLine( center, hy, col_circle, 1.0f );
            dl->AddCircleFilled( hx, 5.f, col_handle );
            dl->AddCircleFilled( hy, 5.f, col_handle );
            dl->AddCircleFilled( center, 4.f, col_circle );
        }

        // ---- Minimap overlay (visible only when zoomed in) ----
        if ( p.zoom_scale > 1.01f && tex_id ) {
            const float cur_uv   = 1.0f / p.zoom_scale;
            const float mini_dim = std::max( 40.0f, std::min( img_size.x, img_size.y ) * 0.20f );
            const float margin   = 8.0f;
            const ImVec2 mini_p0( img_p1.x - mini_dim - margin, img_cursor.y + margin );
            const ImVec2 mini_p1( mini_p0.x + mini_dim,         mini_p0.y + mini_dim );

            dl->AddRectFilled( mini_p0, mini_p1, IM_COL32( 0, 0, 0, 160 ) );
            // Full-texture thumbnail (Y-flipped to match main view orientation)
            dl->AddImage( tex_id, mini_p0, mini_p1, ImVec2( 0, 1 ), ImVec2( 1, 0 ) );
            dl->AddRect( mini_p0, mini_p1, IM_COL32( 180, 180, 180, 200 ) );

            // Viewport rectangle
            const ImVec2 vp_p0( mini_p0.x + p.pan_u * mini_dim,
                                mini_p0.y + p.pan_v * mini_dim );
            const ImVec2 vp_p1( mini_p0.x + ( p.pan_u + cur_uv ) * mini_dim,
                                mini_p0.y + ( p.pan_v + cur_uv ) * mini_dim );
            dl->AddRect( vp_p0, vp_p1, IM_COL32( 255, 255, 255, 220 ), 0.f, 0, 1.5f );
        }
    }

    ImGui::EndChild(); // right column

    ImGui::End();
}

#endif  // SFML_RENDER

} // namespace PHOENIX
