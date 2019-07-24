Shader "c5/Environment/OilLake"
{
	Properties
	{

        _BumpMap("BumpMap", 2D) = "bump" {}
		_Bump_U_Speed("BumpMap U Speed", Float) = 0
        [NoScaleOffset]
		[Space(20)]
        _RefTex("RefTex", 2D) = "white" {}
        _RefPower("RefPower", Range(0.0, 1.0)) = 1
		_RefColor("RefColorFactor", Color) = (1, 1, 1, 1)
		_LightDir("LightDir", Vector) = (0,0,0,1)//假灯光方向
		[Space(20)]
		_SpecColor("Specular Color", Color) = (1, 1, 1, 1)
		_Gloss("Gloss", Range(8.0, 256.0)) = 8
		_GlossFactor("Gloss Factor", Range(0, 1)) = 0.5
		//[KeywordEnum(OFF, ON)] NOISE_DISTURB("NOISE_DISTURB", float) = 0
        [Space(20)]
		_Center("Center for MainTex", Vector) = (0.5, 0.5, 0, 0)
		_Distance("Max Wave Size", Float) = 0.5
		_NoisePower("Max Wave Size Power", Float) = 2
		_Amplitude("Wave Height", Float) = 0.05
		_WaveLength("Wave Length", Float) = 0.05
		_WaveSpeed("Wave Speed", Float) = -0.05
		_WaveIntensity("Wave Intensity", Float) = 0.2
		[Space(20)]
		_DeepTex("DeepTex", 2D) = "white"{}
		_DeepPower("DeepPower", Range(0.0, 1.0)) = 0.5
		_DeepOffset("DeepOffset", float) = 0.1
		[Space(10)]
		[Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull Mode", Float) = 2

	}

	CGINCLUDE
	#include "UnityCG.cginc"

	struct appdata
	{
		float4 vertex : POSITION;
		float3 normal : NORMAL;
        half4 tangent : TANGENT;
		half2 uv : TEXCOORD0;
	};

	struct v2f
	{
		half2 uv : TEXCOORD0;
		float4 pos : SV_POSITION;
		UNITY_FOG_COORDS(1)
        half3 worldNormal : TEXCOORD4;
        half3 worldViewDir : TEXCOORD5;
		half4 texcoord3     : TEXCOORD6; //normaluv and ref uv
        float4 Ttow0 : TEXCOORD7;
        float4 Ttow1 : TEXCOORD8;
        float4 Ttow2 : TEXCOORD9;
	};

	float4 _LightDir;
    sampler2D _RefTex;
    half _RefPower;
	half4 _RefColor;
	half4 _RefTex_ST;

	half4 _SpecColor;
	float _Gloss;
	float _GlossFactor;
    
    sampler2D _BumpMap;
	half4 _BumpMap_ST;
	float _Bump_U_Speed;


	float4 _Center;
	float _Distance;
	float _NoisePower;
	float _Amplitude;
	float _WaveLength;
	float _WaveSpeed;
	float _WaveIntensity;

	sampler2D _DeepTex;
	half _DeepPower;
	half4 _DeepTex_ST;
	half _DeepOffset;

	v2f vert(appdata v)
	{
		v2f o;
		o.pos = UnityObjectToClipPos(v.vertex);
		half2 uv = v.uv ;
    
		o.texcoord3.xy = TRANSFORM_TEX(v.uv, _BumpMap) + float2(_Time.x * _Bump_U_Speed, 0);
		o.texcoord3.zw = TRANSFORM_TEX(v.uv, _DeepTex);
		o.texcoord3.zw += _WorldSpaceCameraPos.xz * _DeepOffset;// 油污效果贴图偏移
		o.uv = TRANSFORM_TEX(v.uv, _RefTex) ;
        o.worldNormal = UnityObjectToWorldNormal(v.normal);
        half3 wpos = mul(unity_ObjectToWorld, v.vertex).xyz;
        o.worldViewDir = UnityWorldSpaceViewDir(wpos);


        half3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
        float3 worldBinormal = cross(o.worldNormal, worldTangent) * v.tangent.w;

        o.Ttow0 = float4(worldTangent.x, worldBinormal.x, o.worldNormal.x, wpos.x);
        o.Ttow1 = float4(worldTangent.y, worldBinormal.y, o.worldNormal.y, wpos.y);
        o.Ttow2 = float4(worldTangent.z, worldBinormal.z, o.worldNormal.z, wpos.z);
		
		UNITY_TRANSFER_FOG(o, o.pos);
		return o;
	}

	fixed4 frag(v2f i) : SV_Target
	{
		
		half4 deepTex = tex2D(_DeepTex, i.texcoord3.zw);
		//---------用波形函数计算涟漪uv偏移-----------------
		float2 noiseDirection = normalize(i.uv - _Center.xy);
		float currentDistance = length(i.uv - _Center.xy);

		float waveAtt = pow(saturate(1.0 - currentDistance / _Distance), _NoisePower);
		float2 currentAmp = waveAtt * noiseDirection * _Amplitude;

		float firstWave = currentDistance / _WaveLength * 6.28;
		float waveSpeed = (6.28 / _WaveLength)* _Time.x * _WaveSpeed;

		float wave = currentAmp * sin((firstWave + waveSpeed));
		//-----------------获得偏移v = A*sin(2*pi*t/L+v0)------
        float3 worldPos = float3(i.Ttow0.w, i.Ttow1.w, i.Ttow2.w);
        half3 bumpTex = UnpackNormal(tex2D(_BumpMap, i.texcoord3.xy ));
        half3 worldLightDir = normalize(UnityWorldSpaceLightDir(worldPos));
        
        float3 N = normalize(half3(dot(i.Ttow0.xyz, bumpTex), dot(i.Ttow1.xyz, bumpTex), dot(i.Ttow2.xyz, bumpTex)));
        half3 V = normalize(i.worldViewDir);

		fixed4 col = 1.0;


		half3 H = normalize(normalize(_LightDir.rgb) + V);
        half3 R = normalize(reflect(-V, N));
		
		float d = saturate(max(0, dot(N, H)));
		float3 spec =  _SpecColor.rgb * pow(d, _Gloss) * _GlossFactor;
		i.uv = R.xy ;
        half3 refCol =tex2D(_RefTex, i.uv + half2(wave, wave) * _WaveIntensity).rgb * _RefColor.rgb * _RefPower + spec;
        
        
        col.rgb = lerp( col.rgb ,  lerp(refCol, deepTex, _DeepPower),  _RefPower);

		UNITY_APPLY_FOG(i.fogCoord, col);

		

		return col;
	}

	ENDCG

	SubShader
	{
		Tags{ "RenderType" = "Transparent" "Queue" = "Transparent" "IgnoreProjector"="True" }

		Blend SrcAlpha OneMinusSrcAlpha
		Cull[_Cull]

		Pass
		{
			Tags{ "LightMode" = "ForwardBase" }

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase
			#pragma multi_compile_fog
			
			ENDCG
		}
	}

	Fallback "VertexLit"
}
