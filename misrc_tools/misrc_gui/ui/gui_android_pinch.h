
    
  
#ifndef MISRC_GUI_ANDROID_PINCH_H
#define MISRC_GUI_ANDROID_PINCH_H

/* Android-only two-finger UI scale control.
 * Included by gui_ui.c immediately before gui_handle_interactions().
 * No Android Java or desktop platform change required.
 */
#if defined(__ANDROID__)
#include <math.h>

static bool gui_android_pinch_process(gui_app_t *app)
{
    static struct {
        bool blocking;
        bool have_distance;
        bool dirty;
        float previous_distance;
        float log_remainder;
    } pinch = {0};
    const int count = GetTouchPointCount();

    if (count >= 2) {
        pinch.blocking = true;
        if (count == 2) {
            const Vector2 a = GetTouchPosition(0);
            const Vector2 b = GetTouchPosition(1);
            const float dx = a.x - b.x;
            const float dy = a.y - b.y;
            const float distance = sqrtf(dx * dx + dy * dy);

            if (isfinite(distance) && distance > 16.0f) {
                if (pinch.have_distance && pinch.previous_distance > 16.0f) {
                    const float ratio = distance / pinch.previous_distance;
                    /* A new/reordered contact should not cause a huge jump. */
                    if (ratio >= 0.65f && ratio <= 1.55f)
                        pinch.log_remainder += logf(ratio);
                    else
                        pinch.log_remainder = 0.0f;

                    /* One UI step per ~12% pinch distance change. Bound work
                     * in a single frame to avoid runaway after a pause. */
                    const float threshold = 0.113329f; /* logf(1.12f) */
                    for (int n = 0; n < 6 &&
                         (pinch.log_remainder >= threshold ||
                          pinch.log_remainder <= -threshold); ++n) {
                        const int direction = (pinch.log_remainder > 0.0f) ? 1 : -1;
                        const int old_percent = app->settings.ui_scale_percent;
                        const int new_percent = gui_ui_scale_step_percent(old_percent, direction);
                        if (new_percent != old_percent) {
                            app->settings.ui_scale_percent = new_percent;
                            gui_ui_set_scale_percent(new_percent);
                            gui_ui_show_scale_hud(new_percent);
                            pinch.dirty = true;
                        }
                        pinch.log_remainder -= threshold * (float)direction;
                    }
                    /* Saturating against the min/max must not stockpile
                     * movement for an unexpected step on reversal. */
                    if ((pinch.log_remainder > threshold &&
                         app->settings.ui_scale_percent >= GUI_UI_SCALE_MAX_PERCENT) ||
                        (pinch.log_remainder < -threshold &&
                         app->settings.ui_scale_percent <= GUI_UI_SCALE_MIN_PERCENT))
                        pinch.log_remainder = 0.0f;
                }
                pinch.previous_distance = distance;
                pinch.have_distance = true;
            } else {
                pinch.have_distance = false;
            }
        } else {
            pinch.have_distance = false;
            pinch.log_remainder = 0.0f;
        }
        /* Do not allow either finger to activate buttons while pinching. */
        return true;
    }

    if (pinch.blocking) {
        /* Also consume the 2->1->0 release sequence: otherwise Android's
         * emulated left mouse button can click through on finger lift. */
        if (count == 0) {
            if (pinch.dirty) gui_settings_save(&app->settings);
            pinch.blocking = false;
            pinch.dirty = false;
            pinch.log_remainder = 0.0f;
        }
        pinch.have_distance = false;
        return true;
    }
    return false;
}
#endif /* __ANDROID__ */
#endif /* MISRC_GUI_ANDROID_PINCH_H */

