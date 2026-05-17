# PoC-0011_Spec（方向を見ないEntry & 継続動意ExitのPoC実装仕様）

## Purpose（目的）

方向を一切見ない Entry 条件（動意ベース）でポジションを仮想保有し、first-touch（±0.03円）以降の「継続動意」を用いた Exit ロジックの候補とその統計的裏付けを得る。

- Entry：方向（UP/DOWN）を問わない動意条件のみで発火
- first-touch：Entry価格基準 ±0.03円 への到達で方向ラベル確定
- Exit観測：first-touch後の継続動意（10秒足／1分足／5分足）をウィンドウ別に記録
- 実売買なし。CSVログへの記録・集計が成果物

---

## Implementation（実装内容）

### ベースコードからの変更方針

`SimpleOutcome/PoC-0010` のベースコード（`PoC-0001_base.mq5`）を差分修正する。主な変更点は以下の通り：

1. **Entry条件の変更**：前回M1終値との比較による方向判定 → 動意スコアによる無方向 Entry
2. **Struct の拡張**：継続動意フィールドを追加（first-touch後3ウィンドウ×複数指標）
3. **CSVヘッダ・LogSession の更新**：新フィールドに対応
4. **ファイル名変更**：`PoC-0010_log.csv` → `PoC-0011_log.csv`
5. **時刻をJST基準に統一**：`TimeToStruct()` + UTC+9 変換を全箇所に適用
6. **シンボル前提をUSDJPYに変更**：価格スケール・閾値をすべてUSDJPY（2桁通貨・円単位）で設定

---

### 2-1. Entry条件（無方向・動意ベース）

Tick ごとに以下をすべて満たしたとき Entry 発火（`entry_direction = 0` で記録）。

|条件|ハードコード値|意味|
|---|---|---|
|直近10秒足値幅|`>= 0.03円`|動いている状態（USDJPY・3銭）|
|10秒足MACD hist絶対値|`MathAbs(macd10s_hist) >= 0.005`|勢いあり（USDJPY価格帯基準）|
|10秒足STOCH極端値|`stoch10s_k <= 20.0 または >= 80.0`|方向問わず偏り|
|Spread|`spread_points <= 3`|広すぎる時間帯除外|
|時間帯フィルタ（JST）|JST 9〜21時のみ許可|22〜23時・6〜8時除外|
|直近60秒値幅（レンジ除外）|`range60s >= 0.03円`|小さな往復のみ除外（USDJPY・3銭）|
|重複抑制|前回 Entry から10秒以上経過|連続 Entry 防止|

※ `entry_direction` は常に `0`（無方向）。方向ラベルは first-touch で確定。

**input変数として公開しない（知見なし・将来ハードコード定数を相談のうえ変更する運用）。**

---

### 2-2. 時刻処理（JST基準）

`Coding_rule.md rule#22` に従い、全時刻処理をJSTで行う。

```mql5
// サーバー時刻 → JST変換（+9時間）
datetime jst_time = TimeCurrent() + 9 * 3600;
MqlDateTime dt;
TimeToStruct(jst_time, dt);
int jst_hour    = dt.hour;
int jst_weekday = dt.day_of_week;  // 0=日〜6=土
```

- ログの `time`・`hour`・`weekday_jst`・`hour_label` はすべてJST基準
- 時間帯フィルタはJST 9〜21時で判定
- セッション定義（`hour_label`）はJST基準：

|hour_label|JST時間帯|
|---|---|
|`TOKYO`|9〜15時|
|`LONDON`|15〜21時|
|`NY`|21〜翌6時|
|`OFF`|その他（Entry除外対象）|

---

### 2-3. Struct 定義（`CSimpleSession`）

ベースの値コピーパターンを維持（`Coding_rule.md rule#18`：参照・ポインタ禁止、`->` 禁止）。

#### Entry時点フィールド

