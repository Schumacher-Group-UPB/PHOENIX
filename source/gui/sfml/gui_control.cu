#include "misc/gui.hpp"
#ifdef SFML_RENDER
#include "imgui_internal.h"
#endif
#include <cmath>
#include <complex>
#include <cstdio>
#include <numbers>
#include <algorithm>
#include <limits>
#include <random>
#include <sstream>
#include <iomanip>
#include "system/noise.hpp"

namespace PHOENIX {

#ifdef SFML_RENDER

// ============================================================
// renderControlWindow - floating simulation control window
// ============================================================

void PhoenixGUI::renderControlWindow( double sim_t, double elapsed, size_t iter ) {
    auto& sys = solver_.system;

    ImGui::SetNextWindowSize( ImVec2( 290, 520 ), ImGuiCond_FirstUseEver );
    ImGui::SetNextWindowPos( ImVec2( 10, 10 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Control##ctrl" );

    // ---- Simulation stats ----
    if ( ImGui::CollapsingHeader( "Simulation", ImGuiTreeNodeFlags_DefaultOpen ) ) {
        // Record dt every frame
        dt_history_.push_back( (float)sys.p.dt );
        if ( (int)dt_history_.size() > kDtHistMax )
            dt_history_.pop_front();

        // Two-column layout: labels left, dt mini-plot right
        if ( ImGui::BeginTable( "##sim_stats", 2, ImGuiTableFlags_None ) ) {
            ImGui::TableSetupColumn( "labels", ImGuiTableColumnFlags_WidthStretch, 0.55f );
            ImGui::TableSetupColumn( "plot",   ImGuiTableColumnFlags_WidthStretch, 0.45f );
            ImGui::TableNextRow();

            ImGui::TableSetColumnIndex( 0 );
            ImGui::Text( "t     = %.4f ps", (double)sys.p.t );
            ImGui::Text( "t_max = %.4f ps", (double)sys.t_max );
            ImGui::Text( "dt    = %.4e ps", (double)sys.p.dt );

            ImGui::TableSetColumnIndex( 1 );
            if ( dt_history_.size() >= 2 ) {
                dt_hist_window_ = std::max( 10, std::min( dt_hist_window_, kDtHistMax ) );
                const int dt_total  = (int)dt_history_.size();
                const int dt_window = std::min( dt_hist_window_, dt_total );
                const int dt_offset = dt_total - dt_window;
                std::vector<float> dtv( dt_history_.begin() + dt_offset, dt_history_.end() );
                float dt_min = *std::min_element( dtv.begin(), dtv.end() );
                float dt_max = *std::max_element( dtv.begin(), dtv.end() );
                if ( dt_max - dt_min < 1e-30f ) dt_max = dt_min + 1e-30f;
                char overlay[32];
                snprintf( overlay, sizeof( overlay ), "%.2e", dtv.back() );
                float plot_h = 3.0f * ImGui::GetTextLineHeightWithSpacing() - ImGui::GetFrameHeight() - ImGui::GetStyle().ItemSpacing.y;
                plot_h = std::max( 10.f, plot_h );
                char wlabel[24];
                if ( dt_hist_window_ >= kDtHistMax ) std::snprintf( wlabel, sizeof(wlabel), "All" );
                else                                  std::snprintf( wlabel, sizeof(wlabel), "%d", dt_hist_window_ );
                ImGui::SetNextItemWidth( -1.f );
                ImGui::SliderInt( "##hw_dt", &dt_hist_window_, 10, kDtHistMax, wlabel );
                ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 0.537f, 0.880f, 0.706f, 0.9f ) );
                ImGui::PlotLines( "##dt_hist", dtv.data(), (int)dtv.size(),
                                  0, overlay, dt_min, dt_max, ImVec2( -1, plot_h ) );
                ImGui::PopStyleColor();
            }

            ImGui::EndTable();
        }

        ImGui::PushStyleColor( ImGuiCol_PlotHistogram, ImVec4( 0.537f, 0.706f, 0.980f, 0.85f ) );
        ImGui::ProgressBar( (float)( sys.p.t / sys.t_max ), ImVec2( -1, 0 ) );
        ImGui::PopStyleColor();
        if ( elapsed > 0.0 ) {
            // Update rolling-average history
            rate_history_.push_back( { sim_t, elapsed } );
            if ( (int)rate_history_.size() > kRateHistMax )
                rate_history_.pop_front();

            ImGui::Text( "ps/s : %.1f",  sim_t / elapsed );
            ImGui::Text( "it/s : %.0f",  (double)iter / elapsed );
            ImGui::Text( "FPS  : %d",    window_.fps );

            // Rolling-average ETA
            double eta_s = -1.0;
            if ( rate_history_.size() >= 2 ) {
                const auto& oldest = rate_history_.front();
                const auto& newest = rate_history_.back();
                double dt_wall = newest.elapsed - oldest.elapsed;
                double dt_sim  = newest.sim_t   - oldest.sim_t;
                if ( dt_wall > 1e-9 && dt_sim > 0.0 ) {
                    double rate  = dt_sim / dt_wall;
                    double t_rem = (double)sys.t_max - sim_t;
                    if ( t_rem > 0.0 )
                        eta_s = t_rem / rate;
                }
            }

            if ( eta_s >= 0.0 ) {
                int h = (int)eta_s / 3600;
                int m = ( (int)eta_s % 3600 ) / 60;
                int s = (int)eta_s % 60;
                if ( h > 0 )
                    ImGui::Text( "ETA  : %dh %02dm", h, m );
                else if ( m > 0 )
                    ImGui::Text( "ETA  : %dm %02ds", m, s );
                else
                    ImGui::Text( "ETA  : %ds",       s );
            } else {
                ImGui::TextDisabled( "ETA  : --" );
            }
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
        if ( ImGui::Button( paused_ ? "Resume##ctrl" : "Pause##ctrl" ) ) {
            paused_ = !paused_;
            if ( st_ ) {
                st_->paused.store( paused_ );
                if ( !paused_ ) st_->pause_cv.notify_all();
            }
        }
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
        ImGui::SameLine();
        if ( ImGui::Button( "Envelope Editor" ) )
            addEnvelopeEditorPanel();
        ImGui::Separator();
        for ( auto& p : panels_ ) {
            bool vis = p.open;
            if ( ImGui::Checkbox( displayTitle( p.title ).c_str(), &vis ) )
                p.open = vis;
        }
    }

    ImGui::Separator();
    ImGui::TextDisabled( "[Space] Pause    [S] Snapshot    [T] Tile    [N] New view    [E] Envelope Editor" );

    ImGui::End();
}

// ============================================================
// renderMenuBar - top application menu bar
// ============================================================

void PhoenixGUI::renderMenuBar() {
    if ( ImGui::BeginMainMenuBar() ) {
        if ( ImGui::BeginMenu( "Windows" ) ) {
            if ( ImGui::MenuItem( "Parameters...", nullptr, params_show_panel_ ) )
                params_show_panel_ = !params_show_panel_;
            ImGui::MenuItem( "Plots",          nullptr, &show_plot_window_    );
            ImGui::MenuItem( "Envelopes",      nullptr, &show_env_window_     );
            ImGui::MenuItem( "Time Evolution", nullptr, &show_tracked_window_ );
            ImGui::MenuItem( "Kymograph",      nullptr, &show_tracked_cuts_window_ );
            ImGui::MenuItem( "Benchmarking",   nullptr, &show_benchmark_window_ );
            if ( ImGui::MenuItem( "Envelope Editor", "E" ) )
                addEnvelopeEditorPanel();
            ImGui::EndMenu();
        }
        if ( ImGui::BeginMenu( "Runstring" ) ) {
            if ( ImGui::MenuItem( "View Runstring", nullptr, show_runstring_window_ ) ) {
                show_runstring_window_ = !show_runstring_window_;
                if ( show_runstring_window_ ) {
                    runstring_cache_ = solver_.system.toRunstring();
                    runstring_buf_.assign( runstring_cache_.begin(), runstring_cache_.end() );
                    runstring_buf_.push_back( '\0' );
                }
            }
            ImGui::EndMenu();
        }
        if ( ImGui::BeginMenu( "Config" ) ) {
            if ( ImGui::MenuItem( "Save Config..." ) ) config_save_.open = true;
            if ( ImGui::MenuItem( "Load Config..." ) ) config_load_.open = true;
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
        if ( dirty ) {
            const bool ap = pauseSolverForUpdate();
            solver_.parameters_are_dirty = true;
            resumeSolverAfterUpdate( ap );
        }
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
        if ( dirty ) {
            const bool ap = pauseSolverForUpdate();
            solver_.parameters_are_dirty = true;
            resumeSolverAfterUpdate( ap );
        }
    }

    if ( ImGui::CollapsingHeader( "Effective Mass" ) ) {
        bool dirty = inputReal( "m_eff", p.m_eff );
        if ( dirty ) {
            const bool ap = pauseSolverForUpdate();
            solver_.parameters_are_dirty = true;
            resumeSolverAfterUpdate( ap );
        }
    }

    if ( ImGui::CollapsingHeader( "Stochastic" ) ) {
        const bool disabled = ( params_saved_.stochastic_amplitude == 0 );
        if ( disabled ) ImGui::BeginDisabled();
        bool dirty = inputReal( "stochastic_amplitude", p.stochastic_amplitude );
        if ( disabled ) ImGui::EndDisabled();
        if ( dirty ) {
            const bool ap = pauseSolverForUpdate();
            solver_.parameters_are_dirty = true;
            resumeSolverAfterUpdate( ap );
        }
    }

    ImGui::Separator();
    if ( ImGui::Button( "Save as Default" ) )
        params_saved_ = sys.kernel_parameters;
    ImGui::SameLine();
    if ( ImGui::Button( "Revert to Default" ) ) {
        const bool ap = pauseSolverForUpdate();
        sys.kernel_parameters = params_saved_;
        solver_.parameters_are_dirty = true;
        resumeSolverAfterUpdate( ap );
    }

    ImGui::End();
}

// ============================================================
// renderPlotsPanel - max history for all open panels
// ============================================================

void PhoenixGUI::renderPlotsPanel() {
    if ( !show_plot_window_ ) return;

    ImGui::SetNextWindowSize( ImVec2( 420, 420 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Plots", &show_plot_window_ );

    // Global window slider for all panels
    plots_hist_window_ = std::max( 10, std::min( plots_hist_window_, MatrixPanel::kMaxHist ) );
    {
        char wlabel[32];
        if ( plots_hist_window_ >= MatrixPanel::kMaxHist ) std::snprintf( wlabel, sizeof(wlabel), "Window: All" );
        else                                               std::snprintf( wlabel, sizeof(wlabel), "Window: %d", plots_hist_window_ );
        ImGui::SetNextItemWidth( -1.f );
        ImGui::SliderInt( "##hw_plots", &plots_hist_window_, 10, MatrixPanel::kMaxHist, wlabel );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Number of history samples to display for all panels" );
        ImGui::Separator();
    }

    auto displayTitle = []( const std::string& t ) -> std::string {
        auto pos = t.find( "##" );
        return ( pos != std::string::npos ) ? t.substr( 0, pos ) : t;
    };
    for ( auto& p : panels_ ) {
        if ( p.hist_max.empty() ) continue;
        const int total_p  = (int)p.hist_max.size();
        const int window_p = std::min( plots_hist_window_, total_p );
        const int offset_p = total_p - window_p;
        std::vector<float> maxv( p.hist_max.begin() + offset_p, p.hist_max.end() );
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
// renderEnvelopePlotWindow - temporal envelope amplitudes
// ============================================================

void PhoenixGUI::renderEnvelopePlotWindow() {
    if ( !show_env_window_ ) return;

    ImGui::SetNextWindowSize( ImVec2( 500, 420 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Envelope Temporal", &show_env_window_ );

    if ( env_histories_.empty() )
        ImGui::TextDisabled( "No time-dependent envelopes detected." );

    for ( auto& h : env_histories_ ) {
        if ( h.values.empty() ) continue;

        // Per-envelope window slider
        h.hist_window = std::max( 10, std::min( h.hist_window, EnvelopeHistory::kMaxHist ) );
        const int env_total  = (int)h.values.size();
        const int env_window = std::min( h.hist_window, env_total );
        const int env_offset = env_total - env_window;
        {
            char wlabel[32];
            if ( h.hist_window >= EnvelopeHistory::kMaxHist ) std::snprintf( wlabel, sizeof(wlabel), "Window: All" );
            else                                              std::snprintf( wlabel, sizeof(wlabel), "Window: %d", h.hist_window );
            ImGui::SetNextItemWidth( -1.f );
            ImGui::SliderInt( ( "##hw_env_" + h.label ).c_str(), &h.hist_window,
                               10, EnvelopeHistory::kMaxHist, wlabel );
        }

        std::vector<float> abs_v( h.values.begin()    + env_offset, h.values.end()    );
        std::vector<float> re_v ( h.values_re.begin() + env_offset, h.values_re.end() );
        std::vector<float> im_v ( h.values_im.begin() + env_offset, h.values_im.end() );
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
// renderTrackedPointsWindow - time evolution of tracked pixels
// ============================================================

namespace {
// Simple iterative Cooley-Tukey radix-2 FFT (in-place, power-of-2 length).
// Uses std::complex<float> — no external library needed.
static void _fft_inplace( std::vector<std::complex<float>>& x ) {
    const int N = (int)x.size();
    // Bit-reversal permutation
    for ( int i = 1, j = 0; i < N; ++i ) {
        int bit = N >> 1;
        for ( ; j & bit; bit >>= 1 ) j ^= bit;
        j ^= bit;
        if ( i < j ) std::swap( x[i], x[j] );
    }
    // Butterfly stages
    for ( int len = 2; len <= N; len <<= 1 ) {
        const float ang = -2.0f * 3.14159265358979f / (float)len;
        const std::complex<float> wlen( std::cos( ang ), std::sin( ang ) );
        for ( int i = 0; i < N; i += len ) {
            std::complex<float> w( 1.f, 0.f );
            for ( int k = 0; k < len / 2; ++k ) {
                std::complex<float> u = x[i + k];
                std::complex<float> v = x[i + k + len / 2] * w;
                x[i + k]             = u + v;
                x[i + k + len / 2]   = u - v;
                w *= wlen;
            }
        }
    }
}

// Zero-pads signal to next power-of-2, applies Hann window, computes FFT,
// then fills out_freq (1/ps) and out_mag (one-sided magnitude spectrum).
static void computeDisplayFFT( const float* samples, int n, float mean_dt_ps,
                                std::vector<float>& out_freq,
                                std::vector<float>& out_mag ) {
    if ( n < 2 || mean_dt_ps <= 0.f ) { out_freq.clear(); out_mag.clear(); return; }
    // Next power of 2
    int N = 1;
    while ( N < n ) N <<= 1;
    std::vector<std::complex<float>> buf( N, { 0.f, 0.f } );
    // Hann window + copy
    for ( int i = 0; i < n; ++i ) {
        float w = 0.5f * ( 1.f - std::cos( 2.f * 3.14159265358979f * i / (float)( n - 1 ) ) );
        buf[i] = { samples[i] * w, 0.f };
    }
    _fft_inplace( buf );
    // One-sided spectrum (DC to Nyquist)
    const int half = N / 2 + 1;
    out_freq.resize( half );
    out_mag.resize( half );
    const float df = 1.0f / ( (float)N * mean_dt_ps );
    for ( int k = 0; k < half; ++k ) {
        out_freq[k] = (float)k * df;
        out_mag[k]  = std::abs( buf[k] ) / (float)n;
    }
}
} // anonymous namespace

void PhoenixGUI::renderTrackedPointsWindow() {
    if ( !show_tracked_window_ ) return;

    ImGui::SetNextWindowSize( ImVec2( 720, 580 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Time Evolution##tev", &show_tracked_window_ );

    auto& sys = solver_.system;

    // ---- Controls row ----
    ImGui::Checkbox( "Overlay##tev_ovl", &tracked_overlay_mode_ );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "All points in one graph (on) vs individual graphs per point (off)" );
    ImGui::SameLine();
    ImGui::Checkbox( "FFT##tev_fft", &tracked_show_fft_ );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Show magnitude spectrum below time series\n"
                           "(Hann-windowed radix-2 FFT; assumes ~uniform dt)" );
    ImGui::SameLine();
    if ( ImGui::Button( "Clear All##tev_clr" ) )
        tracked_points_.clear();
    ImGui::SameLine();
    // Autoscale button — highlighted green when active
    if ( tracked_autoscale_ )
        ImGui::PushStyleColor( ImGuiCol_Button, ImVec4( 0.2f, 0.6f, 0.2f, 0.9f ) );
    if ( ImGui::Button( "Autoscale##tev_as" ) )
        tracked_autoscale_ = !tracked_autoscale_;
    if ( tracked_autoscale_ )
        ImGui::PopStyleColor();
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Autoscale axes (re-enable after manual zoom/pan)" );
    ImGui::SameLine();
    if ( ImGui::Button( "Export CSV##tev_exp" ) && !tracked_points_.empty() ) {
        std::string fname = "tracked_t" + std::to_string( (int)sys.p.t ) + ".csv";
        FILE* f = std::fopen( fname.c_str(), "w" );
        if ( f ) {
            std::fprintf( f, "time_ps" );
            for ( auto& tp : tracked_points_ )
                if ( tp.enabled )
                    std::fprintf( f, ",%s_abs,%s_re,%s_im,%s_arg",
                                  tp.label.c_str(), tp.label.c_str(),
                                  tp.label.c_str(), tp.label.c_str() );
            std::fprintf( f, "\n" );
            size_t min_len = 0;
            for ( auto& tp : tracked_points_ )
                if ( tp.enabled && !tp.times.empty() )
                    min_len = ( min_len == 0 ) ? tp.times.size()
                                              : std::min( min_len, tp.times.size() );
            const TrackedPoint* ref = nullptr;
            for ( auto& tp : tracked_points_ ) if ( tp.enabled && !tp.times.empty() ) { ref = &tp; break; }
            for ( size_t i = 0; i < min_len; ++i ) {
                std::fprintf( f, "%g", ref ? (double)ref->times[i] : (double)i );
                for ( auto& tp : tracked_points_ ) {
                    if ( !tp.enabled ) continue;
                    if ( i < tp.times.size() )
                        std::fprintf( f, ",%g,%g,%g,%g",
                                      (double)tp.values_abs[i], (double)tp.values_re[i],
                                      (double)tp.values_im[i],  (double)tp.values_arg[i] );
                }
                std::fprintf( f, "\n" );
            }
            std::fclose( f );
        }
    }
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Write all enabled point time series to CSV" );

    // ---- Window slider + max history input ----
    tracked_hist_window_ = std::clamp( tracked_hist_window_, 10, tracked_max_hist_ );
    {
        char wlabel[32];
        if ( tracked_hist_window_ >= tracked_max_hist_ )
            std::snprintf( wlabel, sizeof(wlabel), "Window: All" );
        else
            std::snprintf( wlabel, sizeof(wlabel), "Window: %d", tracked_hist_window_ );
        ImGui::SetNextItemWidth( -120.f );
        ImGui::SliderInt( "##tev_win", &tracked_hist_window_, 10, tracked_max_hist_, wlabel );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Number of samples to display (slide right = all)" );
        ImGui::SameLine();
        ImGui::SetNextItemWidth( 160.f );
        ImGui::InputInt( "Max##tev_mxh", &tracked_max_hist_, 256, 1024 );
        tracked_max_hist_ = std::clamp( tracked_max_hist_, 10, TrackedPoint::kMaxHist );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Maximum number of samples stored per tracked point\n"
                               "(reducing this value discards oldest data on the next frame)" );
    }

    ImGui::Separator();

    if ( tracked_points_.empty() ) {
        ImGui::TextDisabled( "No points tracked yet. Right-click a 2D image view to start." );
        ImGui::End();
        return;
    }

    // ---- Per-point list: enable toggle, label, component selectors, delete ----
    int to_delete = -1;
    for ( int i = 0; i < (int)tracked_points_.size(); ++i ) {
        auto& tp = tracked_points_[i];
        ImGui::PushID( i );

        ImGui::Checkbox( "##tev_en", &tp.enabled );
        ImGui::SameLine();
        ImGui::TextUnformatted( tp.label.c_str() );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "x=%.3f  y=%.3f  col=%d  row=%d\n%s",
                               (double)tp.x_phys, (double)tp.y_phys, tp.col, tp.row,
                               tp.is_complex ? "complex matrix" : "real matrix" );
        ImGui::SameLine();
        if ( ImGui::SmallButton( "x##tev_del" ) ) to_delete = i;

        // Component selectors on an indented second line
        ImGui::Indent( 22.f );
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 1.f, 1.f, 1.f, 1.f ) );
        ImGui::Checkbox( "|z|##tc_abs",          &tp.show_abs  );  ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 0.75f, 0.75f, 0.75f, 1.f ) );
        ImGui::Checkbox( "|z|²##tc_ab2",  &tp.show_abs2 );  ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 0.3f, 1.f, 0.3f, 1.f ) );
        ImGui::Checkbox( "Re##tc_re",            &tp.show_re   );  ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 1.f, 0.5f, 0.1f, 1.f ) );
        ImGui::Checkbox( "Im##tc_im",            &tp.show_im   );  ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::PushStyleColor( ImGuiCol_Text, ImVec4( 0.4f, 0.8f, 1.f, 1.f ) );
        ImGui::Checkbox( "arg##tc_arg",          &tp.show_arg  );  ImGui::PopStyleColor();
        ImGui::Unindent( 22.f );

        ImGui::PopID();
    }
    if ( to_delete >= 0 )
        tracked_points_.erase( tracked_points_.begin() + to_delete );

    ImGui::Separator();

    // Collect active (enabled + has data) indices
    std::vector<int> active;
    for ( int i = 0; i < (int)tracked_points_.size(); ++i )
        if ( tracked_points_[i].enabled && !tracked_points_[i].values_abs.empty() )
            active.push_back( i );

    if ( active.empty() ) {
        ImGui::TextDisabled( "All tracked points are disabled or have no data yet." );
        ImGui::End();
        return;
    }

    // Helper: windowed slice from a deque
    auto sliceDeque = []( const std::deque<float>& dq, int window ) -> std::vector<float> {
        const int total = (int)dq.size();
        const int w     = std::min( window, total );
        return std::vector<float>( dq.begin() + ( total - w ), dq.end() );
    };
    // Abs^2 computed on-the-fly
    auto sliceAbs2 = [&]( const TrackedPoint& tp ) {
        auto v = sliceDeque( tp.values_abs, tracked_hist_window_ );
        for ( auto& x : v ) x *= x;
        return v;
    };
    // Short legend name
    auto shortName = [&]( const TrackedPoint& tp ) -> std::string {
        const std::string& mat = matrix_registry_[tp.matrix_idx].label;
        char buf[64];
        std::snprintf( buf, sizeof(buf), "%s(%d,%d)", mat.c_str(), tp.col, tp.row );
        return buf;
    };

    // Component metadata
    struct CompInfo { const char* suffix; ImVec4 col; };
    static const CompInfo kComps[] = {
        { "|z|",         { 1.f,   1.f,   1.f,   1.f } },
        { "|z|²", { 0.75f, 0.75f, 0.75f, 1.f } },
        { "Re",          { 0.3f,  1.f,   0.3f,  1.f } },
        { "Im",          { 1.f,   0.5f,  0.1f,  1.f } },
        { "arg",         { 0.4f,  0.8f,  1.f,   1.f } },
    };

    const ImVec2 avail_tev  = ImGui::GetContentRegionAvail();
    const float  fft_frac   = tracked_show_fft_ ? 0.38f : 0.f;
    const float  ts_height  = std::max( 80.f, avail_tev.y * ( 1.f - fft_frac ) - 8.f );
    const float  fft_height = std::max( 80.f, avail_tev.y * fft_frac - 8.f );

    // ================================================================
    // Autoscale interaction detection — disable if user drags or scrolls
    // ================================================================
    if ( tracked_autoscale_ && tracked_plot_hovered_ ) {
        const auto& io = ImGui::GetIO();
        if ( io.MouseWheel != 0.f ||
             ImGui::IsMouseDragging( ImGuiMouseButton_Left ) ||
             ImGui::IsMouseDragging( ImGuiMouseButton_Right ) )
            tracked_autoscale_ = false;
    }
    tracked_plot_hovered_ = false;  // reset; set inside each BeginPlot block

    const ImPlotAxisFlags kAxisFlags = tracked_autoscale_
        ? ImPlotAxisFlags_AutoFit : ImPlotAxisFlags_None;

    // ================================================================
    // Overlay mode
    // ================================================================
    if ( tracked_overlay_mode_ ) {
        if ( ImPlot::BeginPlot( "##tev_ts", ImVec2( -1.f, ts_height ) ) ) {
            ImPlot::SetupAxis( ImAxis_X1, "Time (ps)", kAxisFlags );
            ImPlot::SetupAxis( ImAxis_Y1, "Value",     kAxisFlags );
            ImPlot::SetupAxisFormat( ImAxis_Y1, "%.3e" );
            if ( ImPlot::IsPlotHovered() ) tracked_plot_hovered_ = true;

            for ( int idx : active ) {
                const auto& tp = tracked_points_[idx];
                const std::string sn = shortName( tp );
                auto tv = sliceDeque( tp.times, tracked_hist_window_ );
                const int n = (int)tv.size();
                if ( n < 1 ) continue;

                auto plotComp = [&]( const std::vector<float>& yv, const CompInfo& ci ) {
                    if ( (int)yv.size() < n ) return;
                    ImPlot::SetNextLineStyle( ImVec4( ci.col.x, ci.col.y, ci.col.z, 0.9f ) );
                    std::string lbl = sn + " " + ci.suffix;
                    ImPlot::PlotLine( lbl.c_str(), tv.data(), yv.data(), n );
                };

                if ( tp.show_abs  ) { auto v = sliceDeque( tp.values_abs, tracked_hist_window_ ); plotComp( v, kComps[0] ); }
                if ( tp.show_abs2 ) { auto v = sliceAbs2( tp );                                   plotComp( v, kComps[1] ); }
                if ( tp.show_re   ) { auto v = sliceDeque( tp.values_re,  tracked_hist_window_ ); plotComp( v, kComps[2] ); }
                if ( tp.show_im   ) { auto v = sliceDeque( tp.values_im,  tracked_hist_window_ ); plotComp( v, kComps[3] ); }
                if ( tp.show_arg  ) { auto v = sliceDeque( tp.values_arg, tracked_hist_window_ ); plotComp( v, kComps[4] ); }
            }
            ImPlot::EndPlot();
        }

        if ( tracked_show_fft_ ) {
            if ( ImPlot::BeginPlot( "##tev_fft_ovl", ImVec2( -1.f, fft_height ) ) ) {
                ImPlot::SetupAxis( ImAxis_X1, "Frequency (1/ps)", kAxisFlags );
                ImPlot::SetupAxis( ImAxis_Y1, "|Amplitude|",      kAxisFlags );
                ImPlot::SetupAxisFormat( ImAxis_Y1, "%.2e" );
                if ( ImPlot::IsPlotHovered() ) tracked_plot_hovered_ = true;
                for ( int idx : active ) {
                    const auto& tp = tracked_points_[idx];
                    const std::string sn = shortName( tp );
                    auto tv = sliceDeque( tp.times, tracked_hist_window_ );
                    const int n = (int)tv.size();
                    if ( n < 2 ) continue;
                    float mean_dt = ( n >= 2 )
                        ? ( tv.back() - tv.front() ) / (float)std::max( 1, n - 1 )
                        : 0.f;

                    struct FftComp { bool enabled; const float* src_begin; int deque_offset; const CompInfo* ci; };
                    auto abs2src  = sliceAbs2( tp );  // pre-computed
                    auto absv     = sliceDeque( tp.values_abs, tracked_hist_window_ );
                    auto rev      = sliceDeque( tp.values_re,  tracked_hist_window_ );
                    auto imv      = sliceDeque( tp.values_im,  tracked_hist_window_ );
                    auto argv     = sliceDeque( tp.values_arg, tracked_hist_window_ );

                    auto doFftLine = [&]( bool show, const std::vector<float>& dat, const CompInfo& ci ) {
                        if ( !show || (int)dat.size() < 2 ) return;
                        std::vector<float> ffreq, fmag;
                        computeDisplayFFT( dat.data(), (int)dat.size(), mean_dt, ffreq, fmag );
                        if ( fmag.empty() ) return;
                        ImPlot::SetNextLineStyle( ImVec4( ci.col.x, ci.col.y, ci.col.z, 0.9f ) );
                        std::string lbl = sn + " " + ci.suffix;
                        ImPlot::PlotLine( lbl.c_str(), ffreq.data(), fmag.data(), (int)fmag.size() );
                    };
                    doFftLine( tp.show_abs,  absv,    kComps[0] );
                    doFftLine( tp.show_abs2, abs2src, kComps[1] );
                    doFftLine( tp.show_re,   rev,     kComps[2] );
                    doFftLine( tp.show_im,   imv,     kComps[3] );
                    doFftLine( tp.show_arg,  argv,    kComps[4] );
                }
                ImPlot::EndPlot();
            }
        }

    // ================================================================
    // Individual mode
    // ================================================================
    } else {
        const int   n_active = (int)active.size();
        const float each_ts  = std::max( 60.f, ts_height  / (float)n_active - 4.f );
        const float each_fft = tracked_show_fft_
                               ? std::max( 40.f, fft_height / (float)n_active - 4.f )
                               : 0.f;

        for ( int pi = 0; pi < n_active; ++pi ) {
            const int idx = active[pi];
            auto& tp      = tracked_points_[idx];

            ImGui::PushID( idx );

            {
                char plt_id[32]; std::snprintf( plt_id, sizeof(plt_id), "##tev_ind_%d", idx );
                if ( ImPlot::BeginPlot( plt_id, ImVec2( -1.f, each_ts ) ) ) {
                    ImPlot::SetupAxis( ImAxis_X1, "Time (ps)",     kAxisFlags );
                    ImPlot::SetupAxis( ImAxis_Y1, tp.label.c_str(), kAxisFlags );
                    ImPlot::SetupAxisFormat( ImAxis_Y1, "%.3e" );
                    if ( ImPlot::IsPlotHovered() ) tracked_plot_hovered_ = true;

                    auto tv = sliceDeque( tp.times, tracked_hist_window_ );
                    const int n = (int)tv.size();

                    auto plotComp = [&]( const std::vector<float>& yv, const CompInfo& ci ) {
                        if ( n < 1 || (int)yv.size() < n ) return;
                        ImPlot::SetNextLineStyle( ImVec4( ci.col.x, ci.col.y, ci.col.z, 0.9f ) );
                        ImPlot::PlotLine( ci.suffix, tv.data(), yv.data(), n );
                    };

                    if ( tp.show_abs  ) { auto v = sliceDeque( tp.values_abs, tracked_hist_window_ ); plotComp( v, kComps[0] ); }
                    if ( tp.show_abs2 ) { auto v = sliceAbs2( tp );                                   plotComp( v, kComps[1] ); }
                    if ( tp.show_re   ) { auto v = sliceDeque( tp.values_re,  tracked_hist_window_ ); plotComp( v, kComps[2] ); }
                    if ( tp.show_im   ) { auto v = sliceDeque( tp.values_im,  tracked_hist_window_ ); plotComp( v, kComps[3] ); }
                    if ( tp.show_arg  ) { auto v = sliceDeque( tp.values_arg, tracked_hist_window_ ); plotComp( v, kComps[4] ); }

                    ImPlot::EndPlot();
                }
            }

            if ( tracked_show_fft_ ) {
                char fft_id[32]; std::snprintf( fft_id, sizeof(fft_id), "##tev_ifft_%d", idx );
                if ( ImPlot::BeginPlot( fft_id, ImVec2( -1.f, each_fft ) ) ) {
                    ImPlot::SetupAxis( ImAxis_X1, "Frequency (1/ps)", kAxisFlags );
                    ImPlot::SetupAxis( ImAxis_Y1, "|Amplitude|",      kAxisFlags );
                    ImPlot::SetupAxisFormat( ImAxis_Y1, "%.2e" );
                    if ( ImPlot::IsPlotHovered() ) tracked_plot_hovered_ = true;

                    auto tv      = sliceDeque( tp.times,          tracked_hist_window_ );
                    auto absv    = sliceDeque( tp.values_abs,      tracked_hist_window_ );
                    auto abs2src = sliceAbs2( tp );
                    auto rev     = sliceDeque( tp.values_re,       tracked_hist_window_ );
                    auto imv     = sliceDeque( tp.values_im,       tracked_hist_window_ );
                    auto argv    = sliceDeque( tp.values_arg,      tracked_hist_window_ );
                    const int n  = (int)tv.size();
                    float mean_dt = ( n >= 2 )
                        ? ( tv.back() - tv.front() ) / (float)std::max( 1, n - 1 )
                        : 0.f;

                    auto doFftLine = [&]( bool show, const std::vector<float>& dat, const CompInfo& ci ) {
                        if ( !show || (int)dat.size() < 2 ) return;
                        std::vector<float> ffreq, fmag;
                        computeDisplayFFT( dat.data(), (int)dat.size(), mean_dt, ffreq, fmag );
                        if ( fmag.empty() ) return;
                        ImPlot::SetNextLineStyle( ImVec4( ci.col.x, ci.col.y, ci.col.z, 0.9f ) );
                        ImPlot::PlotLine( ci.suffix, ffreq.data(), fmag.data(), (int)fmag.size() );
                    };
                    doFftLine( tp.show_abs,  absv,    kComps[0] );
                    doFftLine( tp.show_abs2, abs2src, kComps[1] );
                    doFftLine( tp.show_re,   rev,     kComps[2] );
                    doFftLine( tp.show_im,   imv,     kComps[3] );
                    doFftLine( tp.show_arg,  argv,    kComps[4] );
                    ImPlot::EndPlot();
                }
            }

            ImGui::PopID();
        }
    }

    ImGui::End();
}

// ============================================================
// renderTrackedCutsWindow - kymograph (space-time) heatmaps
// ============================================================

void PhoenixGUI::renderTrackedCutsWindow() {
    if ( !show_tracked_cuts_window_ ) return;

    auto& sys = solver_.system;

    ImGui::SetNextWindowSize( ImVec2( 780, 640 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Kymograph##kymo", &show_tracked_cuts_window_ );

    // ---- Top controls ----
    if ( ImGui::Button( "Clear All##kymo_clr" ) )
        tracked_cuts_.clear();
    ImGui::SameLine();
    {
        cut_hist_window_ = std::clamp( cut_hist_window_, 10, cut_max_hist_ );
        char wlabel[32];
        if ( cut_hist_window_ >= cut_max_hist_ )
            std::snprintf( wlabel, sizeof( wlabel ), "Window: All" );
        else
            std::snprintf( wlabel, sizeof( wlabel ), "Window: %d", cut_hist_window_ );
        ImGui::SetNextItemWidth( -220.f );
        ImGui::SliderInt( "##kymo_win", &cut_hist_window_, 10, cut_max_hist_, wlabel );
        ImGui::SameLine();
        ImGui::SetNextItemWidth( 120.f );
        ImGui::InputInt( "Max##kymo_mxh", &cut_max_hist_, 64, 256 );
        cut_max_hist_ = std::clamp( cut_max_hist_, 10, TrackedCut::kMaxHist );
    }
    ImGui::SameLine();
    if ( ImGui::Button( "Export CSV##kymo_exp" ) ) {
        for ( auto& tc : tracked_cuts_ ) {
            if ( !tc.enabled || tc.times.empty() ) continue;
            char fname[256];
            std::string safe = tc.label.substr( 0, 30 );
            for ( auto& ch : safe ) if ( ch == ' ' || ch == '|' || ch == '/' || ch == ':' ) ch = '_';
            std::snprintf( fname, sizeof( fname ), "kymo_%s_t%d.csv", safe.c_str(), (int)sys.p.t );
            FILE* f = std::fopen( fname, "w" );
            if ( !f ) continue;
            const double dx   = (double)( tc.slice_axis == 0 ? sys.p.L_y : sys.p.L_x ) / (double)tc.slice_len;
            const double x0   = -0.5 * (double)( tc.slice_axis == 0 ? sys.p.L_y : sys.p.L_x );
            std::fprintf( f, "time_ps" );
            for ( int c = 0; c < tc.slice_len; ++c )
                std::fprintf( f, ",%.6g", x0 + ( c + 0.5 ) * dx );
            std::fprintf( f, "\n" );
            const int n = (int)tc.times.size();
            for ( int r = 0; r < n; ++r ) {
                std::fprintf( f, "%g", (double)tc.times[r] );
                for ( int c = 0; c < tc.slice_len; ++c ) {
                    double v = ( r < (int)tc.frames_abs.size() && c < (int)tc.frames_abs[r].size() )
                               ? (double)tc.frames_abs[r][c] : 0.0;
                    std::fprintf( f, ",%g", v );
                }
                std::fprintf( f, "\n" );
            }
            std::fclose( f );
        }
    }
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Export each tracked cut to a CSV file (abs values, rows=time, cols=position)" );

    ImGui::Separator();

    if ( tracked_cuts_.empty() ) {
        ImGui::TextDisabled( "No cuts tracked yet. In Line Cut mode, click 'Track' or right-click the plot." );
        ImGui::End();
        return;
    }

    // ---- Per-cut list ----
    int to_delete = -1;
    for ( int i = 0; i < (int)tracked_cuts_.size(); ++i ) {
        auto& tc = tracked_cuts_[i];
        ImGui::PushID( i );
        ImGui::Checkbox( "##kymo_en", &tc.enabled );
        ImGui::SameLine();
        ImGui::TextUnformatted( tc.label.c_str() );
        ImGui::SameLine();
        if ( ImGui::SmallButton( "x##kymo_del" ) ) to_delete = i;

        ImGui::Indent( 22.f );
        static const char* comp_names[] = { "|z|", "|z|^2", "Re", "Im", "arg" };
        int comp_int = (int)tc.display_comp;
        ImGui::SetNextItemWidth( 72.f );
        if ( ImGui::BeginCombo( "##comp", comp_names[comp_int] ) ) {
            for ( int m = 0; m < 5; ++m ) {
                bool sel = ( comp_int == m );
                if ( ImGui::Selectable( comp_names[m], sel ) )
                    tc.display_comp = (TrackedCut::DisplayComp)m;
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        ImGui::SameLine();
        const char* cmap_preview = ( tc.colormap_idx < 0 || tc.colormap_idx >= (int)colormaps_.size() )
            ? "auto" : colormaps_[tc.colormap_idx].name.c_str();
        ImGui::SetNextItemWidth( 80.f );
        if ( ImGui::BeginCombo( "##cmap", cmap_preview ) ) {
            bool sel_auto = ( tc.colormap_idx < 0 );
            if ( ImGui::Selectable( "auto", sel_auto ) ) tc.colormap_idx = -1;
            if ( sel_auto ) ImGui::SetItemDefaultFocus();
            for ( int k = 0; k < (int)colormaps_.size(); ++k ) {
                bool sel = ( tc.colormap_idx == k );
                if ( ImGui::Selectable( colormaps_[k].name.c_str(), sel ) ) tc.colormap_idx = k;
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        ImGui::SameLine();
        ImGui::Checkbox( "Fix range##fr", &tc.use_manual_range );
        if ( tc.use_manual_range ) {
            ImGui::SameLine();
            ImGui::SetNextItemWidth( 90.f );
            ImGui::InputDouble( "##kymin", &tc.manual_min, 0.0, 0.0, "%.3e" );
            ImGui::SameLine();
            ImGui::SetNextItemWidth( 90.f );
            ImGui::InputDouble( "##kymax", &tc.manual_max, 0.0, 0.0, "%.3e" );
        }
        ImGui::SameLine();
        ImGui::Checkbox( "k-FFT##sfft", &tc.show_spatial_fft );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Show k-space kymograph (FFT along the spatial axis)" );
        ImGui::SameLine();
        ImGui::Checkbox( "f-FFT##tfft", &tc.show_temporal_fft );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Show spectrogram (per-column FFT across the time axis)" );
        ImGui::Unindent( 22.f );
        ImGui::PopID();
    }
    if ( to_delete >= 0 )
        tracked_cuts_.erase( tracked_cuts_.begin() + to_delete );

    ImGui::Separator();

    // Count active cuts so we can distribute available height
    int n_active = 0;
    for ( const auto& tc : tracked_cuts_ )
        if ( tc.enabled && !tc.times.empty() ) ++n_active;
    if ( n_active == 0 ) { ImGui::End(); return; }

    const float avail_h = ImGui::GetContentRegionAvail().y;
    const float plot_h  = std::max( 100.f, avail_h / (float)n_active - 6.f );
    const float bar_w   = 55.f;

    // ---- Heatmap plots ----
    for ( int i = 0; i < (int)tracked_cuts_.size(); ++i ) {
        auto& tc = tracked_cuts_[i];
        if ( !tc.enabled || tc.times.empty() ) continue;
        ImGui::PushID( 0x1000 + i );

        const int total_frames = (int)tc.times.size();
        const int n_frames     = std::min( cut_hist_window_, total_frames );
        const int frame_offset = total_frames - n_frames;
        const int n_cols       = tc.slice_len;

        // Select source data based on display component
        const std::deque<std::vector<float>>* src = &tc.frames_abs;
        switch ( tc.display_comp ) {
            case TrackedCut::DisplayComp::Re:  src = &tc.frames_re;  break;
            case TrackedCut::DisplayComp::Im:  src = &tc.frames_im;  break;
            case TrackedCut::DisplayComp::Arg: src = &tc.frames_arg; break;
            default: break;
        }
        const bool do_abs2 = ( tc.display_comp == TrackedCut::DisplayComp::Abs2 );

        // Flatten to contiguous row-major [n_frames × n_cols]  (row=time, col=space)
        std::vector<float> flat( (size_t)n_frames * (size_t)n_cols, 0.f );
        for ( int r = 0; r < n_frames; ++r ) {
            const auto& row = (*src)[frame_offset + r];
            const int actual = std::min( n_cols, (int)row.size() );
            for ( int c = 0; c < actual; ++c ) {
                float v = row[c];
                flat[(size_t)r * (size_t)n_cols + c] = do_abs2 ? v * v : v;
            }
        }

        double vmin = tc.use_manual_range ? tc.manual_min
            : (double)*std::min_element( flat.begin(), flat.end() );
        double vmax = tc.use_manual_range ? tc.manual_max
            : (double)*std::max_element( flat.begin(), flat.end() );
        if ( vmax - vmin < 1e-30 ) vmax = vmin + 1e-30;

        const double phys_len = (double)( tc.slice_axis == 0 ? sys.p.L_y : sys.p.L_x );
        const double x_min    = -0.5 * phys_len;
        const double x_max    =  0.5 * phys_len;
        const double t_lo     = (double)tc.times[frame_offset];
        const double t_hi     = (double)tc.times[frame_offset + n_frames - 1];

        // Resolve colormap (default to vik = first registered)
        ImPlotColormap cmap = ImPlotColormap_Viridis;
        if ( implot_colormap_base_ >= 0 ) {
            int cm = ( tc.colormap_idx < 0 ) ? 0
                     : std::clamp( tc.colormap_idx, 0, (int)colormaps_.size() - 1 );
            cmap = (ImPlotColormap)( implot_colormap_base_ + cm );
        }

        // --- Main kymograph heatmap ---
        ImPlot::PushColormap( cmap );
        ImPlot::ColormapScale( "##ks", vmin, vmax, ImVec2( bar_w, plot_h ) );
        ImGui::SameLine();
        char plot_id[64];
        std::snprintf( plot_id, sizeof( plot_id ), "##kymo_%d", i );
        if ( ImPlot::BeginPlot( plot_id, ImVec2( -1.f, plot_h ) ) ) {
            const char* xlab = ( tc.slice_axis == 0 ) ? "y (um)" : "x (um)";
            ImPlot::SetupAxes( xlab, "Time (ps)" );
            ImPlot::SetupAxisLimits( ImAxis_X1, x_min, x_max, ImPlotCond_Always );
            ImPlot::SetupAxisLimits( ImAxis_Y1, t_lo,  t_hi,  ImPlotCond_Always );
            ImPlot::PlotHeatmap( tc.label.c_str(),
                                 flat.data(), n_frames, n_cols,
                                 vmin, vmax, nullptr,
                                 ImPlotPoint( x_min, t_lo ),
                                 ImPlotPoint( x_max, t_hi ) );
            ImPlot::EndPlot();
        }
        ImPlot::PopColormap();

        // --- Optional: k-space kymograph (spatial FFT per frame) ---
        if ( tc.show_spatial_fft && n_cols >= 4 ) {
            int N_sfft = 1;
            while ( N_sfft < n_cols ) N_sfft <<= 1;
            const int half_s = N_sfft / 2 + 1;

            std::vector<float> sfft_flat( (size_t)n_frames * (size_t)half_s, 0.f );
            for ( int r = 0; r < n_frames; ++r ) {
                const auto& row = (*src)[frame_offset + r];
                std::vector<std::complex<float>> buf( N_sfft, { 0.f, 0.f } );
                const int actual = std::min( n_cols, (int)row.size() );
                for ( int c = 0; c < actual; ++c ) {
                    float w = 0.5f * ( 1.f - std::cos( 2.f * 3.14159265358979f * (float)c / (float)( n_cols - 1 ) ) );
                    float v = row[c];
                    buf[c] = { ( do_abs2 ? v * v : v ) * w, 0.f };
                }
                _fft_inplace( buf );
                for ( int k = 0; k < half_s; ++k )
                    sfft_flat[(size_t)r * (size_t)half_s + k] = std::abs( buf[k] ) / (float)n_cols;
            }

            double sv_min = (double)*std::min_element( sfft_flat.begin(), sfft_flat.end() );
            double sv_max = (double)*std::max_element( sfft_flat.begin(), sfft_flat.end() );
            if ( sv_max - sv_min < 1e-30 ) sv_max = sv_min + 1e-30;

            const double dk    = 2.0 * 3.14159265358979 / phys_len;
            const double k_max = dk * (double)( half_s - 1 );

            ImPlot::PushColormap( cmap );
            ImPlot::ColormapScale( "##ks2", sv_min, sv_max, ImVec2( bar_w, plot_h ) );
            ImGui::SameLine();
            char sfft_id[64];
            std::snprintf( sfft_id, sizeof( sfft_id ), "##sfft_%d", i );
            if ( ImPlot::BeginPlot( sfft_id, ImVec2( -1.f, plot_h ) ) ) {
                ImPlot::SetupAxes( "k (1/um)", "Time (ps)" );
                ImPlot::SetupAxisLimits( ImAxis_X1, 0.0,  k_max, ImPlotCond_Always );
                ImPlot::SetupAxisLimits( ImAxis_Y1, t_lo, t_hi,  ImPlotCond_Always );
                ImPlot::PlotHeatmap( "##sfft_hm",
                                     sfft_flat.data(), n_frames, half_s,
                                     sv_min, sv_max, nullptr,
                                     ImPlotPoint( 0.0, t_lo ),
                                     ImPlotPoint( k_max, t_hi ) );
                ImPlot::EndPlot();
            }
            ImPlot::PopColormap();
        }

        // --- Optional: temporal spectrogram (per-column FFT across time) ---
        if ( tc.show_temporal_fft && n_frames >= 4 ) {
            const float mean_dt = ( n_frames >= 2 )
                ? ( tc.times[frame_offset + n_frames - 1] - tc.times[frame_offset] ) / (float)( n_frames - 1 )
                : 1.f;

            int N_tfft = 1;
            while ( N_tfft < n_frames ) N_tfft <<= 1;
            const int half_t = N_tfft / 2 + 1;

            std::vector<float> tfft_flat( (size_t)half_t * (size_t)n_cols, 0.f );
            for ( int c = 0; c < n_cols; ++c ) {
                std::vector<float> col_data( n_frames );
                for ( int r = 0; r < n_frames; ++r ) {
                    const auto& row = (*src)[frame_offset + r];
                    float v = ( c < (int)row.size() ) ? row[c] : 0.f;
                    col_data[r] = do_abs2 ? v * v : v;
                }
                std::vector<float> ffreq, fmag;
                computeDisplayFFT( col_data.data(), n_frames, mean_dt, ffreq, fmag );
                const int n_freq = (int)fmag.size();
                for ( int k = 0; k < n_freq && k < half_t; ++k )
                    tfft_flat[(size_t)k * (size_t)n_cols + c] = fmag[k];
            }

            double tv_min = (double)*std::min_element( tfft_flat.begin(), tfft_flat.end() );
            double tv_max = (double)*std::max_element( tfft_flat.begin(), tfft_flat.end() );
            if ( tv_max - tv_min < 1e-30 ) tv_max = tv_min + 1e-30;

            const double f_max = ( mean_dt > 0.f )
                ? (double)( half_t - 1 ) / ( (double)N_tfft * (double)mean_dt )
                : 1.0;

            ImPlot::PushColormap( cmap );
            ImPlot::ColormapScale( "##ks3", tv_min, tv_max, ImVec2( bar_w, plot_h ) );
            ImGui::SameLine();
            char tfft_id[64];
            std::snprintf( tfft_id, sizeof( tfft_id ), "##tfft_%d", i );
            if ( ImPlot::BeginPlot( tfft_id, ImVec2( -1.f, plot_h ) ) ) {
                const char* xlab2 = ( tc.slice_axis == 0 ) ? "y (um)" : "x (um)";
                ImPlot::SetupAxes( xlab2, "Freq (1/ps)" );
                ImPlot::SetupAxisLimits( ImAxis_X1, x_min, x_max, ImPlotCond_Always );
                ImPlot::SetupAxisLimits( ImAxis_Y1, 0.0,   f_max, ImPlotCond_Always );
                ImPlot::PlotHeatmap( "##tfft_hm",
                                     tfft_flat.data(), half_t, n_cols,
                                     tv_min, tv_max, nullptr,
                                     ImPlotPoint( x_min, 0.0 ),
                                     ImPlotPoint( x_max, f_max ) );
                ImPlot::EndPlot();
            }
            ImPlot::PopColormap();
        }

        ImGui::PopID();
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

#endif  // SFML_RENDER

} // namespace PHOENIX
