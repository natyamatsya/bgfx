// 1-to-1 Slang port of examples/15-shadowmaps-simple vs_sms_shadow_pd.sc.
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
};

struct V2F
{
	vec4 pos        : SV_Position;
	vec4 v_position : TEXCOORD2;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	output.v_position = output.pos;
	return output;
}
