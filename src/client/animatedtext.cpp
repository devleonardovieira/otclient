/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "animatedtext.h"

#include "game.h"
#include "gameconfig.h"
#include "map.h"
#include "framework/core/eventdispatcher.h"
#include "framework/core/graphicalapplication.h"
#include "framework/graphics/drawpoolmanager.h"
#include <framework/stdext/math.h>

AnimatedText::AnimatedText()
{
    m_cachedText.setFont(g_gameConfig.getAnimatedTextFont());
    m_cachedText.setAlign(Fw::AlignLeft);

    // Initial random velocity for arc movement
    // "Falls randomly to right, left or north"
    // We simulate this with initial velocity + gravity
    int dir = stdext::random_range(0, 2);
    float vx = 0;
    float vy = -140.f; // Increased initial upward burst for higher jump

    if (dir == 0) { // Left
        vx = stdext::random_range(-90.f, -50.f); // Increased side distance
    } else if (dir == 1) { // Right
        vx = stdext::random_range(50.f, 90.f); // Increased side distance
    } else { // North (Up/Center)
        vx = stdext::random_range(-15.f, 15.f);
        vy -= 40.f; // Jump slightly higher for center hits
    }
    m_velocity = PointF(vx, vy);
}

void AnimatedText::drawText(const Point& dest, const Rect& visibleRect)
{
    const float tf = g_gameConfig.getAnimatedTextDuration();
    const float t = m_animationTimer.ticksElapsed();
    const float progress = t / tf;

    if (progress >= 1.0f)
        return;

    const auto& textSize = m_cachedText.getTextSize();
    const float scale = g_app.getAnimatedTextScale();

    // Base position (centered)
    // Original logic: p.x += (24.f / scale - (textSize.width() / 2.f));
    PointF p(dest.x, dest.y);
    p.x += (24.f / scale - (textSize.width() / 2.f));
    
    // Physics Arc
    float t_sec = t / 1000.0f;
    const float gravity = 350.0f; // Increased gravity for a more pronounced arc

    float dx = m_velocity.x * t_sec;
    float dy = m_velocity.y * t_sec + 0.5f * gravity * t_sec * t_sec;

    p.x += dx;
    p.y += dy;

    // Manual Offset
    p.x += m_offset.x;
    p.y += m_offset.y;

    // Growth (Size 14 -> 20 implies ~1.43x scale)
    // Smooth transition
    float growFactor = 1.0f + (0.43f * progress);
    
    // Calculate Scaled Size
    Size finalSize = textSize * growFactor;
    
    // Re-center based on growth
    // Shift left/up by half the growth difference
    p.x -= (finalSize.width() - textSize.width()) / 2.0f;
    p.y -= (finalSize.height() - textSize.height()) / 2.0f;

    // Apply global scale to position (matching original logic)
    p.x *= scale;
    p.y *= scale;

    Rect drawRect(std::round(p.x), std::round(p.y), finalSize.width(), finalSize.height());

    // Visibility Check
    if (!visibleRect.contains(drawRect))
        return;

    Color color = m_color;
    
    // Smooth Fade Out (Last 40%)
    if (progress > 0.6f) {
        color.setAlpha(1.0f - (progress - 0.6f) / 0.4f);
    }

    m_cachedText.draw(drawRect, color);
}

void AnimatedText::onAppear()
{
    m_animationTimer.restart();

    uint16_t textDuration = g_gameConfig.getAnimatedTextDuration();
    if (g_app.mustOptimize())
        textDuration /= 2;

    // schedule removal
    g_textDispatcher.scheduleEvent([self = asAnimatedText()] { g_map.removeAnimatedText(self); }, textDuration);
}

bool AnimatedText::merge(const AnimatedTextPtr& other)
{
    if (other->getColor() != m_color)
        return false;

    if (other->getCachedText().getFont() != m_cachedText.getFont())
        return false;

    if (m_animationTimer.ticksElapsed() > g_gameConfig.getAnimatedTextDuration() / 2.5)
        return false;

    try {
        const int number = stdext::safe_cast<int>(m_cachedText.getText());
        const int otherNumber = stdext::safe_cast<int>(other->getCachedText().getText());
        m_cachedText.setText(fmt::format("{}", number + otherNumber));
        return true;
    } catch (...) {
        return false;
    }
}