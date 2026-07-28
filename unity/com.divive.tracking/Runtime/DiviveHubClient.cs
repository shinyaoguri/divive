using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Divive.Stage;
using Google.FlatBuffers;

namespace Divive.Tracking
{
    /// <summary>Hubへの接続設定。</summary>
    [Serializable]
    public struct DiviveHubClientSettings
    {
        public string Host;
        public int Port;

        /// <summary>Hubの診断表示に出るclient名。識別子としては使われない。</summary>
        public string ClientName;

        /// <summary>希望する配信頻度。0はHubの設定に従う。v1のHubは診断表示にだけ使う。</summary>
        public ushort RequestedRateHz;

        /// <summary>購読の有効期間。これを過ぎるとHubは配信を止める。</summary>
        public uint SubscriptionTtlMilliseconds;

        public static DiviveHubClientSettings Default => new DiviveHubClientSettings
        {
            Host = "127.0.0.1",
            Port = DiviveStageWire.DefaultPort,
            ClientName = "unity",
            RequestedRateHz = 0,
            SubscriptionTtlMilliseconds = DiviveStageWire.DefaultSubscriptionTtlMilliseconds,
        };
    }

    public struct DiviveClientStatistics
    {
        public ulong DatagramsReceived;
        public ulong FramesApplied;
        public ulong DecodeErrors;
        public ulong SocketErrors;
        public ulong SubscriptionsSent;

        /// <summary>frame sequenceの飛びから数えた、届かなかったframe数。</summary>
        public ulong MissedFrames;

        /// <summary>Hub sessionが変わった回数。Hubの再起動で増える。</summary>
        public ulong SessionResets;

        public DiviveDecodeError LastDecodeError;
        public string LastSocketError;
    }

    /// <summary>
    /// Hubのstage planeへ購読を送り、最新値を受け取るUDP client。
    ///
    /// 受信は専用threadで行い、main threadへはlatest valueだけを渡す。届いたframeを
    /// queueに貯めないため、描画が遅れても古い姿勢が後追いで再生されることはない。
    /// MonoBehaviourに依存しないので、Editor testからも直接使える。
    /// </summary>
    public sealed class DiviveHubClient : IDisposable
    {
        private const int ReceiveTimeoutMilliseconds = 200;

        private readonly object _exchangeLock = new object();
        private readonly object _statisticsLock = new object();
        private readonly DiviveStageFrameDecoder _decoder = new DiviveStageFrameDecoder();
        private readonly Stopwatch _clock = Stopwatch.StartNew();
        private readonly DiviveUuid _sessionId = DiviveUuid.NewRandom();
        private readonly DiviveUuid _clientId = DiviveUuid.NewRandom();

        // 受信thread、共有、main threadで1つずつ持ち、交換だけで受け渡す。
        private DiviveStageSnapshot _decoding = new DiviveStageSnapshot();
        private DiviveStageSnapshot _pending = new DiviveStageSnapshot();
        private DiviveStageSnapshot _consumed = new DiviveStageSnapshot();
        private bool _hasPending;

        private readonly byte[] _receiveBuffer = new byte[DiviveStageWire.MaximumDatagramSize];
        private readonly byte[] _sendBuffer = new byte[DiviveStageWire.MaximumDatagramSize];

        private DiviveHubClientSettings _settings;
        private Socket _socket;
        private Thread _thread;
        private volatile bool _running;
        private DiviveClientStatistics _statistics;
        private ulong _lastFrameSequence;
        private DiviveUuid _lastSessionId;
        private bool _hasLastFrame;
        private double _lastFrameRealtimeSeconds = double.NegativeInfinity;
        private ulong _subscriptionSequence;

        public DiviveHubClient(DiviveHubClientSettings settings)
        {
            _settings = Normalize(settings);
        }

        public bool IsRunning => _running;

        public DiviveHubClientSettings Settings => _settings;

        /// <summary>最後にframeを受け取ってからの経過秒。未受信はdouble.PositiveInfinity。</summary>
        public double SecondsSinceLastFrame
        {
            get
            {
                lock (_statisticsLock)
                {
                    return double.IsNegativeInfinity(_lastFrameRealtimeSeconds)
                        ? double.PositiveInfinity
                        : ElapsedSeconds() - _lastFrameRealtimeSeconds;
                }
            }
        }

