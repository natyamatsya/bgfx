// Slang port of examples/53-sky2/vs_sky2_bg.sc.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD2;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos         = vec4(input.a_position.xy, 1.0, 1.0);
	output.v_texcoord0 = input.a_position.xy;
	return output;
}
