#pragma once

#include <SFML/Graphics.hpp>
#include <SFML/Window.hpp>
#include <omp.h>
#include <iostream>
#include "misc/colormap.hpp"
#include "cuda/typedef.cuh"

// Resources
#include "resources/font.hpp"

class BasicWindow;

class WindowObject {
   public:
    int x, y;
    bool visible = true;

    WindowObject( int x, int y, bool visible = true ) : x( x ), y( y ), visible( visible ) {
    }
    WindowObject() = default;

    virtual bool draw( BasicWindow* basicwindow ) = 0;
    virtual void update() = 0;
    virtual void onClick( int x, int y ) = 0;
    virtual void onHover( int x, int y, bool mouseDown ) = 0;
};

class BasicWindow {
   protected:
    int mouseX, mouseY;
    bool mouseLB, mouseRB;
    int texture_w, texture_h;

   public:
    // Most basic colors
    static inline auto COLOR_WHITE = sf::Color( 255, 255, 255 );
    static inline auto COLOR_BLACK = sf::Color( 0, 0, 0 );
    static inline auto COLOR_GREEN = sf::Color( 0, 255, 0 );
    static inline auto COLOR_RED = sf::Color( 255, 0, 0 );
    static inline auto COLOR_BLUE = sf::Color( 0, 0, 255 );

    // Keys
    static inline auto KEY_a = sf::Keyboard::A;
    static inline auto KEY_b = sf::Keyboard::B;
    static inline auto KEY_c = sf::Keyboard::C;
    static inline auto KEY_d = sf::Keyboard::D;
    static inline auto KEY_e = sf::Keyboard::E;
    static inline auto KEY_f = sf::Keyboard::F;
    static inline auto KEY_g = sf::Keyboard::G;
    static inline auto KEY_h = sf::Keyboard::H;
    static inline auto KEY_i = sf::Keyboard::I;
    static inline auto KEY_j = sf::Keyboard::J;
    static inline auto KEY_k = sf::Keyboard::K;
    static inline auto KEY_l = sf::Keyboard::L;
    static inline auto KEY_m = sf::Keyboard::M;
    static inline auto KEY_n = sf::Keyboard::N;
    static inline auto KEY_o = sf::Keyboard::O;
    static inline auto KEY_p = sf::Keyboard::P;
    static inline auto KEY_q = sf::Keyboard::Q;
    static inline auto KEY_r = sf::Keyboard::R;
    static inline auto KEY_s = sf::Keyboard::S;
    static inline auto KEY_t = sf::Keyboard::T;
    static inline auto KEY_u = sf::Keyboard::U;
    static inline auto KEY_v = sf::Keyboard::V;
    static inline auto KEY_w = sf::Keyboard::W;
    static inline auto KEY_x = sf::Keyboard::X;
    static inline auto KEY_y = sf::Keyboard::Y;
    static inline auto KEY_z = sf::Keyboard::Z;
    static inline auto KEY_UP = sf::Keyboard::Up;
    static inline auto KEY_DOWN = sf::Keyboard::Down;
    static inline auto KEY_LEFT = sf::Keyboard::Left;
    static inline auto KEY_RIGHT = sf::Keyboard::Right;
    static inline auto KEY_SPACE = sf::Keyboard::Space;
    static inline auto KEY_LSHIFT = sf::Keyboard::LShift;
    static inline auto KEY_RSHIFT = sf::Keyboard::RShift;
    static inline auto KEY_ESCAPE = sf::Keyboard::Escape;
    static inline auto KEY_PLUS = sf::Keyboard::Add;
    static inline auto KEY_MINUS = sf::Keyboard::Subtract;

    int width;
    int height;
    double frametime = 0;
    int fps = 0;
    std::string name;
    double time_ticks = 0;
    int maxFPS = 60;
    sf::RenderWindow window;
    sf::Font font;
    sf::RenderTexture mainTexture;
    std::vector<sf::Vertex> pixMat;
    sf::Text printtext;
    sf::Clock clock;
    float textheight;
    int keyDown = -1;
    bool maintexture_has_changed = true;
    bool mouseLB_old = false;
    bool mouseRB_old = false;

    std::vector<WindowObject*> objects;

    BasicWindow( int w = 300, int h = 300, std::string n = "Unnamed" ) {
        construct( w, h, w, h, n );
    }

