// Slang port of examples/52-layered/fs_layered.sc. Tints each eye/layer so the
// two array layers are visibly distinct (left red, right blue).
import bgfx_shader;

struct V2F
{
	vec4  pos      : SV_Position;
	vec4  v_color0 : COLOR0;
	float v_eye    : TEXCOORD1;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	vec3 tint = lerp(vec3(1.0, 0.15, 0.15), vec3(0.15, 0.4, 1.0), input.v_eye);
	return vec4(input.v_color0.xyz * tint, 1.0);
}
