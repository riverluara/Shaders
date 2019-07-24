Shader "TFW/UnLitShadowTransparent" {
	Properties
	{

		_BaseColor("Main Color", Color) = (1,1,1,1)
		_BaseMap("Base (RGB)", 2D) = "white" {}
		//[HDR]
		_MaskColor("MaskColor", Color) = (1,1,1,0)
		_MaskColorAdd("MaskColorAdd", Range(1, 2)) = 1
		[Space(20)]

		_ShadowColor("Shadow Color", Color) = (0,0,0,0.5)

		[Space(20)]
		_FlowMap("FlowMap", 2D) = "bump" {}
		_FlowSpeed("FlowSpeed", float) = 0.1
		_FlowPower("FlowPower", float) = 0.1

		//[Space(20)]

		//[Enum(Off, 0, On, 1)] _ZWrite("ZWrite", Float) = 0

		[Space(20)]

		[KeywordEnum(OFF, ON)] _RECEIVE_SHADOWS("ReceiveShadows", float) = 1
		
		// Blending state
		[HideInInspector]_Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5 //深度获取与自阴影AlphaTest裁剪相关必要不可删除
		[HideInInspector] _Cull("__cull", Float) = 2.0
		[HideInInspector] _ReceiveShadows("Receive Shadows", Float) = 1.0
	}

		SubShader
		{
			Tags{"RenderType" = "Opaque" "RenderPipeline" = "LightweightPipeline"  "Queue" = "Geometry"}
			LOD 100

			HLSLINCLUDE
			#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Core.hlsl"
			//光照相关 无光照禁用
			#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Lighting.hlsl"

			CBUFFER_START(UnityPerMaterial)
			float4 _BaseMap_ST;
			half4 _BaseColor;
			half4 _ShadowColor;
			half _Cutoff; //深度获取与自阴影AlphaTest裁剪相关必要不可删除
			float4 _MaskColor;
			half _MaskColorAdd;
			float4 _FlowMap_ST;
			float _FlowPower;
			float _FlowSpeed;
			CBUFFER_END

			TEXTURE2D(_BaseMap);  SAMPLER(sampler_BaseMap);
			TEXTURE2D(_FlowMap);  SAMPLER(sampler_FlowMap);
	
			struct LWAttributes
			{
				float4 positionOS   : POSITION;
				float3 normalOS     : NORMAL;
				float4 tangentOS    : TANGENT;
				float2 texcoord     : TEXCOORD0;
			};

			struct LWVaryings
			{
				float2 uv                       : TEXCOORD0;
				float4 positionCS               : SV_POSITION;
				float3 positionWS               : TEXCOORD1;

				#ifdef _MAIN_LIGHT_SHADOWS
					float4 shadowCoord              : TEXCOORD2; //阴影
				#endif
			};

			LWVaryings LWBaseVertex(LWAttributes input)
			{
				LWVaryings output = (LWVaryings)0;

				//获取位置相关信息
				VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz); //VertexPositionInputs 是自带的吗
				output.positionCS = vertexInput.positionCS;

				output.positionWS = vertexInput.positionWS;//WS worldspace OS objectspace CS clipspace

				output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);

				#if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
					output.shadowCoord = GetShadowCoord(vertexInput);
				#endif
					return output;
				}

				float3 FlowUVW  (float2 uv, float2 flowVector, float time, bool flowB) {
					float phaseOffset = flowB ? 0.5 : 0;
					float progress = frac(time + phaseOffset);
					float3 uvw;
					uvw.xy = uv - flowVector * progress;
					uvw.z =  1 - abs(1 - 2 * progress);
					return uvw;
				}


				half4 LWBaseFragment(LWVaryings input) : SV_Target
				{

					//获取主光源阴影
					#if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
						float4 shadowCoord = input.shadowCoord;
						//获取主光源
						Light mainLight = GetMainLight(shadowCoord); //使用Light要include light的library吗
					#else
						//获取主光源
						Light mainLight = GetMainLight();
					#endif

						float4 FlowMap = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, input.uv);
						float2 flowVector = FlowMap.rg * 2 - 1;
						flowVector *= _FlowPower;

						float tmie = _Time.y * _FlowSpeed;
					/*	float3 FlowUVW(float2 uv, float2 flowVector, float time, bool flowB) {
							float phaseOffset = flowB ? 0.5 : 0;
							float progress = frac(time + phaseOffset);
							float3 uvw;
							uvw.xy = uv - flowVector * progress;
							uvw.z = 1 - abs(1 - 2 * progress);
							return uvw;
						}*/
						float3 uvwA = FlowUVW(input.uv, flowVector, tmie, false);
						float3 uvwB = FlowUVW(input.uv, flowVector, tmie, true);

						float4 texA = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvwA.xy) * uvwA.z;
						float4 texB = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvwB.xy) * uvwB.z;

						float4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
					
						half4 col = 1;
						col = lerp(baseTex, texA + texB, FlowMap.b);
						col.a = baseTex.a;

						col.rgb *= _BaseColor.rgb;

						col.rgb = lerp(col.rgb, _MaskColor.rgb * _MaskColorAdd, col.a * _MaskColor.a);

						half4 sc = _ShadowColor * _ShadowColor.a + (1 - _ShadowColor.a) * col;
						col = lerp(sc, col, mainLight.shadowAttenuation);
						col.rgb *= mainLight.color;

						return col;
					}


					half4 LWBaseFragmentMask(LWVaryings input) : SV_Target
					{
						return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a;
					}

					//从SurfaceInput.hlsl 提取为了支持深度以及阴影投射
					half Alpha(half albedoAlpha, half4 color, half cutoff)
					{
					#if !defined(_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A) && !defined(_GLOSSINESS_FROM_BASE_ALPHA) //？
						half alpha = albedoAlpha * color.a;
					#else
						half alpha = color.a;
					#endif

					#if defined(_ALPHATEST_ON)
						clip(alpha - cutoff);
					#endif

						return alpha;
					}

					half4 SampleAlbedoAlpha(float2 uv, TEXTURE2D_PARAM(albedoAlphaMap, sampler_albedoAlphaMap))
					{
						return SAMPLE_TEXTURE2D(albedoAlphaMap, sampler_albedoAlphaMap, uv);
					}

					ENDHLSL

					Pass 
					{

						Name "ForwardLit"   
						Tags{"LightMode" = "LightweightForward" "RenderType"="Transparent"}

						Blend SrcAlpha OneMinusSrcAlpha 
						//ZWrite[_ZWrite]
					

						HLSLPROGRAM

						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0

						// -------------------------------------
						// Material Keywords
						#pragma shader_feature _RECEIVE_SHADOWS_OFF

						// -------------------------------------
						// Lightweight Pipeline keywords
						#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
						#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
						#pragma multi_compile _ _SHADOWS_SOFT
						#pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

						//--------------------------------------
						// GPU Instancing
						#pragma multi_compile_instancing

						#pragma vertex LWBaseVertex
						#pragma fragment LWBaseFragment

						ENDHLSL
					}

					Pass
					{
						//阴影投射不需要可删除
						Name "ShadowCaster"
						Tags{"LightMode" = "ShadowCaster"}

						ZWrite On
						ZTest LEqual
						Cull[_Cull]

						HLSLPROGRAM

						// Required to compile gles 2.0 with standard srp library
						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0

						// -------------------------------------
						// Material Keywords
						#pragma shader_feature _ALPHATEST_ON

						//--------------------------------------
						// GPU Instancing
						#pragma multi_compile_instancing
						#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

						#pragma vertex ShadowPassVertex
						#pragma fragment ShadowPassFragment

						//#include "LitInput.hlsl"
						#include "Packages/com.unity.render-pipelines.lightweight/Shaders/ShadowCasterPass.hlsl"
						ENDHLSL
					}

					Pass
					{
						//深度获取不可删除会影响排序
						Name "DepthOnly"
						Tags{"LightMode" = "DepthOnly"}

						ZWrite On
						ColorMask 0
						Cull[_Cull]

						HLSLPROGRAM
						// Required to compile gles 2.0 with standard srp library
						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0

						#pragma vertex DepthOnlyVertex
						#pragma fragment DepthOnlyFragment

						// -------------------------------------
						// Material Keywords
						#pragma shader_feature _ALPHATEST_ON
						#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

						#include "Packages/com.unity.render-pipelines.lightweight/Shaders/DepthOnlyPass.hlsl"
						ENDHLSL
					}

					Pass 
					{

						Name "ForwardLit"   
						Tags{"LightMode" = "GetMask"}

						//Blend SrcAlpha OneMinusSrcAlpha //写法有区别
						//ZWrite[_ZWrite]
					

						HLSLPROGRAM

						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0

						// -------------------------------------
						// Material Keywords
						#pragma shader_feature _RECEIVE_SHADOWS_OFF

						// -------------------------------------
						// Lightweight Pipeline keywords
						#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
						#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
						#pragma multi_compile _ _SHADOWS_SOFT
						#pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

						//--------------------------------------
						// GPU Instancing
						#pragma multi_compile_instancing

						#pragma vertex LWBaseVertex
						#pragma fragment LWBaseFragmentMask

						ENDHLSL
					}

		}
			FallBack "Hidden/InternalErrorShader"
}
