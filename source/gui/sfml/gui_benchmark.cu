#include "misc/gui.hpp"
#ifdef SFML_RENDER
#include "misc/timeit.hpp"
#include <algorithm>
#include <numeric>
#include <vector>
#include <string>

namespace PHOENIX {

void PhoenixGUI::renderBenchmarkWindow() {
    if ( !show_benchmark_window_ ) return;

    ImGui::SetNextWindowSize( ImVec2( 560, 560 ), ImGuiCond_FirstUseEver );
    ImGui::Begin( "Benchmarking##bench", &show_benchmark_window_ );

    bool& bench_on = solver_.system.benchmarking_enabled;
    if ( ImGui::Checkbox( "Enable##bench_toggle", &bench_on ) )
        PHOENIX::TimeIt::clear(); // flush stale data on toggle
    ImGui::SameLine();
    ImGui::TextDisabled( bench_on ? "active  (one sync/step overhead)"
                                  : "off  (no overhead)" );
    ImGui::Separator();

    const auto& all_times = PHOENIX::TimeIt::getTimes();
    if ( !bench_on && all_times.empty() ) {
        ImGui::TextDisabled( "Enable benchmarking above to start collecting timing data." );
        ImGui::End();
        return;
    }
    if ( all_times.empty() ) {
        ImGui::TextDisabled( "No timing data yet — start the simulation." );
        ImGui::End();
        return;
    }

    // Collect kernel-level timers only — exclude "Main-Loop" (outer batch timer, includes GUI)
    struct TimerEntry {
        std::string name;
        float mean_ms = 0.f;
        float min_ms  = 0.f;
        float max_ms  = 0.f;
        int   count   = 0;
    };

    std::vector<TimerEntry> entries;
    float total_ms = 0.f;

    // std::map iterates in alphabetical order — use that directly (stable, no flicker)
    for ( const auto& [key, vec] : all_times ) {
        if ( vec.empty() ) continue;
        if ( key == "Main-Loop" ) continue; // GUI/outer-loop timer, not a kernel
        const int n   = std::min( (int)vec.size(), bench_hist_window_ );
        const int off = (int)vec.size() - n;
        float mn  = (float)( vec[off] * 1000.0 );
        float mx  = mn;
        float sum = 0.f;
        for ( int i = off; i < (int)vec.size(); ++i ) {
            float v = (float)( vec[i] * 1000.0 );
            mn  = std::min( mn, v );
            mx  = std::max( mx, v );
            sum += v;
        }
        float mean = sum / n;
        entries.push_back( { key, mean, mn, mx, (int)vec.size() } );
        total_ms += mean;
    }

    if ( entries.empty() ) {
        ImGui::TextDisabled( "No kernel timing data yet." );
        ImGui::End();
        return;
    }

    // History window slider
    {
        int slider_max = 0;
        for ( const auto& [key, vec] : all_times )
            slider_max = std::max( slider_max, (int)vec.size() );
        slider_max = std::max( slider_max, 512 );
        bench_hist_window_ = std::clamp( bench_hist_window_, 10, slider_max );

        char wlabel[32];
        std::snprintf( wlabel, sizeof( wlabel ), "%d", bench_hist_window_ );
        ImGui::SetNextItemWidth( 220.f );
        ImGui::SliderInt( "Sample window##bench_hw", &bench_hist_window_, 10, slider_max, wlabel );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Number of recent measurements used for statistics" );
    }

    ImGui::Separator();
    ImGui::Text( "Kernel breakdown  (avg over last %d samples)", bench_hist_window_ );
    ImGui::Spacing();

    // Horizontal bar chart + statistics table — sorted by name (stable, from std::map order)
    const float bar_width = 180.f;
    for ( int i = 0; i < (int)entries.size(); ++i ) {
        const auto& e    = entries[i];
        const float frac = ( total_ms > 0.f ) ? e.mean_ms / total_ms : 0.f;
        const float hue  = (float)i / std::max( 1, (int)entries.size() - 1 );

        ImVec4 col{ 0.2f + 0.6f * hue, 0.55f - 0.3f * hue, 0.9f - 0.5f * hue, 0.85f };
        ImGui::PushStyleColor( ImGuiCol_PlotHistogram, col );
        ImGui::ProgressBar( frac, ImVec2( bar_width, 0.f ) );
        ImGui::PopStyleColor();
        ImGui::SameLine();
        ImGui::Text( "%-22s  %6.3f ms  (%5.1f%%)  min %.3f  max %.3f  n=%d",
                     e.name.c_str(), (double)e.mean_ms, (double)( frac * 100.f ),
                     (double)e.min_ms, (double)e.max_ms, e.count );
    }

    if ( total_ms > 0.f ) {
        ImGui::Spacing();
        ImGui::Text( "Total kernel (avg per step): %.3f ms", (double)total_ms );
        const auto& totals = PHOENIX::TimeIt::getTimesTotal();
        double grand = 0.0;
        for ( const auto& [k, v] : totals ) {
            if ( k == "Main-Loop" ) continue;
            grand += v;
        }
        if ( grand > 0.0 )
            ImGui::Text( "Cumulative kernel wall time : %.3f s", grand );
    }

    ImGui::Separator();

    // History plot controls
    ImGui::Checkbox( "Overlay all##bench_ov", &bench_overlay_all_ );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Show all kernel histories in a single overlay plot" );

    if ( !bench_overlay_all_ ) {
        // Single-kernel combo selector
        ImGui::SameLine();
        std::vector<const char*> names;
        names.reserve( entries.size() );
        for ( const auto& e : entries ) names.push_back( e.name.c_str() );
        bench_selected_key_ = std::clamp( bench_selected_key_, 0, (int)names.size() - 1 );
        ImGui::SetNextItemWidth( 220.f );
        ImGui::Combo( "##bench_sel", &bench_selected_key_, names.data(), (int)names.size() );
    }

    ImGui::Spacing();

    if ( bench_overlay_all_ ) {
        // --- Overlay plot: all kernels in one ImPlot graph ---
        if ( ImPlot::BeginPlot( "##bench_overlay", ImVec2( -1.f, 160.f ) ) ) {
            ImPlot::SetupAxes( "sample", "ms" );
            for ( int i = 0; i < (int)entries.size(); ++i ) {
                const std::string& key = entries[i].name;
                auto it = all_times.find( key );
                if ( it == all_times.end() || it->second.empty() ) continue;
                const auto& raw = it->second;
                const int n   = std::min( (int)raw.size(), bench_hist_window_ );
                const int off = (int)raw.size() - n;
                std::vector<float> samples( n );
                for ( int j = 0; j < n; ++j )
                    samples[j] = (float)( raw[off + j] * 1000.0 );
                ImPlot::PlotLine( entries[i].name.c_str(), samples.data(), n );
            }
            ImPlot::EndPlot();
        }
    } else {
        // --- Single-kernel history plot ---
        if ( bench_selected_key_ >= 0 && bench_selected_key_ < (int)entries.size() ) {
            const std::string& key = entries[bench_selected_key_].name;
            auto it = all_times.find( key );
            if ( it != all_times.end() && !it->second.empty() ) {
                const auto& raw = it->second;
                const int n   = std::min( (int)raw.size(), bench_hist_window_ );
                const int off = (int)raw.size() - n;
                std::vector<float> samples( n );
                for ( int i = 0; i < n; ++i )
                    samples[i] = (float)( raw[off + i] * 1000.0 );

                float s_min = *std::min_element( samples.begin(), samples.end() );
                float s_max = *std::max_element( samples.begin(), samples.end() );
                if ( s_max - s_min < 1e-9f ) s_max = s_min + 1e-9f;

                char overlay[32];
                std::snprintf( overlay, sizeof( overlay ), "%.3f ms", (double)samples.back() );
                ImGui::PushStyleColor( ImGuiCol_PlotLines, ImVec4( 0.980f, 0.706f, 0.537f, 0.9f ) );
                ImGui::PlotLines( "##bench_hist_plot", samples.data(), n,
                                  0, overlay, s_min * 0.9f, s_max * 1.1f, ImVec2( -1.f, 120.f ) );
                ImGui::PopStyleColor();
            }
        }
    }

    ImGui::End();
}

} // namespace PHOENIX
#endif // SFML_RENDER
