Shader "Hidden/Custom/DownSampleBloom"
{
		SubShader
		{
			Tags{"RenderPipeline" = "LightweightPipeline" }
			//LOD 300

			HLSLINCLUDE
			#include "Packages/com.unity.postprocessing/PostProcessing/Shaders/StdLib.hlsl"

			CBUFFER_START(UnityPerMaterial)
			float4 _MainTex_ST;
			half4 _MainTex_TexelSize;
			
			half4 _Filter;
			half _Intensity;
			half _Cutoff; //深度获取与自阴影AlphaTest裁剪相关必要不可删除
			CBUFFER_END

			TEXTURE2D_SAMPLER2D(_MainTex, sampler_MainTex);
			TEXTURE2D_SAMPLER2D(_Bloom, sampler_Bloom);
			TEXTURE2D_SAMPLER2D(_Mask, sampler_Mask);
			
			half3 Sample(float2 uv) {
				return  SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;
			}

			half3 SampleBox(float2 uv, float delta) {
				float4 o = _MainTex_TexelSize.xyxy*float2(-delta, delta).xxyy;
				half3 s = Sample(uv + o.xy) + Sample(uv + o.zy) + Sample(uv + o.xw) + Sample(uv + o.zw);
				return s * 0.25f;
			}
			half3 Prefilter(half3 c) {
				half brightness = max(c.r, max(c.g, c.b));
				half soft = brightness - _Filter.y;
				soft = clamp(soft, 0, _Filter.z);
				soft = soft * soft*_Filter.w;
				half contribution = max(soft, brightness - _Filter.x);
				contribution /= max(brightness, 0.00001);
				return c * contribution;

			}

			half4 PreMask(VaryingsDefault input) : SV_Target
			{	
				half4 mask = SAMPLE_TEXTURE2D(_Mask, sampler_Mask, input.texcoord);
				
				return half4(Sample(input.texcoord)*mask.a, 1);

			}
			half4 LWBaseFragment(VaryingsDefault input) : SV_Target
			{	
				return half4(Prefilter(SampleBox(input.texcoord, 1)), 1) ;
						
			}
			half4 DownSampling(VaryingsDefault input) : SV_Target
			{
						return half4(SampleBox(input.texcoord, 1), 1);
			
			}
			half4 UpSampling(VaryingsDefault input) : SV_Target
			{
						return half4(SampleBox(input.texcoord, 0.5), 1);
			
			}
			half4 fragAdd(VaryingsDefault input) : SV_Target
			{	
						half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.texcoord);
						half4 bloom = SAMPLE_TEXTURE2D(_Bloom, sampler_Bloom, input.texcoord);
						col.rgb += _Intensity * bloom.rgb;
						return col;

			}
				
					

					ENDHLSL
					Pass //3个分开的pass吗？分别是阴影 光照 深度 可以不用都写吗
					{
						ZTest Always
						ZWrite Off
						Cull Off //参数来自于？？ Properties

						HLSLPROGRAM

						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0


						#pragma vertex VertDefault
						#pragma fragment PreMask

						ENDHLSL
					}
					Pass //3个分开的pass吗？分别是阴影 光照 深度 可以不用都写吗
					{
						ZTest Always
						ZWrite Off
						Cull Off //参数来自于？？ Properties

						HLSLPROGRAM

						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0


						#pragma vertex VertDefault
						#pragma fragment LWBaseFragment

						ENDHLSL
					}
					Pass 
					{
				
						ZTest Always
						ZWrite Off
						Cull Off //参数来自于？？ Properties

						HLSLPROGRAM

						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0

						
						#pragma vertex VertDefault
						#pragma fragment DownSampling

						ENDHLSL
					}

					Pass
					{
							Blend One One
							ZTest Always
							ZWrite Off
							Cull Off //参数来自于？？ Properties

							HLSLPROGRAM

							#pragma prefer_hlslcc gles
							#pragma exclude_renderers d3d11_9x
							#pragma target 2.0


							#pragma vertex VertDefault
							#pragma fragment UpSampling

							ENDHLSL
					}
					Pass
					{
						
						ZTest Always
						ZWrite Off
						Cull Off //参数来自于？？ Properties

						HLSLPROGRAM

						#pragma prefer_hlslcc gles
						#pragma exclude_renderers d3d11_9x
						#pragma target 2.0


						#pragma vertex VertDefault
						#pragma fragment fragAdd

						ENDHLSL
					}
						

					
		}
			FallBack "Hidden/InternalErrorShader"
}