    void construct( int window_w, int window_h, int tx_w, int tx_h, std::string n ) {
        width = window_w;
        height = window_h;
        texture_w = tx_w;
        texture_h = tx_h;
        name = n;
        mainTexture.create( tx_w, tx_h );
        pixMat.clear();
        pixMat.reserve( ( tx_w + 1 ) * ( tx_h + 1 ) );
        font.loadFromMemory( PHOENIX::Misc::Resources::font_ttf.data(), PHOENIX::Misc::Resources::font_ttf.size() );
        textheight = 25;
        printtext.setFont( font );
        printtext.setCharacterSize( textheight );
        printtext.setOutlineColor( COLOR_BLACK );
        printtext.setOutlineThickness( 1.0f );
        for ( int i = 0; i < tx_w; i++ ) {
            for ( int j = 0; j < tx_h; j++ ) {
                pixMat.push_back( sf::Vertex( sf::Vector2f( i + .5f, j + .5f ), sf::Color( 0, 0, 0 ) ) );
            }
        }
        std::cout << "Constructed Basic window with " << width << "x" << height << " pixels, reserved are " << texture_w << "x" << texture_h << " -> " << pixMat.size() << " pixels." << std::endl;
    }

    void init() {
        window.create( sf::VideoMode( width, height, 32 ), name, sf::Style::Default, sf::ContextSettings( 0, 0, 1, 2, 0 ) );
        window.setVerticalSyncEnabled( true );
        mainTexture.setSmooth( true );
    }

    bool run() {
        keyDown = -1;
        window.clear();
        updateMouseState();
        if ( maintexture_has_changed ) {
            mainTexture.draw( pixMat.data(), texture_w * texture_h, sf::Points );
            maintexture_has_changed = false;
        }
        sf::Sprite mainSprite( mainTexture.getTexture() );
        mainSprite.setScale( (float)width / texture_w, (float)height / texture_h );
        window.draw( mainSprite );

        // Time, FPS
        frametime = clock.restart().asMilliseconds();
        fps = (int)( 1000.0 / frametime );

        sf::Event event;
        while ( window.pollEvent( event ) ) {
            if ( event.type == sf::Event::Closed )
                window.close();
            if ( event.type == sf::Event::KeyPressed )
                keyDown = event.key.code;
        }

        return window.isOpen();
    }

    void flipscreen() {
        window.display();
    }

    void blitMatrixPtr( const PHOENIX::Type::real* vector, PHOENIX::Type::real min, PHOENIX::Type::real max, ColorPalette& cp, int cols = 0, int rows = 0, int posX = 0, int posY = 0, int border = 0, int skip = 1 ) {
        const int cols_over_skip = cols / skip;
        const int rows_over_skip = rows / skip;
        //std::cout << "Attempting to blit array at " << posX << "x" << posY << " with cols x rows = " << cols << "x" << rows << " pixels, skipping " << skip << " pixels, resulting in " << cols_over_skip << "x" << rows_over_skip << " pixels." << std::endl;
#pragma omp parallel for schedule( static )
        for ( int r = 0; r < rows_over_skip; r++ ) {
            for ( int c = 0; c < cols_over_skip; c++ ) {
                auto color = cp.getColor( ( vector[( r * skip ) * cols + c * skip] - min ) / ( max - min ) );
                const auto index = ( c + 1 + posX ) * texture_h - 1 - ( r + posY );
                pixMat.at( index ).color.r = color.r;
                pixMat.at( index ).color.g = color.g;
                pixMat.at( index ).color.b = color.b;
                if ( border != 0 && ( c < border || c >= cols_over_skip - border || r < border || r >= rows_over_skip - border ) ) {
                    pixMat.at( index ).color.r = 0;
                    pixMat.at( index ).color.g = 0;
                    pixMat.at( index ).color.b = 0;
                }
            }
        }
        maintexture_has_changed = true;
    }
    void blitMatrixPtr( const PHOENIX::Type::complex* vector, PHOENIX::Type::complex min, PHOENIX::Type::complex max, ColorPalette& cp, int cols = 0, int rows = 0, int posX = 0, int posY = 0, int border = 0, int skip = 1 ) {
        const int cols_over_skip = cols / skip;
        const int rows_over_skip = rows / skip;
        //std::cout << "Attempting to blit array at " << posX << "x" << posY << " with cols x rows = " << cols << "x" << rows << " pixels, skipping " << skip << " pixels, resulting in " << cols_over_skip << "x" << rows_over_skip << " pixels." << std::endl;
#pragma omp parallel for schedule( static )
        for ( int r = 0; r < rows_over_skip; r++ ) {
            for ( int c = 0; c < cols_over_skip; c++ ) {
                auto color = cp.getColor( PHOENIX::CUDA::abs( ( vector[( r * skip ) * cols + c * skip] - min ) / ( max - min ) ) );
                const auto index = ( c + 1 + posX ) * texture_h - 1 - ( r + posY );
                pixMat.at( index ).color.r = color.r;
                pixMat.at( index ).color.g = color.g;
                pixMat.at( index ).color.b = color.b;
                if ( border != 0 && ( c < border || c >= cols_over_skip - border || r < border || r >= rows_over_skip - border ) ) {
                    pixMat.at( index ).color.r = 0;
                    pixMat.at( index ).color.g = 0;
                    pixMat.at( index ).color.b = 0;
                }
            }
        }
        maintexture_has_changed = true;
    }

