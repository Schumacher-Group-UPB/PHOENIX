#include "misc/gui.hpp"
#include <mutex>
#ifdef SFML_RENDER
#include "imgui_internal.h"
#endif
#include <cmath>
#include <cfloat>
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
// addPanel - create and append a new viewer window
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
    p.subsample_3d   = std::max( 1, std::max( W, H ) / 200 );  // ≈100×100 initial display
    p.tex      = std::make_unique<sf::RenderTexture>();
    p.tex->create( W, H );
    p.pix.resize( W * H );
    for ( int r = 0; r < H; r++ )
        for ( int c = 0; c < W; c++ )
            p.pix[r * W + c] = sf::Vertex( sf::Vector2f( c + 0.5f, r + 0.5f ), sf::Color::Black );

    panels_.push_back( std::move( p ) );
}

// ============================================================
// blitPanel<T> - compute pixels and upload to the panel texture
// ============================================================

template <typename T>
void PhoenixGUI::blitPanel( MatrixPanel& p, const MatrixDescriptor& desc, ColorPalette& cp ) {
    const int W = p.tex_w, H = p.tex_h;
    if ( W == 0 || H == 0 ) return;

    // Use getHostData() instead of getHostPtr() to avoid the implicit
    // deviceToHostSync() that getHostPtr() triggers when host_is_ahead==false.
    // We only ever read host_data here under display_mutex; the solver writes
    // it only under the same mutex via syncDisplayMatrices(). No implicit GPU
    // transfer is needed or safe from the GUI thread.
    const T* data = nullptr;
    if constexpr ( std::is_same_v<T, Type::complex> ) {
        if ( !desc.complex_mat ) return;
        const auto& hd = desc.complex_mat->getHostData();
        if ( hd.empty() ) return;
        data = hd.data();
    } else {
        if ( !desc.real_mat ) return;
        const auto& hd = desc.real_mat->getHostData();
        if ( hd.empty() ) return;
        data = hd.data();
    }
    if ( !data ) return;

    // Subsampling stride - shared between 2D image and 3D surface modes
    const int stride  = std::max( 1, p.subsample_3d );
    const int cols_s  = ( W + stride - 1 ) / stride;
    const int rows_s  = ( H + stride - 1 ) / stride;

    // FFT-shift index remapping: shifts DC from corners to centre.
    // Maps display pixel (r,c) back to the source layout ((r+H/2)%H, (c+W/2)%W).
    auto shiftIdx = [&]( int r, int c ) -> int {
        if ( p.fft_shift ) {
            r = ( r + H / 2 ) % H;
            c = ( c + W / 2 ) % W;
        }
        return r * W + c;
    };

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

    // Determine colormap range (strided scan)
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
        for ( int ri = 0; ri < rows_s; ri++ ) {
            for ( int ci = 0; ci < cols_s; ci++ ) {
                int idx = shiftIdx( std::min( ri * stride, H - 1 ), std::min( ci * stride, W - 1 ) );
                double v = displayVal( idx );
                if ( v < vmin ) vmin = v;
                if ( v > vmax ) vmax = v;
            }
        }
        if ( vmax - vmin < 1e-30 ) vmax = vmin + 1e-30;
    }

    // Update history with raw (non-log) values (strided scan)
    {
        double hmax = -std::numeric_limits<double>::max();
        double hmin =  std::numeric_limits<double>::max();
        for ( int ri = 0; ri < rows_s; ri++ ) {
            for ( int ci = 0; ci < cols_s; ci++ ) {
                int idx = shiftIdx( std::min( ri * stride, H - 1 ), std::min( ci * stride, W - 1 ) );
                double v = rawVal( idx );
                if ( v > hmax ) hmax = v;
                if ( v < hmin ) hmin = v;
            }
        }
        p.hist_max.push_back( (float)hmax );
        p.hist_min.push_back( (float)hmin );
        while ( (int)p.hist_max.size() > MatrixPanel::kMaxHist ) p.hist_max.pop_front();
        while ( (int)p.hist_min.size() > MatrixPanel::kMaxHist ) p.hist_min.pop_front();
    }

    // Write colormap pixels - block-fill so each sampled value covers a stride×stride tile
    for ( int ri = 0; ri < rows_s; ri++ ) {
        const int row0  = ri * stride;
        const int row1  = std::min( row0 + stride, H );
        const int src_r = std::min( row0, H - 1 );
        for ( int ci = 0; ci < cols_s; ci++ ) {
            const int col0  = ci * stride;
            const int col1  = std::min( col0 + stride, W );
            const int src   = shiftIdx( src_r, std::min( col0, W - 1 ) );
            double v = displayVal( src );
            double t = ( v - vmin ) / ( vmax - vmin );
            t = std::max( 0.0, std::min( 1.0, t ) );
            auto& col = cp.getColor( t );
            const sf::Color sfcol( col.r, col.g, col.b );
            for ( int r = row0; r < row1; r++ )
                for ( int c = col0; c < col1; c++ )
                    p.pix[r * W + c].color = sfcol;
        }
    }

    p.tex->clear( sf::Color::Black );
    p.tex->draw( p.pix.data(), W * H, sf::Points );
    p.tex->display();
}

