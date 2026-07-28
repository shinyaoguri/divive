using Divive.Tracking;
using UnityEngine;

namespace Divive.Sample
{
    /// <summary>
    /// Play押下だけでsampleが動くよう、sceneの中身をcodeで組み立てる。
    ///
    /// sceneをassetとして持たないのは、Unityのversionやrender pipelineが変わっても
    /// sampleが壊れないようにするため。既にDiviveHubConnectionが置かれたsceneでは
    /// 何もしないので、自分でsceneを作って試すこともできる。
    /// </summary>
    public static class DiviveSampleBootstrap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Bootstrap()
        {
            if (Object.FindAnyObjectByType<DiviveHubConnection>() != null)
            {
                return;
            }

            var root = new GameObject("divive Sample");
            Object.DontDestroyOnLoad(root);

            root.AddComponent<DiviveHubConnection>();
            root.AddComponent<DiviveSampleTrackerSpawner>();
            root.AddComponent<DiviveSampleHud>();

            CreateCamera(root.transform);
            CreateLight(root.transform);
            CreateGround(root.transform);
        }

        private static void CreateCamera(Transform parent)
        {
            if (Camera.main != null)
            {
                return;
            }

            var cameraObject = new GameObject("divive Sample Camera");
            cameraObject.tag = "MainCamera";
            cameraObject.transform.SetParent(parent, worldPositionStays: true);

            // Stage原点を見下ろす位置。SimulatorのTrackerは原点付近に生成される。
            cameraObject.transform.position = new Vector3(0f, 2.4f, -3.6f);
            cameraObject.transform.rotation = Quaternion.Euler(22f, 0f, 0f);

            Camera camera = cameraObject.AddComponent<Camera>();
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.09f, 0.10f, 0.12f);
            camera.nearClipPlane = 0.05f;
        }

        private static void CreateLight(Transform parent)
        {
            var lightObject = new GameObject("divive Sample Light");
            lightObject.transform.SetParent(parent, worldPositionStays: true);
            lightObject.transform.rotation = Quaternion.Euler(50f, -30f, 0f);

            Light light = lightObject.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 1.1f;
        }

        /// <summary>1m格子の床。Stage Spaceの尺度が目で分かるようにする。</summary>
        private static void CreateGround(Transform parent)
        {
            var grid = new GameObject("Stage Grid");
            grid.transform.SetParent(parent, worldPositionStays: true);

            const int halfExtent = 5;
            for (int index = -halfExtent; index <= halfExtent; index++)
            {
                CreateGridLine(
                    grid.transform,
                    new Vector3(index, 0f, 0f),
                    new Vector3(0.01f, 0.002f, halfExtent * 2f),
                    index == 0);
                CreateGridLine(
                    grid.transform,
                    new Vector3(0f, 0f, index),
                    new Vector3(halfExtent * 2f, 0.002f, 0.01f),
                    index == 0);
            }
        }

        private static void CreateGridLine(
            Transform parent,
            Vector3 position,
            Vector3 scale,
            bool isAxis)
        {
            GameObject line = GameObject.CreatePrimitive(PrimitiveType.Cube);
            line.name = isAxis ? "Axis" : "Grid";
            Object.Destroy(line.GetComponent<Collider>());
            line.transform.SetParent(parent, worldPositionStays: true);
            line.transform.localPosition = position;
            line.transform.localScale = scale;

            Renderer renderer = line.GetComponent<Renderer>();
            renderer.material.color = isAxis
                ? new Color(0.55f, 0.58f, 0.65f)
                : new Color(0.22f, 0.24f, 0.28f);
        }
    }
}
