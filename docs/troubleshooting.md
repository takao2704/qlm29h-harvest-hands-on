# トラブルシューティング

問題が起きた場所を「事前確認」「HTTP送信」「シリアル受信」「GGA変換」「Harvest Data表示」に分けて確認します。

## `00-check-environment.sh`が失敗する

### 必須コマンドがない

Raspberry Pi OSで次を実行します。

```bash
sudo apt update
sudo apt install -y curl coreutils gawk grep sed libc-bin
```

インストール後、もう一度確認します。

```bash
./scripts/00-check-environment.sh
```

### `uni.soracom.io`を名前解決できない

- SORACOM AirのIoT SIMが通信中か確認します。
- Raspberry Piのデフォルト経路が意図したセルラーインターフェースか確認します。
- 通常のWi-Fiや有線インターネットだけで実行していないか確認します。

```bash
getent ahostsv4 uni.soracom.io
ip route
```

SORACOM経由では、Unified Endpointは通常`100.127.x.x`のプライベートアドレスとして名前解決されます。

## HTTP送信に失敗する

### `curl: (6) Could not resolve host`

DNSまたはSORACOM Airの通信経路を確認します。エンドポイントのスペルは`http://uni.soracom.io`です。

### `curl: (7) Failed to connect`

- SIMのセッションがオンラインか確認します。
- セルラーアンテナ、USBモデム、電源を確認します。
- VPGやアウトバウンドフィルターを使用している場合は、Unified Endpointへの通信が許可されているか確認します。

### HTTP 400

主に次を確認します。

- 使用しているSIMが正しいグループへ所属している
- そのグループでHarvest Dataが有効
- `Content-Type: application/json`が付いている
- JSONが壊れていない
- 送信データが1024バイト以内

### HTTP 500番台

一時的なサービス側エラーや経路上の問題が考えられます。本教材のスクリプトは自動再送しないため、状態を確認してから手動でもう一度実行します。

## シリアルポートが見つからない

USB接続前後の差を確認します。

```bash
ls -l /dev/serial/by-id/ 2>/dev/null
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

候補が出ない場合:

- USBケーブルが通信対応か確認する
- QLM29HとUSBシリアル変換器の電源を確認する
- USBハブを外して直接接続する
- `dmesg --follow`を実行してからUSBを挿し直す

## シリアルポートが複数ある

使用するポートを環境変数で指定します。

```bash
export SERIAL_PORT=/dev/serial/by-id/実際に表示された名前
```

指定は現在のターミナルだけで有効です。新しいターミナルを開いた場合は、もう一度設定します。

## Permission deniedが出る

現在のユーザーを`dialout`グループへ追加します。

```bash
sudo usermod -aG dialout "$USER"
```

設定反映のため、いったんログアウトしてログインし直します。その後で確認します。

```bash
groups
```

一時的に`sudo`でスクリプト全体を動かす方法は、環境変数や作成ファイルの所有者が変わるため推奨しません。

## ポートが使用中と表示される

1つのシリアルポートを複数のプログラムが同時に読むと、各プログラムへデータが分散したり、ポートを開けなかったりします。

```bash
fuser /dev/ttyUSB0
```

既存のQLM29H送信サービスを使っている場合は、講師の指示に従ってハンズオン中だけ停止します。

```bash
sudo systemctl stop qlm29h-nmea-unified.service
```

終了後は必要に応じて再開します。

```bash
sudo systemctl start qlm29h-nmea-unified.service
```

サービス名は環境によって異なります。分からないサービスを停止しないでください。

## NMEAが表示されない

### ボーレートを確認する

本教材の既定値は115200 bpsです。機器設定が異なる場合だけ変更します。

```bash
export SERIAL_BAUD=115200
```

### 読み取り時間を延ばす

```bash
export SERIAL_READ_TIMEOUT=30
./scripts/02-show-nmea.sh
```

### 文字化けする

ボーレートが一致しているか確認します。正しいポートを選んでいるかも確認してください。

## GGAが見つからない

NMEAは流れているのにGGAがない場合、QLM29HのNMEA出力設定でGGAが無効になっている可能性があります。ハンズオン機材の準備担当者へ確認してください。

サンプルで後続の演習を続けられます。

```bash
./scripts/03-show-gga.sh --input samples/nmea-stream.nmea
```

## `quality=0（No Fix）`になる

QLM29Hが位置を確定できていません。

- GNSSアンテナを屋外または窓際の上空が開けた場所へ移動する
- アンテナ接続を確認する
- 数分待ってから再実行する
- 金属屋根、ビル、高い壁から離れる

測位できるまで、次のサンプルで変換と送信を進められます。

```bash
./scripts/05-send-position-once.sh --input samples/fixed-rtk.nmea
```

## qualityが4または5にならない

単独測位の`quality=1`は取得できているがRTKにならない場合、GNSS受信ではなく補正経路を確認します。

- NTRIP接続が確立している
- RTCM補正データがQLM29Hへ書き込まれている
- NTRIP casterへ最新GGAを返している
- 補正サービスの対応エリア内にいる
- アンテナの上空視界が確保されている

NTRIP接続の構築は本教材の対象外です。準備担当者へ確認してください。

## JSON変換に失敗する

### フィールド数が不足

受信途中で切れた行や、GGAではないデータを入力している可能性があります。元のNMEAを表示して確認します。

```bash
./scripts/02-show-nmea.sh
```

### 緯度・経度が数値ではない

No Fixや破損したセンテンスの可能性があります。GGAのqualityと座標欄を確認します。

### 任意項目が空欄

衛星数、HDOP、高度が空欄の場合、JSONでは`null`になります。緯度、経度、方位、UTC、qualityは必須です。

## Harvest Dataにはあるが地図に出ない

- JSONのキーが`lat`と`lon`になっているか確認する
- 2つの値が文字列ではなく数値として保存されているか確認する
- 緯度が-90〜90、経度が-180〜180の範囲か確認する
- 表示期間に最新データの時刻が含まれているか確認する

GGAには日付が含まれません。本教材はHarvest Dataが受信した時刻をデータ時刻として使用し、GGAの`utc_time`は参考値として保存します。

## 問題を報告するとき

認証情報、IMSI、正確な自宅位置などを削除したうえで、次を共有します。

- 実行したコマンド
- エラーメッセージ全文
- Raspberry Pi OSのバージョン
- 使用したシリアルポート名とボーレート
- GGAの匿名化した1行
- HTTPステータス