|フィールド|型|説明|
|---|---|---|
|`active`|bool|セッション処理中フラグ|
|`date`|string|日付（JST）|
|`time`|string|時刻（JST）|
|`hour`|int|時（JST）|
|`weekday_jst`|int|曜日（JST、0=日〜6=土）|
|`hour_label`|string|セッションラベル（TOKYO/LONDON/NY/OFF）|
|`bid`|double|Entry時Bid|
|`ask`|double|Entry時Ask|
|`spread_points`|int|Spread（points）|
|`entry_mid`|double|Entry時Mid価格|
|`range60s`|double|直近60秒の値幅（円）|
|`macd10s_main`|double|10秒足MACD main|
|`macd10s_signal`|double|10秒足MACD signal|
|`macd10s_hist`|double|10秒足MACD histogram（= main - signal）|
|`stoch10s_k`|double|10秒足STOCH %K|
|`stoch10s_d`|double|10秒足STOCH %D|
|`vol_1s`|double|直近1秒の値幅|
|`vol_5s`|double|直近5秒の値幅|
|`std_10ticks`|double|直近10tick標準偏差|
|`slope_10ticks`|double|直近10tick線形回帰傾き|
|`slope_30ticks`|double|直近30tick線形回帰傾き|
|`tick_density_1s`|int|直近1秒のtick数|
|`tick_density_5s`|int|直近5秒のtick数|
|`m1_direction`|int|1分足方向（1/-1/0）|
|`m5_direction`|int|5分足方向（1/-1/0）|
|`bb_width_m1`|double|1分足BBバンド幅|
|`adx_m5`|double|5分足ADX|
|`rsi_m1`|double|1分足RSI|
|`distance_to_prev_high`|double|直近60秒高値からの距離（円）|
|`distance_to_prev_low`|double|直近60秒安値からの距離（円）|
|`target_up`|double|ターゲット上方（entry_mid + 0.03）|
|`target_down`|double|ターゲット下方（entry_mid - 0.03）|
|`start_time`|datetime|Entry時刻（内部処理用）|

#### first-touchフィールド

|フィールド|型|説明|
|---|---|---|
|`ft_direction`|int|first-touch方向（1=UP / -1=DOWN / 0=NONE）|
|`ft_time_sec`|int|first-touch到達秒数|
|`ft_max_retracement`|double|first-touch到達までの最大逆行幅（円）|
|`ft_macd10s_hist`|double|first-touch時点の10秒足MACD hist|
|`ft_stoch10s_k`|double|first-touch時点の10秒足STOCH %K|
|`ft_m1_direction`|int|first-touch時点の1分足方向|
|`ft_m5_direction`|int|first-touch時点の5分足方向|
|`ft_observed`|bool|first-touch確定済みフラグ（ログ出力には含めない）|

#### 継続動意フィールド（3ウィンドウ × 6項目）

ウィンドウ：1分・3分・5分（X = 1 / 3 / 5）

|フィールド名パターン|型|説明|
|---|---|---|
|`cont_Xm_max_extend`|double|first-touch方向への最大伸び幅（円）|
|`cont_Xm_max_retrace`|double|逆方向最大逆行幅（円）|
|`cont_Xm_cum_same`|double|同方向累積値幅（円）※|
|`cont_Xm_cum_opposite`|double|逆方向累積値幅（円）|
|`cont_Xm_m1_align`|int|1分足整合性（1=一致/-1=逆/0=中立）|
|`cont_Xm_m5_align`|int|5分足整合性（1=一致/-1=逆/0=中立）|

※ 同方向累積値幅：ft_direction=UP なら各Tick間の上昇分のみ加算、DOWN なら下落分のみ加算。

---

### 2-4. 10秒足MACD・STOCHの実装方法

MT5標準の `iMACD` / `iStochastic` はPERIOD_S10非対応のため、Tick履歴から自前計算する。

#### 10秒バー生成

```mql5
struct Bar10s {
    datetime bar_time;  // バー開始時刻（10秒境界）
    double   open;
    double   high;
    double   low;
    double   close;
};
Bar10s g_bar10s[];      // 最大200本保持（動的配列）
```

- Tick受信ごとに最新バーのhigh/low/closeを更新
- 10秒境界でバーを確定し新規バーを追加

#### MACD（10秒バー・ハードコード）

- Fast EMA: 5本（50秒相当）、Slow EMA: 13本（130秒相当）、Signal: 3本
- 計算対象：10秒バーのClose（mid）
- **histogramは `main - signal` で自前計算**（`Coding_rule.md rule#21`：iMACDのバッファ2は存在しないため）
- EMA計算は `CalcEma()` 関数で自前実装

#### STOCH（10秒バー・ハードコード）

- %K期間: 5本（50秒相当）、%D期間: 3本
- %K = (Close - Lowest_Low) / (Highest_High - Lowest_Low) × 100
- %D = %Kの単純移動平均

#### CopyBuffer使用上の注意

`Coding_rule.md rule#19`：標準インジケータ（BB・ADX・RSI）のCopyBufferに渡す配列に `ArraySetAsSeries(buf, true)` を設定しない。

---

### 2-5. セッションライフサイクル

