using NUnit.Framework;
using UnityEngine;

namespace Divive.Tracking.Tests
{
    public sealed class DiviveCoordinatesTests
    {
        private const float Tolerance = 1e-4f;

        [Test]
        public void 単位姿勢は単位姿勢のまま変換される()
        {
            Quaternion rotation = DiviveCoordinates.ToUnityRotation(0f, 0f, 0f, 1f);

            Assert.That(Quaternion.Angle(rotation, Quaternion.identity), Is.LessThan(Tolerance));
        }

        [Test]
        public void canonicalの局所前方はUnityの局所前方と一致する()
        {
            // canonicalは局所-Zが前方、Unityは局所+Zが前方。単位姿勢どうしが対応する。
            Vector3 canonicalForward = new Vector3(0f, 0f, -1f);
            Vector3 mapped = DiviveCoordinates.ToUnityPosition(
                canonicalForward.x,
                canonicalForward.y,
                canonicalForward.z);

            Assert.That(Vector3.Distance(mapped, Vector3.forward), Is.LessThan(Tolerance));
        }

        [Test]
        public void 位置はZ軸を反転して変換される()
        {
            Vector3 position = DiviveCoordinates.ToUnityPosition(1.25f, 0.5f, -2f);

            Assert.That(position.x, Is.EqualTo(1.25f).Within(Tolerance));
            Assert.That(position.y, Is.EqualTo(0.5f).Within(Tolerance));
            Assert.That(position.z, Is.EqualTo(2f).Within(Tolerance));
        }

        [Test]
        public void 姿勢変換は回転後のvectorと整合する()
        {
            // +Yまわり90度（右手系）。canonicalの前方-Zは-Xへ向く。
            float half = Mathf.Sqrt(0.5f);
            Quaternion unityRotation = DiviveCoordinates.ToUnityRotation(0f, half, 0f, half);

            Vector3 canonicalForward = new Vector3(0f, 0f, -1f);
            Vector3 rotatedCanonical = RotateCanonical(0f, half, 0f, half, canonicalForward);
            Vector3 expected = DiviveCoordinates.ToUnityPosition(
                rotatedCanonical.x,
                rotatedCanonical.y,
                rotatedCanonical.z);

            Vector3 actual = unityRotation * Vector3.forward;

            Assert.That(Vector3.Distance(rotatedCanonical, new Vector3(-1f, 0f, 0f)), Is.LessThan(Tolerance));
            Assert.That(Vector3.Distance(actual, expected), Is.LessThan(Tolerance));
        }

        [Test]
        public void 任意の姿勢とvectorで変換が可換になる()
        {
            var random = new System.Random(20260728);
            for (int trial = 0; trial < 32; trial++)
            {
                float qx = NextFloat(random);
                float qy = NextFloat(random);
                float qz = NextFloat(random);
                float qw = NextFloat(random);
                float norm = Mathf.Sqrt((qx * qx) + (qy * qy) + (qz * qz) + (qw * qw));
                if (norm < 1e-3f)
                {
                    continue;
                }

                qx /= norm;
                qy /= norm;
                qz /= norm;
                qw /= norm;

                var canonicalVector = new Vector3(NextFloat(random), NextFloat(random), NextFloat(random));
                Vector3 rotatedThenMapped = ToUnity(RotateCanonical(qx, qy, qz, qw, canonicalVector));
                Vector3 mappedThenRotated =
                    DiviveCoordinates.ToUnityRotation(qx, qy, qz, qw) * ToUnity(canonicalVector);

                Assert.That(
                    Vector3.Distance(rotatedThenMapped, mappedThenRotated),
                    Is.LessThan(1e-3f),
                    $"trial {trial} で回転と座標変換が可換になりませんでした");
            }
        }

        [Test]
        public void 角速度は姿勢の時間変化と整合する()
        {
            // canonicalで+Yまわりに1 rad/s回すとき、変換後の角速度で積分した姿勢が、
            // 変換後の姿勢と一致すること。極性vectorと同じ式では一致しない。
            //
            // dtは小さすぎても大きすぎてもいけない。小さいとQuaternion.Angleの
            // epsilon以下になって誤った式との差が消え、大きいと1次積分の誤差が増える。
            const float dt = 0.1f;
            var canonicalAngular = new Vector3(0f, 1f, 0f);

            float halfAngle = 0.5f * dt;
            float sin = Mathf.Sin(halfAngle);
            float cos = Mathf.Cos(halfAngle);
            Quaternion expected = DiviveCoordinates.ToUnityRotation(0f, sin, 0f, cos);

            Vector3 unityAngular = DiviveCoordinates.ToUnityAngularVector(
                canonicalAngular.x,
                canonicalAngular.y,
                canonicalAngular.z);
            Quaternion integrated = Integrate(Quaternion.identity, unityAngular, dt);

            Assert.That(Quaternion.Angle(integrated, expected), Is.LessThan(0.02f));

            Vector3 wrongAngular = DiviveCoordinates.ToUnityLinearVector(
                canonicalAngular.x,
                canonicalAngular.y,
                canonicalAngular.z);
            Quaternion wrong = Integrate(Quaternion.identity, wrongAngular, dt);

            Assert.That(
                Quaternion.Angle(wrong, expected),
                Is.GreaterThan(1f),
                "極性vectorと同じ式でも一致してしまうため、testが変換の違いを検出できていません");
        }

        private static float NextFloat(System.Random random)
        {
            return (float)((random.NextDouble() * 2.0) - 1.0);
        }

        private static Vector3 ToUnity(Vector3 canonical)
        {
            return DiviveCoordinates.ToUnityPosition(canonical.x, canonical.y, canonical.z);
        }

        /// <summary>canonical（右手系）のquaternionでvectorを回す。Unity APIを使わない。</summary>
        private static Vector3 RotateCanonical(float x, float y, float z, float w, Vector3 v)
        {
            var u = new Vector3(x, y, z);
            float dot = Vector3.Dot(u, v);
            Vector3 cross = Vector3.Cross(u, v);
            return (2f * dot * u) + (((w * w) - Vector3.Dot(u, u)) * v) + (2f * w * cross);
        }

        private static Quaternion Integrate(Quaternion rotation, Vector3 angularVelocity, float dt)
        {
            var omega = new Quaternion(angularVelocity.x, angularVelocity.y, angularVelocity.z, 0f);
            Quaternion derivative = omega * rotation;
            float scale = 0.5f * dt;
            var integrated = new Quaternion(
                rotation.x + (derivative.x * scale),
                rotation.y + (derivative.y * scale),
                rotation.z + (derivative.z * scale),
                rotation.w + (derivative.w * scale));
            return Normalize(integrated);
        }

        private static Quaternion Normalize(Quaternion value)
        {
            float norm = Mathf.Sqrt(
                (value.x * value.x) + (value.y * value.y) + (value.z * value.z) + (value.w * value.w));
            return new Quaternion(value.x / norm, value.y / norm, value.z / norm, value.w / norm);
        }
    }
}
