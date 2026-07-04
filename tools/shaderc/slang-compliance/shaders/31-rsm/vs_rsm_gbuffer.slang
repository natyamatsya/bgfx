// 1-to-1 Slang port of examples/31-rsm vs_rsm_gbuffer.sc.
// G-buffer geometry pass: transforms position and writes a compressed world-space
// normal into a varying. u_modelViewProj / u_model are auto-provided.
// (The stock .sc declares `uniform vec4 u_tint;` but never uses it in the VS, so
// glslang strips it from the reflection envelope; we drop it here to match.)
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
	vec3 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos      : SV_Position;
	vec3 v_normal : NORMAL;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	// Calculate vertex position
	vec3 pos = input.a_position;
	output.pos = mul(u_modelViewProj, vec4(pos, 1.0) );

	// Calculate normal.  Note that compressed normal is stored in the vertices
	vec3 normalObjectSpace = input.a_normal.xyz*2.0+-1.0; // Normal is stored in [0,1], remap to [-1,1].

	// Transform normal into world space.
	vec3 normalWorldSpace = mul(u_model, vec4(normalObjectSpace, 0.0) ).xyz;
	// Normalize to remove (uniform...) scaling, however, recompress
	output.v_normal.xyz = normalize(normalWorldSpace)*0.5+0.5;

	return output;
}
