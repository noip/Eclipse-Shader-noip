// How far light propagates (block)
const float LpvBlockRange = 15.0;
const vec2 LpvBlockSkyRange = vec2(15.0, 24.0);

#if defined IS_LPV_ENABLED || defined SHADER_GRASS
	const uint LpvSize = uint(exp2(LPV_SIZE));
	const uvec3 LpvSize3 = uvec3(LpvSize);
	const ivec3 LpvCenter = ivec3(LpvSize / 2u);
	const float LpvShiftF = LPV_FRUSTUM_OFFSET * 0.01;

	ivec3 GetLpvCenter(const in vec3 viewDir) {
		vec3 offset = viewDir * (float(LpvSize) * LpvShiftF);
		return LpvCenter + ivec3(floor(offset));
	}
#else
	const uint LpvSize = uint(5);
	const uvec3 LpvSize3 = uvec3(LpvSize);
	const ivec3 LpvCenter = ivec3(LpvSize / 2u);

	ivec3 GetLpvCenter(const in vec3 viewDir) {
		return LpvCenter;
	}
#endif

vec3 GetLpvPosition(const in vec3 playerPos) {
    vec3 cameraOffset = cameraPosition - floor(previousCameraPosition);
    vec3 prevViewDir = vec3(gbufferPreviousModelView[0].z, gbufferPreviousModelView[1].z, gbufferPreviousModelView[2].z);
    return playerPos + cameraOffset + vec3(GetLpvCenter(prevViewDir));
}

vec3 GetLpvPosition2(const in vec3 playerPos) {
    #if !defined IS_LPV_ENABLED && !defined SHADER_GRASS
	    vec3 cameraOffset = fract(cameraPosition-relativeEyePosition);
    #else
        vec3 cameraOffset = fract(cameraPosition);
    #endif
    vec3 viewDir = gbufferModelViewInverse[2].xyz;
    return playerPos + cameraOffset + vec3(GetLpvCenter(viewDir));
}
