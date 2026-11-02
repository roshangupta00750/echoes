shader_type canvas_item;
// The arcade screen: scanlines, a soft glow, a little colour fringing and a dark vignette.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float shake = 0.0;       // 0..1: colour split on hits
uniform float flash = 0.0;       // white flash
uniform float time = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float ab = 0.0005 + shake * 0.006;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(ab, 0.0)).b;
	// a cheap glow: a few blurred taps added on top of the bright parts
	vec3 g = vec3(0.0);
	vec2 px = SCREEN_PIXEL_SIZE * 2.5;
	g += texture(screen_tex, uv + vec2(px.x, 0)).rgb; g += texture(screen_tex, uv - vec2(px.x, 0)).rgb;
	g += texture(screen_tex, uv + vec2(0, px.y)).rgb; g += texture(screen_tex, uv - vec2(0, px.y)).rgb;
	g += texture(screen_tex, uv + px * 1.6).rgb; g += texture(screen_tex, uv - px * 1.6).rgb;
	g += texture(screen_tex, uv + vec2(px.x, -px.y) * 1.6).rgb; g += texture(screen_tex, uv + vec2(-px.x, px.y) * 1.6).rgb;
	g /= 8.0;
	c += max(g - 0.4, 0.0) * 0.9;
	// scanlines, one per game pixel row
	float rows = 1.0 / SCREEN_PIXEL_SIZE.y;
	float sl = mix(1.0, 0.9, mod(floor(uv.y * rows), 2.0));
	c *= sl;
	// vignette
	vec2 d = uv - 0.5;
	c *= 1.0 - dot(d, d) * 0.4;
	c = mix(c, vec3(1.0), flash);
	COLOR = vec4(c, 1.0);
}
