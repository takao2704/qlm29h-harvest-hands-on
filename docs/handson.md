# QLM29Hの測位データをHarvest Dataへ送る

このページを上から順番に進めます。コマンドは、特に指定がない限りRaspberry Piのターミナルで実行してください。

## 0. 今日作るもの

QLM29Hは測位結果をNMEAというテキスト形式で出力します。Raspberry Piはその中から位置と測位品質を含むGGAセンテンスを選び、JSONへ変換してSORACOM Harvest Dataへ送信します。

このハンズオンでは次の小さな成功を積み重ねます。

1. GPSとは関係のないダミーデータを送る
2. シリアルにデータが流れていることを確認する
3. 必要なGGAだけを取り出す
4. GGAをクラウド向けJSONへ変換する
5. ここまでの処理を1回のコマンドで動かす

最初からすべてを統合しないことで、問題が通信、シリアル、データ変換のどこにあるかを切り分けられます。

### 作業ディレクトリ

まだ取得していない場合は、教材を取得します。

```bash
git clone https://github.com/takao2704/qlm29h-harvest-hands-on.git
cd qlm29h-harvest-hands-on
```

すでに取得済みの場合は、そのディレクトリへ移動します。

```bash
cd ~/qlm29h-harvest-hands-on
```

以降のコマンドは、プロンプトの直前が`qlm29h-harvest-hands-on`になっている状態で実行します。

### 事前確認

```bash
./scripts/00-check-environment.sh
```

最後に次の表示が出れば準備完了です。

```text
[確認] ハンズオンを開始できる状態です。
```

問題があった場合は[トラブルシューティング](troubleshooting.md)を参照します。

## 1. Harvest Dataを有効にする