    sf::Color convertColorToSFML( int r, int g, int b ) {
        return sf::Color( r, g, b );
    }

    void print( int x, int y, std::string text, sf::Color textcolor = COLOR_WHITE, int background = 0, sf::Color backgroundcolor = COLOR_BLACK ) {
        print( x, y, textheight, text, textcolor, background, backgroundcolor );
    }

    void print( int x, int y, float h, std::string text, sf::Color textcolor = COLOR_WHITE, int background = 0, sf::Color backgroundcolor = COLOR_BLACK ) {
        printtext.setFillColor( textcolor );
        printtext.setPosition( (float)x, (float)y );
        printtext.setString( text );
        if ( h > 0 )
            printtext.setCharacterSize( h );
        window.draw( printtext );
    }

    void scaledPrint( int x, int y, std::string text, sf::Color textcolor = COLOR_WHITE, int background = 0, sf::Color backgroundcolor = COLOR_BLACK ) {
        scaledPrint( x, y, textheight, text, textcolor, background, backgroundcolor );
    }

    void scaledPrint( int x, int y, float h, std::string text, sf::Color textcolor = COLOR_WHITE, int background = 0, sf::Color backgroundcolor = COLOR_BLACK ) {
        float x_scale = (float)width / texture_w;
        float y_scale = (float)height / texture_h;
        x = x * x_scale;
        y = y * y_scale;
        printtext.setFillColor( textcolor );
        printtext.setPosition( (float)x, (float)y );
        printtext.setString( text );
        if ( h > 0 )
            printtext.setCharacterSize( h );
        window.draw( printtext ); // std::cout << "Test " << text << std::endl;
    }

    bool keyPressed( int key ) {
        return keyDown == key;
    }

    void updateMouseState() {
        mouseLB = sf::Mouse::isButtonPressed( sf::Mouse::Left );
        mouseRB = sf::Mouse::isButtonPressed( sf::Mouse::Right );
        sf::Vector2i position = sf::Mouse::getPosition( window );
        mouseX = position.x;
        mouseY = position.y;
    }

    int MouseX() {
        return mouseX;
    }

    int MouseY() {
        return mouseY;
    }

    bool leftMouseDown() {
        return mouseLB;
    }
    bool rightMouseDown() {
        return mouseRB;
    }
    bool leftMouseClicked() {
        if ( mouseLB && !mouseLB_old ) {
            mouseLB_old = true;
            return true;
        }
        if ( !mouseLB && mouseLB_old ) {
            mouseLB_old = false;
        }
        return false;
    }
    bool rightMouseClicked() {
        if ( mouseRB && !mouseRB_old ) {
            mouseRB_old = true;
            return true;
        }
        if ( !mouseRB && mouseRB_old ) {
            mouseRB_old = false;
        }
        return false;
    }

    void horLine( int y0, int x0, int x1, sf::Color color = COLOR_WHITE ) {
        float x_scale = (float)width / texture_w;
        float y_scale = (float)height / texture_h;
        x0 = x0 * x_scale;
        y0 = y0 * y_scale;
        sf::RectangleShape line( sf::Vector2f( x1 - x0, 1.0f ) );
        line.setPosition( sf::Vector2f( x0, y0 ) );
        line.setFillColor( color );
        window.draw( line );
    }

    void verLine( int x0, int y0, int y1, sf::Color color = COLOR_WHITE ) {
        float x_scale = (float)width / texture_w;
        float y_scale = (float)height / texture_h;
        x0 = x0 * x_scale;
        y0 = y0 * y_scale;
        sf::RectangleShape line( sf::Vector2f( y1 - y0, 1.0f ) );
        line.setPosition( sf::Vector2f( x0, y0 ) );
        line.setFillColor( color );
        line.rotate( 90 );
        window.draw( line );
    }

