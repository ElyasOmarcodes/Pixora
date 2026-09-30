#version 460 core

// Signed pixel arithmetic for Unsharp Mask, High Pass and Emboss:
//   colour = base + uK * (a - b), on straight colour, alpha from uAlpha.
// base is [uBase] when uGrey < 0, else the flat grey uGrey (0..1).
// Blend-mode tricks for this came out wrong on Impeller.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uK;
uniform float uGrey;
uniform sampler2D uBase;
uniform sampler2D uA;
uniform sampler2D uB;
uniform sampler2D uAlpha;

out vec4 fragColor;

vec3 straight(vec4 c) {
  return c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float alpha = texture(uAlpha, p).a;
  if (alpha <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 base = uGrey < 0.0 ? straight(texture(uBase, p)) : vec3(uGrey);
  vec3 d = straight(texture(uA, p)) - straight(texture(uB, p));
  vec3 c = clamp(base + uK * d, 0.0, 1.0);
  fragColor = vec4(c * alpha, alpha);
}