この章の操作はSORACOMユーザーコンソールで行います。画面の名称は更新で変わることがあるため、見つからない場合は公式の[データを蓄積する手順](https://users.soracom.io/ja-jp/guides/getting-started/send-data-to-harvest-data/)も参照してください。

### 1-1. SIMをグループへ所属させる

1. [SORACOMユーザーコンソール](https://console.soracom.io/)へログインします。
2. 使用するIoT SIMを確認します。
3. ハンズオン用のグループを新規作成するか、既存グループを選びます。
4. 使用するSIMをそのグループへ所属させます。

複数人で同じアカウントを使う場合は、講師が指定したSIMとグループの組み合わせを使ってください。他のSIMのグループを変更しないよう注意します。

### 1-2. Harvest Dataを有効にする

1. SIMが所属するグループの設定画面を開きます。
2. `SORACOM Harvest Data`の設定を開きます。
3. Harvest Dataを有効にします。
4. 設定を保存します。

Unified Endpoint自体はグループごとの追加設定なしで利用できます。データの保存先としてHarvest Dataを有効にすることで、`uni.soracom.io`へ送ったデータがHarvest Dataへ保存されます。

### 1-3. ダミーデータを送る

Raspberry Piから`curl`コマンドでJSONを直接送信します。

```bash
curl -i -X POST \
  -H 'Content-Type: application/json' \
  -d '{"temperature":20}' \
  http://uni.soracom.io
```

レスポンスの先頭付近に次のステータスが表示されることを確認します。

```text
HTTP/1.1 201 Created
```

値を変える場合は、`-d`に指定したJSONの数値を書き換えて、もう一度実行します。

```bash
curl -i -X POST \
  -H 'Content-Type: application/json' \
  -d '{"temperature":23.5}' \
  http://uni.soracom.io
```

- `POST`: データを送信するHTTPメソッド
- `Content-Type`: 送るデータがJSONであることを示すヘッダー
- `-d`: 送信する本文
- `http://uni.soracom.io`: SORACOM Unified Endpoint

このHTTPエンドポイントはSORACOM Airのネットワーク内で利用します。インターネット上へ認証情報なしで公開されたエンドポイントではありません。

### 1-4. Harvest Dataで確認する

1. ユーザーコンソールでHarvest Dataの画面を開きます。
2. ハンズオンで使用しているSIMを選びます。
3. 直近のデータとして`temperature`が表示されることを確認します。

表示まで少し時間がかかる場合は画面を更新します。それでも見えない場合は、HTTPステータスと選択中のSIMを確認します。

ここまでで、GPSとは無関係な「Raspberry Piからクラウドへ送る経路」が動作しました。

## 2. QLM29Hのデータを受信する

### 2-1. シリアルポートを確認する

QLM29Hを接続した状態で、候補を表示します。

```bash
ls -l /dev/serial/by-id/
```

1つだけならスクリプトが自動検出します。複数ある場合は使用するポートを指定します。

```bash
export SERIAL_PORT=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
```

`/dev/serial/by-id/`の名前は、USBの接続順が変わっても比較的安定しています。表示された実際の名前をコピーしてください。

### 2-2. NMEAを表示する

```bash
./scripts/02-show-nmea.sh
```

既定では115200 bpsで5秒間表示します。次のように`$`で始まる複数種類の行が流れます。

```text
$GNRMC,...
$GNGSA,...
$GPGSV,...
$GNGGA,...
```

#### `02-show-nmea.sh`の内容を確認する

実行した[`scripts/02-show-nmea.sh`](../scripts/02-show-nmea.sh)は、次の処理を行っています。

```bash
#!/usr/bin/env bash

# コマンドの失敗、未設定変数、パイプ途中の失敗を検出する
set -euo pipefail

# どのディレクトリから実行しても共通処理を読み込めるよう、
# このスクリプト自身が置かれているディレクトリを取得する
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/common.sh"

# NMEA表示に必要なコマンドが使えることを確認する
require_command timeout
require_command stty

# 読み取り時間は環境変数で変更でき、未指定時は5秒とする
read_timeout=${SERIAL_READ_TIMEOUT:-5}
require_positive_number "$read_timeout" SERIAL_READ_TIMEOUT

# QLM29Hのシリアルポートを特定し、既定115200 bpsのrawモードに設定する
port=$(resolve_serial_port)
configure_serial_port "$port"

# 使用するポート、通信速度、読み取り時間を表示する
info "${port} を ${SERIAL_BAUD:-115200} bpsで ${read_timeout}秒間読み取ります。"
printf '%s\n' '--- NMEA受信開始 ---'

# timeoutによる予定どおりの終了（終了コード124）を自分で判定するため、
# この区間だけエラー時の自動終了を無効にする
set +e
# シリアルから届く文字を表示し、NMEA行末のCRを取り除く
timeout "${read_timeout}s" cat "$port" | sed 's/\r$//'
# パイプ左側にあるtimeoutコマンドの終了コードを保存する
read_status=${PIPESTATUS[0]}
set -e

printf '%s\n' '--- NMEA受信終了 ---'
# 0（通常終了）と124（時間切れ）以外は読み取りエラーとして終了する
if ((read_status != 0 && read_status != 124)); then
  error "シリアル読み取りに失敗しました（終了コード: ${read_status}）。"
  exit 1
fi
```

上から順に役割を見ていきます。

| 処理 | 役割 |
|---|---|
| `#!/usr/bin/env bash` | このファイルをBashで実行します。 |
| `set -euo pipefail` | コマンドの失敗、未設定変数、パイプ途中の失敗を見逃しにくくします。 |
| `SCRIPT_DIR=...` | どのディレクトリから実行しても、スクリプト自身が置かれた場所を取得します。 |
| `source .../common.sh` | ポート検出、シリアル設定、エラー表示などの共通関数を読み込みます。 |
| `require_command` | この処理で使う`timeout`と`stty`がインストール済みか確認します。 |
| `read_timeout=${SERIAL_READ_TIMEOUT:-5}` | 環境変数がなければ、読み取り時間を5秒にします。 |
| `port=$(resolve_serial_port)` | `SERIAL_PORT`の指定を使うか、USBシリアルポートを自動検出します。 |
| `configure_serial_port "$port"` | ポートを既定115200 bpsのrawモードに設定します。 |
| `timeout ... cat "$port"` | 指定時間だけシリアルポートを開き、届いた文字をそのまま表示します。 |
| `sed 's/\r$//'` | NMEAの行末にあるCRを取り除き、ターミナルで読みやすくします。 |
| `read_status=${PIPESTATUS[0]}` | パイプ左側の`timeout`の終了状態を保存します。 |
| `set +e` / `set -e` | `timeout`の終了状態を自分で判定する間だけ、自動終了を一時的に無効化し、その後元へ戻します。 |
| 最後の`if` | 予定した時間切れ以外の読み取りエラーだけを異常終了にします。 |

`configure_serial_port`の内部では、次の`stty`相当の設定を行っています。

```bash
baud=${SERIAL_BAUD:-115200}
stty -F "$port" "$baud" raw -echo -ixon -ixoff
```

- `115200`: QLM29Hと合わせる既定の通信速度です。
- `raw`: 受信文字を端末側で変換せず、そのまま読みます。
- `-echo`: 受信文字をシリアル側へ送り返しません。
- `-ixon -ixoff`: XON/XOFFによるソフトウェアフロー制御を無効にします。

`timeout`は指定時間が経過すると終了コード`124`を返します。このスクリプトでは「5秒間の表示が予定どおり終わった」ことを意味するため、エラーにはしていません。それ以外の失敗だけを最後の`if`でエラーにします。

この段階ではNMEAの内容を解析していません。`cat`で受信した全文を観察し、次の章でGGAだけを取り出します。

この1行ずつをNMEAセンテンスと呼びます。代表的なセンテンスは次のとおりです。

| 種類 | 正式名称 | 日本語での意味 | 主な内容 |
|---|---|---|---|
| GGA | Global Positioning System Fix Data | GPS/GNSSの測位結果データ | 時刻、緯度、経度、測位品質、衛星数、高度 |
| RMC | Recommended Minimum Specific GNSS Data | 推奨される最小限のGNSSデータ | 時刻、日付、位置、速度、進行方向 |
| GSA | GNSS DOP and Active Satellites | GNSSの精度指標と測位使用衛星 | 測位に使用する衛星と精度指標 |
| GSV | GNSS Satellites in View | 受信機から見えているGNSS衛星 | 観測している衛星の情報 |

これらはNMEAでセンテンスの種類を表す3文字の識別子です。必ずしも各文字が英単語の頭文字と一対一で対応する略語ではありません。例えばGGAの正式名称は`Global Positioning System Fix Data`です。また、GSAに含まれるDOPは`Dilution of Precision`の略で、衛星の配置によって測位精度がどの程度低下しやすいかを表す指標です。

今回は現在位置とRTK状態を1行で確認できるGGAを使います。

受信できない場合は次へ進む前に[「NMEAが表示されない」](troubleshooting.md#nmeaが表示されない)を確認してください。

## 3. 必要なGGAを取り出す

### 3-1. 実機から取り出す

```bash
./scripts/03-show-gga.sh
```

表示例:

```text
$GNGGA,030405.000,3540.874160,N,13946.027500,E,4,24,0.60,12.3,M,39.5,M,1.0,0001*63
```

### 3-2. サンプルから取り出す

実機で受信できない場合や、同じ入力で繰り返し確認したい場合に使用します。

```bash
./scripts/03-show-gga.sh --input samples/nmea-stream.nmea
```

`nmea-stream.nmea`には複数種類のセンテンスがありますが、最初のGGAだけが表示されます。

### 3-3. GGAのフィールドを読む

GGAはカンマで区切られています。

```text
$GNGGA,UTC,緯度,N/S,経度,E/W,quality,衛星数,HDOP,高度,M,...*チェックサム
```

先ほどの例では次の意味になります。

| 項目 | 値 | 意味 |
|---|---:|---|
| UTC | `030405.000` | 03時04分05.000秒（UTC） |
| 緯度 | `3540.874160,N` | 北緯35度40.874160分 |
| 経度 | `13946.027500,E` | 東経139度46.027500分 |
| quality | `4` | Fixed RTK |
| 衛星数 | `24` | 測位に使用した衛星数 |
| HDOP | `0.60` | 水平方向の衛星配置による精度指標 |
| 高度 | `12.3,M` | 平均海面から12.3 m |

主なquality値:

| 値 | 状態 |
|---:|---|
| 0 | No Fix。位置を確定できていない |
| 1 | 単独測位 |
| 2 | DGPS / SBASなど |
| 4 | Fixed RTK。整数アンビギュイティが確定 |
| 5 | Float RTK。整数アンビギュイティが未確定 |
| 6 | 推測航法 |

`quality=4`だけが「常に正しい位置」を保証するわけではありません。アンテナ環境、補正情報、HDOP、衛星数なども合わせて評価します。

末尾の`*63`はチェックサムです。`$`と`*`の間の文字から計算し、通信中の破損検出に使います。本編のスクリプトはフィールド構造と値を検証し、完全なチェックサム検証は実運用時の追加事項として扱います。

## 4. GGAをJSONへ変換する

### 4-1. 度分から十進数度へ変換する

GGAの緯度経度は、度と分を続けた形式です。地図やWeb APIで一般的な十進数度へ変換します。

```text
十進数度 = 度 + 分 ÷ 60
```

緯度`3540.874160,N`の場合:

```text
35 + 40.874160 ÷ 60 = 35.681236
```

経度`13946.027500,E`の場合:

```text
139 + 46.027500 ÷ 60 = 139.767125
```

南緯`S`と西経`W`は負数にします。

### 4-2. サンプルをJSONへ変換する

```bash
./scripts/04-format-gga.sh --input samples/fixed-rtk.nmea
```

出力は改行を除いて1行のJSONです。

```json
{"source":"qlm29h-gga","lat":35.68123600,"lon":139.76712500,"quality":4,"quality_label":"Fixed RTK","satellites":24,"hdop":0.60,"altitude_m":12.3,"utc_time":"03:04:05.000Z"}
```

Harvest DataはJSON内の数値をグラフにできます。`lat`と`lon`は地図表示に利用します。送信サイズの上限を考え、元のGGA全文は含めず、必要な項目だけにしています。

#### `04-format-gga.sh`の処理を確認する

実行した[`scripts/04-format-gga.sh`](../scripts/04-format-gga.sh)は、次の順番で処理します。

```text
fixed-rtk.nmea
    ↓ GGAを1行抽出
$GNGGA,030405.000,3540.874160,N,...
    ↓ カンマで分割・検証・座標変換
{"source":"qlm29h-gga","lat":35.68123600,"lon":139.76712500,...}
```

##### 1. `--input`で指定されたファイルを受け取る

最初の部分はコマンドライン引数を確認します。

```bash
input_file=''
if (($# > 0)); then
  if [[ ${1:-} == '--input' && $# == 2 ]]; then
    input_file=$2
  else
    error '使い方: 04-format-gga.sh [--input FILE]'
    exit 2
  fi
fi
```

このハンズオンで実行したコマンドでは、引数は次のように対応します。

```text
$1 = --input
$2 = samples/fixed-rtk.nmea
$# = 2（引数の個数）
```

`--input`とファイル名の2つが揃っていなければ、使い方を表示して終了します。

##### 2. ファイルからGGAを1行取り出す

```bash
if [[ -n "$input_file" ]]; then
  gga=$(extract_first_gga_from_file "$input_file")
else
  # --inputがない場合は、標準入力から最初のGGAを探す
  # ...
fi
```

`extract_first_gga_from_file`は共通処理`common.sh`に定義されています。ファイルを読み、`$GNGGA,`などで始まる最初のGGAセンテンスを返します。

`--input`を付けない場合は標準入力を読みます。そのため、次の章では`03-show-gga.sh`の出力をパイプで渡せます。

```bash
./scripts/03-show-gga.sh | ./scripts/04-format-gga.sh
```

##### 3. GGAをカンマで分割する

抽出したGGAをAWKへ渡します。

```bash
printf '%s\n' "$gga" | awk -F, '
  # AWKの処理
'
```

`-F,`は、カンマをフィールドの区切り文字にする指定です。例えば、次のGGAを渡したとします。

```text
$GNGGA,030405.000,3540.874160,N,13946.027500,E,4,24,0.60,12.3,M,...
```

AWKの中では各項目が次の変数に入ります。

| AWKの表記 | GGAの値 | スクリプト内の変数 | 意味 |
|---|---|---|---|
| `$1` | `$GNGGA` | ― | センテンスの種類 |
| `$2` | `030405.000` | `utc` | UTC時刻 |
| `$3` | `3540.874160` | `lat_raw` | 変換前の緯度 |
| `$4` | `N` | `north_south` | 北緯・南緯 |
| `$5` | `13946.027500` | `lon_raw` | 変換前の経度 |
| `$6` | `E` | `east_west` | 東経・西経 |
| `$7` | `4` | `quality` | 測位品質 |
| `$8` | `24` | `satellites` | 使用衛星数 |
| `$9` | `0.60` | `hdop` | 水平精度指標 |
| `$10` | `12.3` | `altitude` | 高度 |

ここでの`$1`や`$2`はAWKが分割したフィールドです。先ほどのShellの`$1`や`$2`はコマンドライン引数なので、同じ表記でも意味が異なります。

実際の代入部分は次のとおりです。

```awk
utc = $2
lat_raw = $3
north_south = $4
lon_raw = $5
east_west = $6
quality = $7
satellites = $8
hdop = $9
altitude = $10
```

##### 4. 送信してよい値か検証する

スクリプトはJSONを作る前に、主に次を確認します。

- GGAセンテンスである
- 必要な数のフィールドがある
- `quality`が整数で、No Fixを表す`0`ではない
- 緯度の方位が`N`または`S`
- 経度の方位が`E`または`W`
- UTC時刻、緯度、経度が正しい形式と範囲にある

検証に失敗した場合は`fail`関数が理由を表示し、JSONを出力せず終了します。

```awk
function fail(message, code) {
  print "[エラー] " message > "/dev/stderr"
  exit code
}
```

衛星数、HDOP、高度は空欄になることがあります。`optional_number`関数は空欄をJSONの`null`へ変換します。

```awk
function optional_number(value, label) {
  if (value == "") {
    return "null"
  }
  if (!is_number(value)) {
    fail(label "が数値ではありません: " value, 2)
  }
  return value
}
```

##### 5. 緯度経度を十進数度へ変換する

`coordinate`関数が、前節で確認した「度 + 分 ÷ 60」を実行します。

```awk
degrees = substr(value, 1, degree_digits) + 0
minutes = substr(value, degree_digits + 1) + 0
result = degrees + minutes / 60

if (direction == "S" || direction == "W") {
  result = -result
}
```

- 緯度は先頭2桁を度として読みます。
- 経度は先頭3桁を度として読みます。
- 残りを分として60で割ります。
- 南緯`S`または西経`W`なら負数にします。

呼び出し時の`2, 90`と`3, 180`は、それぞれ度の桁数と許容する最大値です。

```awk
lat = coordinate(lat_raw, north_south, 2, 90, "緯度")
lon = coordinate(lon_raw, east_west, 3, 180, "経度")
```

##### 6. JSONを1行で出力する

最後に`printf`でJSONを組み立てます。

```awk
printf "{\"source\":\"qlm29h-gga\",\"lat\":%.8f,\"lon\":%.8f,", lat, lon
printf "\"quality\":%d,\"quality_label\":\"%s\",", quality, quality_label(quality)
printf "\"satellites\":%s,\"hdop\":%s,\"altitude_m\":%s,", satellites_json, hdop_json, altitude_json
printf "\"utc_time\":\"%s\"}\n", utc_formatted
```

`%.8f`は緯度経度を小数点以下8桁で表示する指定です。`quality_label`関数は、例えば`quality=4`を`Fixed RTK`という読みやすい文字列へ変換します。

このスクリプトの標準出力はJSONだけです。そのため、次の送信スクリプトは出力をそのままHTTPリクエストの本文として使用できます。

### 4-3. 実機のGGAをJSONへ変換する

2つのスクリプトを`|`で接続します。

```bash
./scripts/03-show-gga.sh | ./scripts/04-format-gga.sh
```

`|`は左側の標準出力を右側の標準入力へ渡します。この形がゲートウェイの「受信 → 抽出 → 変換」に相当します。

No Fixの場合はJSONを作らず、次のように終了します。

```text
[エラー] quality=0（No Fix）のため送信データを作成しません。
```

屋外へ移動してアンテナの上空を開けるか、Fixed RTKのサンプルで先へ進んでください。

## 5. 測位データを1ショットで送信する

### 5-1. サンプルで処理全体を確認する

```bash
./scripts/05-send-position-once.sh --input samples/fixed-rtk.nmea
```

このコマンドは次の処理を1回だけ実行します。

1. ファイルからGGAを探す
2. 緯度経度と各フィールドを検証する
3. Harvest Data向けJSONへ変換する
4. Unified EndpointへHTTP POSTする

`[成功] HTTP 201`または別の2xxが表示されることを確認します。

### 5-2. 実機データを送信する

```bash
./scripts/05-send-position-once.sh
```

今度はファイルではなくQLM29HのシリアルからGGAを1件受信して送ります。連続送信ではないため、もう1件送りたい場合はコマンドをもう一度実行します。

### 5-3. Harvest Dataで位置を確認する

1. Harvest Dataの画面で使用中のSIMを選びます。
2. 最新データに`source`、`lat`、`lon`、`quality`などがあることを確認します。
3. 地図表示を選び、送信した位置が表示されることを確認します。
4. `quality`と`quality_label`でFixed RTKまたはFloat RTKかを確認します。

サンプルの位置は教材用の固定値です。実機データと取り違えないよう、`source`と実行したコマンドを確認してください。

### 5-4. 応用: Unified Endpointを変えずにAWSへ転送する

SIMグループでSORACOM Funnelを追加すると、Raspberry Piの送信先を変更せず、同じ測位JSONをHarvest DataとAWSの両方へ送れます。

```text
Raspberry Pi → Unified Endpoint ┬→ Harvest Data
                               └→ Funnel → AWS IoT Core → Firehose → S3（JSONL）
```

Raspberry Piで実行するコマンドは、5-2と同じです。

```bash
./scripts/05-send-position-once.sh
```

S3は通常、1つのファイルへ1行ずつ追記するのではなく、Firehoseが複数レコードを改行で連結し、`.jsonl`オブジェクトを順次作成します。設定方法と確認ポイントは[Unified Endpointを変えずにAWS IoT Core経由でS3へ蓄積する](funnel-iot-core-s3.md)で説明します。

## 6. エラーハンドリングと再送を考える

本編のスクリプトは学習用のため、失敗するとその場で停止し、自動再送しません。実際のゲートウェイでは、通信が一時的に切れてもシリアルデータは流れ続けます。HTTP送信を待つ間に受信を止めると、測位データを失う可能性があります。

実運用では次のように役割を分けます。

```text
QLM29H受信プロセス → JSONファイルをspoolへ保存
                                  ↓
HTTP送信プロセス   ← 古いJSONから順番に送信
```

- 2xxならspoolから削除する
- DNSエラー、接続エラー、5xxは待ち時間を増やしながら再送する
- 4xxは設定やデータの修正が必要な可能性が高いため、無限再送しない
- timeoutではサーバーが受信済みか不明なため、重複送信を許容する設計にする
- spoolの容量上限と、満杯になったときの破棄方針を決める

詳しくは[エラーハンドリングと再送の設計](reliability-design.md)を読みます。

## 7. 後片付け

ハンズオン専用のSIMグループを作成した場合は、講師の指示に従い、終了後にHarvest Dataを無効化またはSIMの所属グループを元へ戻してください。
