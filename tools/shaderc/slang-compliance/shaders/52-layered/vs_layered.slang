// Slang port of examples/52-layered/vs_layered.sc (the layered path).
// One instance per array layer: gl_InstanceID -> SV_InstanceID selects the eye,
// gl_Layer -> SV_RenderTargetArrayIndex routes each instance to its own layer.
// The stock's ESSL/WGSL single-layer fallback is irrelevant here (those targets
// never advertise BGFX_CAPS_VIEWPORT_LAYER_ARRAY); we port the layered branch.
import bgfx_shader; // vec/mat aliases, mul; u_modelViewProj is auto-provided.

float4 u_eyeParams; // x = eye separation

struct VSInput
{
	vec3 a_position    : POSITION;
	vec4 a_color0      : COLOR0;
	uint gl_InstanceID : SV_InstanceID;
};

struct V2F
{
	vec4  pos      : SV_Position;
	uint  gl_Layer : SV_RenderTargetArrayIndex;
	vec4  v_color0 : COLOR0;
	float v_eye    : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	float eyeIndex = float(input.gl_InstanceID);
	output.gl_Layer = input.gl_InstanceID;

	vec4 pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	pos.x += (eyeIndex * 2.0 - 1.0) * u_eyeParams.x * pos.w;
	output.pos = pos;

	output.v_color0 = input.a_color0;
	output.v_eye    = eyeIndex;
	return output;
}