    void drawRect( int x0, int x1, int y0, int y1, sf::Color color = COLOR_WHITE, bool filled = false ) {
        if ( x0 <= 0 )
            x0 = 0;
        if ( x1 >= width )
            x1 = width;
        if ( y0 <= 0 )
            y0 = 0;
        if ( y1 >= height )
            y1 = height;
        if ( filled ) {
            sf::RectangleShape rect( sf::Vector2f( x1 - x0, y1 - y0 ) );
            rect.setPosition( x0, y0 );
            rect.setFillColor( color );
            window.draw( rect );
            return;
        }
        horLine( y0, x0, x1, color );
        horLine( y1, x0, x1, color );
        verLine( x0, y0, y1, color );
        verLine( x1, y0, y1, color );
    }

    void addObject( WindowObject* object ) {
        objects.push_back( object );
    }

    void drawObjects() {
        // Draw Objects
        bool mouse_clicked = leftMouseClicked();
        auto mx = MouseX();
        auto my = MouseY();
        for ( auto obj : objects ) {
            bool has_been_drawn = obj->draw( this );

            if ( !has_been_drawn )
                continue;

            if ( mouse_clicked ) {
                obj->onClick( mx, my );
            }
            obj->onHover( mx, my, leftMouseDown() );
        }
    }
};

class CheckBox : public WindowObject {
   public:
    bool checked = false;
    std::string text;
    int w, h;
    CheckBox( int x, int y, std::string text, bool checked = false ) : WindowObject( x, y ), text( text ), checked( checked ) {
        w = 20;
        h = 20;
    }
    CheckBox() = default;

    bool isChecked() {
        return checked;
    }

    bool draw( BasicWindow* basicwindow ) override {
        if ( !visible )
            return false;
        sf::RectangleShape rect_outer( sf::Vector2f( w, h ) );
        sf::RectangleShape rect_inner( sf::Vector2f( w - 4, h - 4 ) );
        sf::RectangleShape rect( sf::Vector2f( w - 8, h - 8 ) );
        rect_outer.setPosition( x, y );
        rect_inner.setPosition( x + 2, y + 2 );
        rect.setPosition( x + 4, y + 4 );

        rect_outer.setFillColor( sf::Color::White );
        rect_inner.setFillColor( sf::Color::Black );
        rect.setFillColor( checked ? sf::Color( 50, 50, 50 ) : sf::Color::White );
        basicwindow->window.draw( rect_outer );
        basicwindow->window.draw( rect_inner );
        basicwindow->window.draw( rect );
        basicwindow->print( x + w + 5, y, 16, text );
        return true;
    }

    void update() override {
    }

    void onClick( int x, int y ) override {
        if ( x >= this->x && x <= this->x + w && y >= this->y && y <= this->y + h ) {
            checked = !checked;
        }
    }
    void onHover( int x, int y, bool mouseDown ) override {
        // if ( x >= this->x && x <= this->x + w && y >= this->y && y <= this->y + h )
    }
};

class Button : public WindowObject {
   public:
    std::string text;
    bool toggled;
    int w, h;
    Button( int x, int y, std::string text, bool toggled = false ) : WindowObject( x, y ), text( text ), toggled( toggled ) {
        w = 170;
        h = 25;
    }
    Button() = default;

    bool draw( BasicWindow* basicwindow ) override {
        if ( !visible )
            return false;
        sf::RectangleShape rect_outer( sf::Vector2f( w, h ) );
        sf::RectangleShape rect_inner( sf::Vector2f( w - 4, h - 4 ) );
        rect_outer.setPosition( x, y );
        rect_inner.setPosition( x + 2, y + 2 );

        rect_outer.setFillColor( sf::Color::Black );
        rect_inner.setFillColor( sf::Color( 50, 50, 50 ) );
        basicwindow->window.draw( rect_outer );
        basicwindow->window.draw( rect_inner );
        basicwindow->print( x + 7, y, 16, text );
        return true;
    }

    void update() override {
    }

    void onClick( int x, int y ) override {
        if ( x >= this->x && x <= this->x + w && y >= this->y && y <= this->y + h ) {
            toggled = true;
        }
    }
    void onHover( int x, int y, bool mouseDown ) override {
        // if ( x >= this->x && x <= this->x + w && y >= this->y && y <= this->y + h )
    }
    bool isToggled() {
        if ( toggled ) {
            toggled = false;
            return true;
        }
        return false;
    }
};