```
[Tick受信]
  ↓
10秒バー更新
  ↓
ProcessActiveSessions（先に実行）
  ├─ first-touch未確定セッション
  │   ├─ ±0.03円到達 → ft_direction確定・ft_フィールド記録 → 観測フェーズへ
  │   └─ 600秒タイムアウト → ft_direction=0(NONE)でクローズ・CSV出力（1行）
  └─ first-touch確定済みセッション（継続動意観測中）
      ├─ 各ウィンドウ（1分・3分・5分）のmax/cumを随時更新
      └─ 300秒経過 → 全ウィンドウ確定・CSV出力（1行）
  ↓
Entry条件判定（全条件AND）
  ↓ 成立
StartSession（entry_direction=0、全Entry時点フィールド記録）
```

**1Entry = 1行のCSV出力**（first-touch後5分経過時、またはfirst-touchタイムアウト時）

---

### 2-6. CSVスキーマ（PoC-0011_log.csv）

**ファイルオープンフラグ（`Coding_rule.md rule#22`）：**

- ヘッダー出力（OnInit）：`FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON`
- データ追記（OnTick）：`FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON`
- `FILE_CSV` は使用禁止（ロケール依存でタブ区切りになるため）
- ヘッダー行はOnInitで1回のみ出力

**ヘッダー列（順序厳守）：**

```
date, time, hour, weekday_jst, hour_label,
bid, ask, spread_points, entry_mid,
range60s, macd10s_main, macd10s_signal, macd10s_hist,
stoch10s_k, stoch10s_d,
vol_1s, vol_5s, std_10ticks,
slope_10ticks, slope_30ticks,
tick_density_1s, tick_density_5s,
m1_direction, m5_direction,
bb_width_m1, adx_m5, rsi_m1,
distance_to_prev_high, distance_to_prev_low,
ft_direction, ft_time_sec, ft_max_retracement,
ft_macd10s_hist, ft_stoch10s_k,
ft_m1_direction, ft_m5_direction,
cont_1m_max_extend, cont_1m_max_retrace, cont_1m_cum_same, cont_1m_cum_opposite, cont_1m_m1_align, cont_1m_m5_align,
cont_3m_max_extend, cont_3m_max_retrace, cont_3m_cum_same, cont_3m_cum_opposite, cont_3m_m1_align, cont_3m_m5_align,
cont_5m_max_extend, cont_5m_max_retrace, cont_5m_cum_same, cont_5m_cum_opposite, cont_5m_m1_align, cont_5m_m5_align
```

`SimpleOutcome/PoC-0010` ベースから**削除する列**： `outcome_type`、`outcome_time_sec`、`direction_changes`、`end_time`、`entry_direction`

---

### 2-7. ハードコード定数一覧

```mql5
// first-touch閾値（USDJPY・円単位）
const double FIRST_TOUCH_PIPS   = 0.03;   // 円（3銭）

// Entry動意閾値（USDJPY・円単位）
const double ENTRY_RANGE_10S    = 0.03;   // 直近10秒足値幅（円・3銭）
const double ENTRY_MACD_HIST    = 0.005;  // MACD hist絶対値閾値（USDJPY価格帯基準）
const double ENTRY_STOCH_MAX    = 80.0;   // STOCH上限
const double ENTRY_STOCH_MIN    = 20.0;   // STOCH下限
const int    ENTRY_MAX_SPREAD   = 3;      // Spread上限（points）
const double ENTRY_RANGE_60S    = 0.03;   // 60秒レンジ最小閾値（円・3銭）
const int    ENTRY_INTERVAL_SEC = 10;     // Entry間隔最小（秒）

// 時間帯フィルタ（JST）
const int    SESSION_START_JST  = 9;      // Entry許可開始（JST時）
const int    SESSION_END_JST    = 21;     // Entry許可終了（JST時）

// タイムアウト
const int    FT_TIMEOUT_SEC     = 600;    // first-touch待機最大（秒）
const int    CONT_WINDOW_SEC    = 300;    // 継続動意観測最大（秒）

// 10秒バーMACD（10秒バー本数）
const int    MACD_FAST          = 5;
const int    MACD_SLOW          = 13;
const int    MACD_SIGNAL        = 3;

// 10秒バーSTOCH（10秒バー本数）
const int    STOCH_K            = 5;
const int    STOCH_D            = 3;

// 履歴サイズ
const int    HISTORY_MAX        = 10000;  // Tick履歴最大保持数
const int    BAR10S_MAX         = 200;    // 10秒バー最大保持数
```

---

### 2-8. inputパラメータ（公開パラメータ）

|パラメータ名|デフォルト値|説明|
|---|---|---|
|`InpEnableDebugPrint`|false|デバッグ出力（Print）の有効化|

※ 動意閾値・時間帯・MACD/STOCHパラメータはすべてハードコード定数。

---

## Execution Conditions（実行条件）

