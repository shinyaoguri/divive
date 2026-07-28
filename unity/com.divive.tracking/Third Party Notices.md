# Third Party Notices

## FlatBuffers

`Runtime/ThirdParty/FlatBuffers` はGoogleのFlatBuffers C# runtimeをそのまま同梱した
ものです。`Runtime/Generated` のcodeは、同じreleaseの`flatc`が生成しています。

- Project: https://github.com/google/flatbuffers
- Release: `v25.12.19-2026-02-06-03fffb2`
- Source commit: `03fffb25e2d777462b719cb4964249c30b19d58f`
- License: Apache License 2.0（`Runtime/ThirdParty/FlatBuffers/LICENSE.txt`）
- Copyright 2014 Google Inc.

WindowsのC++ Bridgeと、MacのSwift Hubも同じreleaseへpinしています。版を上げるときは
`protocol/CMakeLists.txt`のpinと合わせて更新し、`protocol/golden`のvectorが
そのままdecodeできることを確認してください。

`UNSAFE_BYTEBUFFER`、`ENABLE_SPAN_T`、`BYTEBUFFER_NO_BOUNDS_CHECK`は定義していません。
bounds checkを有効にしたsafe modeで動かします。
