// 1-to-1 Slang port of examples/15-shadowmaps-simple fs_sms_shadow_pd.sc
// (packed-depth shadow-map generation pass: encode NDC depth into RGBA).
import bgfx_shader;
import shaderlib; // packFloatToRgba

uniform vec4 u_depthScaleOffset;  // for GL, map depth values into [0, 1] range
// #define u_depthScale u_depthScaleOffset.x
// #define u_depthOffset u_depthScaleOffset.y

struct V2F
{
	vec4 v_position : TEXCOORD2;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float depth = input.v_position.z/input.v_position.w * u_depthScaleOffset.x + u_depthScaleOffset.y;
	return packFloatToRgba(depth);
}
