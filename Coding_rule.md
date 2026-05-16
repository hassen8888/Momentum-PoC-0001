# コード生成時注意点（MQL5 / OpenAI 生成の癖まとめ・Gaitame Finest 対応版）

このファイルは、PoC オーケストレーターが必要なルールだけを抽出できるよう  
`:::rule id="..."` ～ `:::endrule` のブロック構造で記述されている。

Python 側では、  
`:::rule id="xxx"` から `:::endrule` までを抽出して system_prompt に渡す。

---

:::rule id="gaitamefinest_mql4_disabled"
## 🚨 0. Gaitame Finest MT5 の最重要注意点

### ■ Gaitame Finest MT5 には MQL4 互換レイヤーが存在しない
以下の MQL4 系 API は **すべて使用不可**：

- TimeHour()
- TimeMinute()
- TimeSeconds()
- TimeDay()
- TimeDayOfWeek()
- TimeDayOfYear()
- TimeMonth()
- TimeYear()
- OrderSend()
- OrderSelect()
- OrderClose()
- iMA(), iMACD() の MQL4 形式
- iTime(), iClose() の MQL4 形式
- MarketInfo()
- NormalizeDouble() の MQL4 版
- その他 MQL4 由来の関数

### ■ 代わりに MQL5 ネイティブ API を必ず使う

#### 時刻取得（必須）

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int hh = dt.hour;
    int mm = dt.min;

#### インジケータ（MQL5 ネイティブ）

    int h = iMACD(_Symbol, PERIOD_M5, 12, 26, 9, PRICE_CLOSE);
    CopyBuffer(h, 0, 0, 3, buf);

#### 注文（CTrade）

    CTrade trade;
    trade.Buy(lots, _Symbol);

### ■ MQL4 API を使うと起きる典型エラー
- undeclared identifier 'TimeHour'
- 'now' - some operator expected
- カーソルが __HAS_MQL4_FUNCTIONS__ に飛ぶ

### ■ OpenAI への指示（system_prompt に必須）
「Gaitame Finest MT5 は MQL4 互換レイヤーが存在しないため、  
MQL4 系 API を一切使用せず、MQL5 ネイティブ API のみでコード生成すること」
:::endrule

---

:::rule id="ea_structure"
## 1. OnInit / OnTick / OnDeinit の戻り値・定義の癖
- OnInit() → **int OnInit()**
- OnInit() の最後は return(INIT_SUCCEEDED)
- OnTick() → void OnTick()
- OnDeinit() → void OnDeinit(const int reason)
:::endrule

---

:::rule id="carrayobj"
## 2. CArrayObj / オブジェクト配列の扱い
- [] アクセス禁止 → **At(index) を使う**
- At() の戻り値は CObject* → キャスト必須
- Add() は index を返さない
:::endrule

---

:::rule id="struct_init"
## 3. 構造体の初期化漏れ
- struct のフィールド未初期化に注意
- MqlTick は SymbolInfoTick() の戻り値チェック必須
:::endrule

---

:::rule id="fileio"
## 4. ファイル操作（CSV）
- FileWrite() の引数数ミス
- FILE_WRITE \| FILE_CSV を忘れる
- 毎 tick でヘッダ行を書かない（初回のみ）
- 絶対パス禁止 → Common フォルダを使う
:::endrule

---

:::rule id="indicator"
## 5. インジケータハンドル
- iMACD() の引数順ミス
- CopyBuffer() の戻り値チェック必須
- MACD バッファ番号  
  - 0 = main  
  - 1 = signal  
  - 2 = histogram
:::endrule

---

:::rule id="mtf"
## 6. 時間足（MTF）
- PERIOD_CURRENT と固定時間足の混同
- CopyBuffer() の shift 指定ミス
:::endrule

---

:::rule id="logging"
## 7. ログ出力
- DoubleToString() を使う
- 毎 tick でヘッダ行を書かない
- FileWrite() の型変換忘れ
:::endrule

---

:::rule id="globals_static"
## 8. グローバル変数・static
- static と global の混同
- 初期化は OnInit で行う
:::endrule

---

:::rule id="error_handling"
## 9. エラー処理
- CopyBuffer()
- SymbolInfoTick()
- FileOpen()
の戻り値チェックを必ず行う
:::endrule

---

:::rule id="ea_basics"
## 10. EA の基本構造
- #property strict を付ける
- input 初期値を適切に
- OnInit でインジケータハンドル作成
- OnDeinit で IndicatorRelease()
:::endrule

---

:::rule id="order_logic"
## 11. 注文ロジック
- OrderSend() の戻り値チェック
- trade.Buy() / trade.Sell() の戻り値チェック
- ストップレベル・最小ロットのチェック
:::endrule

---