|項目|設定|
|---|---|
|シンボル|USDJPY|
|期間|`SimpleOutcome/PoC-0010` と同一期間|
|データ粒度|Tick（MT5テスター：Every tick based on real ticks）|
|ブローカー|Gaitame Finest MT5（MQL4互換レイヤーなし）|
|時刻基準|JST（UTC+9、`TimeCurrent() + 9*3600` → `TimeToStruct()`）|
|出力ファイル|`%COMMON_DATA%\Files\PoC-0011_log.csv`|
|ベースコード|`SimpleOutcome/PoC-0010` の `PoC-0001_base.mq5`（差分修正）|

---

## Evaluation Hypotheses（評価仮説）

1. **H1（Entry発火率）**：無方向・動意ベースの Entry 条件は first-touch発生率が方向ありEntryと有意差がないか、到達時間分布が異なる。
2. **H2（継続動意の有意性）**：first-touch後の最大伸び幅は、10秒足MACD hist絶対値・STOCHの極端度と正の相関を持つ。
3. **H3（上位足整合性の効果）**：first-touch後に1分足・5分足がsame-directionの場合、`cont_5m_max_extend` が非整合ケースより大きい。
4. **H4（Exit期待値）**：first-touch後の継続動意Exitルールは、first-touch時点即クローズより期待値が高いケースが存在する。

---

## Evaluation Specification（評価仕様）

### 分析対象指標

|指標|集計方法|
|---|---|
|first-touch発生率|`ft_direction != 0` の割合|
|first-touch到達時間分布|`ft_time_sec` の p25/p50/p75|
|first-touch最大逆行幅|`ft_max_retracement` の分布|
|継続動意（各ウィンドウ）|`cont_Xm_max_extend` の平均・中央値|
|上位足整合性との相関|`ft_m1_direction` × `cont_Xm_max_extend` クロス集計|
|即利確 vs 継続動意Exit|first-touch到達を利確基準とした期待値比較|
|JST時間帯別分布|`hour_label` × `ft_direction` クロス集計|
|JST曜日別分布|`weekday_jst` × `ft_direction` クロス集計|

### 評価基準

- サンプル数 ≥ 200件（`ft_direction != 0`）を分析の最低条件とする
- first-touch発生率 ≥ 60% を「動意Entry条件の有効性あり」とみなす
- H3の検証：`ft_m1_direction == ft_direction` かつ `ft_m5_direction == ft_direction` のケースで `cont_5m_max_extend` 平均が非整合ケースの ≥ 1.5倍であれば支持

---

## Next Step（次のステップ）

- 継続動意Exitルールの具体的な閾値（伸び幅・ウィンドウ選択）を確定 → PoC-0012
- Entry動意フィルタの最適パラメータ探索（ハードコード定数の見直し・相談）
- 上位足整合性フィルタをEntryに組み込んだ版の検証
- JST曜日・時間帯別の継続動意傾向から除外条件候補の抽出

---

## Question（不明点・確認事項）

**質問なし。本仕様は確定版とする。**

---

## 改訂履歴

|日付|バージョン|修正内容|
|---|---|---|
|2026-05-17|v1.0|初版生成（Q1〜Q5回答前ドラフト）|
|2026-05-17|v1.1|Q1〜Q5回答反映・Coding_rule.md対応による確定版。変更要点：① `±0.03` → `±0.03円` に全置換、② `SimpleOutcome/PoC-0010` に全置換、③ 時刻処理をJST（UTC+9）基準に統一・`weekday_jst` 列追加・`hour_label` セッション定義をTOKYO/LONDON/NY/OFFに変更、④ 閾値をハードコード定数に変更・定数一覧セクション追加、⑤ 同方向累積値幅の計算定義を明文化、⑥ ベースCSVから不要列を削除、⑦ 1Entry=1行・5分後一括CSV出力を確定、⑧ Coding_rule各種対応（ArraySetAsSeries禁止・iMACDバッファ2不在・FILE_CSV禁止・struct値コピー）|
|2026-05-17|v1.2|シンボルをUSDJPY前提に変更。変更要点：① シンボルを `EURUSD` → `USDJPY` に変更（Execution Conditions）、② `ENTRY_RANGE_10S`・`ENTRY_RANGE_60S` を `0.0003円` → `0.03円`（3銭）に修正（USDJPY 2桁通貨スケール）、③ `ENTRY_MACD_HIST` を `0.00005` → `0.005` に修正（USDJPY価格帯基準）、④ ベースコードの変更方針に「シンボル前提をUSDJPYに変更」を追記|

---

_生成日: 2026-05-17 / ベース: SimpleOutcome/PoC-0010 (PoC-0001_base.mq5) / 要求仕様: PoC-0011_Request.md / コーディングルール: Coding_rule.md_