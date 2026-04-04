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

    ImGui::SetNextWindowSize( ImVec2( 680, 520 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Time Evolution##tev", &show_tracked_window_ );

    // ---- Controls row ----
    ImGui::Checkbox( "Overlay##tev_ovl", &tracked_overlay_mode_ );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Show all points in one graph (on) vs individual graphs (off)" );
    ImGui::SameLine();
    ImGui::Checkbox( "FFT##tev_fft", &tracked_show_fft_ );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Show magnitude spectrum of each point's time series\n(assumes ~uniform dt; approximate for adaptive solvers)" );
    ImGui::SameLine();
    if ( ImGui::Button( "Clear All##tev_clr" ) )
        tracked_points_.clear();
    ImGui::SameLine();
    // Export CSV
    if ( ImGui::Button( "Export CSV##tev_exp" ) && !tracked_points_.empty() ) {
        std::string fname = "tracked_points_t" + std::to_string( (int)solver_.system.p.t ) + ".csv";
        FILE* f = std::fopen( fname.c_str(), "w" );
        if ( f ) {
            // Header
            std::fprintf( f, "time_ps" );
            for ( auto& tp : tracked_points_ )
                if ( tp.enabled )
                    std::fprintf( f, ",%s_abs,%s_re,%s_im,%s_arg",
                                  tp.label.c_str(), tp.label.c_str(),
                                  tp.label.c_str(), tp.label.c_str() );
            std::fprintf( f, "\n" );
            // Determine min time-series length
            size_t min_len = 0;
            for ( auto& tp : tracked_points_ )
                if ( tp.enabled && !tp.times.empty() )
                    min_len = ( min_len == 0 ) ? tp.times.size()
                                              : std::min( min_len, tp.times.size() );
            for ( size_t i = 0; i < min_len; ++i ) {
                std::fprintf( f, "%g", (double)tracked_points_[0].times[i] );
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
        ImGui::SetTooltip( "Write all enabled point time series to a CSV file" );

    // ---- Window slider ----
    tracked_hist_window_ = std::max( 10, std::min( tracked_hist_window_, TrackedPoint::kMaxHist ) );
    {
        char wlabel[32];
        if ( tracked_hist_window_ >= TrackedPoint::kMaxHist )
            std::snprintf( wlabel, sizeof(wlabel), "Window: All" );
        else
            std::snprintf( wlabel, sizeof(wlabel), "Window: %d samples", tracked_hist_window_ );
        ImGui::SetNextItemWidth( -1.f );
        ImGui::SliderInt( "##tev_win", &tracked_hist_window_,
                          10, TrackedPoint::kMaxHist, wlabel );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Number of history samples to display (drag left = fewer, right = all)" );
    }

    ImGui::Separator();

    if ( tracked_points_.empty() ) {
        ImGui::TextDisabled( "No points tracked yet.\nRight-click on a 2D image to start tracking." );
        ImGui::End();
        return;
    }

    // ---- Tracked points list ----
    int to_delete = -1;
    for ( int i = 0; i < (int)tracked_points_.size(); ++i ) {
        auto& tp = tracked_points_[i];
        ImGui::PushID( i );
        ImGui::Checkbox( "##tev_en", &tp.enabled );
        ImGui::SameLine();
        ImGui::TextUnformatted( tp.label.c_str() );
        if ( ImGui::IsItemHovered() ) {
            // Show physical coords on hover
            ImGui::SetTooltip( "x = %.3f  y = %.3f\ncol = %d  row = %d\n%s",
                               (double)tp.x_phys, (double)tp.y_phys,
                               tp.col, tp.row,
                               tp.is_complex ? "complex matrix" : "real matrix" );
        }
        ImGui::SameLine();
        if ( ImGui::SmallButton( "x##tev_del" ) )
            to_delete = i;
        ImGui::PopID();
    }
    if ( to_delete >= 0 )
        tracked_points_.erase( tracked_points_.begin() + to_delete );

    ImGui::Separator();

    // Collect enabled points
    std::vector<int> active;
    for ( int i = 0; i < (int)tracked_points_.size(); ++i )
        if ( tracked_points_[i].enabled && !tracked_points_[i].values_abs.empty() )
            active.push_back( i );

    if ( active.empty() ) {
        ImGui::TextDisabled( "All tracked points disabled or no data yet." );
        ImGui::End();
        return;
    }

    // Helper: get windowed slice from a deque
    auto sliceDeque = []( const std::deque<float>& dq, int window ) -> std::vector<float> {
        const int total   = (int)dq.size();
        const int w       = std::min( window, total );
        return std::vector<float>( dq.begin() + ( total - w ), dq.end() );
    };

    // Palette: cycle through a few distinct colors
    static const ImVec4 kPalette[] = {
        { 0.537f, 0.706f, 0.980f, 1.f },  // sky blue
        { 0.3f,   1.f,    0.3f,   1.f },  // green
        { 1.f,    0.5f,   0.1f,   1.f },  // orange
        { 1.f,    0.4f,   0.6f,   1.f },  // pink
        { 0.4f,   0.9f,   0.9f,   1.f },  // cyan
        { 1.f,    1.f,    0.4f,   1.f },  // yellow
        { 0.8f,   0.4f,   1.f,    1.f },  // purple
        { 1.f,    1.f,    1.f,    1.f },  // white
    };
    static constexpr int kPaletteSize = (int)( sizeof(kPalette) / sizeof(kPalette[0]) );

    const ImVec2 avail_tev  = ImGui::GetContentRegionAvail();
    const float  fft_height = tracked_show_fft_ ? std::max( 10.f, avail_tev.y * 0.40f ) : 0.f;
    const float  ts_height  = std::max( 10.f, avail_tev.y - fft_height - ( tracked_show_fft_ ? 12.f : 0.f ) );

    if ( tracked_overlay_mode_ ) {
        // ---- All points in one graph ----
        // Global y range
        float gmin = FLT_MAX, gmax = -FLT_MAX;
        for ( int idx : active ) {
            const auto& tp = tracked_points_[idx];
            auto sv = sliceDeque( tp.values_abs, tracked_hist_window_ );
            for ( float v : sv ) { gmin = std::min( gmin, v ); gmax = std::max( gmax, v ); }
        }
        if ( gmax - gmin < 1e-30f ) gmax = gmin + 1e-30f;

        ImVec2 saved_pos = ImGui::GetCursorPos();
        bool first = true;
        for ( int pi = 0; pi < (int)active.size(); ++pi ) {
            const int idx    = active[pi];
            const auto& tp   = tracked_points_[idx];
            auto sv          = sliceDeque( tp.values_abs, tracked_hist_window_ );
            const ImVec4& col = kPalette[pi % kPaletteSize];
            char pid[32]; std::snprintf( pid, sizeof(pid), "##tev_ovl_%d", idx );

            if ( !first ) {
                ImGui::SetCursorPos( saved_pos );
                ImGui::PushStyleColor( ImGuiCol_FrameBg, ImVec4( 0.f, 0.f, 0.f, 0.f ) );
            }
            ImGui::PushStyleColor( ImGuiCol_PlotLines, col );
            char ov[64]; std::snprintf( ov, sizeof(ov), first ? "%.3e" : "", sv.empty() ? 0.f : sv.back() );
            ImGui::PlotLines( pid, sv.data(), (int)sv.size(), 0,
                              first ? ov : nullptr, gmin, gmax, ImVec2( -1.f, ts_height ) );
            ImGui::PopStyleColor( first ? 1 : 2 );
            first = false;
        }

        // FFT overlay section
        if ( tracked_show_fft_ ) {
            ImGui::Spacing();
            ImGui::TextDisabled( "Magnitude spectrum (|abs| series):" );
            float fmin = FLT_MAX, fmax = -FLT_MAX;
            // Pre-compute to find range
            std::vector<std::vector<float>> fft_mags( active.size() );
            std::vector<std::vector<float>> fft_freqs( active.size() );
            for ( int pi = 0; pi < (int)active.size(); ++pi ) {
                const auto& tp = tracked_points_[active[pi]];
                auto sv = sliceDeque( tp.values_abs, tracked_hist_window_ );
                float mean_dt = 0.f;
                if ( tp.times.size() >= 2 ) {
                    auto tv = sliceDeque( tp.times, tracked_hist_window_ );
                    mean_dt = ( tv.back() - tv.front() ) / std::max( 1, (int)tv.size() - 1 );
                }
                computeDisplayFFT( sv.data(), (int)sv.size(), mean_dt,
                                   fft_freqs[pi], fft_mags[pi] );
                for ( float v : fft_mags[pi] ) { fmin = std::min( fmin, v ); fmax = std::max( fmax, v ); }
            }
            if ( fmax - fmin < 1e-30f ) fmax = fmin + 1e-30f;

            ImVec2 fft_saved = ImGui::GetCursorPos();
            bool ffirst = true;
            for ( int pi = 0; pi < (int)active.size(); ++pi ) {
                if ( fft_mags[pi].empty() ) continue;
                const ImVec4& col = kPalette[pi % kPaletteSize];
                char pid[32]; std::snprintf( pid, sizeof(pid), "##tev_fft_%d", active[pi] );
                if ( !ffirst ) {
                    ImGui::SetCursorPos( fft_saved );
                    ImGui::PushStyleColor( ImGuiCol_FrameBg, ImVec4( 0.f, 0.f, 0.f, 0.f ) );
                }
                ImGui::PushStyleColor( ImGuiCol_PlotLines, col );
                char fov[64]; std::snprintf( fov, sizeof(fov), ffirst ? "freq (1/ps)" : "" );
                ImGui::PlotLines( pid, fft_mags[pi].data(), (int)fft_mags[pi].size(),
                                  0, ffirst ? fov : nullptr, fmin, fmax, ImVec2( -1.f, fft_height ) );
                ImGui::PopStyleColor( ffirst ? 1 : 2 );
                ffirst = false;
            }
        }
    } else {
        // ---- Individual graph per point ----
        const float each_h = std::max( 60.f, ( ts_height - (float)active.size() * ImGui::GetFrameHeightWithSpacing() ) / (float)active.size() );
        for ( int pi = 0; pi < (int)active.size(); ++pi ) {
            const int idx    = active[pi];
            auto& tp         = tracked_points_[idx];
            const ImVec4& col = kPalette[pi % kPaletteSize];

            auto sv = sliceDeque( tp.values_abs, tracked_hist_window_ );
            float pmin = sv.empty() ? 0.f : *std::min_element( sv.begin(), sv.end() );
            float pmax = sv.empty() ? 1.f : *std::max_element( sv.begin(), sv.end() );
            if ( pmax - pmin < 1e-30f ) pmax = pmin + 1e-30f;

            // Point label as small header
            ImGui::PushStyleColor( ImGuiCol_Text, col );
            ImGui::TextUnformatted( tp.label.c_str() );
            ImGui::PopStyleColor();

            char pid[32]; std::snprintf( pid, sizeof(pid), "##tev_ind_%d", idx );
            ImGui::PushStyleColor( ImGuiCol_PlotLines, col );
            char ov[48]; std::snprintf( ov, sizeof(ov), "%.3e", sv.empty() ? 0.f : sv.back() );
            ImGui::PlotLines( pid, sv.data(), (int)sv.size(), 0, ov, pmin, pmax, ImVec2( -1.f, each_h ) );
            ImGui::PopStyleColor();

            if ( tracked_show_fft_ ) {
                std::vector<float> fmag, ffreq;
                float mean_dt = 0.f;
                if ( tp.times.size() >= 2 ) {
                    auto tv = sliceDeque( tp.times, tracked_hist_window_ );
                    mean_dt = ( tv.back() - tv.front() ) / std::max( 1, (int)tv.size() - 1 );
                }
                computeDisplayFFT( sv.data(), (int)sv.size(), mean_dt, ffreq, fmag );
                if ( !fmag.empty() ) {
                    float fmin2 = *std::min_element( fmag.begin(), fmag.end() );
                    float fmax2 = *std::max_element( fmag.begin(), fmag.end() );
                    if ( fmax2 - fmin2 < 1e-30f ) fmax2 = fmin2 + 1e-30f;
                    char fpid[32]; std::snprintf( fpid, sizeof(fpid), "##tev_ifft_%d", idx );
                    ImGui::PushStyleColor( ImGuiCol_PlotLines, col );
                    ImGui::PlotLines( fpid, fmag.data(), (int)fmag.size(), 0,
                                      "freq (1/ps)", fmin2, fmax2, ImVec2( -1.f, each_h * 0.6f ) );
                    ImGui::PopStyleColor();
                }
            }
        }
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
