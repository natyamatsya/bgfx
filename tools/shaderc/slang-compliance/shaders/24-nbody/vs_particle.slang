// 1-to-1 Slang port of examples/24-nbody vs_particle.sc.
// Billboards each simulated particle (i_data0 = per-instance position, w = color factor)
// into a view-facing quad. Per-stage port (not combined with fs_particle): the VS pulls in
// the predefined u_view/u_proj matrices, which would leak into the FS envelope. u_view/u_proj
// are predefined uniforms -- never declared, used directly.
import bgfx_shader;

// uniforms.sh: uniform vec4 u_params[3]; this stage reads only u_params[1], and glslang
// reflects the active extent [2] while reserving the declared [3] in $Globals -- the reserved
// tail (1*vec4 = 16 bytes) is reproduced by an unused pad member so the UBO size stays 48.
struct ParamsTailPad { vec4 _unused[1]; };
float4 u_params[2];
ParamsTailPad _paramsTailPad;

// #define u_particleSize u_params[1].y

struct VSInput
{
	vec2 a_position : POSITION;
	vec4 i_data0    : TEXCOORD7;
};

struct V2F
{
	vec4 pos        : SV_Position;
	vec3 v_texCoord : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	vec3  eye = mul(u_view, vec4(input.i_data0.xyz, 1.0) ).xyz;
	vec3  up = normalize(cross(eye, vec3(1.0, 0.0, 0.0) ) );
	vec3  right = normalize(cross(up, eye));
	float size = u_params[1].y;
	vec3  position = eye + size * right * input.a_position.x + size * up * input.a_position.y;

	V2F output;
	output.v_texCoord.xy = input.a_position;
	output.v_texCoord.z = input.i_data0.w;
	output.pos = mul(u_proj, vec4(position, 1.0) );
	return output;
}
