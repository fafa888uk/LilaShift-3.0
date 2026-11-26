[![LilaShift](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

# LilaShift 4.2.1 · 紫序

**スマートなデバイス検出 · 機能管理 · 安全なバックアップ · 追跡可能な復元**

[English](README.md) · [简体中文](README_ZH-CN.md) · [日本語](README_JA.md)

> **現在のソース：LilaShift 4.2.1** — ビルド `42000002`、2026-11-27 に準備したメンテナンス更新です。[4.2.1 の変更・検証記録](docs/RELEASE_4_2_1.md)を参照し、CI 結果と IPA を正確なソースコミットに対応させてください。
> **以前の公開版：[4.2.0](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.2.0)** — 2026-11-19 公開、コミット `3152fc7c49ccb00f80f97da90666a65fb66a6d89`、ビルド `42000001`。4.2.1 のソース準備は新しいリリースの公開を意味しません。
> 4.2.1 の実機インストール、eSIM、Apple Intelligence、復元は未検証です。以下の 3.0.0-rc.1 に関する記述は過去の記録として残しています。

[![Source 4.2.1](https://img.shields.io/badge/version-4.2.1-purple)](docs/RELEASE_4_2_1.md)
[![Build LilaShift IPA](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml)
[![Run Swift Tests](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/run-swift-tests.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/run-swift-tests.yml)
[![Check Licenses](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/check-licenses.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/check-licenses.yml)
[![SwiftLint](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/swiftlint.yml)
[![Platform](https://img.shields.io/badge/iOS-27.x-black?logo=apple)](#互換性)
[![License](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

> **リポジトリ名についての注意:** このリポジトリは 2026-11-17 に `LilaShift-2.0` から `LilaShift-3.0` に改名されました（アカウントも `fafa920q-hue` から `fafa888uk` に変更）。古いリンクは新しい場所へリダイレクトされるため、既存のリンクは壊れません。

### クイックリンク

- **4.2.1 更新:** [変更内容・上流確認・検証記録](docs/RELEASE_4_2_1.md) · [IPA ビルド履歴](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml)
- **リリース履歴:** [すべてのリリース](https://github.com/fafa888uk/LilaShift-3.0/releases)（バージョンとリリースノートを確認してください）。
- **インストールガイド:** [docs/INSTALL_ZH-CN.md](docs/INSTALL_ZH-CN.md)（簡体字中国語）
- **ユーザーガイド:** [docs/USER_GUIDE_ZH-CN.md](docs/USER_GUIDE_ZH-CN.md) · **互換性:** [docs/COMPATIBILITY_ZH-CN.md](docs/COMPATIBILITY_ZH-CN.md) · **バックアップと復元:** [docs/BACKUP_RESTORE_ZH-CN.md](docs/BACKUP_RESTORE_ZH-CN.md) · **トラブルシューティング:** [docs/TROUBLESHOOTING_ZH-CN.md](docs/TROUBLESHOOTING_ZH-CN.md) · **FAQ:** [docs/FAQ_ZH-CN.md](docs/FAQ_ZH-CN.md)
- **お知らせ:** [Telegram チャンネル](https://t.me/LilaShiftUpdates)（お知らせ専用 — 議論用のグループではありません）
- **バグ報告:** [GitHub Issues](https://github.com/fafa888uk/LilaShift-3.0/issues) — [COMMUNITY.md](COMMUNITY.md) を参照してください。**シリアル番号、UDID、アカウントのキー、その他の個人データを Issue に投稿しないでください。**

中国向け iPhone の eSIM、地域コード、Apple Intelligence 設定を支援する LilaShift 4.x の完全なソースです。GestaltX の元の履歴と確認済みの上流更新を維持し、リポジトリ名は `LilaShift-3.0` を引き続き使用します。

---

## 目次

- [検証済みの内容と未検証の内容](#検証済みの内容と未検証の内容)
- [このリポジトリについて](#このリポジトリについて)
- [4.2.1 の更新内容](#421-の更新内容)
- [3.0.0-rc.1 の過去の変更](#300-rc1-の新機能)
- [4.1.0 の新機能](#410-の新機能)
- [4.2.0 の新機能](#420-の新機能)
- [機能](#機能)
- [互換性](#互換性)
- [ダウンロード](#ダウンロード)
- [インストール](#インストール)
- [要件と注意事項](#要件と注意事項)
- [スクリーンショット](#スクリーンショット)
- [よくある質問](#よくある質問)
- [plist をインポートする](#plist-をインポートする)
- [自分でビルドする](#自分でビルドする)
- [対応言語](#対応言語)
- [オープンソースとライセンス](#オープンソースとライセンス)
- [クレジット](#クレジット)
- [免責事項](#免責事項)

---

## 検証済みの内容と未検証の内容

| 項目 | 検証状況 |
|---|---|
| ソースが CI でビルドできること（`Build LilaShift IPA`） | 対象リリースの CI 記録を確認してください。ブランチのバッジは個別の成果物の検証証拠ではありません。 |
| Swift ユニットテスト（`Run Swift Tests`） | 対象リリースの CI 記録を確認してください。ブランチのバッジは個別の成果物の検証証拠ではありません。 |
| ライセンス / 帰属チェック（`Check Licenses`） | 対象リリースの CI 記録を確認してください。ブランチのバッジは個別の成果物の検証証拠ではありません。 |
| コード規約（`SwiftLint`） | 同じソースコミットの完了結果を確認してください。キャンセルされた、または未実行のジョブは成功扱いにしません。 |
| この IPA の実機インストール | ⚠️ **このビルドでは未検証** — この HEAD に対する実機の証拠はこのリポジトリにありません（`CHANGELOG.md` の「既知の不足」を参照） |
| アンロック後の eSIM 有効化 | ⚠️ **このビルドでは未検証** — この HEAD に対する実機の証拠はこのリポジトリにありません |
| Apple Intelligence が実際に表示 / 動作すること | ⚠️ **このビルドでは未検証** — この HEAD に対する実機の証拠はこのリポジトリにありません |
| 復元でデバイスが完全に以前の状態に戻ること | ⚠️ **このビルドでは未検証** — この HEAD に対する実機の証拠はこのリポジトリにありません |

MobileGestalt のフラグを変更することと、その機能が実際に動作することは**同じではありません**。フラグが「オン」と表示されていても、ハードウェア、OS バージョン、Apple のサービスが「不可」と言う場合があります。この README は、すべてのデバイスですべてをアンロックできると主張するものではありません。

## このリポジトリについて

これは **LilaShift 4.x（紫序）** の**フルソースプロジェクト**です。GestaltX の China Unlock 強化版です。変更済みの完全なソースがこのリポジトリにあります。別途パッチを適用する手順はありません。CI はこのソースから直接 IPA をビルドします。

- 上流 [huamidev/GestaltX](https://github.com/huami1314/GestaltX) `v1.0.7`（コミット `dfd4a7e`、ビルド `11130112`）を基にし、上流の壁紙削除修正 PR #126（コミット `c60519c`）を含みます。
- 以前のパッチベースのビルドリポジトリ（[fafa888uk/LilaShift](https://github.com/fafa888uk/LilaShift)）はそのまま残されており、積極的な開発は行われていません。
- LilaShift の機能強化は **`@steam8871`** がメンテナンスしています。上流 GestaltX の作業は引き続き huamidev のものです。

## 4.2.1 の更新内容

- ZIPFoundation を 0.9.20 から [0.9.21](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.21) に更新し、不正なアーカイブとシンボリックリンクのパス検証に関する上流修正を取り込みます。既存のインポートパス、サイズ、整合性の検証は維持します。
- 復元の警告、監視、アーカイブのメッセージなど、4.x 画面で不足していた翻訳を補います。ローカライズの検証も受け入れ条件に含めます。
- PR #20–#25 のリポジトリ管理、3 言語の文書、CI 権限、About ページの変更を統合します。旧 `main` のみにあった 30 個の一時的なパッチワークフローは 4.x に再導入しません。
- GitHub の標準無料ランナーを使用し、SwiftLint 0.65.1 を固定してチェックサムを検証します。IPA ごとにチェックサムとビルド元の記録を生成します。通常の CI は成果物をアップロードし、手動リリース処理は実際にチェックアウトしたコミットを対象にドラフトを作成します。
- GestaltX と Erosion-CN の最新ソースを確認します。既存の 4.x 機能を維持し、新しい広告ブロック、ペアリング、音声キャプチャ機能を統合済みとは扱いません。[上流確認の記録](docs/RELEASE_4_2_1.md#开源更新核查)を参照してください。

4.2.0 のナビゲーション分類、4.1.0 の App Audio Library とロック画面テキストの統合は 4.x 基盤に引き続き含まれます。バージョン履歴は [CHANGELOG.md](CHANGELOG.md) を参照してください。

## 3.0.0-rc.1 の新機能

- **LilaShift 3.0 ダッシュボード** — 実際のデバイス読み取りとステージング済み変更の状態を表示する軽量なホーム画面、11 カテゴリ 58 項目の機能カタログ（プリセット 45 項目 + ページ項目 13 件）、統一された 8 状態の互換性モデル、確認ステップ付きの履歴 / 復元ビュー、ファイル読み取りと SHA-256 ハッシュを描画パスから外す診断キャッシュ。詳細は [CHANGELOG.md](CHANGELOG.md) を参照してください。
- **ワンタップ China Unlock（10 項目。ネイティブ Apple Intelligence モデルでは 3 項目）** — eSIM スイッチ（`green-tea` をオフ、`not-green-tea` をオン）、地域コードを米国（`LL`、販売地域は変更なし）に設定、7 つの Apple Intelligence 機能をワンタップでステージングし、適用前に確認できます。
  - eSIM キャッシュのレイアウトはステージング前に検証されます。検証できない場合、eSIM グループ全体が停止して理由が表示されます。地域と AI フラグは個別に設定できます。
  - ネイティブ Apple Intelligence 搭載モデル（iPhone Air など）では、7 つの AI 項目はスキップされます。デバイスがすでに備えているためです。そのためワンタップでは 2 つの eSIM スイッチ + 地域コードのみがステージングされます。
  - 適用時は毎回自動的にバックアップが作成され、書き込み後に読み戻して検証されます。ワンタップ復元では、記録された元の値からステージング済みのすべての項目が元に戻ります。
- **スタンドアロンの Siri AI Mode プリセット** — SiriMode = 2 のみをステージングする単一項目のトグルで、China AI プリセットと eSIM + 地域プリセットの横に専用のカードがあります。China AI プリセットとは異なり、ネイティブ Apple Intelligence モデルでも利用できます（明示的なオプトイン）。実験的な機能で、Siri AI がネイティブに動作するモデルでは通常不要です。不明なモデルは拒否されます（フェイルクローズド）。
- **ライトラベンダーの Liquid Glass デザイン** — ページ背景 `#F6F3FF`、プライマリパープル `#8652DC`。大きな暗い背景はありません。
- **すべての機能に目的の説明** — すべてのプリセットに簡体字中国語の一行の目的説明が表示されます。デバイス要件と効果の詳細は詳細ビューにあります。
- **作成者バッジとライブ進捗カード** — メンテナー `@steam8871` がヘッダーと About ページにクレジットされています。読み取り / 適用時は実際の操作に基づく本物の進捗（バックアップ / 書き込み / 検証 / 完了）が表示され、シミュレーションされることはありません。
- **オープンソースコンプライアンス** — About ページはコントリビューターセンターになっており、使用または参照しているすべてのプロジェクトについて、作成者、関係、技術、ライセンス、ソースリンクを一覧表示します。GPL v3.0 の全文がアプリに同梱されています。[docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md) と [docs/FEATURE_ORIGIN_MATRIX.md](docs/FEATURE_ORIGIN_MATRIX.md) を参照してください。
- **MobileGestalt 書き込みの強化**（Erosion-CN から着想を得た設計で、コードのコピーはありません）— インプレース書き込み（事前の切り詰めなし、`F_FULLFSYNC`、完全な読み戻し、失敗時のインプレースロールバック）、eSIM キャッシュレイアウトの実行時動的解決、適用前の差分プレビュー、デュアルボールトバックアップ（アンインストール / 再インストール後も残るファクトリーボールトを含む）、地域モードの選択（地域コードのみ、または完全な米国 `LL` + `LL/A`）、競合ガード付きの 4 要素 Apple Intelligence チェックアップ。
- **ライセンス上の理由によりリスプリングを削除** — NeoSpring / Ketamine のリスプリング実装は 2026-11-14 に削除されました（NeoSpring はライセンスを明記していません）。このビルドにはリスプリングのコードはありません。代わりにアプリは手動でのデバイス再起動を促します。[docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md) §3–§4 を参照してください。
- **LilaShift のアイデンティティ** — アプリ名は **LilaShift**（中文：紫序）で、猫の写真がアプリアイコンです。

## 4.2.0 の新機能

- **ナビゲーションの再分類** — ホームの 4 枚のカード（ワンタップアンロック / AI のみ / Siri AI モード / eSIM と地域）が、それぞれ専用のページを開くようになりました。以前は 4 枚とも同じワンタップの長いページを開いていました。ツールタブの重複カードも削除されました。
- **ホームのタイトルが動的に** — ホームのタイトルがバンドルの実際のバージョンを読むようになりました（以前は "LilaShift 3.0" とハードコードされていました）。
- 分類はツールページの 7 グループに統一されました。プリセット 46 項目 / カタログ 59 項目は変わりません。

## 4.1.0 の新機能

- **App Audio Library（フェーズ 1: ライブラリのみ）** — アプリの通知音を自分の音声に置き換えます。上流 GestaltX v1.1.1 から 1:1 で移植（GPL-3.0、帰属表示あり）。コンテナ内に通知音をすでに公開しているアプリが対象です。キャプチャガイド（バンドル内に音声があるアプリ向け）は Pairing & Device Connection が必要なため、後のステージに延期されました。詳細は Stage 13 の実装記録を参照してください。
- **ロック画面テキスト（カタログ統合）** — システム設定ページ自体は 4.0.0 にすでにありました（上流 GestaltX v1.0.6 から 1:1 で移植）。Stage 13 では、検索とカタログブラウザから見つけられるカタログのポインター項目、バージョンセンチネルゲート（ブロックされるビルドでは誤解を招くエラーの代わりに残留 / ダウングレードの案内が表示されます）を追加し、全体復元ではフットノートが戻らないことを明記しました。システム設定ページの Revert を使ってください。
- **バックアップ削除の失敗後に再試行できることの確認** — 上流 v1.1.1 の比較で確認されました。削除に失敗してもバックアップは一覧に残り、回復可能な状態が保たれるため、もう一度削除すれば再試行できます（中断されたメタデータのクリーンアップも再開できます）。
- **日本語 README** — このファイルです。上流 README_JA.md を基にし、LilaShift 4.1.0 のブランド / バージョン / 機能に合わせてあります。
- プリセット 46 項目 / カタログ 59 項目（4.0.0 では 45 / 58）。テストは 762 メソッド。

## 機能

| カテゴリ | プリセットとツール |
|---|---|
| China Unlock | 10 項目のワンタップステージング（ネイティブ Apple Intelligence モデルでは 3 項目。7 つの AI 項目はスキップされます）：eSIM スイッチ、地域コード米国（`LL`）、7 つの Apple Intelligence 機能 — 適用前に確認でき、eSIM キャッシュレイアウトの検証、自動バックアップ、読み戻し検証、ワンタップ復元付き |
| ディスプレイ | Dynamic Island の機能とレイアウト、常時表示ディスプレイ（Always-On Display）、AOD Vibrancy、高輝度 AOD、AOD フリップブック、HDR 写真表示、壁紙の視差効果、Liquid Glass の低電力レンダリング、実験的な PWM および DisplayPort フラグ |
| デバイス | モデル名、起動 / シャットダウン音、充電上限、タップしてスリープ解除、カメラコントロールの設定、アクションボタンの設定、衝突事故検出 SOS、Audio Mix、空間 FaceTime オーディオ |
| iPad | Apple Pencil の設定、ステージマネージャの機能、iPad アプリの互換性 |
| インテリジェンス | 独立した地域コードのオプション、Apple Intelligence の機能フラグ、オンデバイス Siri、Audio Intelligence、Personal Translator、写真のクリーンアップ、手書き合成（Handwriting Synthesis）、常時待ち受けの Hey Siri、Siri AI Mode（スタンドアロンの単一項目トグル。ネイティブ Apple Intelligence モデルでも利用可）、中国本土モデルのデバイスで有効化を試みるための販売地域オプション |
| ツール | App Audio Library（アプリの通知音を自分の音声に置き換える。コンテナ内に音声があるアプリが対象）、ロック画面テキスト（システム設定ページでロック画面下部に自分のテキストを追加。デバイスの再起動は不要） |
| 詳細 | Apple 社内向けの機能フラグ、有効化時に個別の確認が必要なシステム全体の InternalBuild フラグ、内部設定バンドル、Security Research Device フラグ |
| フィールドエディター | `CacheExtra` フィールドの読み取り、検索、追加、編集、削除。ローカル plist のインポート / エクスポート。String、Integer、Real、Boolean、Data、Date、Array、Dictionary の値に対応 |
| 変更 | 自動読み取りと手動での再読み込み、変更前 / 変更後を確認できるステージング、検証付きの書き込み、プリセットごとの復元 |
| バックアップ | デバイスの編集前に自動で初期バックアップを作成、書き込みのたびにバックアップ、元の値の記録。開く、エクスポート、復元、削除に対応。削除に失敗したバックアップは一覧に残り、再試行できます |
| ログと再起動 | エクスプロイトの各段階の実際のログと、手動でのデバイス再起動の案内 |

通常、AI の有効化を試すには地域コードを変更するだけで十分で、Sales Region を変更する必要はありません。Region Code で United States を選択すると、`RegionCode` が `LL` に設定され、販売地域のサフィックスはそのまま維持されます。China (Mainland)、Hong Kong、Taiwan、Japan、United Kingdom も選択できます。Sales Region と Region Code は同時に適用できます。その場合、販売サフィックスは Sales Region に、コードは Region Code に従います。

> 以前に Sales Region を変更したことがある場合は、まずデバイス本来の販売地域に戻して適用してください。

プリセットを無効にするか、その Revert ボタンを使うと、記録されている元の値と型が復元されます。元々存在しなかったキーは削除されます。古い変更に元の値の記録がない場合は、それらのフィールドが追加されたものだとわかっているときに限り Remove Added Fields を使用してください。

プリセットは機能フラグを変更するものであり、実際の効果はデバイスと OS によって異なります。中国本土モデルのデバイスでは、Apple Intelligence と地域のオプションを使って有効化を試すことができますが、利用できるかどうかはモデル、OS のバージョン、Apple のサービスにも左右されます。

機能の完全な一覧（中国語）: [docs/FEATURES_ZH-CN.md](docs/FEATURES_ZH-CN.md)。

## 互換性

オンデバイスでの MobileGestalt アクセスには **iOS / iPadOS 27.x** に対応しています。**iOS / iPadOS 26.x では、オンデバイスでの MobileGestalt へのアクセスには対応していません。**（アプリ自体はインストールできます — 最小 iOS `26.0` — ローカルの plist 編集は引き続き動作します。）[worse_query](https://github.com/forcequitOS/worse_query) を利用しています。SystemGroup へのアクセスには iOS 27 が必要で、利用できる機能はデバイスと OS によって異なります。

**新機能は iOS 27.0〜27.3 beta 1 で動作します。** Apple は iOS 27.3 beta 2 で基盤となる仕組みをブロックしたため、これらの機能を使う場合は 27.3 beta 1 より先にアップデートしないでください。

署名には、使用可能な App Group を少なくとも 1 つ含む証明書とプロビジョニングプロファイルが必要です。アプリとそれに埋め込まれた共有拡張機能は、少なくとも 1 つの**共通の App Group**（`group.com.huami.gestultx`）で署名し、再署名の際も拡張機能を残してください。どちらのプロセスも、実際に署名された App Group を実行時に検出します。配布されている IPA には、これらのエンタイトルメントを埋め込んだ ad-hoc 署名が施されているため、SideStore や AltStore が再署名時にそれらを検出できます。開発者証明書では署名されていません。

最も簡単なインストールでは署名は一切不要です。[LiveContainer](https://github.com/khanhduytran0/LiveContainer) は元の IPA を再署名なしで実行するため、有料の開発者アカウントがなくても App Group の要件を満たせます。

完全な互換性表: [docs/COMPATIBILITY_ZH-CN.md](docs/COMPATIBILITY_ZH-CN.md)。

## ダウンロード

4.2.1 を取得するには、対象のソースコミットに対して成功した [Build LilaShift IPA の実行](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml)から、`LilaShift-4.2.1-<run_id>-<run_attempt>` 成果物をダウンロードしてください。GitHub のワークフロー成果物のダウンロードにはサインインが必要な場合があります。展開後は次のファイルを確認します。

- `LilaShift_4.2.1.ipa`
- `LilaShift_4.2.1.ipa.sha256`
- `build-manifest.json`（ソースコミット、バージョン、ビルド番号、ツールチェーン、IPA ハッシュ）

SHA-256 を照合し、manifest のバージョンが `4.2.1`、ビルド番号が `42000002`、ソースコミットが対象の更新と一致することを確認してください。ワークフロー成果物の保存期間は 14 日です。ビルド成果物と公開リリースは別に管理され、公開済みバージョンは [Releases](https://github.com/fafa888uk/LilaShift-3.0/releases) に表示されます。

以前の公開版は [LilaShift 4.2.0](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.2.0) です。過去の `LilaShift_3.0.0.ipa` は 4.x のパッケージではありません。ダウンロードが不完全、またはハッシュが一致しない場合は、インストール前に再取得してください。

## インストール

詳細なステップバイステップのチュートリアル（中国語）: [docs/INSTALL_ZH-CN.md](docs/INSTALL_ZH-CN.md)。短い手順：

1. [LiveContainer](https://github.com/khanhduytran0/LiveContainer) で IPA をインストールします（再署名は不要です）。または AltStore / SideStore / Sideloadly / 開発者証明書で再署名します。違いはチュートリアルを参照してください。
2. LilaShift を開き、まず **Read Device** をタップします。
3. **China Unlock** を開き、ステージングされた項目（ほとんどのモデルでは 10 項目。ネイティブ Apple Intelligence モデルでは 3 項目）を確認してから適用します。
4. 適用後、**デバイスを再起動**してください。電源を完全に切ってから入れ直します。SpringBoard の更新だけでは eSIM には不十分です。その後、システム設定で eSIM と Apple Intelligence を確認します。
5. すべてを元に戻すには、ワンタップ復元を使用します。バックアップからステージング済みのすべての項目が元に戻ります。

> サードパーティの署名サービスから証明書を購入しないでください。また、Apple ID のパスワードを他人に教えないでください。どちらかを求められたら中止してください。

## 要件と注意事項

- **eSIM ハードウェアが必要です。** アンロックは機能フラグを切り替えるだけです。eSIM ハードウェアがないデバイスに eSIM を追加することはできません。
- **Apple Intelligence はハードウェアと Apple のサーバーに依存します。** フラグをオンにしても、機能が表示されたり動作したりすることが保証されるわけではありません。
- **ストックの電話機では、キャリアと位置情報のルールが引き続き適用されます。** アンロックなしでは、中国本土にいる間に海外の eSIM をインストールすることはできません（Apple のルール）。アンロック後は、中国本土にいるユーザーが直接海外の eSIM を追加できます。出国する必要はありません。海外でインストールする場合は通常、位置情報サービスをオンにする必要があります。中国のキャリアの eSIM は中国のキャリアショップで有効化しなければなりません。
- **システムアップデートにより変更が元に戻る場合があります。** iOS をアップデートした後は、必要に応じて再適用してください。
- **iOS をむやみにアップデートしないでください。** GestaltX は、パッチが当てられていない iOS サンドボックス脱出の脆弱性（`worse_query`）に依存しています。Apple は将来のアップデートでこれを塞ぐ可能性があります。このツールに依存している場合は、アップデート前に互換性を確認してください。
- **適用前にバックアップしてください。** アプリは自動的にバックアップしますが、別途デバイスのバックアップを取っておくことも良い習慣です。
- **「記録された元の値を復元」は「真の工場出荷時状態」ではありません。** 復元は、アプリ自身が変更前に記録した値を戻します。アプリの最初のバックアップの前にすでに値が変更されていた場合、バックアップにはすでに変更された値が含まれています。[docs/BACKUP_RESTORE_ZH-CN.md](docs/BACKUP_RESTORE_ZH-CN.md) を参照してください。

## スクリーンショット

4.2.1 の実機スクリーンショットはここにはまだ記録されていません。シミュレータのスナップショットはテスト用の参照画像であり、このバージョンの実機インストールやデバイス機能の動作を証明するものではありません。

## よくある質問

### アンロック後も eSIM が動作しない、または「eSIM を追加」が消えた

- **2 枚の物理 SIM をトレイに入れた iPhone 18 Pro / Pro Max。** これらのモデルは、2 つの物理スロットと eSIM で 1 つのベースバンドチャネルを共有しています。両方の物理スロットがふさがっていると、ベースバンドが「eSIM を追加」を隠す場合があります。対処法：SIM トレイを取り外し（空にし）、アンロックを適用し、コールドリスタートしてから eSIM を追加し、その後物理 SIM を戻します。
- **eSIM には SpringBoard の更新だけでは不十分です。** ベースバンドデーモン（`CommCenter`、`ctkd`）は SpringBoard の更新ではキャッシュを再読み込みしません。適用後、デバイスの電源を完全に切ってから入れ直してください。
- **両方のスイッチがオンでなければなりません。** 地域の変更と eSIM の変更の両方を適用しなければなりません。地域コードだけを変更しても、eSIM のハードウェアロックは残ります。
- **モデル識別子（`ProductType`）は絶対に変更しないでください。** 中国版ボード（例：`iPhone19,7`）を米国モデルに強制すると、ベースバンドチェックが壊れて eSIM メニューが完全に隠れます。
- **中国本土内で海外の eSIM を追加することは、ストックの電話機では Apple によりブロックされています。** アンロック後は、中国本土で直接追加できます。出国する必要はありません。（機内モード + 海外プロキシ経由の Wi-Fi は、アンロック前のケースの回避策にすぎません。）
- **ハードウェアの制限。** 物理的な eUICC チップを持つモデル（iPhone Air、iPhone 18 シリーズなど）のみが eSIM を追加できます。デュアル nano-SIM 専用の古いモデルには eUICC チップがないため、スイッチは FaceTime オーディオと AI の地域アクセスのみをアンロックします。

### プリセットページと MG Control が一致しない

MG Control はライブの `CacheExtra` 値を表示し、プリセットページは最後に読み取った値を表示します。まずホームページで **再読み込み** をタップしてください。それでも一致しない場合、値は（プリセットを介さず）直接書き込まれています。ワンタップアンロックを一度適用して正規化してください。

### AI が 1/7（または 7 未満）と表示される

7 つの AI 機能フラグのうち、現在オンになっているのはその数だけです。Apple Intelligence ページを開いて、どれがオンか確認してください。古いバージョンで行われた変更は、元に戻すまでキャッシュに残ります。その変更がこのアプリの最初のバックアップより前に行われた場合、バックアップにはすでにその変更が含まれています。

### 元の状態に戻したいが、バックアップがない

復元できるのは、アプリが記録した値だけです。まず Backups ページで以前のバックアップがないか確認してください。ない場合：

- **追加された**キー（以前は存在しなかったもの）→ **Remove Added Fields** を使用してください。追加されたことが確実なキーに限ります。
- **変更された**キー → MG Control で元に戻してください。`RegionCode` と AI フラグは `CacheExtra` キーで、検索できます。`green-tea` / `not-green-tea` は `CacheData` スロット（#383 / #506）で**検索できません**。代わりに eSIM プリセットで設定してください（`green-tea` → `true`、`not-green-tea` → `false`）。
- 復元後、デバイスを再起動してください。

### AI メニューが表示されない、または Siri が「問題が発生しました」と言う

地域コードが `LL` であること、7 つの AI フラグがオンであること、デバイスが AI モデルのダウンロードを終えていること（Wi-Fi + 充電中で、しばらくアイドル状態）を確認してください。プロキシのルールも重要です。Siri のドメイン（`guzzoni.apple.com`、`*.siri.apple.com`、`dejavu.apple.com`、`sequoia.apple.com`）はプロキシを介さず、**DIRECT** で実際の IP を使う必要があります。中国語の通話スクリーニングを維持したい場合は、システムの地域を United States に設定しないでください。代わりに Taiwan に設定してください。

プロキシを使う場合：Siri のコアドメインはプロキシや Fake-IP を介さず、DIRECT で実際の IP を使わなければなりません — `guzzoni.apple.com`、`*.siri.apple.com`、`dejavu.apple.com`、`sequoia.apple.com`、`*.smoot.apple.com`（Surge では、`guzzoni.apple.com`、`*.guzzoni.apple.com`、`*.siri.apple.com` も skip-proxy と always-real-ip に追加してください）。AI の承認と Private Cloud Compute のドメインは、UDP/QUIC に対応したクリーンな米国ノードを経由します — `gspe1-ssl.ls.apple.com`、`*.issuer.apple.com`、`ropes.apple.com`、`mask-api.icloud.com`、`mask.icloud.com`、`mask-h2.icloud.com`、`*.app.apple.com`、`apple-relay.*`。`gspe1-ssl.ls.apple.com` や `*.smoot.apple.com` に対して MitM 復号を有効にしないでください。生成機能がネットワークエラー（例：Code=32033 や Code=1009）で失敗する場合は、まずこれらのルールを確認してください。既成のルールセット：AppleFlow（github.com/Kianuni/AppleFlow）。出典：Erosion-CN FAQ Q3/Q6。

iOS 27.3 の制限：中国ハードウェアのデバイス（CH/A）では、iOS 27.3 にハードウェアを直接読む適格性チェックが追加されました（ログ：`Eligibility returned no CN region policy on a CH region code device`）。地域コードが LL で、すべての AI フラグがオンでも、27.3 では Siri AI と一部の生成機能がブロックされる場合があります。MobileGestalt を変更しても回避できません（Erosion-CN FAQ Q6、状況 C）。回避策は iOS 27.2.x に留まるか、ダウングレードすることです。

### 写真のクリーンアップは動作するが、高品質クリーンアップ / 拡張 / リイマジンが失敗する

ネイティブ AI 搭載の iPhone では、工場出荷時のベースラインとして `Personal Translator` スロット #266 = `true` と `Audio Intelligence` スロット #178 = `false` が必要です。実験的な Audio Intelligence スロットを強制すると、ModelCatalog のアセットチェックが壊れ、高品質クリーンアップが失敗する場合があります。オフにするか、ベースラインに戻してから再試行してください。

### アプリを再インストールする、または証明書の有効期限が切れる

バックアップはアプリコンテナ内に保持されます。アプリをアンインストールすると削除されます。再インストールする前や証明書の有効期限が切れる前に、バックアップをエクスポートしてください。

その他の質問：[docs/FAQ_ZH-CN.md](docs/FAQ_ZH-CN.md) と [docs/TROUBLESHOOTING_ZH-CN.md](docs/TROUBLESHOOTING_ZH-CN.md)。

## plist をインポートする

ファイルアプリなどのアプリで MobileGestalt の plist を選択し、**共有**をタップして **LilaShift** を選びます。共有拡張機能が渡されたファイルを読み取り、共有の App Group を通じてアプリに引き渡します。自動的に開かない場合は LilaShift に戻ってください。アプリは、GestaltX からエクスポートしたファイルに含まれるデバイス固有の証明、またはこのデバイスから取得した少なくとも 2 つの固有識別子を確認したうえで、インポートの確認を求めます。検証できないファイルは拒否されます。以前にインポートしたファイルが、デバイスの識別の基準として使われることはありません。

元の plist の中には、デバイスの固有識別子を含まないものもあります。その場合は、まずこのデバイス上の LilaShift からコピーをエクスポートしてください。その検証キーはこのデバイス専用のキーチェーンに保存され、ファイルに含まれることはありません。

共有されたファイルは、起動時とフォアグラウンドに戻ったときに確認されます。保留中の編集は、保存するか破棄するまで保持されます。確認済みのインポートはローカルドキュメントとして開かれます。**MG Control** では、型付きのキーと値の追加、編集、名前変更、削除ができます。検証済みのファイルをこのデバイスに復元するには **Restore Imported Plist** を使用します。復元には一致するシステムキャッシュのレイアウトと追加の確認が必要で、現在のファイルをバックアップしてから書き込みを検証します。復元後はデバイスを再起動してください。

## 自分でビルドする

- **Build LilaShift IPA**（`.github/workflows/build.yml`）は設定されたブランチ、PR、タグ、Release、手動トリガーに応じて選択したソースをビルドします。標準 `xcode-27` ランナーを使用し、IPA、SHA-256 ファイル、ビルド manifest を `LilaShift-<version>-<run_id>-<run_attempt>` にアップロードします。通常のビルドはリポジトリの読み取り専用権限で動作し、リリース添付ファイルを作成・上書きしません。
- **Run Swift Tests**（`.github/workflows/run-swift-tests.yml`）は `xcode-27` の iOS シミュレータで XCTest を実行します。スナップショット成果物の保存期間は 7 日です。
- **SwiftLint**（`.github/workflows/swiftlint.yml`）は `xcode-27` を使用し、固定バージョン 0.65.1 のチェックサムを検証します。既存の検査ルールは維持します。
- **Check Licenses**（`.github/workflows/check-licenses.yml`）は標準 `ubuntu-latest` ランナーで `scripts/check-licenses.py` を実行します。
- **Prepare Draft Release**（`.github/workflows/prepare-release.yml`、手動のみ）は選択したブランチをビルドし、実際にチェックアウトしたコミットを対象に**ドラフト** Release を作成します。既存のバージョンタグやリリースは上書きせず、自動公開もしません。

構成には[公開リポジトリで無料の GitHub 標準ランナー](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)を使用し、有料ランナーへのフォールバックは設定していません。ビルド manifest はソースとツールチェーンを確認するもので、実機での動作検証を証明するものではありません。

## 対応言語

GestaltX は iOS の言語設定に従い、英語をデフォルトおよびフォールバックとして使用します。ペルシア語では右から左へのレイアウトにも対応しています。

| 言語 | ロケール |
|---|---|
| English | `en` |
| 简体中文 — 簡体字中国語 | `zh-Hans` |
| 繁體中文（台灣）— 繁体字中国語 (台湾) | `zh-Hant-TW` |
| 繁體中文（香港）— 繁体字中国語 (香港) | `zh-Hant-HK` |
| Tiếng Việt — ベトナム語 | `vi` |
| Русский — ロシア語 | `ru` |
| فارسی — ペルシア語 | `fa` |
| 한국어 — 韓国語 | `ko` |
| Español — スペイン語 | `es` |
| 日本語 | `ja` |

## オープンソースとライセンス

このプロジェクトは **GNU General Public License v3.0** の下で配布されています — [LICENSE](LICENSE)（上流 v1.0.7 とバイト単位で同一）を参照してください。

- 上流プロジェクト：[huamidev/GestaltX](https://github.com/huami1314/GestaltX)（`v1.0.7`、コミット `dfd4a7e`、PR #126、コミット `c60519c` を含む）
- 強化版メンテナー：`@steam8871`
- このビルドでの変更点：China Unlock プリセット（10 項目。ネイティブ Apple Intelligence モデルでは 3 項目）とその安全チェック、ライトラベンダーの Liquid Glass デザイン、一行の目的説明、作成者バッジと進捗カード、アプリ内のソースリポジトリリンク、オープンソースコンプライアンスセクション、Erosion-CN に着想を得た強化（書き込みパス、動的レイアウト解決、差分プレビュー、デュアルボールトバックアップ、地域モード、AI チェックアップ）、LilaShift へのリブランド、猫のアプリアイコン。
- LilaShift 3.0 での追加：軽量ダッシュボード、58 項目の機能カタログ、統一された互換性モデル、履歴 / 復元ビュー、診断キャッシュ、オープンソースコントリビューターセンター（About ページ）と `docs/OPEN_SOURCE_REFERENCES.md` のプロジェクト別ソース記録。さらに：Face ID 復旧（検証済みの同一デバイスバックアップから 4 つのハードウェア識別フィールドのみを復元。上流 GestaltX #128/#146 を iPhone 16/17/Air に拡張）、MobileGestalt キャッシュのクリアと再構築（Erosion-CN の仕組みを再実装。バックアップを先に取得）、ワンタップフローでのワンクリック AI ベースライン修正（Personal Translator スロット #266 = 1、Audio Intelligence スロット #178 = 0、存在しない AI キーの補完）。
- LilaShift 4.1.0 での追加：App Audio Library フェーズ 1（上流 GestaltX v1.1.1 から 1:1 で移植）、ロック画面テキストのカタログ統合とバージョンセンチネルゲート（上流 v1.0.6 から 1:1 で移植）、この日本語 README。
- 対応する完全なソースはこのリポジトリにあります（フルソースで、パッチの手順はありません）。

## クレジット

- **huamidev** — GestaltX
- [forcequitOS / Taj C — worse_query](https://github.com/forcequitOS/worse_query)
- [neonmodder123](https://github.com/neonmodder123)
- [skadz108](https://github.com/skadz108)
- [rooootdev — NeoSpring](https://github.com/rooootdev/neospring)（ライセンスの明記なし。リスプリングの使用は中止され、2026-11-14 に削除されました — `docs/OPEN_SOURCE_REFERENCES.md` を参照）
- [Nouvborne — Ketamine](https://github.com/Nouvborne/Ketamine)
- [huamidev — LCSign](https://sign.lc)
- [Kianuni — Erosion-CN](https://github.com/Kianuni/Erosion-CN)
- [lunginspector / jailbreak.party — Erosion](https://github.com/jailbreakdotparty/Erosion)
- [sasobhabha — Gester](https://github.com/sasobhabha/Gester)
- [Thomas Zoechling — ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [GitHub Inc. — Primer Octicons](https://github.com/primer/octicons)
- [PoomSmart — MGKeys](https://github.com/PoomSmart/MGKeys)
- [leminlimez — Nugget](https://github.com/leminlimez/Nugget)（AGPL-3.0、参照のみ — コードの移植はありません）
- [rooootdev — mond](https://github.com/rooootdev/mond)（AGPL-3.0、参照のみ — コードの移植はありません）
- [frs0n — GestaltEdit](https://github.com/frs0n/GestaltEdit)
- [Point-Free — SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing)（テストツール。アプリには同梱されません）
- [Realm — SwiftLint](https://github.com/realm/SwiftLint)（ビルドツール。アプリには同梱されません）

プロジェクト別の完全な記録（ライセンス、証拠、関係、ファイル、IPA への同梱）：[docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md)。機能別の出所マップ：[docs/FEATURE_ORIGIN_MATRIX.md](docs/FEATURE_ORIGIN_MATRIX.md)。

## 免責事項

これは非公式の変更ビルドであり、Apple や上流の作成者とは関係なく、支持されているものでもありません。セキュリティ研究および教育目的に限ります。自分が所有している、または管理する権限を持つデバイスでのみ使用してください。

変更を加える前にデータをバックアップしてください。MobileGestalt を変更すると、システムが不安定になったり、デバイスの復元が必要になったりする場合があります。機能フラグは機能を保証するものではありません。適用した変更とその結果生じるリスクについては、ご自身の責任となります。

## ライセンス

[GNU GPL v3](LICENSE) · Copyright © 2026 huamidev. China Unlock の機能強化は `@steam8871` がメンテナンスしています。
