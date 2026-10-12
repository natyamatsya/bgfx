// Slang port of examples/53-sky2/fs_sky2_shadow.sc.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
import bgfx_shader;

struct V2F
{
	vec4 pos           : SV_Position;
	vec4 v_shadowcoord : TEXCOORD3;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return vec4(input.v_shadowcoord.z / input.v_shadowcoord.w, 0.0, 0.0, 1.0);
}
