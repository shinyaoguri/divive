# divive Unity SDK

Mac Hubが配信するStage Spaceの6DoF姿勢を、Unityで受け取るためのSDKと、動作確認用の
サンプルプロジェクトです。SteamVRやVIVE固有の処理は含みません。

| 場所 | 内容 |
| --- | --- |
| [com.divive.tracking](com.divive.tracking) | UPM package本体 |
| [DiviveSample](DiviveSample) | Play押下で動作確認できるUnityプロジェクト |

## 動作確認の手順

実機もWindowsも不要です。Simulatorが生成した姿勢をHubからUnityへ配信します。

1. Hubから配信を開始する。

```bash
swift run --package-path hub divive-simulator --trackers 3 --motion circle --publish
```

2. Unity Hubで `unity/DiviveSample` を追加して開く。
3. Play を押す。3台のTrackerが円運動し、画面左上に接続状態が出ます。

停止するときはPlayを止めてから、Simulator側でControl-Cを押します。

サンプルはsceneをassetとして持たず、Play時に`DiviveSampleBootstrap`が床・カメラ・
接続componentを組み立てます。空のsceneのままPlayしても動きます。

サンプルはBuilt-in Render Pipelineを前提にしています。`GameObject.CreatePrimitive`が
付ける既定materialをそのまま使うため、URPやHDRPを入れると表示がmagentaになります。
`Packages/manifest.json`へrender pipeline packageを足す場合は、materialも
そのpipeline用に差し替えてください。

## パッケージを自分のプロジェクトで使う

`Packages/manifest.json`へ相対パスで追加します。

```json
{
  "dependencies": {
    "com.divive.tracking": "file:../../divive/unity/com.divive.tracking"
  }
}
```

最小の使い方は次のとおりです。

```csharp
using Divive.Tracking;
using UnityEngine;

public sealed class FollowWaist : MonoBehaviour
{
    [SerializeField] private DiviveHubConnection connection;

    private void LateUpdate()
    {
        if (connection.TryGetTrackerByRole("waist", out DiviveTrackerState tracker)
            && tracker.IsPoseUsable)
        {
            transform.SetPositionAndRotation(tracker.Position, tracker.Rotation);
        }
    }
}
```

`DiviveTrackerBinding`をGameObjectへ付ければ、同じことをcodeなしでできます。

## public contract

### 接続

- transportはlocalhost UDP。既定portは`41321`
- clientが購読messageを送り、TTL（既定3秒）内に更新し続ける間だけHubが配信する
- Hubは既定でloopbackからの購読しか受け付けない
- `DiviveHubConnection`は`OnEnable`で接続し、`OnDisable`で購読を解除する

### 最新値のみ

Hubは過去のframeを再送しません。SDKも受信threadでlatest valueだけを保持し、
main threadへ渡します。描画が遅れても古い姿勢が後追いで再生されることはありません。

`DiviveHubClient`は受信・共有・消費で3つのsnapshotを持ち回し、定常状態では
frameごとのallocationが発生しません。Tracker IDとroleのstringも内容が同じなら
同じinstanceを返します。

### thread

受信は専用threadで行いますが、eventとpropertyはすべてmain threadから読みます。
`DiviveHubConnection`が毎frameのUpdateで取り込み、そのあとでeventを発火します。
UnityのAPIをそのまま呼んで構いません。

### 座標

canonicalは右手系で`-Z`前方、Unityは左手系で`+Z`前方です。SDK境界で変換するため、
contentは変換を意識する必要はありません。変換の内訳は次のとおりです。

| 量 | 変換 |
| --- | --- |
| 位置、線速度 | `(x, y, -z)` |
| 姿勢quaternion | `(-x, -y, z, w)` |
| 角速度 | `(-x, -y, z)` |

角速度は軸性vectorなので、位置と同じ式では姿勢の時間変化と整合しません。
`DiviveCoordinatesTests`が、変換した角速度で積分した姿勢と、変換した姿勢が
一致することを確認しています。

### 配信区分

`DiviveTrackerState.Delivery`はHubの較正状態を表します。

| 値 | 意味 |
| --- | --- |
| `Stage` | 較正済み。Stage Spaceの値 |
| `RawTrackerSpace` | Hubがpreview mode。較正していないTracker Spaceの値 |
| `Blocked` | 未較正またはepoch不一致。姿勢を配信しない |

`Blocked`のTrackerも一覧には残ります。姿勢は`HasPose == false`で入りません。
「表示されない」理由をcontentとoperatorが説明できるようにするためです。

Simulatorは較正profileを持たないため、既定では`RawTrackerSpace`になります。

### 追跡状態

`IsPoseUsable`は`HasPose`かつ`TrackingState`が`Tracking`か`Simulated`のときだけ
trueです。追跡喪失中もHubは最後の姿勢を配信し続けるので、位置の変化だけで
追跡できているかを判断しないでください。

`Liveness`は受信ageによる評価で、`TrackingState`とは独立です。光学的な追跡喪失と
ネットワーク上の停止を混同しないために分けています。

### 補間

時刻に基づく補間は提供しません。WindowsとMacのclock mappingが入るまで、描画時刻へ
正しく合わせられないためです。`DiviveTrackerBinding`の平滑化は見た目のための
指数平滑であり、予測ではありません。既定は無効です。

## テスト

Unity Editorを開ける場合は、`unity/DiviveSample`でTest Runner（EditMode）を実行します。

Editorのlicenseがない環境では、Unity同梱のRoslynと.NET runtimeで同じsourceを
compileして実行できます。

```bash
python3 scripts/run_unity_package_tests.py
```

Hubの実配信をSDKで受信できることは、次で確認します。`divive-simulator`を
起動してUDP越しに受信し、frame数、decode error、位置の変化を検査します。

```bash
python3 scripts/check_stage_end_to_end.py
```

どちらもMonoBehaviourの挙動やEditor統合までは検証しません。componentを含む確認は
Unity Editorでsampleを動かしてください。

## 制約

- 検証したUnityは`6000.4.7f1`です。`package.json`の最小versionは`2022.3`ですが、
  それより古い環境での動作は確認していません
- `.meta`はcommitしていません。Editorで最初に開いたときに生成されます
- 認証はありません。LANへ広げる場合はHub側にHMACとtokenが入るまで待ってください
- 実機Bridgeとの結合はまだ検証していません。Windows実機が来た時点で確認します

## 依存

FlatBuffersのC# runtimeを`Runtime/ThirdParty/FlatBuffers`へ同梱しています。
ライセンスと版は[Third Party Notices](com.divive.tracking/Third%20Party%20Notices.md)を
参照してください。
