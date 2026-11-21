#ifdef RENDER_SHADOW
	#if defined BEACON_FLOODFILL && defined IS_LPV_ENABLED
		layout(r32ui) uniform uimage3D imgVoxelMask;
	#else
		layout(r16ui) uniform uimage3D imgVoxelMask;
	#endif
	// layout(r8ui) uniform uimage3D imgQuarterVoxelMask;
// 
	// layout(std430, binding = 5) buffer voxelSSBO {
	// 	vec4[6] voxelData[];
	// };  
#else
	#if defined BEACON_FLOODFILL && defined IS_LPV_ENABLED
		layout(r32ui) uniform readonly uimage3D imgVoxelMask;
	#else
		layout(r16ui) uniform readonly uimage3D imgVoxelMask;
	#endif
	// layout(r8ui) uniform readonly uimage3D imgQuarterVoxelMask;
// 
	// layout(std430, binding = 5) readonly buffer voxelSSBO {
	// 	vec4[6] voxelData[];
	// };  
#endif

#if defined IS_LPV_ENABLED || defined SHADER_GRASS
	const uint VoxelSize = uint(exp2(LPV_SIZE));
	const uvec3 VoxelSize3 = uvec3(VoxelSize);
	const ivec3 VoxelCenter = ivec3(VoxelSize / 2u);
	const float VoxelShiftF = LPV_FRUSTUM_OFFSET * 0.01;

	ivec3 GetVoxelCenter(const in vec3 viewDir) {
		vec3 offset = viewDir * (float(VoxelSize) * VoxelShiftF);
		return VoxelCenter + ivec3(floor(offset));
	}
#else
	const uint VoxelSize = uint(5);
	const uvec3 VoxelSize3 = uvec3(VoxelSize);
	const ivec3 VoxelCenter = ivec3(VoxelSize / 2u);

	ivec3 GetVoxelCenter(const in vec3 viewDir) {
		return VoxelCenter;
	}
#endif

bool InVoxelBounds(const in ivec3 voxelPos) {
	const ivec3 voxelMin = ivec3(0);
	const ivec3 voxelMax = ivec3(VoxelSize - 1u);
	return clamp(voxelPos, voxelMin, voxelMax) == voxelPos;
}

#define BLOCK_EMPTY 0
#define BLOCK_DEFAULT 1
