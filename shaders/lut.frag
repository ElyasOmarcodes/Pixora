#version 460 core

// Curves / Levels: maps each colour channel of [uImg] through a 256-entry
// table [uLut] (a 256 x 1 image; red, green and blue tables in its red,
// green and blue channels). Works on straight colour; alpha is kept.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uImg;
uniform sampler2D uLut;

out vec4 fragColor;

float look(float v, int ch) {
  vec4 t = texture(uLut, vec2((floor(clamp(v, 0.0, 1.0) * 255.0 + 0.5) + 0.5) / 256.0, 0.5));
  return ch == 0 ? t.r : (ch == 1 ? t.g : t.b);
}

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uImg, p);
  if (c.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 u = c.rgb / c.a;
  fragColor = vec4(vec3(look(u.r, 0), look(u.g, 1), look(u.b, 2)) * c.a, c.a);
}
