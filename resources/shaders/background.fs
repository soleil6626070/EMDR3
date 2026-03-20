// Precision boilerplate: use highp on capable hardware, mediump as fallback.
// This avoids visual artefacts on mobile/lower-end GPUs.
#if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
	#define FLOAT_PRECISION highp
#else
	#define FLOAT_PRECISION mediump
#endif

// --- Uniforms sent from Lua each frame ---
extern FLOAT_PRECISION number time;         // Drives the paint animation. Increment slowly for a calm effect.
extern FLOAT_PRECISION number spin_time;    // Drives the rotational drift of the whole pattern.
extern FLOAT_PRECISION vec4 colour_1;       // Primary/base colour (RGBA)
extern FLOAT_PRECISION vec4 colour_2;       // Secondary colour, blended into low-intensity areas
extern FLOAT_PRECISION vec4 colour_3;       // Accent colour, appears at the boundaries between c1 and c2
extern FLOAT_PRECISION number contrast;     // Sharpness of colour band edges. Higher = harder edges.
extern FLOAT_PRECISION number spin_amount;  // 0 = no swirl, 1 = full vortex pulled toward centre

// How many screen pixels map to one "logical" pixel in the blocky pixelation effect.
// Higher value = smaller/finer pixels; lower = chunkier blocks.
#define PIXEL_SIZE_FAC 700.

// Softens the relationship between spin_time and the actual rotation angle.
// Acts as a fixed speed multiplier baked into the shader.
#define SPIN_EASE 0.5

vec4 effect( vec4 colour, Image texture, vec2 texture_coords, vec2 screen_coords )
{
    // --- Step 1: Pixelation ---
    // Snap screen_coords to a grid to create the blocky pixel look,
    // then re-centre so (0,0) is the middle of the screen.
    FLOAT_PRECISION number pixel_size = length(love_ScreenSize.xy) / PIXEL_SIZE_FAC;
    FLOAT_PRECISION vec2 uv = (floor(screen_coords.xy * (1. / pixel_size)) * pixel_size - 0.5 * love_ScreenSize.xy)
                                  / length(love_ScreenSize.xy) - vec2(0.12, 0.);
    FLOAT_PRECISION number dist_from_centre = length(uv);

    // --- Step 2: Rotational swirl ---
    // Rotate each pixel around the centre by an angle that varies with spin_time.
    // Pixels further from the centre are rotated less when spin_amount is high,
    // creating a vortex/whirlpool pull toward the middle.
    FLOAT_PRECISION number rotation_offset = (spin_time * SPIN_EASE * 0.2) + 302.2;
    FLOAT_PRECISION number swirled_angle = (atan(uv.y, uv.x))
                                               + rotation_offset
                                               - SPIN_EASE * 20. * (1. * spin_amount * dist_from_centre + (1. - 1. * spin_amount));
    FLOAT_PRECISION vec2 screen_centre = (love_ScreenSize.xy / length(love_ScreenSize.xy)) / 2.;
    // Rebuild the uv position from the new swirled angle, keeping the same distance from centre.
    uv = (vec2((dist_from_centre * cos(swirled_angle) + screen_centre.x),
               (dist_from_centre * sin(swirled_angle) + screen_centre.y)) - screen_centre);

    // --- Step 3: Paint/fluid noise ---
    // Scale uv up so the noise pattern covers the screen at a good density.
    uv *= 30.;
    FLOAT_PRECISION number anim_speed = time * 2.;
    // uv2 is a secondary coordinate that feeds back into itself each iteration,
    // creating an organic, self-similar swirling pattern (domain warping).
    FLOAT_PRECISION vec2 warped_uv = vec2(uv.x + uv.y);

    // Each iteration feeds the previous result back in, warping the space further.
    // More iterations = more complex/detailed pattern but more GPU cost.
    for (int i = 0; i < 5; i++) {
        warped_uv += sin(max(uv.x, uv.y)) + uv;
        uv += 0.5 * vec2(cos(5.1123314 + 0.353 * warped_uv.y + anim_speed * 0.131121),
                         sin(warped_uv.x - 0.113 * anim_speed));
        uv -= 1.0 * cos(uv.x + uv.y) - 1.0 * sin(uv.x * 0.711 - uv.y);
    }

    // --- Step 4: Map noise output to colour blend weights ---
    // contrast_mod sharpens or softens the boundaries between the three colours.
    FLOAT_PRECISION number contrast_mod = (0.25 * contrast + 0.5 * spin_amount + 1.2);
    // paint_val is a 0-2 value representing which "band" this pixel falls in.
    FLOAT_PRECISION number paint_val = min(2., max(0., length(uv) * 0.035 * contrast_mod));

    // c1_weight, c2_weight, c3_weight are how much of each colour to blend at this pixel.
    // They are mutually exclusive: only one (or a mix of two adjacent) will be non-zero.
    FLOAT_PRECISION number c1_weight = max(0., 1. - contrast_mod * abs(1. - paint_val)); // peaks at paint_val == 1
    FLOAT_PRECISION number c2_weight = max(0., 1. - contrast_mod * abs(paint_val));      // peaks at paint_val == 0
    FLOAT_PRECISION number c3_weight = 1. - min(1., c1_weight + c2_weight);              // fills the remainder (boundary accent)

    // --- Step 5: Final colour output ---
    // A small amount of colour_1 is added as a base tint across the whole screen (controlled by contrast).
    // The rest is the blended result of the three colour weights.
    FLOAT_PRECISION vec4 final_colour = (0.3 / contrast) * colour_1
        + (1. - 0.3 / contrast) * (colour_1 * c1_weight
                                  + colour_2 * c2_weight
                                  + vec4(c3_weight * colour_3.rgb, c3_weight * colour_1.a));

    return final_colour;
}
