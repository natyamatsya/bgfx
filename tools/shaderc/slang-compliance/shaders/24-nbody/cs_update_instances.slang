// 1-to-1 Slang port of examples/24-nbody cs_update_instances.sc.
// The real N-body integration step: each thread advances one particle by summing the
// gravitational acceleration from every other particle, tiled through groupshared memory
// (GROUP_SIZE particles staged per barrier-synchronised pass). Verlet integration then
// produces the new position; the acceleration magnitude is baked into the .w channel as a
// color. calcAcceleration is an inline .sc-body helper, kept inline here. SHARED -> groupshared.
// floatBitsToUint comes from bgfx_shader_glsl_compat to match the stock spelling.
import bgfx_shader;
import bgfx_compute;
import bgfx_shader_glsl_compat;

// uniforms.sh: uniform vec4 u_params[3]; this shader reads through index [2], so the full
// declared extent is active -- no reserved tail padding needed.
float4 u_params[3];

// #define u_timeStep        u_params[0].x
// #define u_dispatchSize    floatBitsToUint(u_params[0].y)
// #define u_gravity         u_params[0].z
// #define u_damping         u_params[0].w
// #define u_maxAcceleration u_params[2].z

// BUFFER_RO(prevPositionBuffer, vec4, 0); BUFFER_RO(currPositionBuffer, vec4, 1)
StructuredBuffer<vec4> prevPositionBuffer : register(t0);
StructuredBuffer<vec4> currPositionBuffer : register(t1);
// BUFFER_WO(outPrevPositionBuffer, vec4, 2); BUFFER_WO(outCurrPositionBuffer, vec4, 3)
RWStructuredBuffer<vec4> outPrevPositionBuffer : register(u2);
RWStructuredBuffer<vec4> outCurrPositionBuffer : register(u3);

#define GROUP_SIZE 512
groupshared vec3 otherEntries[GROUP_SIZE];

vec3 calcAcceleration(vec3 _currPosition, vec3 _otherPosition)
{
	vec3  difference = _otherPosition - _currPosition;
	float dist2 = dot(difference, difference);
	float dist6 = dist2 * dist2 * dist2;
	float invDist3 = 1.0 / (sqrt(dist6) + 0.1);
	float u_gravity = u_params[0].z;
	return u_gravity * u_gravity * invDist3 * difference;
}

[shader("compute")]
[numthreads(GROUP_SIZE, 1, 1)]
void computeMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID, uint gl_LocalInvocationIndex : SV_GroupIndex)
{
	uint u_dispatchSize     = floatBitsToUint(u_params[0].y);
	float u_damping         = u_params[0].w;
	float u_maxAcceleration = u_params[2].z;
	float u_timeStep        = u_params[0].x;

	vec3 prevPosition = prevPositionBuffer[gl_GlobalInvocationID.x].xyz;
	vec3 currPosition = currPositionBuffer[gl_GlobalInvocationID.x].xyz;

	vec3 newAcceleration = vec3_splat(0.0);

	for (int j = 0; j < int(u_dispatchSize); ++j)
	{
		otherEntries[gl_LocalInvocationIndex] = currPositionBuffer[j * GROUP_SIZE + int(gl_LocalInvocationIndex)].xyz;

		barrier();
		for (int i = 0; i < GROUP_SIZE; ++i)
		{
			newAcceleration += calcAcceleration(currPosition, otherEntries[i]);
		}
	}

	newAcceleration += (prevPosition - currPosition) * u_damping;
	float accelerationMagnitude = length(newAcceleration);
	float color = pow(min(accelerationMagnitude / 3.0, 1.0), 0.25);
	if (accelerationMagnitude > 0.0)
	{
		newAcceleration = normalize(newAcceleration) * min(accelerationMagnitude, u_maxAcceleration);
	}

	vec3 newPosition = 2.0 * currPosition - prevPosition + newAcceleration * u_timeStep;

	outPrevPositionBuffer[gl_GlobalInvocationID.x] = vec4(currPosition, 0.0);
	outCurrPositionBuffer[gl_GlobalInvocationID.x] = vec4(newPosition, color);
}