// ============================================================
// updatePanel - dispatch blitPanel for the selected matrix
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

    if ( st_ ) {
        std::lock_guard<std::mutex> lk( st_->display_mutex );
        if ( desc.complex_mat )
            blitPanel<Type::complex>( p, desc, *cp );
        else if ( desc.real_mat )
            blitPanel<Type::real>( p, desc, *cp );
    } else {
        if ( desc.complex_mat )
            blitPanel<Type::complex>( p, desc, *cp );
        else if ( desc.real_mat )
            blitPanel<Type::real>( p, desc, *cp );
    }
}

// ============================================================
// updateEnvelopeHistories - record temporal amplitude each frame
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
// renderMatrixPanel - one ImGui viewer window per panel
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

    // Display mode selector (complex matrices only) - Row 1
    if ( p.selected >= 0 && p.selected < (int)matrix_registry_.size()
         && matrix_registry_[p.selected].complex_mat != nullptr ) {
        ImGui::SameLine();
        ImGui::SetNextItemWidth( 80.f );
        static const char* mode_names[] = { "|.|^2", "|.|", "Re", "Im", "arg" };
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
    {
        static const char* view_labels[] = { "Image", "Line cut", "3D" };
        int vm = (int)p.view_mode;
        ImGui::SetNextItemWidth( 90.f );
        if ( ImGui::BeginCombo( "##viewmode", view_labels[vm] ) ) {
            for ( int i = 0; i < 3; i++ ) {
                bool sel = ( vm == i );
                if ( ImGui::Selectable( view_labels[i], sel ) )
                    p.view_mode = (MatrixPanel::ViewMode)i;
                if ( sel ) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Switch between 2D image, 1D line-cut, and 3D surface views" );
    }

    ImGui::SameLine();
    if ( ImGui::Button( "Save##ss" ) ) {
        std::string fname = "phoenix_";
        {
            auto sep = p.title.find( "##" );
            fname += ( sep != std::string::npos ) ? p.title.substr( 0, sep ) : p.title;
        }
        fname += "_t" + std::to_string( (int)sys.p.t );
        if ( p.view_mode == MatrixPanel::ViewMode::Image2D && p.tex ) {
            sf::Image img = p.tex->getTexture().copyToImage();
            img.saveToFile( fname + "_image.png" );
        } else {
            // For line-cut and 3D views, capture the full window
            auto winSize = window_.window.getSize();
            sf::Texture capTex;
            capTex.create( winSize.x, winSize.y );
            capTex.update( window_.window );
            sf::Image img = capTex.copyToImage();
            img.saveToFile( fname + ( p.view_mode == MatrixPanel::ViewMode::LineCut ? "_lines.png" : "_volume.png" ) );
        }
    }
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Save current view to PNG (_image / _lines / _volume)" );

    // ---- Line-cut component visibility / legend (only in 1D mode, complex matrices) ----
    if ( p.view_mode == MatrixPanel::ViewMode::LineCut
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
    ImGui::SetNextItemWidth( 80.f );
    ImGui::SliderInt( "Skip##dl", &p.download_every, 1, 32 );
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

    ImGui::SameLine();
    ImGui::Checkbox( "Sqare##sq", &p.square_aspect );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Force square pixels (letterbox to N_c:N_r aspect ratio)" );

    ImGui::SameLine();
    ImGui::Checkbox( "FFT shift##fftsh", &p.fft_shift );
    if ( ImGui::IsItemHovered() )
        ImGui::SetTooltip( "Remap indices so DC (k=0) is at the centre instead of the corners" );

    if ( p.view_mode != MatrixPanel::ViewMode::LineCut ) {
        ImGui::SameLine();
        ImGui::SetNextItemWidth( 80.f );
        ImGui::SliderInt( "Stride##3ds", &p.subsample_3d, 1, 64 );
        if ( ImGui::IsItemHovered() )
            ImGui::SetTooltip( "Subsampling stride - display every N-th pixel (1 = full, higher = faster)" );
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

    if ( p.view_mode == MatrixPanel::ViewMode::Image2D ) {
        // --- 2D colormap image ---
        const float full_w = avail.x;
        const float full_h = std::max( 10.f, avail.y - plot_h );
        float off_x = 0.f, off_y = 0.f;
        ImVec2 img_size( full_w, full_h );
        if ( p.square_aspect && p.tex_w > 0 && p.tex_h > 0 ) {
            const float aspect = (float)p.tex_w / (float)p.tex_h;
            const float fit_w  = full_h * aspect;
            if ( fit_w <= full_w ) {
                img_size = ImVec2( fit_w, full_h );
                off_x    = ( full_w - fit_w ) * 0.5f;
            } else {
                img_size = ImVec2( full_w, full_w / aspect );
                off_y    = ( full_h - img_size.y ) * 0.5f;
            }
        }

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

            ImDrawList* dl = ImGui::GetWindowDrawList();
            ImVec2 pre_cursor = ImGui::GetCursorScreenPos();

            // Fill letterbox background when square aspect is active
            if ( p.square_aspect )
                dl->AddRectFilled( pre_cursor,
                                   ImVec2( pre_cursor.x + full_w, pre_cursor.y + full_h ),
                                   ImGui::GetColorU32( ImGuiCol_WindowBg ) );

            ImVec2 img_cursor( pre_cursor.x + off_x, pre_cursor.y + off_y );
            ImVec2 img_p1( img_cursor.x + img_size.x, img_cursor.y + img_size.y );

            // InvisibleButton covers full layout space; interaction restricted to image bounds
            ImGui::InvisibleButton( "##canvas", ImVec2( full_w, full_h ) );
            const bool is_hovered = ImGui::IsItemHovered();
            const bool is_active  = ImGui::IsItemActive();

            dl->AddImage( tex_id, img_cursor, img_p1, uv0, uv1 );

            // Only interact when mouse is within the actual image (not the letterbox)
            const ImVec2 mouse = ImGui::GetIO().MousePos;
            const bool in_image = mouse.x >= img_cursor.x && mouse.x <= img_p1.x
                                && mouse.y >= img_cursor.y && mouse.y <= img_p1.y;

            // ---- Scroll-wheel zoom (zoom toward cursor) ----
            if ( is_hovered && in_image ) {
                const float wheel = ImGui::GetIO().MouseWheel;
                if ( wheel != 0.0f ) {
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
            if ( is_active && in_image && p.zoom_scale > 1.001f ) {
                const ImVec2 delta   = ImGui::GetIO().MouseDelta;
                const float  cur_uv  = 1.0f / p.zoom_scale;
                p.pan_u = std::clamp( p.pan_u - ( delta.x / img_size.x ) * cur_uv, 0.0f, 1.0f - cur_uv );
                p.pan_v = std::clamp( p.pan_v - ( delta.y / img_size.y ) * cur_uv, 0.0f, 1.0f - cur_uv );
            }

            // ---- Double-click to reset zoom & pan ----
            if ( is_hovered && in_image && ImGui::IsMouseDoubleClicked( ImGuiMouseButton_Left ) ) {
                p.zoom_scale = 1.0f;
                p.pan_u = p.pan_v = 0.0f;
            }

            // ---- Cursor hint ----
            if ( is_hovered && in_image )
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
                    const int src_r = p.fft_shift ? ( ri + p.tex_h / 2 ) % p.tex_h : ri;
                    const int src_c = p.fft_shift ? ( ci + p.tex_w / 2 ) % p.tex_w : ci;
                    const int idx_px = src_r * p.tex_w + src_c;
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
    } else if ( p.view_mode == MatrixPanel::ViewMode::LineCut ) {
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
                    int si = i, scol = p.slice_index, srow = p.slice_index;
                    if ( p.fft_shift ) {
                        si   = ( i + slice_len / 2 ) % slice_len;
                        scol = ( p.slice_index + N_c / 2 ) % N_c;
                        srow = ( p.slice_index + N_r / 2 ) % N_r;
                    }
                    const int didx = ( p.slice_axis == 0 )
                        ? ( si * N_c + scol )
                        : ( srow * N_c + si );
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
    } else {
        // --- 3D surface plot ---
        renderMatrixPanel3D( p );
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
// renderMatrixPanel3D - interactive 3D surface via implot3d
// ============================================================

void PhoenixGUI::renderMatrixPanel3D( MatrixPanel& p ) {
    if ( p.selected < 0 || p.selected >= (int)matrix_registry_.size() ) return;
    const auto& desc = matrix_registry_[p.selected];
    if ( !desc.available ) return;

    auto& sys = solver_.system;
    const int W = p.tex_w, H = p.tex_h;
    if ( W == 0 || H == 0 ) return;

    // Reuse the already-downloaded host pointer (blitPanel synced it this frame)
    const bool is_complex = ( desc.complex_mat != nullptr );
    const Type::complex* cdata = is_complex ? desc.complex_mat->getHostPtr() : nullptr;
    const Type::real*    rdata = ( !is_complex && desc.real_mat ) ? desc.real_mat->getHostPtr() : nullptr;
    if ( !cdata && !rdata ) return;

    int stride  = std::max( 1, p.subsample_3d );
    int cols_3d = ( W + stride - 1 ) / stride;
    int rows_3d = ( H + stride - 1 ) / stride;

    // PlotSurface requires xs, ys, zs to all be flat arrays of length x_count*y_count.
    // Build full 2D coordinate grids (not 1D axes).
    const size_t n3d = (size_t)rows_3d * cols_3d;
    std::vector<double> xs( n3d ), ys( n3d ), zs( n3d );

    const double dx_phys = (double)sys.p.L_x / W;
    const double dy_phys = (double)sys.p.L_y / H;
    for ( int ri = 0; ri < rows_3d; ri++ ) {
        for ( int ci = 0; ci < cols_3d; ci++ ) {
            xs[ri * cols_3d + ci] = ( ci * stride + 0.5 ) * dx_phys - 0.5 * (double)sys.p.L_x;
            ys[ri * cols_3d + ci] = ( ri * stride + 0.5 ) * dy_phys - 0.5 * (double)sys.p.L_y;
        }
    }

    // FFT-shift helper (same remapping as in blitPanel)
    auto shiftIdx3D = [&]( int r, int c ) -> int {
        if ( p.fft_shift ) {
            r = ( r + H / 2 ) % H;
            c = ( c + W / 2 ) % W;
        }
        return r * W + c;
    };

    // Compute display values using same logic as blitPanel
    for ( int ri = 0; ri < rows_3d; ri++ ) {
        for ( int ci = 0; ci < cols_3d; ci++ ) {
            const int src = shiftIdx3D( std::min( ri * stride, H - 1 ), std::min( ci * stride, W - 1 ) );
            double v = 0.0;
            if ( cdata ) {
                switch ( p.display_mode ) {
                    case MatrixPanel::DisplayMode::Abs:   v = (double)CUDA::sqrt( CUDA::abs2( cdata[src] ) ); break;
                    case MatrixPanel::DisplayMode::Real:  v = (double)CUDA::real( cdata[src] ); break;
                    case MatrixPanel::DisplayMode::Imag:  v = (double)CUDA::imag( cdata[src] ); break;
                    case MatrixPanel::DisplayMode::Phase: v = (double)CUDA::arg(  cdata[src] ); break;
                    default:                              v = (double)CUDA::abs2( cdata[src] ); break;
                }
            } else {
                v = (double)rdata[src];
            }
            if ( p.log_scale && p.display_mode != MatrixPanel::DisplayMode::Phase )
                v = std::log10( std::max( v, 1e-30 ) );
            zs[ri * cols_3d + ci] = v;
        }
    }

    // Apply manual range or auto-scale
    double zmin, zmax;
    if ( p.display_mode == MatrixPanel::DisplayMode::Phase ) {
        zmin = -std::numbers::pi;
        zmax =  std::numbers::pi;
    } else if ( p.use_manual_range ) {
        zmin = p.log_scale ? std::log10( std::max( p.manual_min, 1e-30 ) ) : p.manual_min;
        zmax = p.log_scale ? std::log10( std::max( p.manual_max, 1e-30 ) ) : p.manual_max;
    } else {
        zmin =  std::numeric_limits<double>::max();
        zmax = -std::numeric_limits<double>::max();
        for ( double v : zs ) { zmin = std::min( zmin, v ); zmax = std::max( zmax, v ); }
        if ( zmax - zmin < 1e-30 ) zmax = zmin + 1e-30;
    }

    // Map the panel colormap index to a registered implot3d colormap.
    // colormap_idx < 0 means "auto": vik (index 0) for amplitude, viko (index 1) for phase.
    ImPlot3DColormap cmap = ImPlot3DColormap_Viridis; // fallback if not yet registered
    if ( implot3d_colormap_base_ >= 0 ) {
        int cm_idx = p.colormap_idx;
        if ( cm_idx < 0 ) {
            const bool is_phase_mode = ( p.display_mode == MatrixPanel::DisplayMode::Phase )
                                    || ( desc.is_phase );
            cm_idx = is_phase_mode ? 1 : 0;   // viko=1 for phase, vik=0 for amplitude
        }
        cm_idx = std::clamp( cm_idx, 0, (int)colormaps_.size() - 1 );
        cmap = (ImPlot3DColormap)( implot3d_colormap_base_ + cm_idx );
    }

    const ImVec2 plot_sz = ImGui::GetContentRegionAvail();
    ImPlot3D::PushColormap( cmap );
    if ( ImPlot3D::BeginPlot( "##surf3d", plot_sz ) ) {
        ImPlot3D::SetupAxes( "x (µm)", "y (µm)", "z" );
        ImPlot3D::SetupAxisLimits( ImAxis3D_Z, zmin, zmax, ImPlot3DCond_Always );
        ImPlot3D::PlotSurface( "##surface",
            xs.data(), ys.data(), zs.data(),
            cols_3d, rows_3d,
            zmin, zmax,
            ImPlot3DSurfaceFlags_NoLines );
        ImPlot3D::EndPlot();
    }
    ImPlot3D::PopColormap();
}

// ============================================================
// tileHelper / tileViews - auto-arrange open panels
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

#endif  // SFML_RENDER

} // namespace PHOENIX
