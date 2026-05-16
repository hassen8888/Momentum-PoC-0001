# **PoC管理ルール（Claude.ai中心版）**

この文書は、Claude.ai が PoC の実装仕様（仕様レビュー）および コード生成を行う際に従うべき **運用ルール** を定義する。

> **環境前提**
> 
> - 要求仕様・実装仕様・ルール類は GitHub で管理し、Claude.ai にURLを渡して参照させる
> - Claude.ai が生成したテキスト（仕様・コード・分析結果）は、人間がコピーしてローカルに保存・GitHubにpushする
> - Pythonによるデータ前処理・サマリ生成は引き続き自動化スクリプトで行う

---

## **1. PoCの基本原則**

### **1.1 PoCは「要求仕様 → 実装仕様 → 実装 → 分析」の順で進む**

Claude.ai は以下の順序を厳守する：

1. **PoC-XXXX_Request.md（要求仕様）を読み、実装仕様を作成する（PoC仕様）**
2. **実装仕様に質問があれば列挙し、回答後に再生成する（仕様レビュー）**
3. **完成版Spec.mdをもとに、csvschema.json と preprocess_rule.json を生成する（分析スキーム）**
4. **質問がなくなったら、実装仕様に従ってEAを生成する（コード生成）**
5. **分析では、summary.json と PoC-XXXX_Spec.md のみを参照する（分析）**

### **1.2 各フェーズのファイルと担当**

| フェーズ    | 入力ファイル                                      | 出力ファイル                                 | 担当           |
| ------- | ------------------------------------------- | -------------------------------------- | ------------ |
| 要求整理    | （PoC-XXXX-1_Report.md）<br>（議論）              | PoC-XXXX_Request.md                    | 人間＋Claude.ai |
| PoC仕様   | PoC-XXXX_Request.md                         | PoC-XXXX_Spec.md                       | Claude.ai    |
| 仕様レビュー  | PoC-XXXX_Spec.md                            | （修正版Spec.md）                           | 人間＋Claude.ai |
| 分析スキーム  | （完成版Spec.md）                                | csvschema.json<br>preprocess_rule.json | Claude.ai    |
| コード生成   | PoC-XXXX_Spec.md<br>csvschema.json<br>ベースEA | PoC-XXXX.mq5                           | Claude.ai    |
| コンパイル   | PoC-XXXX.mq5                                | PoC-XXXX.ex5                           | 人間（MT5 CLI）  |
| テスター実行  | PoC-XXXX.ex5                                | CSVログ                                  | 人間（MT5）      |
| 前処理・サマリ | CSVログ<br>preprocess_rule.json               | summary.json                           | 人間（Python）   |
| 分析      | summary.json＋Spec.md                        | PoC-XXXX_Report.md                     | Claude.ai    |
| 次のPoC議論 | PoC-XXXX_Report.md                          | PoC-XXXX+1_Request.md                  | 人間＋Claude.ai |

---

## **2. PoC要求仕様（Request.md）について**

- 人間とClaude.aiの議論によって作成する
- Claude.ai は **Request.md の内容を最優先で解釈する**
- 曖昧な点があれば **必ず質問として列挙する**
- 質問が解消されるまで実装仕様を確定してはならない

---

## **3. PoC実装仕様（Spec.md）について**

Claude.ai（makespec）が生成する文書であり、以下を必ず含める：

- Purpose（目的）
- Implementation（実装内容）
- Execution Conditions（実行条件）
- Evaluation Hypotheses（評価仮説）
- Evaluation Specification（評価仕様）
- Next Step（次のステップ）
- Question（不明点・確認事項）

### **3.1 質問が残っている状態では generate に進んではならない**

- 質問が0件になるまで **Spec.md を再生成する**
- generate は **Spec.md が確定した後のみ** 実行される

---

## **4. EA生成（generate）について**

Claude.ai は以下を厳守する：

### **4.1 ベースコードを必ず参照する**

- generate では **ベースmq5のURLを渡し、構造を維持したまま差分修正する**
- Request.md や Spec.md に明記されていない変更を勝手に行ってはならない
- 全面書き換えは禁止

### **4.2 csvschema.json をログ仕様として厳守する**

