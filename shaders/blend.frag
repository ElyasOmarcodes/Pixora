#version 460 core

// Photoshop blend modes the GPU compositor lacks (and an exact Soft
// Light): composites the layer [uSrc] onto the backdrop [uDst] with
// Photoshop's formulas. Both images are premultiplied and cover the same
// area; the output is the composited backdrop.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uMode;
uniform float uSeed;
uniform sampler2D uSrc;
uniform sampler2D uDst;

out vec4 fragColor;

float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

float vivid(float b, float s) {
  if (s <= 0.5) {
    float s2 = 2.0 * s;
    return s2 <= 0.0 ? (b >= 1.0 ? 1.0 : 0.0) : 1.0 - min(1.0, (1.0 - b) / s2);
  }
  float s2 = 2.0 * (s - 0.5);
  return s2 >= 1.0 ? (b <= 0.0 ? 0.0 : 1.0) : min(1.0, b / (1.0 - s2));
}

float softLightPs(float b, float s) {
  // Photoshop's Soft Light (no polynomial for dark backdrops).
  return s <= 0.5 ? b - (1.0 - 2.0 * s) * b * (1.0 - b)
                  : b + (2.0 * s - 1.0) * (sqrt(b) - b);
}

float pinLight(float b, float s) {
  return s <= 0.5 ? min(b, 2.0 * s) : max(b, 2.0 * s - 1.0);
}

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21) + uSeed);
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

vec3 blend(vec3 b, vec3 s, int m) {
  if (m == 1) return b + s - 1.0;                                // linear burn
  if (m == 2) return b + s;                                      // (unused)
  if (m == 3) return vec3(vivid(b.r, s.r), vivid(b.g, s.g), vivid(b.b, s.b));
  if (m == 4) return b + 2.0 * s - 1.0;                          // linear light
  if (m == 5) return vec3(pinLight(b.r, s.r), pinLight(b.g, s.g), pinLight(b.b, s.b));
  if (m == 6) {                                                  // hard mix
    vec3 v = vec3(vivid(b.r, s.r), vivid(b.g, s.g), vivid(b.b, s.b));
    return step(0.5, v);
  }
  if (m == 7) return b - s;                                      // subtract
  if (m == 8) {                                                  // divide
    return vec3(s.r <= 0.0 ? (b.r > 0.0 ? 1.0 : 0.0) : b.r / s.r,
                s.g <= 0.0 ? (b.g > 0.0 ? 1.0 : 0.0) : b.g / s.g,
                s.b <= 0.0 ? (b.b > 0.0 ? 1.0 : 0.0) : b.b / s.b);
  }
  if (m == 9) return lum(s) < lum(b) ? s : b;                    // darker color
  if (m == 10) return lum(s) > lum(b) ? s : b;                   // lighter color
  if (m == 11) {                                                 // soft light
    return vec3(softLightPs(b.r, s.r), softLightPs(b.g, s.g), softLightPs(b.b, s.b));
  }
  return s;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 src = texture(uSrc, uv);
  vec4 dst = texture(uDst, uv);
  int m = int(uMode + 0.5);
  if (m == 12) {
    // Dissolve: each pixel shows the layer fully or not at all, with the
    // layer's alpha as the chance.
    float keep = hash(floor(FlutterFragCoord().xy)) < src.a ? 1.0 : 0.0;
    vec4 s = src.a > 0.0 ? vec4(src.rgb / src.a, 1.0) * keep : vec4(0.0);
    fragColor = s + dst * (1.0 - s.a);
    return;
  }
  float as = src.a, ad = dst.a;
  vec3 cs = as > 0.0 ? src.rgb / as : vec3(0.0);
  vec3 cd = ad > 0.0 ? dst.rgb / ad : vec3(0.0);
  vec3 bl = clamp(blend(cd, cs, m), 0.0, 1.0);
  // W3C / Photoshop compositing: the blended colour where both overlap.
  vec3 co = (1.0 - ad) * cs + ad * bl;
  float ao = as + ad * (1.0 - as);
  vec3 prem = as * co + (1.0 - as) * ad * cd;
  fragColor = vec4(prem, ao);
}
