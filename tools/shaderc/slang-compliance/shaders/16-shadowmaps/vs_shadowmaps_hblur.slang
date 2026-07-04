// 1-to-1 Slang port of examples/16-shadowmaps/vs_shadowmaps_hblur.sc
import bgfx_shader;

// u_viewTexel is a predefined uniform (auto-provided); u_smSamplingParams is user.
float4 u_smSamplingParams;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
	vec4 v_texcoord3 : TEXCOORD3;
	vec4 v_texcoord4 : TEXCOORD4;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	float offset = u_viewTexel.x*u_smSamplingParams.z;

	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	output.v_texcoord0 = input.a_texcoord0;
	output.v_texcoord1 = vec4(input.a_texcoord0.x - offset*1.0, input.a_texcoord0.y,
					   input.a_texcoord0.x + offset*1.0, input.a_texcoord0.y
					  );
	output.v_texcoord2 = vec4(input.a_texcoord0.x - offset*2.0, input.a_texcoord0.y,
					   input.a_texcoord0.x + offset*2.0, input.a_texcoord0.y
					  );
	output.v_texcoord3 = vec4(input.a_texcoord0.x - offset*3.0, input.a_texcoord0.y,
					   input.a_texcoord0.x + offset*3.0, input.a_texcoord0.y
					  );
	output.v_texcoord4 = vec4(input.a_texcoord0.x - offset*4.0, input.a_texcoord0.y,
					   input.a_texcoord0.x + offset*4.0, input.a_texcoord0.y
					  );
	return output;
}
