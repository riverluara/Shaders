//�������߳������ݲο�����Shader��Ҫֱ���޸ĸ���������ʹ�� ��֧��LightMap �� GPUʵ��
Shader "LWC5/MatcapBase"
{
    Properties
    {

        _BaseColor("albedo", Color) = (1,1,1,1)
        _BaseMap("AlbedoTex", 2D) = "white" {}
	    [NoScaleOffset]
		_BumpMap("Normal Map", 2D) = "bump" {}
		_ControlTex("ControlTex R(metallic),G(Smoothness)B(ao)A(Emission)", 2D) = "white" {}
		_EmissionColor("EmissionColor", Color) = (0,0,0,1)

		_metallic("Metallic", Range(0,1)) = 0
		_smoothness("Smoothness", Range(0,1)) = 1.0

		_MatcapTex("MatcapTex", 2D) = "white" {}

		_EvtPower("EvtPower", Range(0, 1)) = 0.1
        // Blending state
		[HideInInspector]_Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5 //��Ȼ�ȡ������ӰAlphaTest�ü���ر�Ҫ����ɾ��
        [HideInInspector] _ReceiveShadows("Receive Shadows", Float) = 1.0
    }

    SubShader
    {
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "LightweightPipeline" "Queue" = "Geometry"  "IgnoreProjector" = "True"}
        LOD 100
		
		HLSLINCLUDE
		#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Core.hlsl"
		//������� �޹��ս���
		#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Lighting.hlsl"

		CBUFFER_START(UnityPerMaterial)
		float4 _BaseMap_ST;
		half4 _BaseColor;
		half4 _EmissionColor;
		half _metallic;
		half _smoothness;
		half _EvtPower;
		half _Cutoff; //��Ȼ�ȡ������ӰAlphaTest�ü���ر�Ҫ����ɾ��
		CBUFFER_END

		TEXTURE2D(_BaseMap);  SAMPLER(sampler_BaseMap);
		TEXTURE2D(_BumpMap);  SAMPLER(sampler_BumpMap);
		TEXTURE2D(_ControlTex);  SAMPLER(sampler_ControlTex);
		TEXTURE2D(_MatcapTex);  SAMPLER(sampler_MatcapTex);
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
			half4 normalWS                  : TEXCOORD1;    // xyz: normal, w: viewDir.x
		
			half3 viewDirT                 : TEXCOORD2;//view direction and light direction in tangent space
			half3 lightDirT				   : TEXCOORD3;
			half4 fogFactorAndVertexLight  : TEXCOORD4; //�������֧�� 

			#ifdef _MAIN_LIGHT_SHADOWS
				float4 shadowCoord              : TEXCOORD5; //��Ӱ
			#endif
			half3 TtoV0                     : TEXCOORD6;
			half3 TtoV1                     : TEXCOORD7;

		};

		LWVaryings LWBaseVertex(LWAttributes input)
		{
			LWVaryings output = (LWVaryings)0;

			//��ȡλ�������Ϣ
			VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz); //VertexPositionInputs ���Դ�����
			output.positionCS = vertexInput.positionCS;
			
			//��ȡ�۲췽��
			half3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS; //UnityWorldSpaceViewDir

			//��ȡ���������Ϣ
			VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);//VertexNormalInputs
			
			output.normalWS = half4(normalInput.normalWS, viewDirWS.x);
			half3 tangentWS = normalInput.tangentWS; //
			half3 bitangentWS = normalInput.bitangentWS;
			//���߿ռ�ת������
			half3x3 rotation = half3x3(tangentWS.xyz, bitangentWS.xyz, output.normalWS.xyz);
			//�����ߴ�ģ�Ϳռ䵽�۲�ռ��ת��
			//https://www.cnblogs.com/flytrace/p/3379816.html
			output.TtoV0 = normalize(mul(rotation, UNITY_MATRIX_IT_MV[0].xyz));
			output.TtoV1 = normalize(mul(rotation, UNITY_MATRIX_IT_MV[1].xyz));
			//��ȡ����Դ����
			float3 lightDir = vertexInput.positionWS-GetMainLight().direction;
			//������Դ��ģ�Ϳռ�ת�������߿ռ�
			output.lightDirT = mul(rotation,mul(unity_WorldToObject,float4(lightDir,1)).xyz);
			//output.lightDirT = mul(rotation, lightDir);
			output.viewDirT = mul(rotation, mul(unity_WorldToObject, float4(viewDirWS,1)).xyz);
			output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
			
			//���붥�����
			half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS); //VertexLighting
			half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);//ComputeFogFactor����
			output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);  // fogFactorAndVertexLight   : TEXCOORD6; //�������֧�� 

			#if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
				output.shadowCoord = GetShadowCoord(vertexInput);
			#endif
			

			return output;
		}
		

		half4 LWBaseFragment(LWVaryings input) : SV_Target
		{
			
			
			//��ȡ����Դ��Ӱ
			#if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
				float4 shadowCoord = input.shadowCoord;
				//��ȡ����Դ
				Light mainLight = GetMainLight(shadowCoord); 
			#else
				//��ȡ����Դ
				Light mainLight = GetMainLight();
			#endif

			half3 N = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv));
			half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
			half4 controlCol = SAMPLE_TEXTURE2D(_ControlTex, sampler_ControlTex, input.uv);
			half4 col = 1;

			_BaseColor.rgb *= baseCol.rgb;
			_metallic *= controlCol.r;
			_smoothness *= controlCol.g;

			half ao = controlCol.b;
			half3 V = normalize(input.viewDirT);
			half3 L = normalize(input.lightDirT);
			half3 H = normalize(V + L);
			half3 R = normalize(reflect(-V, N));
			half3 radiance = mainLight.color;
			half atten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
			
			half NdotL = (max(0.0, dot(N, L)) * 0.5 + 0.5) * atten;
			half spec = pow(max(dot(H, N), 0), 1024 * _smoothness * _smoothness) * _smoothness * 2;
			//a*(1-mixValue)+b*mixValue
			half texmipValue = lerp(4, 1, _smoothness);

			half2 vr;
			vr.x = dot(input.TtoV0, R);
			vr.y = dot(input.TtoV1, R);
			half4 evtS = SAMPLE_TEXTURE2D_LOD(_MatcapTex, sampler_MatcapTex, vr * 0.5 + 0.5, texmipValue);


			half2 vn;
			vn.x = dot(input.TtoV0, N);
			vn.y = dot(input.TtoV1, N);
			//half4 evtD = tex2Dlod(sampler_MatcapTex, half4(vn * 0.5 + 0.5, 0, texmipValue));
			half4 evtD = SAMPLE_TEXTURE2D_LOD(_MatcapTex, sampler_MatcapTex, vn * 0.5 + 0.5, texmipValue);


			col.rgb = _BaseColor.rgb;
			col.rgb *= NdotL*radiance;
			col.rgb += evtS.rgb * 4.0 * _metallic * _EvtPower;

			col.rgb += evtD.rgb * _EvtPower;

			col.rgb += spec;
			

			//half3 bakedGI = SampleSHPixel(input.vertexSH, input.normalWS);

			//half dif = saturate(dot(normalWS, mainLight.direction)) * ;

		
			col.rgb = lerp(col.rgb, _EmissionColor.rgb, controlCol.a * _EmissionColor.a);

			//��֧��
			col.rgb = MixFog(col.rgb, input.fogFactorAndVertexLight.x); //MixFog�������
			 

			return col;
			//return half4(vn,0,1);
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
