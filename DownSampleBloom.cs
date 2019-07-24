using System;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;


[Serializable]
[PostProcess(typeof(DownSampleBloomRenderer), PostProcessEvent.AfterStack, "Custom/DownSampleBloom")]
public sealed class DownSampleBloom : PostProcessEffectSettings
{
    //const int BoxDownPrefilterPass = 0;
    //const int BoxDownPass = 1;
    //const int BoxUpPass = 2;
    //const int ApplyBloomPass = 3;
    //const int DebugBloomPass = 4;
    //[Range(0f, 1f), Tooltip("Grayscale effect intensity.")]
    //public FloatParameter blend = new FloatParameter { value = 0.5f };

    [Range(0f, 10f)]
    public FloatParameter m_intensity = new FloatParameter { value = 1f };  //bloom强度

    [Range(0, 10)]
    public FloatParameter m_threshold = new FloatParameter { value = 1f };   //

    [Range(0, 1)]
    public FloatParameter m_softThreshold = new FloatParameter { value = 0.5f };   //

    [Range(1, 16)]
    public IntParameter m_iterations = new IntParameter { value = 4 }; //迭代次数

    public  RenderTexture[] textures = new RenderTexture[16];
     


}

public sealed class DownSampleBloomRenderer : PostProcessEffectRenderer<DownSampleBloom>
{
    private Camera _CamTemp;
    private Camera _CamMain;

    public override void Init()
    {
        _CamMain = Camera.current;

        if (_CamMain && _CamTemp == null)
        {
            GameObject go = new GameObject("TempCamera");
            //go.hideFlags = HideFlags.HideAndDontSave;
            _CamTemp = go.AddComponent<Camera>();
            _CamTemp.enabled = false;
        }

        base.Init();
    }

   

    public void RenderTempCam(RenderTexture rt)
    {
        if (_CamTemp)
        {
            _CamTemp.CopyFrom(_CamMain);
            _CamTemp.clearFlags = CameraClearFlags.Color;
            _CamTemp.backgroundColor = Color.black;
            _CamTemp.targetTexture = rt;

            
            _CamTemp.Render();
        }
    }

    public override void Render(PostProcessRenderContext context)
    {
        var sheet = context.propertySheets.Get(Shader.Find("Hidden/Custom/DownSampleBloom"));
 
        float knee = settings.m_threshold * settings.m_softThreshold;
        Vector4 filter;
        filter.x = settings.m_threshold;
        filter.y = filter.x - knee;
        filter.z = 2.0f * knee;
        filter.w = 0.25f / (knee + 0.00001f);
        sheet.properties.SetVector("_Filter", filter);
        sheet.properties.SetFloat("_Intensity", Mathf.GammaToLinearSpace(settings.m_intensity));
        int w = (int)(context.width / 2);
        int h = (int)(context.height / 2);
        RenderTextureFormat format = context.sourceFormat;
        RenderTexture buffer0 = RenderTexture.GetTemporary(w, h, 0, format);
        RenderTexture buffer1 = RenderTexture.GetTemporary(context.width, context.height);
        settings.textures[0] = RenderTexture.GetTemporary(w, h, 0, format);
        RenderTempCam(buffer1);
        sheet.properties.SetTexture("_Mask", buffer1);
        context.command.BlitFullscreenTriangle(context.source, buffer1, sheet, 0);//BoxDownPrefilterPass
        context.command.BlitFullscreenTriangle(buffer1, settings.textures[0], sheet, 1);//BoxDownPrefilterPass
        buffer0 = settings.textures[0];
        
        int count = 0;
        for (int i = 1 ; i < settings.m_iterations; i++)
        {
            w /= 2;
            h /= 2;
            if (h < 2)
            {
                break;
            }
            settings.textures[i] = RenderTexture.GetTemporary(w, h, 0, format);
            context.command.BlitFullscreenTriangle(buffer0, settings.textures[i], sheet, 2);//BoxDownPass
            buffer0 = settings.textures[i];
            count = i;
            //每一次都是将高分辨率渲染到低分辨率的render texture里
        }

        for (int i = count - 1; i >= 0; i--)
        {
            context.command.BlitFullscreenTriangle(buffer0, settings.textures[i], sheet, 3);
            buffer0 = settings.textures[i];
        }
        sheet.properties.SetTexture("_Bloom", buffer0);
        context.command.BlitFullscreenTriangle(context.source, context.destination, sheet, 4);//Add pass

        for(int i = 0; i <= count; i++)
        {
            RenderTexture.ReleaseTemporary(settings.textures[i]);
        }

        RenderTexture.ReleaseTemporary(buffer0);
        //RenderTexture.ReleaseTemporary(buffer1);
     

    }

    public override void Release()
    {
        if (_CamTemp)
        {
            if (Application.isPlaying)
            {
                GameObject.Destroy(_CamTemp.gameObject);
            }
            else
            {
                GameObject.DestroyImmediate(_CamTemp.gameObject);
            }
        }

        base.Release();
    }
}