using UnityEngine;

namespace Divive.Tracking
{
    /// <summary>
    /// canonical座標とUnity座標の変換。
    ///
    /// canonical: 右手系、metre、+X right、+Y up、<b>-Z forward</b>、quaternion (x, y, z, w)。
    /// Unity: 左手系、metre、+X right、+Y up、<b>+Z forward</b>。
    ///
    /// 手系の違いはZ軸の反転 M = diag(1, 1, -1) で吸収する。これは鏡映なので、
    /// 量の種類ごとに変換が変わる。
    ///
    /// - 位置・線速度のような極性vector: (x, y, -z)
    /// - 姿勢quaternion: (-x, -y, z, w)
    /// - 角速度のような軸性vector: (-x, -y, z)
    ///
    /// 角速度をpositionと同じ式で変換すると、姿勢の変換と整合しない。
    /// canonicalの局所-Z前方は、変換後にUnityの局所+Z前方（transform.forward）と一致する。
    /// </summary>
    public static class DiviveCoordinates
    {
        public static Vector3 ToUnityPosition(float x, float y, float z)
        {
            return new Vector3(x, y, -z);
        }

        /// <summary>位置と同じ変換。線速度など極性vectorに使う。</summary>
        public static Vector3 ToUnityLinearVector(float x, float y, float z)
        {
            return new Vector3(x, y, -z);
        }

        /// <summary>姿勢quaternionの変換と整合する、角速度など軸性vectorの変換。</summary>
        public static Vector3 ToUnityAngularVector(float x, float y, float z)
        {
            return new Vector3(-x, -y, z);
        }

        public static Quaternion ToUnityRotation(float x, float y, float z, float w)
        {
            return new Quaternion(-x, -y, z, w);
        }

        public static void ToCanonicalPosition(Vector3 position, out float x, out float y, out float z)
        {
            x = position.x;
            y = position.y;
            z = -position.z;
        }

        public static void ToCanonicalRotation(
            Quaternion rotation,
            out float x,
            out float y,
            out float z,
            out float w)
        {
            x = -rotation.x;
            y = -rotation.y;
            z = rotation.z;
            w = rotation.w;
        }
    }
}
