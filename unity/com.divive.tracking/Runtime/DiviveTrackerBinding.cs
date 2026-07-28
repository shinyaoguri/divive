using UnityEngine;

namespace Divive.Tracking
{
    public enum DiviveTrackerMatch
    {
        /// <summary>Tracker IDで一致させる。再起動後も同じ個体へ結び付く。</summary>
        TrackerId = 0,

        /// <summary>Hubが割り当てた論理roleで一致させる。個体を差し替えられる。</summary>
        Role = 1,
    }

    /// <summary>
    /// Trackerの姿勢をTransformへ反映するcomponent。
    ///
    /// 平滑化は既定で無効。Hubは補間せず最新値だけを配信するため、平滑化を入れると
    /// 表示は滑らかになるが遅れが増える。時刻に基づく補間はclock mappingが入るまで
    /// 提供しない。ここにあるのは見た目のための指数平滑であり、予測ではない。
    /// </summary>
    [AddComponentMenu("divive/divive Tracker Binding")]
    public sealed class DiviveTrackerBinding : MonoBehaviour
    {
        [Header("対象")]
        [SerializeField]
        private DiviveHubConnection connection;

        [SerializeField]
        private DiviveTrackerMatch matchBy = DiviveTrackerMatch.Role;

        [Tooltip("matchByがTrackerIdのときに使う。例: htc/vive-tracker-3/LHR-XXXXXXXX")]
        [SerializeField]
        private string trackerId = string.Empty;

        [Tooltip("matchByがRoleのときに使う。例: waist、left_foot")]
        [SerializeField]
        private string role = "waist";

        [Header("反映")]
        [SerializeField]
        private bool applyPosition = true;

        [SerializeField]
        private bool applyRotation = true;

        [Tooltip("親からの相対ではなくworld座標へ反映する。")]
        [SerializeField]
        private bool applyInWorldSpace = false;

        [Tooltip("追跡できていない間、子のRendererを隠す。")]
        [SerializeField]
        private bool hideWhenNotTracking = true;

        [Header("平滑化")]
        [Tooltip("0で無効。値は追従の半減期（秒）。大きいほど滑らかで遅れる。")]
        [SerializeField]
        private float smoothingHalfLifeSeconds = 0f;

        private Renderer[] _renderers;
        private bool _hasState;
        private bool _hasSmoothedPose;
        private Vector3 _smoothedPosition;
        private Quaternion _smoothedRotation = Quaternion.identity;
        private DiviveTrackerState _state;

        /// <summary>直近に一致したTracker状態。一致していない間は既定値。</summary>
        public DiviveTrackerState State => _state;

        public bool HasState => _hasState;

        public DiviveTrackerMatch MatchBy
        {
            get => matchBy;
            set => matchBy = value;
        }

        public string TrackerId
        {
            get => trackerId;
            set => trackerId = value;
        }

        public string Role
        {
            get => role;
            set => role = value;
        }

        public DiviveHubConnection Connection
        {
            get => connection;
            set => connection = value;
        }

        private void Awake()
        {
            _renderers = GetComponentsInChildren<Renderer>(includeInactive: true);
        }

        private void LateUpdate()
        {
            DiviveHubConnection source = connection != null ? connection : DiviveHubConnection.Instance;
            if (source == null)
            {
                SetVisible(!hideWhenNotTracking);
                return;
            }

            bool matched = matchBy == DiviveTrackerMatch.Role
                ? source.TryGetTrackerByRole(role, out _state)
                : source.TryGetTracker(trackerId, out _state);

            _hasState = matched;
            if (!matched || !_state.IsPoseUsable)
            {
                SetVisible(!hideWhenNotTracking);
                return;
            }

            SetVisible(true);
            ApplyPose(_state.Position, _state.Rotation);
        }

        private void ApplyPose(Vector3 position, Quaternion rotation)
        {
            if (smoothingHalfLifeSeconds > 0f && _hasSmoothedPose)
            {
                float factor = 1f - Mathf.Pow(0.5f, Time.deltaTime / smoothingHalfLifeSeconds);
                position = Vector3.Lerp(_smoothedPosition, position, factor);
                rotation = Quaternion.Slerp(_smoothedRotation, rotation, factor);
            }

            _smoothedPosition = position;
            _smoothedRotation = rotation;
            _hasSmoothedPose = true;

            if (applyPosition)
            {
                if (applyInWorldSpace)
                {
                    transform.position = position;
                }
                else
                {
                    transform.localPosition = position;
                }
            }

            if (applyRotation)
            {
                if (applyInWorldSpace)
                {
                    transform.rotation = rotation;
                }
                else
                {
                    transform.localRotation = rotation;
                }
            }
        }

        private void SetVisible(bool visible)
        {
            if (_renderers == null)
            {
                return;
            }

            for (int index = 0; index < _renderers.Length; index++)
            {
                Renderer target = _renderers[index];
                if (target != null && target.enabled != visible)
                {
                    target.enabled = visible;
                }
            }
        }
    }
}
