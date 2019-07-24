//�������߳������ݲο�����Shader��Ҫֱ���޸ĸ���������ʹ�� ��֧��LightMap �� GPUʵ��
Shader "Lightweight Render Pipeline/LWStippleTransparency"
{
    Properties
    {

        _BaseColor("Color", Color) = (0.5,0.5,0.5,1)
        _BaseMap("BaseMap", 2D) = "white" {}
		_Alpha("Alpha", Range(0,1)) = 1.0
		 [HideInInspector]_Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5 //��Ȼ�ȡ������ӰAlphaTest�ü���ر�Ҫ����ɾ��

		//_BumpMap("Normal Map", 2D) = "bump" {}

        // Blending state
        [HideInInspector] _Surface("__surface", Float) = 0.0
        [HideInInspector] _Blend("__blend", Float) = 0.0
        [HideInInspector] _AlphaClip("__clip", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _Cull("__cull", Float) = 2.0

        [HideInInspector] _ReceiveShadows("Receive Shadows", Float) = 1.0
    }

    SubShader
    {
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "LightweightPipeline" "IgnoreProjector" = "True" "Queue" = "Geometry"}
        LOD 100
		
		HLSLINCLUDE
		#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Core.hlsl"
		//������� �޹��ս���
		#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Lighting.hlsl"

		CBUFFER_START(UnityPerMaterial)
		float4 _BaseMap_ST;
		half4 _BaseColor;
		half _Alpha;
		half _Cutoff; //��Ȼ�ȡ������ӰAlphaTest�ü���ر�Ҫ����ɾ��
		CBUFFER_END

		TEXTURE2D(_BaseMap);  SAMPLER(sampler_BaseMap);

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
			float4 screenPos				: TEXCOORD1;
			half3 normalWS                  : TEXCOORD2;
			half3 viewDirWS                 : TEXCOORD3;
		};

		LWVaryings LWBaseVertex(LWAttributes input)
		{
			LWVaryings output = (LWVaryings)0;

			//��ȡλ�������Ϣ
			VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz); //VertexPositionInputs ���Դ�����
			output.positionCS = vertexInput.positionCS;
			output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
			output.screenPos = ComputeScreenPos(output.positionCS);//����任���������ϵ�µ�����
			//�����ڱ任������������x��y�����ķ�Χ��[-w, w],
			//o.x = (pos.x * 0.5 + pos.w * 0.5)
			//o.y = (pos.y * 0.5 * _ProjectionParams.x + pos.w * 0.5)
			//ComputeScreenPos���ص�ֵ���������ϵ�µ���Ļ����ֵ���䷶ΧΪ[0, w]
			output.viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;
			VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);//VertexNormalInputs
			output.normalWS = normalInput.normalWS;
			return output;
		}


		half4 LWBaseFragment(LWVaryings input) : SV_Target
		{
			Light mainLight = GetMainLight();
			half dif = saturate(dot(mainLight.direction, input.normalWS ) ) * mainLight.shadowAttenuation * mainLight.distanceAttenuation;

			half4 col = 1;
			col.rgb = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb * dif * mainLight.color;
			
			/*float4x4 thresholdMatrix =
			{
				1.0 / 17.0,      9.0 / 17.0,       3.0 / 17.0,     11.0 / 17.0,

				13.0 / 17.0,      5.0 / 17.0,      15.0 / 17.0,     7.0 / 17.0,

				 4.0 / 17.0,     12.0 / 17.0,       2.0 / 17.0,    10.0 / 17.0,

				16.0 / 17.0,      8.0 / 17.0,       14.0 / 17.0,     6.0 / 17.0
			};*/

			float3x3 thresholdMatrix =
			{
				1.0 / 10.0, 3.0 / 10.0, 4.0 / 10.0,
				7.0 / 10.0, 5.0 / 10.0, 9.0 / 10.0,
				6.0 / 10.0, 8.0 / 10.0, 2.0 / 10.0
			};
			float3x3 _RowAcess = {
				1,0,0,
				0,1,0,
				0,0,1,
			};
			float2 pos = input.screenPos.xy / input.screenPos.w;
			//screenPosX / width = ((x / w) * 0.5 + 0.5)
			//screenPosY / height = ((y / w) * 0.5 + 0.5)
			//תΪ��Ļ����
			pos *= _ScreenParams.xy; 

			clip(_Alpha - thresholdMatrix[fmod(pos.x, 3)] * _RowAcess[fmod(pos.y, 3)]);
			return col;
			//return half4(bakedGI, 1);
			//return 1 - dot(normalize( viewDirWS ), normalWS);
		}

		//��SurfaceInput.hlsl ��ȡΪ��֧������Լ���ӰͶ��
		half Alpha(half albedoAlpha, half4 color, half cutoff)
		{
		#if !defined(_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A) && !defined(_GLOSSINESS_FROM_BASE_ALPHA) //��
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

        Pass //3���ֿ���pass�𣿷ֱ�����Ӱ ���� ��� ���Բ��ö�д��
        {

            Name "ForwardLit"   //�����pass�����֣�
            Tags{"LightMode" = "LightweightForward"}

            Blend[_SrcBlend][_DstBlend] //д��������
            ZWrite[_ZWrite]
            Cull[_Cull] //���������ڣ��� Properties

            HLSLPROGRAM

            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

			// -------------------------------------
            // Material Keywords
            #pragma shader_feature _NORMALMAP  //�Զ��壿
            #pragma shader_feature _RECEIVE_SHADOWS_OFF

			// -------------------------------------
            // Lightweight Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            #pragma vertex LWBaseVertex
            #pragma fragment LWBaseFragment

            ENDHLSL
        }

        Pass
        {
			//��ӰͶ�䲻��Ҫ��ɾ��
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
			//��Ȼ�ȡ����ɾ����Ӱ������
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
    }
    FallBack "Hidden/InternalErrorShader"
}
