#define RENDER_SHADOWCOMP

layout (local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

#if   LPV_SIZE == 8
    const ivec3 workGroups = ivec3(32, 32, 32);
#elif LPV_SIZE == 7
    const ivec3 workGroups = ivec3(16, 16, 16);
#elif LPV_SIZE == 6
    const ivec3 workGroups = ivec3(8, 8, 8);
#endif

#ifdef IS_LPV_ENABLED
    shared vec4 lpvSharedData[10*10*10];
    shared uint voxelSharedData[10*10*10];

    const float LpvBlockFalloff = 0.96;
    const ivec3 lpvFlatten = ivec3(1, 10, 100);

    uniform int frameCounter;
    uniform vec3 cameraPosition;
    uniform vec3 previousCameraPosition;
    uniform mat4 gbufferModelViewInverse;
    uniform mat4 gbufferPreviousModelView;

    #include "/lib/hsv.glsl"
    #include "/lib/util.glsl"
    #include "/lib/blocks.glsl"
    #include "/lib/entities.glsl"
    #include "/lib/lpv_common.glsl"
    #include "/lib/lpv_blocks.glsl"
    #include "/lib/lpv_buffer.glsl"
    #include "/lib/voxel_common.glsl"

    int sumOf(ivec3 vec) {return vec.x + vec.y + vec.z;}

    int getSharedIndex(ivec3 pos) {
        return sumOf(pos * lpvFlatten);
    }

    ivec3 GetVoxelFrameOffset() {
        vec3 cameraViewDir = gbufferModelViewInverse[2].xyz;
        vec3 previousCameraViewDir = vec3(gbufferPreviousModelView[0].z, gbufferPreviousModelView[1].z, gbufferPreviousModelView[2].z);
        return (GetVoxelCenter(previousCameraViewDir) - GetVoxelCenter(cameraViewDir)) + ivec3(floor(cameraPosition) - floor(previousCameraPosition));
    }

    vec4 GetLpvValue(in ivec3 texCoord) {
        if (!InVoxelBounds(texCoord)) return vec4(0.0);

        vec4 lpvSample = (frameCounter % 2) == 0
            ? imageLoad(imgLpv2, texCoord)
            : imageLoad(imgLpv1, texCoord);

        vec3 hsv = RgbToHsv(lpvSample.rgb);
        hsv.z = exp2(hsv.z * LpvBlockRange) - 1.0;
        lpvSample.rgb = HsvToRgb(hsv);

        return lpvSample;
    }
    
    uint GetVoxelBlock(const in ivec3 voxelPos) {
        if (!InVoxelBounds(voxelPos))
            return BLOCK_EMPTY;

        uint blockId = imageLoad(imgVoxelMask, voxelPos).r;

        #ifdef BEACON_FLOODFILL
            if(blockId >= 50000u) return blockId;
        #endif

        blockId = blockId % 2000u;

        #if IRIS_VERSION < 11004
            if (blockId == ENTITY_BOAT || blockId == ENTITY_SMALLSHIPS) return BLOCK_EMPTY;
        #endif
                
        return blockId;
    }

    void PopulateSharedIndex(const in ivec3 imgCoordOffset, const in ivec3 workGroupOffset, const in uint i) {
        ivec3 pos = workGroupOffset + ivec3(i / lpvFlatten) % 10;

        lpvSharedData[i] = GetLpvValue(imgCoordOffset + pos);
        voxelSharedData[i] = GetVoxelBlock(pos);
    }

    vec3 sampleShared(ivec3 pos, int mask_index) {
        int shared_index = getSharedIndex(pos + 1);

        uint mask = 0xFFFFu;
        uint blockId = voxelSharedData[shared_index];
        
        if (blockId > 0u && blockId < 2048u) {
            uvec2 blockData = imageLoad(imgBlockData, int(blockId)).rg;
            mask = (blockData.g >> 24u) & 0xFFFFu;
        }

        return lpvSharedData[shared_index].rgb * ((mask >> mask_index) & 1u);
    }

    vec3 mixNeighbours(const in ivec3 fragCoord, const in uint mask) {
        uvec3 m1 = (uvec3(mask) >> uvec3(0, 2, 4)) & uvec3(1u);
        uvec3 m2 = (uvec3(mask) >> uvec3(1, 3, 5)) & uvec3(1u);

        vec3 sX1 = sampleShared(fragCoord + ivec3(-1,  0,  0), 1) * m1.x;
        vec3 sX2 = sampleShared(fragCoord + ivec3( 1,  0,  0), 0) * m2.x;
        vec3 sY1 = sampleShared(fragCoord + ivec3( 0, -1,  0), 3) * m1.y;
        vec3 sY2 = sampleShared(fragCoord + ivec3( 0,  1,  0), 2) * m2.y;
        vec3 sZ1 = sampleShared(fragCoord + ivec3( 0,  0, -1), 5) * m1.z;
        vec3 sZ2 = sampleShared(fragCoord + ivec3( 0,  0,  1), 4) * m2.z;

        const float avgFalloff = (1.0/6.0) * LpvBlockFalloff;
        return (sX1 + sX2 + sY1 + sY2 + sZ1 + sZ2) * avgFalloff;
    }
#endif

vec3 UnpackColor(uint packedC) {
    int idx = int(packedC) - 50000;

    int b = idx % 101;
    idx /= 101;
    int g = idx % 101;
    idx /= 101;
    int r = idx % 101;

    return vec3(r / 100.0, g / 100.0, b / 100.0);
}

////////////////////////////// VOID MAIN //////////////////////////////

void main() {
    #ifdef IS_LPV_ENABLED
        uvec3 chunkPos = gl_WorkGroupID * gl_WorkGroupSize;
        if (any(greaterThanEqual(chunkPos, LpvSize3))) return;

        // Pre-populate shared-memory buffer for improved sampling performance
        uint i = uint(gl_LocalInvocationIndex) * 2u;
        if (i < 1000u) {
            ivec3 imgCoordOffset = GetVoxelFrameOffset();
            ivec3 workGroupOffset = ivec3(gl_WorkGroupID * gl_WorkGroupSize) - 1;

            PopulateSharedIndex(imgCoordOffset, workGroupOffset, i);
            PopulateSharedIndex(imgCoordOffset, workGroupOffset, i + 1u);
        }

        memoryBarrierShared();
        barrier();

        // Exit early if outside LPV buffer size
        ivec3 imgCoord = ivec3(gl_GlobalInvocationID);
        if (any(greaterThanEqual(imgCoord, LpvSize3))) return;

        vec4 lightValue = vec4(0.0);
        vec3 lightColor = vec3(0.0);
        vec3 tintColor = vec3(1.0);
        float lightRange = 0.0;
        uint mixMask = 0xFFFFu;
    
        // Decode light data for current voxel
        uint blockId = voxelSharedData[getSharedIndex(ivec3(gl_LocalInvocationID) + 1)];

        if (blockId > 0u && blockId < 2048u) {
            uvec2 blockData = imageLoad(imgBlockData, int(blockId)).rg;
            vec4 lightColorRange = unpackUnorm4x8(blockData.r);
            lightColor = srgbToLinear(lightColorRange.rgb);
            lightRange = lightColorRange.a * 255.0;
            vec4 tintColorMask = unpackUnorm4x8(blockData.g);
            tintColor = srgbToLinear(tintColorMask.rgb);
            mixMask = (blockData.g >> 24u) & 0xFFFFu;
        }
        #ifdef BEACON_FLOODFILL
        else if(blockId >= 50000u) {
            lightColor = BEACON_FLOODFILL_BRIGHTNESS * 17.0 * srgbToLinear(UnpackColor(blockId));

            lightRange = 0.0425 * 255.0;
            tintColor = vec3(1.0);
            mixMask = 0xFFFFu;
        }
        #endif

        // Mix neighbor voxel light values
        if (any(greaterThan(tintColor, vec3(0.0)))) {
            vec3 lightMixed = mixNeighbours(ivec3(gl_LocalInvocationID), mixMask);
            lightMixed *= tintColor;
            lightValue.rgb += lightMixed;
        }

        // Add light for current voxel
        if (lightRange > 0.0) {
            vec3 hsv = RgbToHsv(lightColor);
            #ifdef BEACON_FLOODFILL
            if(blockId < 50000u)
            #endif
            {
                hsv.z = exp2(lightRange) - 1.0;
            }
            lightValue.rgb += HsvToRgb(hsv);
        }

        // Propagate roof/glass rain cover mask downward in alpha channel
        int up_index = getSharedIndex(ivec3(gl_LocalInvocationID) + ivec3(1, 2, 1));
        lightValue.a = lpvSharedData[up_index].a;
        if ((blockId >= BLOCK_GLASS && blockId <= BLOCK_GLASS_YELLOW) || blockId == BLOCK_HONEY || blockId == BLOCK_SLIME || (mixMask & 12u) != 12u || all(lessThanEqual(tintColor, vec3(0.0)))) {
            lightValue.a = 1.0;
        }

        // Convert back to linear RGB space
        vec3 hsv = RgbToHsv(lightValue.rgb);
        hsv.z = log2(hsv.z + 1.0) / LpvBlockRange;
        lightValue.rgb = HsvToRgb(hsv);

        // Store final value
        if (frameCounter % 2 == 0)
            imageStore(imgLpv1, imgCoord, lightValue);
        else
            imageStore(imgLpv2, imgCoord, lightValue);
    #endif
}
