# 実機検証の記録

実機検証は`docs/hardware-validation.md`に従い、再現手順と判定を残します。

## 新しい検証run

`templates`を`runs/YYYY-MM-DD-machine-test`へコピーします。

```powershell
$run = "hardware-tests\runs\2026-07-23-windows-h1"
New-Item -ItemType Directory -Force $run
Copy-Item hardware-tests\templates\* $run
New-Item -ItemType Directory -Force "$run\raw"
New-Item -ItemType Directory -Force "$run\screenshots"
```

記録対象:

- `environment.md`: hardware、OS、runtime、firmware
- `procedure.md`: 実際に実行した再現可能な手順
- `result.md`: PASS / FAIL / INCONCLUSIVEと設計への影響
- `raw/`: JSONLやruntime log。Gitではignore
- `screenshots/`: 補助証跡。Gitではignore

大きなraw dataはGitHub artifactなどへ保存し、`result.md`へSHA-256と保管先を記録します。

## M0 OpenVR probe

[OpenVR実機検証probe](../bridge/probes/openvr/README.md)をbuildし、最初は全deviceを記録します。

```powershell
.\dist\windows-tools\divive-openvr-probe.exe `
  --all-devices `
  --rate 120 `
  --duration 60 `
  --output "$run\raw\openvr-all-devices.jsonl"
```

結果を確認してから、Trackerだけの30分試験へ進みます。
