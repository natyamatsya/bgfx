// 1-to-1 Slang port of examples/19-oit fs_oit_wb.sc.
// Weighted-blended OIT: writes two render targets via a SV_Target0/SV_Target1 struct.
import bgfx_shader;

float4 u_color;

struct V2F
{
	vec4 v_pos : TEXCOORD4;
};

struct FragData
{
	vec4 target0 : SV_Target0;
	vec4 target1 : SV_Target1;
};

[shader("fragment")]
FragData fragmentMain(V2F input)
{
	vec4 color = u_color;

	float depth = input.v_pos.z/input.v_pos.w;

	color.xyz *= color.w;
	float weight = color.w * clamp(0.03 / (1e-5 + pow(depth / 200.0, 5.0) ), 0.01, 3000.0);

	FragData output;
	output.target0 = color * weight;
	output.target1 = color.wwww;
	return output;
}
