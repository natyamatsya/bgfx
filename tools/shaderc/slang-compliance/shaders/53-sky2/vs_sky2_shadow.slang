// Slang port of examples/53-sky2/vs_sky2_shadow.sc.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
import bgfx_shader;

mat4 u_lightViewProj;
mat4 u_lightMtx;

struct VSInput
{
	vec3 a_position : POSITION;
};

struct V2F
{
	vec4 pos           : SV_Position;
	vec4 v_shadowcoord : TEXCOORD3;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec4 wpos = mul(u_model, vec4(input.a_position, 1.0) );

	output.pos           = mul(u_lightViewProj, wpos);
	output.v_shadowcoord = mul(u_lightMtx, wpos);
	return output;
}