:::rule id="timeseries"
## 12. 時系列アクセス
- iTime() / iClose() の shift ミス
- 確定バーは shift=1
:::endrule

---

:::rule id="comments"
## 13. コメント
- PoC では処理意図の説明コメント必須
:::endrule

---

:::rule id="single_file"
## 14. EA の完結性
- PoC では 1 ファイル完結
- 外部ライブラリ禁止
:::endrule

---

:::rule id="misc"
## 15. その他
- MetaEditor は exit code 1 を返すことがある  
  → returncode 0/1 を成功扱いにする
- コードは Markdown のコードブロック（```）で囲まないこと
- プレーンテキストの MQL5 コードのみを返すこと
- 先頭に余計な文字（```mq5 など）を絶対に付けないこと
:::endrule

---

:::rule id="mql4_forbidden"
## 16. MQL4 互換 API の禁止（再掲）
- TimeHour / TimeMinute / TimeSeconds  
- TimeLocal / TimeGMT（MQL4 形式）  
- OrderSend / OrderClose（MQL4 形式）  
- iTime / iClose（MQL4 形式）  
- NormalizeDouble（MQL4 版）  
は **すべて禁止**
:::endrule

---

:::rule id="mql5_native"
## 17. MQL5 ネイティブ API の使用ルール
- 時刻は TimeToStruct()
- 注文は CTrade
- インジケータは iMACD()（MQL5 形式）
- 時系列は CopyBuffer()
- ファイルは FileOpen()（ANSI/CSV）
:::endrule

:::rule id="struct_reference_rules"
## 18. MQL5 の struct は値型であり、参照(&)・ポインタ(*)は禁止

### ■ MQL5 の struct は C++ のような参照型ではない
- MQL5 の struct は **完全な値型**であり、  
  C/C++ のような参照（&）やポインタ（*）は使用できない。

### ■ 以下はすべてコンパイルエラーになる
【禁止例】
EntrySession &s = g_sessions[i];     // 参照は不可
EntrySession *s = &g_sessions[i];    // ポインタも不可
s->field = value;                    // -> 演算子も存在しない
- MQL5 では struct だけでなく class でも “->” は存在しないため、すべて session.xxx でアクセスすること

### ■ 正しいアクセス方法（値コピー）
【正しい例】
EntrySession s = g_sessions[i];

### ■ 書き戻しが必要な場合
【正しい例】
EntrySession s = g_sessions[i];
... // s を更新
g_sessions[i] = s;   // 明示的に書き戻す

### ■ OpenAI への指示
- struct に対して参照(&)・ポインタ(*)・-> を絶対に使わないこと
- 配列要素は必ず「値コピー」で扱うこと
- 書き戻しが必要な場合は g_sessions[i] = s; を明示的に行うこと
:::endrule

:::rule id="copybuffer_series_false"
## 19. CopyBuffer と ArraySetAsSeries の組み合わせ禁止（MQL5 固有の重要ルール）

### ■ 背景
MQL5 の `CopyBuffer()` は **通常配列（series=false）** を前提としており、  
`ArraySetAsSeries(out, true)` を設定すると配列方向が逆転し、  
**CopyBuffer が正しく書き込めなくなる。**

その結果：

- `copied < count` が頻発  
- SafeCopyBuffer が常に false  
- MACD/STOCH/ATR がすべて 0 になる  
- Impact / effective_zone / OutcomePattern が壊れる  
- ログが無意味になる（PoC-0008 で実際に発生）

### ■ 禁止事項
- `CopyBuffer()` に渡す配列に対して  
  **ArraySetAsSeries(out, true) を絶対に使わないこと**
- series=true の配列に CopyBuffer を書き込ませない
:::endrule

:::rule id="mql5_macd_buffers"
## 21. MQL5 の iMACD は「2 バッファのみ」：ヒストグラムは自前計算すること

### ■ 背景（PoC-0008 で実際に発生した重大バグ）
MQL5 の `iMACD()` は **MQL4 と異なり 2 バッファしか持たない**。
- buffer 0 → main（MACD ライン）
- buffer 1 → signal（シグナルライン）
- buffer 2 → **存在しない**（MQL4 では histogram だった）

そのため、以下のコードは **必ず失敗**する：
```mq5
CopyBuffer(handle, 2, 0, 5, hist_buf);   // ★ MT5 では存在しないバッファ
```
### ■ 禁止事項
- **iMACD の buffer=2（ヒストグラム）を CopyBuffer で取得しないこと**
- MQL4 の MACD バッファ仕様を流用しないこと
### ■ 正しい MACD の取得方法（MT5 版）
ヒストグラムは **main - signal を自前計算**する。
```
bool ok_main   = SafeCopyBuffer(handle, 0, 0, 5, main_buf);
bool ok_signal = SafeCopyBuffer(handle, 1, 0, 5, signal_buf);

double hist_buf[5];
for(int i = 0; i < 5; i++)
    hist_buf[i] = main_buf[i] - signal_buf[i];
```
:::endrule