        public DiviveClientStatistics Statistics
        {
            get
            {
                lock (_statisticsLock)
                {
                    return _statistics;
                }
            }
        }

        public void Start()
        {
            if (_running)
            {
                return;
            }

            IPAddress address = ResolveHost(_settings.Host);
            _socket = new Socket(address.AddressFamily, SocketType.Dgram, ProtocolType.Udp)
            {
                ReceiveTimeout = ReceiveTimeoutMilliseconds,
            };

            // Hub以外からのdatagramを受け取らないようconnectする。
            _socket.Connect(new IPEndPoint(address, _settings.Port));

            _running = true;
            _thread = new Thread(Run)
            {
                IsBackground = true,
                Name = "divive-hub-client",
            };
            _thread.Start();
        }

        public void Stop()
        {
            if (!_running)
            {
                return;
            }

            _running = false;

            // Hubが購読TTLを待たずに配信を止められるよう、明示的に解除する。
            TrySendSubscription(unsubscribe: true);

            try
            {
                _socket?.Close();
            }
            catch (SocketException)
            {
                // closeの失敗は停止処理を妨げない。
            }

            if (_thread != null && _thread.IsAlive)
            {
                _thread.Join(TimeSpan.FromSeconds(1));
            }

            _thread = null;
            _socket = null;
        }

        public void Dispose()
        {
            Stop();
        }

        /// <summary>
        /// 新しいsnapshotがあれば受け取る。main threadから毎frame呼ぶ。
        ///
        /// 返すinstanceは次の呼び出しまで有効。保持したい値はcopyすること。
        /// </summary>
        public bool TryTakeLatest(out DiviveStageSnapshot snapshot)
        {
            lock (_exchangeLock)
            {
                if (!_hasPending)
                {
                    snapshot = null;
                    return false;
                }

                DiviveStageSnapshot taken = _pending;
                _pending = _consumed;
                _consumed = taken;
                _hasPending = false;
            }

            snapshot = _consumed;
            return true;
        }

        private void Run()
        {
            // Stopがfieldをnilにしたあともthreadが動く可能性がある。
            // 受信threadは開始時のsocketだけを見る。
            Socket socket = _socket;
            if (socket == null)
            {
                return;
            }

            double nextSubscriptionSeconds = 0;

            while (_running)
            {
                double now = ElapsedSeconds();
                if (now >= nextSubscriptionSeconds)
                {
                    TrySendSubscription(unsubscribe: false);
                    nextSubscriptionSeconds = now + KeepaliveIntervalSeconds();
                }

                int received;
                try
                {
                    received = socket.Receive(_receiveBuffer);
                }
                catch (SocketException exception)
                {
                    if (exception.SocketErrorCode == SocketError.TimedOut)
                    {
                        continue;
                    }

                    if (exception.SocketErrorCode == SocketError.ConnectionReset)
                    {
                        // Hubが未起動のときのICMP port unreachable。再購読で回復する。
                        RecordSocketError(exception.SocketErrorCode.ToString());
                        continue;
                    }

                    if (!_running)
                    {
                        return;
                    }

                    RecordSocketError(exception.SocketErrorCode.ToString());
                    continue;
                }
                catch (ObjectDisposedException)
                {
                    return;
                }

                HandleDatagram(received);
            }
        }

        private void HandleDatagram(int length)
        {
            if (!_decoder.TryDecode(_receiveBuffer, length, _decoding, out DiviveDecodeError error))
            {
                lock (_statisticsLock)
                {
                    _statistics.DatagramsReceived++;
                    _statistics.DecodeErrors++;
                    _statistics.LastDecodeError = error;
                }

                return;
            }

            double now = ElapsedSeconds();
            _decoding.ReceivedRealtimeSeconds = now;

            lock (_statisticsLock)
            {
                _statistics.DatagramsReceived++;
                _statistics.FramesApplied++;
                _statistics.LastDecodeError = DiviveDecodeError.None;
                _lastFrameRealtimeSeconds = now;

                if (_hasLastFrame && _lastSessionId == _decoding.SessionId)
                {
                    if (_decoding.FrameSequence > _lastFrameSequence + 1)
                    {
                        _statistics.MissedFrames += _decoding.FrameSequence - _lastFrameSequence - 1;
                    }
                }
                else if (_hasLastFrame)
                {
                    _statistics.SessionResets++;
                }

                _hasLastFrame = true;
                _lastFrameSequence = _decoding.FrameSequence;
                _lastSessionId = _decoding.SessionId;
            }

            lock (_exchangeLock)
            {
                DiviveStageSnapshot filled = _decoding;
                _decoding = _pending;
                _pending = filled;
                _hasPending = true;
            }

            _decoding.Reset();
        }

