#include "misc/gui.hpp"
#ifdef SFML_RENDER
#include "imgui_internal.h"
#include "misc/commandline_io.hpp"
#include <fstream>
#include <sstream>

namespace PHOENIX {

// ============================================================
// renderRunstringWindow
// ============================================================

void PhoenixGUI::renderRunstringWindow() {
    if ( !show_runstring_window_ ) return;

    ImGui::SetNextWindowSize( ImVec2( 720, 420 ), ImGuiCond_FirstUseEver );
    if ( !ImGui::Begin( "Runstring##rswin", &show_runstring_window_ ) ) {
        ImGui::End();
        return;
    }

    if ( ImGui::Button( "Refresh" ) ) {
        runstring_cache_ = solver_.system.toRunstring();
        runstring_buf_.assign( runstring_cache_.begin(), runstring_cache_.end() );
        runstring_buf_.push_back( '\0' );
    }
    ImGui::SameLine();
    if ( ImGui::Button( "Copy to Clipboard" ) )
        ImGui::SetClipboardText( runstring_cache_.c_str() );

    ImGui::Separator();

    ImVec2 avail = ImGui::GetContentRegionAvail();
    if ( runstring_buf_.empty() ) {
        // Populate on first open if not yet done
        runstring_cache_ = solver_.system.toRunstring();
        runstring_buf_.assign( runstring_cache_.begin(), runstring_cache_.end() );
        runstring_buf_.push_back( '\0' );
    }
    ImGui::InputTextMultiline( "##rstext",
                               runstring_buf_.data(),
                               runstring_buf_.size(),
                               ImVec2( -1.0f, avail.y ),
                               ImGuiInputTextFlags_ReadOnly );

    ImGui::End();
}

// ============================================================
// renderConfigSaveDialog
// ============================================================

void PhoenixGUI::renderConfigSaveDialog() {
    if ( config_save_.open ) {
        ImGui::OpenPopup( "Save Config##sp" );
        config_save_.open = false;
    }

    if ( !ImGui::BeginPopupModal( "Save Config##sp", nullptr, ImGuiWindowFlags_AlwaysAutoResize ) )
        return;

    ImGui::Text( "Save current parameters to a PHOENIX config file." );
    ImGui::Separator();

    ImGui::InputText( "File path##savepath", config_save_.filepath, sizeof( config_save_.filepath ) );
    ImGui::Checkbox( "Also save matrices now", &config_save_.include_matrices );
    ImGui::TextDisabled( "(config can be reloaded with: --config <path>)" );

    ImGui::Separator();

    if ( ImGui::Button( "Save" ) ) {
        std::ofstream f( config_save_.filepath );
        if ( f.is_open() ) {
            f << "# PHOENIX config — saved from GUI\n";
            f << solver_.system.toRunstring();
            f.close();
            config_save_.status_msg = std::string( "Saved: " ) + config_save_.filepath;
        } else {
            config_save_.status_msg = "ERROR: could not open file for writing";
        }
        if ( config_save_.include_matrices ) {
            auto& sys = solver_.system;
            solver_.outputMatrices( 0, sys.p.N_c, 0, sys.p.N_r, 1, "_config_save" );
            config_save_.status_msg += "  + matrices saved";
        }
        ImGui::CloseCurrentPopup();
    }
    ImGui::SameLine();
    if ( ImGui::Button( "Cancel" ) ) {
        config_save_.status_msg.clear();
        ImGui::CloseCurrentPopup();
    }

    if ( !config_save_.status_msg.empty() )
        ImGui::TextUnformatted( config_save_.status_msg.c_str() );

    ImGui::EndPopup();
}

// ============================================================
// renderConfigLoadDialog
// ============================================================

void PhoenixGUI::renderConfigLoadDialog() {
    if ( config_load_.open ) {
        ImGui::OpenPopup( "Load Config##lp" );
        config_load_.open = false;
    }

    if ( !ImGui::BeginPopupModal( "Load Config##lp", nullptr, ImGuiWindowFlags_AlwaysAutoResize ) )
        return;

    ImGui::Text( "Apply physics/time parameters from a PHOENIX config file." );
    ImGui::Separator();

    ImGui::InputText( "File path##loadpath", config_load_.filepath, sizeof( config_load_.filepath ) );
    ImGui::Checkbox( "Load matrices from file", &config_load_.load_matrices );
    if ( config_load_.load_matrices )
        ImGui::TextColored( ImVec4( 1.0f, 0.65f, 0.0f, 1.0f ),
                            "Note: matrix loading is not yet supported via GUI.\n"
                            "Grid/envelope/boundary changes require a full restart\n"
                            "with --config <file>." );

    ImGui::Separator();

    if ( ImGui::Button( "Load" ) ) {
        applyUpdatableParamsFromFile( config_load_.filepath );
        ImGui::CloseCurrentPopup();
    }
    ImGui::SameLine();
    if ( ImGui::Button( "Cancel" ) ) {
        config_load_.status_msg.clear();
        ImGui::CloseCurrentPopup();
    }

    if ( !config_load_.status_msg.empty() )
        ImGui::TextUnformatted( config_load_.status_msg.c_str() );

    ImGui::EndPopup();
}

// ============================================================
// applyUpdatableParamsFromFile
// ============================================================

void PhoenixGUI::applyUpdatableParamsFromFile( const char* filepath ) {
    config_load_.status_msg.clear();

    // --- Read file into tokens (same logic as readConfigFromFile) ---
    std::ifstream f( filepath );
    if ( !f.is_open() ) {
        config_load_.status_msg = std::string( "ERROR: cannot open " ) + filepath;
        return;
    }

    std::vector<std::string> token_strings;
    token_strings.push_back( "phoenix" ); // dummy argv[0]
    std::string line;
    while ( std::getline( f, line ) ) {
        std::istringstream iss( line );
        std::string word;
        while ( iss >> word ) {
            if ( word[0] == '#' ) break; // rest of line is a comment
            token_strings.push_back( word );
        }
    }

    // Build char* array (tokens own their storage via token_strings)
    std::vector<char*> argv;
    for ( auto& s : token_strings )
        argv.push_back( const_cast<char*>( s.c_str() ) );
    int argc = static_cast<int>( argv.size() );

    auto& sys = solver_.system;
    auto& p   = sys.kernel_parameters;

    // --- Detect non-updatable params and warn ---
    bool has_structural = false;
    for ( const auto& key : { "--N", "--L", "--subgrids", "--boundary", "--pump", "--potential",
                               "--pulse", "--fftMask", "--initState", "--initialState",
                               "--initReservoir", "--initialReservoir", "-tetm", "-dense" } ) {
        if ( CLIO::findInArgv( key, argc, argv.data() ) != -1 ) {
            has_structural = true;
            break;
        }
    }

    // --- Apply updatable physics params under pause ---
    bool any_applied = false;
    int idx = 0;

    auto tryReal = [&]( const std::vector<std::string>& keys, Type::real& target ) -> bool {
        if ( ( idx = CLIO::findInArgv( keys, argc, argv.data(), 0, "--" ) ) != -1 ) {
            target = CLIO::getNextInput( argv.data(), argc, keys.front().c_str(), ++idx );
            return true;
        }
        return false;
    };
    auto tryRealSingle = [&]( const char* key, Type::real& target ) -> bool {
        if ( ( idx = CLIO::findInArgv( key, argc, argv.data() ) ) != -1 ) {
            target = CLIO::getNextInput( argv.data(), argc, key, ++idx );
            return true;
        }
        return false;
    };

    const bool ap = pauseSolverForUpdate();

    any_applied |= tryReal( { "gammaC", "gamma_C", "gammac", "gamma_c" }, p.gamma_c );
    any_applied |= tryReal( { "gammaR", "gamma_R", "gammar", "gamma_r" }, p.gamma_r );
    any_applied |= tryReal( { "gc", "g_c" }, p.g_c );
    any_applied |= tryReal( { "gr", "g_r" }, p.g_r );
    any_applied |= tryRealSingle( "--R", p.R );
    any_applied |= tryReal( { "g_pm", "gpm", "g_PM" }, p.g_pm );
    any_applied |= tryReal( { "deltaLT", "delta_LT", "deltalt", "dlt" }, p.delta_LT );
    any_applied |= tryReal( { "meff", "m_eff" }, p.m_eff );
    any_applied |= tryRealSingle( "--dw", p.stochastic_amplitude );

    // Time params
    any_applied |= tryReal( { "tmax", "tend" }, sys.t_max );
    any_applied |= tryRealSingle( "--outEvery", sys.output_every );
    any_applied |= tryRealSingle( "--fftEvery", sys.fft_every );
    any_applied |= tryRealSingle( "--tol", sys.tolerance );
    if ( ( idx = CLIO::findInArgv( "--rkvdt", argc, argv.data() ) ) != -1 ) {
        sys.dt_min = CLIO::getNextInput( argv.data(), argc, "dt_min", ++idx );
        sys.dt_max = CLIO::getNextInput( argv.data(), argc, "dt_max", idx );
        any_applied = true;
    }
    if ( ( idx = CLIO::findInArgv( { "tstep", "dt" }, argc, argv.data(), 0, "--" ) ) != -1 ) {
        p.dt = CLIO::getNextInput( argv.data(), argc, "dt", ++idx );
        any_applied = true;
    }

    if ( any_applied )
        solver_.parameters_are_dirty = true;

    resumeSolverAfterUpdate( ap );

    // --- Build status message ---
    if ( any_applied )
        config_load_.status_msg = "Applied physics/time params from: " + std::string( filepath );
    else
        config_load_.status_msg = "No updatable params found in: " + std::string( filepath );

    if ( has_structural )
        config_load_.status_msg += "\n(Grid/envelope/boundary changes need --config restart)";
}

} // namespace PHOENIX

#endif // SFML_RENDER
