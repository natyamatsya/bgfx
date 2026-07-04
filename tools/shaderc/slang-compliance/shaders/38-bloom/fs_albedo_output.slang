// 1-to-1 Slang port of examples/38-bloom fs_albedo_output.sc.
// MRT: gl_FragData[0]/[1] -> a struct of SV_Target0/SV_Target1.
import bgfx_shader;

vec4 u_color;

struct V2F
{
	vec3 v_wpos      : TEXCOORD1;
	vec3 v_view      : TEXCOORD2;
	vec3 v_normal    : NORMAL;
	vec3 v_tangent   : TANGENT;
	vec3 v_bitangent : BINORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
};

struct FragData
{
	vec4 target0 : SV_Target0;
	vec4 target1 : SV_Target1;
};

[shader("fragment")]
FragData fragmentMain(V2F input)
{
	FragData output;

	// the albedo-buffer of the g-buffer.
	output.target0 = u_color;

	// for convenience, we also output the same color, to the first texture of the texture chain used for bloom.
	// this color will now be bloomed, in the following passes.
	output.target1 = u_color;
	return output;
}
