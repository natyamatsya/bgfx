// Slang port of examples/53-sky2/vs_sky2.sc.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
	vec3 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos      : SV_Position;
	vec3 v_normal : TEXCOORD0;
	vec3 v_wpos   : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec4 wpos  = mul(u_model, vec4(input.a_position, 1.0) );
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	output.v_normal = mul(u_model, vec4(input.a_normal, 0.0) ).xyz;
	output.v_wpos   = wpos.xyz;
	return output;
}
