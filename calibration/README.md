# Calibration golden fixture

Tracker SpaceからStage Spaceへの剛体変換について、実装言語をまたいで共有する
適合性fixtureを置きます。設計の正本は[Calibration](../docs/calibration.md)です。

## ファイル

| ファイル | 内容 |
| --- | --- |
| [golden/transform_v1.cases.json](golden/transform_v1.cases.json) | 変換caseの入力と期待値 |

現在の利用者はSwiftの`HubCalibration`だけです。Unity、Unreal、p5.jsのSDKを実装する
際も、SDKごとに期待値を再定義せず、このファイルを読んで検証します。

## 形式

```json
{
  "formatVersion": 1,
  "cases": [
    {
      "name": "yaw_90_about_up",
      "transforms": [
        { "translation": [0.0, 0.0, 0.0], "rotation": [0.0, 0.7071068, 0.0, 0.7071068] }
      ],
      "input": {
        "position": [1.0, 0.0, 0.0],
        "orientation": [0.0, 0.0, 0.0, 1.0],
        "linearVelocity": [0.0, 0.0, -1.0],
        "angularVelocity": [0.0, 1.0, 0.0]
      },
      "expected": {
        "position": [0.0, 0.0, -1.0],
        "orientation": [0.0, 0.7071068, 0.0, 0.7071068],
        "linearVelocity": [-1.0, 0.0, 0.0],
        "angularVelocity": [0.0, 1.0, 0.0]
      }
    }
  ]
}
```

- `transforms`は合成順で、先頭が最初に適用される
- quaternionは`x, y, z, w`の順
- 単位はm、座標は右手系で`+X`右、`+Y`上、`-Z`前方
- positionはrotationとtranslationを、velocityはrotationだけを受ける

## 期待値の作り方

期待値は実装の出力をそのまま貼らず、人が手で追える値だけを使います。90度回転、
単位ベクトル、整数のtranslationに限定しているのはこのためです。実装が誤った変換を
返した場合にfixtureごと追随してしまうと、golden testの意味がなくなります。

比較時の許容誤差は`1e-5`を目安にします。wire上の姿勢がFloatであることと、
quaternionからの回転計算で下位桁が動くことを見込んだ値です。

quaternion `q`と`-q`は同じrotationです。orientationは成分の一致ではなく、
回転として比較してください。`quaternion_sign_equivalence` caseがこの判定を固定
しています。

## caseを追加するとき

- 期待値を手計算できる構成にする
- 既存caseの名前を変えない（SDK側が名前で必須caseを検査するため）
- `docs/calibration.md`の適合性テスト一覧と対応を保つ
- Swift側の必須case検査（`RigidTransformTests`）へも名前を追加する
