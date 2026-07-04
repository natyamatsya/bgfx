// Slang port of examples/52-layered/vs_layered_eye.sc (the non-layered path:
// the eye is selected by a uniform and rendered into a single array layer).
import bgfx_shader; // u_modelViewProj is auto-provided.

float4 u_eyeParams; // x = eye separation, y = eye index

struct VSInput
{
	vec3 a_position : POSITION;
	vec4 a_color0   : COLOR0;
};

struct V2F
{
	vec4  pos      : SV_Position;
	vec4  v_color0 : COLOR0;
	float v_eye    : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	float eyeIndex = u_eyeParams.y;

	vec4 pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	pos.x += (eyeIndex * 2.0 - 1.0) * u_eyeParams.x * pos.w;
	output.pos = pos;

	output.v_color0 = input.a_color0;
	output.v_eye    = eyeIndex;
	return output;
}