        private void TrySendSubscription(bool unsubscribe)
        {
            Socket socket = _socket;
            if (socket == null)
            {
                return;
            }

            try
            {
                var builder = new FlatBufferBuilder(128);
                StringOffset name = builder.CreateString(ClampClientName(_settings.ClientName));
                Offset<StageSubscription> root = StageSubscription.CreateStageSubscription(
                    builder,
                    name,
                    _settings.RequestedRateHz,
                    _settings.SubscriptionTtlMilliseconds,
                    unsubscribe);
                builder.Finish(root.Value, DiviveStageWire.SubscriptionFileIdentifier);

                ArraySegment<byte> payload = builder.DataBuffer.ToArraySegment(
                    builder.DataBuffer.Position,
                    builder.Offset);

                int length = DiviveEnvelopeCodec.Encode(
                    _sendBuffer,
                    DiviveMessageType.StageSubscription,
                    _sessionId,
                    _clientId,
                    _subscriptionSequence++,
                    payload.Array,
                    payload.Offset,
                    payload.Count);

                socket.Send(_sendBuffer, 0, length, SocketFlags.None);

                lock (_statisticsLock)
                {
                    _statistics.SubscriptionsSent++;
                }
            }
            catch (SocketException exception)
            {
                RecordSocketError(exception.SocketErrorCode.ToString());
            }
            catch (ObjectDisposedException)
            {
                // 停止処理と競合した場合は何もしない。
            }
        }

        private void RecordSocketError(string description)
        {
            lock (_statisticsLock)
            {
                _statistics.SocketErrors++;
                _statistics.LastSocketError = description;
            }
        }

        private double ElapsedSeconds()
        {
            return _clock.Elapsed.TotalSeconds;
        }

        private double KeepaliveIntervalSeconds()
        {
            // TTLの1/3で更新し、1回の欠落では配信が止まらないようにする。
            return Math.Max(0.05, _settings.SubscriptionTtlMilliseconds / 3000.0);
        }

        private static string ClampClientName(string name)
        {
            if (string.IsNullOrEmpty(name))
            {
                return "unity";
            }

            return name.Length <= DiviveStageWire.MaximumClientNameLength
                ? name
                : name.Substring(0, DiviveStageWire.MaximumClientNameLength);
        }

        private static IPAddress ResolveHost(string host)
        {
            if (IPAddress.TryParse(host, out IPAddress parsed))
            {
                return parsed;
            }

            IPAddress[] addresses = Dns.GetHostAddresses(host);
            if (addresses.Length == 0)
            {
                throw new SocketException((int)SocketError.HostNotFound);
            }

            return addresses[0];
        }

        private static DiviveHubClientSettings Normalize(DiviveHubClientSettings settings)
        {
            if (string.IsNullOrEmpty(settings.Host))
            {
                settings.Host = "127.0.0.1";
            }

            if (settings.Port <= 0 || settings.Port > 65535)
            {
                settings.Port = DiviveStageWire.DefaultPort;
            }

            if (settings.SubscriptionTtlMilliseconds == 0)
            {
                settings.SubscriptionTtlMilliseconds = DiviveStageWire.DefaultSubscriptionTtlMilliseconds;
            }

            settings.SubscriptionTtlMilliseconds = Math.Min(
                Math.Max(
                    settings.SubscriptionTtlMilliseconds,
                    DiviveStageWire.MinimumSubscriptionTtlMilliseconds),
                DiviveStageWire.MaximumSubscriptionTtlMilliseconds);
            return settings;
        }
    }
}