- ログ列名・型・意味は **csvschema.json の定義に完全一致** させる
- Request.md に書かれていない列を追加してはならない
- schema にない列を出力してはならない

### **4.3 コード生成時の参照ファイル**

コード生成の際に Claude.ai に渡すURLは以下の順序で渡す：

1. コード生成時注意点.md
2. PoC-XXXX_Spec.md
3. csvschema.json（分析スキームフェーズで生成済みのもの）
4. ベースEA（前バージョンの.mq5）

---

## **5. analyze（評価レポート生成）について**

Claude.ai（analyze）は以下のみを参照する：

- summary.json（前処理の結果）
- PoC-XXXX_Spec.md（実装仕様）

以下は **Claude.aiに渡さない**：

- csvschema.json
- preprocess_rules.json
- Request.md
- ベースコード

分析レポート（PoC-XXXX_Report.md）には以下を含める：

- Purpose（目的）
- Evaluation Specification（評価仕様）
- Results（結果）
- Analysis（分析）
- Improvement Plan（改善案）
- Next Step（次のPoC方向性）

---

## **6. Claude.aiが守るべき禁止事項**

Claude.ai は以下を行ってはならない：

- ベースコードの構造を勝手に変更する
- Request.md に書かれていない仕様を勝手に追加する
- ログ列を勝手に追加・削除する
- 実装仕様に質問が残っている状態で generate を進める
- analyze で Request.md や schema を参照する
- 行間補完による仕様の改変

---

## **7. 人間が行う作業（手動ステップ）**

Claude.ai はファイルの書き込みやGit操作を行えないため、以下は人間が実施する：

|作業|タイミング|
|---|---|
|Claude.aiが生成したSpec.mdをコピーしてGitHubにpush|PoC仕様完了後|
|Claude.aiが生成したcsvschema.json・preprocess_rule.jsonをコピーしてGitHubにpush|分析スキーム完了後|
|Claude.aiが生成した.mq5をコピーしてローカルに保存|コード生成完了後|
|MT5 CLIでEX5をコンパイル|コード生成完了後|
|MT5テスターを実行してCSVを取得|コンパイル完了後|
|PythonでCSVをpreprocess_rule.jsonに従い前処理しsummary.jsonを生成|テスター実行後|
|Claude.aiの分析レポートをコピーしてGitHubにpush|分析完了後|

---

## **8. GitHubリポジトリ構成（推奨）**

```
PoC-XXXX/
├── PoC-XXXX.md              # PoCインデックス（参照ファイル一覧）
├── PoC-XXXX_Request.md      # 要求仕様
├── PoC-XXXX_Spec.md         # 実装仕様（PoC仕様出力）
├── PoC-XXXX_Report.md       # 分析レポート（分析出力）
├── PoC-XXXX.mq5             # EAソースコード
├── csvschema.json           # ログCSVスキーマ定義（分析スキーム出力）
├── preprocess_rule.json     # 前処理ルール（分析スキーム出力）
└── summary.json             # 前処理済みサマリ（分析の入力）
```

共通ルール類は別リポジトリ（例：PoC-0010）で管理し、各PoCからURLで参照する：

- コード生成時注意点.md
- PoC管理ルール.md
- csvschema.json
- preprocess_rules.json

---

## 🟦 **このルールが満たすもの**

- Claude.ai が理解すべき "PoC改善ループのルール" を定義
- 仕様レビュー / コード生成 / 分析 の対応に必要な参照ファイルを明確化
- Claude.ai が仕様を逸脱しないためのガードレールを維持
- Request.md → Spec.md → generate の流れを強制
- ベースコード尊重・差分修正の原則を明確化
- Claude.ai と人間の役割分担（手動ステップ）を明示

---

## **更新履歴**

|日付|バージョン|修正内容|
|---|---|---|
|2026-05-17|v2.1|分析スキームフェーズ追加（csvschema.json・preprocess_rule.json生成をClaude.ai担当に）、フェーズ表・手動ステップ・リポジトリ構成を更新|
|2026-05-17|v2.0|OpenAI中心→Claude.ai中心に全面改定。手動ステップ・リポジトリ構成を追加|
|（旧版）|v1.0|OpenAI向け最小版（初版）|