:::rule id="operation"
## 22. PoC 運用ルール（PoC-0002 の追加確認・追加要求から抽出）

### ■ CSV 出力の運用ルール
- ヘッダー行は **OnInit() の 1 回のみ** 出力し、OnTick() では絶対に出力しない。
- FILE_OPEN のフラグは以下に統一する：
  - ヘッダー出力：`FILE_WRITE | FILE_TXT | FILE_ANSI (+ FILE_COMMON)`
  - データ追記：`FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI (+ FILE_COMMON)`
- `FILE_CSV` はロケール依存でタブ区切りになるため **使用禁止**。
- 区切り文字は **必ずカンマ**。  
- `EscapeCsv()` は **カンマ or ダブルクォートを含む場合のみ** クォートする。

### ■ 時間・JST・曜日・セッションの運用
- サーバー時間は必ず `TimeToStruct()` で JST (+9h) に変換する。
- 曜日は JST の `day_of_week` を使用し、`weekday_jst` 列に出力する。
- セッション判定は JST 基準で行う：
  - Tokyo：9〜15  
  - London：15〜21  
  - NY：21〜翌6  
  - その他：Off

### ■ Spread 判定の運用
- `spread_expansion_flag` は **双方向検知**（増加・減少の両方）。
if (MathAbs(spread_points - prev_spread) >= threshold)
flag = 1;

### ■ MACD/STOCH 計算の運用
- MACD:
- diff = hist[0] − hist[1]
- slope = hist[0] − hist[1]
- peak_norm = hist[0] / max(|hist[0..4]|)
- STOCH:
- diff = k − d
- slope = (k−d) − (k_prev−d_prev)
- extreme_flag = (k>=80 or d>=80 or k<=20 or d<=20)

### ■ CopyBuffer / CopyTicks の運用
- CopyBuffer の戻り値チェックは必須。失敗時は 0.0 補完でログ継続。
- 配列はすべて **動的配列**にする（固定長禁止）。
- `ArraySetAsSeries(..., true)` を必ず設定する。
- CopyHigh / CopyLow / CopyTime の start_pos は **shift（整数）** を使う。

### ■ ファイルアクセスの運用
- FILE_COMMON を使う場合、MT5 の「共通ファイルアクセスを許可」を ON にする必要がある。
- FileDelete の直後に FileOpen を連続実行しない（ロック対策）。

### ■ ヘッダー構成の運用
- ヘッダーは **1 行に統合**し、列名は Orchestrator 仕様に完全一致させる。
- 列名の大文字・小文字・順序・アンダースコアは厳密一致。

### ■ デバッグログの運用
- Print() は大量に出すとバックテストが重くなるため、`InpEnableDebugPrint=false` をデフォルトにする。
- デバッグ時のみ true にする。

### ■ MQL4 API の禁止（再掲）
- TimeHour / TimeMinute / TimeSeconds  
- iTime / iClose（MQL4 形式）  
- OrderSend（MQL4 形式）  
- NormalizeDouble（MQL4 版）  
- MarketInfo  
など **MQL4 API は一切使用禁止**。

### ■ 関数宣言順序の運用
- SafeCopyBuffer → GetMacdMetrics → GetStochMetrics の順で定義する。
- 未定義関数呼び出しはビルドエラーになるため、順序を厳守する。

### ■ CSV 列名の固定（Orchestrator 仕様）
- MACD_1M_hist / STOCH_1M_k など、列名は **Orchestrator 仕様に完全一致**させる。
- 独自命名は禁止。

:::endrule

:::rule id="struct_rules"
## 23. struct / class / MqlTick（MQL5 の型仕様）

- MQL5 には C/C++ の “->” 演算子は存在しない  
  → struct/class どちらでも **session.xxx** でアクセスすること

- struct は完全な値型  
  → 参照(&)・ポインタ(*) 禁止  
  → 配列要素は **値コピー** で扱う  
  → 更新が必要な場合は g_sessions[i] = s; を明示的に行う

- class も “->” を使わない  
  → new で生成したオブジェクトも **session.xxx** でアクセスする  
  → 参照(&)・ポインタ(*) を使わない

- OpenAI は struct/class に対して  
  **参照(&)・ポインタ(*)・-> を絶対に使わないこと**
:::endrule
---


:::rule id="operation"
## 今後の運用
- デバッグで新しい癖を発見したら、この md に追記する
- PoC の system_prompt にこの md の内容を反映する
- PoC の改善ループで「癖学習」を行う基盤として使用する
:::endrule
