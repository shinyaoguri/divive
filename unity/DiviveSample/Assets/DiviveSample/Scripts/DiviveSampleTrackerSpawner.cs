using System.Collections.Generic;
using Divive.Tracking;
using UnityEngine;

namespace Divive.Sample
{
    /// <summary>
    /// Hubが配信するTrackerごとに表示用のGameObjectを作る。
    ///
    /// 姿勢の反映自体はSDKのDiviveTrackerBindingへ任せる。sample独自のcodeで
    /// 座標変換をやり直さないことで、SDKの使い方をそのまま示す。
    /// </summary>
    [RequireComponent(typeof(DiviveHubConnection))]
    public sealed class DiviveSampleTrackerSpawner : MonoBehaviour
    {
        private static readonly Color[] Palette =
        {
            new Color(0.30f, 0.68f, 1.00f),
            new Color(1.00f, 0.72f, 0.30f),
            new Color(0.45f, 0.90f, 0.55f),
            new Color(0.95f, 0.45f, 0.65f),
            new Color(0.75f, 0.60f, 1.00f),
        };

        private readonly Dictionary<string, GameObject> _spawned = new Dictionary<string, GameObject>();

        private DiviveHubConnection _connection;
        private int _nextColor;

        private void Awake()
        {
            _connection = GetComponent<DiviveHubConnection>();
        }

        private void OnEnable()
        {
            _connection.TrackerAppeared += HandleTrackerAppeared;
            _connection.TrackerRemoved += HandleTrackerRemoved;
        }

        private void OnDisable()
        {
            _connection.TrackerAppeared -= HandleTrackerAppeared;
            _connection.TrackerRemoved -= HandleTrackerRemoved;
        }

        private void HandleTrackerAppeared(DiviveTrackerState tracker)
        {
            if (_spawned.ContainsKey(tracker.TrackerId))
            {
                return;
            }

            var root = new GameObject($"Tracker {tracker.TrackerId}");
            root.transform.SetParent(transform, worldPositionStays: false);

            Color color = Palette[_nextColor % Palette.Length];
            _nextColor++;

            CreateBox(root.transform, Vector3.zero, new Vector3(0.12f, 0.12f, 0.12f), color);

            // Trackerの前方（Unityでは局所+Z）が見えるようにする。
            CreateBox(
                root.transform,
                new Vector3(0f, 0f, 0.11f),
                new Vector3(0.035f, 0.035f, 0.12f),
                Color.Lerp(color, Color.white, 0.55f));

            DiviveTrackerBinding binding = root.AddComponent<DiviveTrackerBinding>();
            binding.Connection = _connection;
            binding.MatchBy = DiviveTrackerMatch.TrackerId;
            binding.TrackerId = tracker.TrackerId;

            _spawned.Add(tracker.TrackerId, root);
        }

        private void HandleTrackerRemoved(string trackerId)
        {
            if (_spawned.TryGetValue(trackerId, out GameObject spawned))
            {
                _spawned.Remove(trackerId);
                Destroy(spawned);
            }
        }

        private static void CreateBox(Transform parent, Vector3 localPosition, Vector3 scale, Color color)
        {
            GameObject box = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Destroy(box.GetComponent<Collider>());
            box.transform.SetParent(parent, worldPositionStays: false);
            box.transform.localPosition = localPosition;
            box.transform.localScale = scale;
            box.GetComponent<Renderer>().material.color = color;
        }
    }
}
