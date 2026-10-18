# App Store用スクリーンショットの撮り方

MacもDynamic Island搭載iPhoneも13インチiPadも購入しなくてOK。
GitHub Actions上のiOS Simulatorで、実際のFlutter画面を撮影できます。

## 実行方法

1. [App Store screenshots (iPhone + 13-inch iPad)](https://github.com/kaeruko/kotohogu/actions/workflows/app-store-screenshots.yml) を開く。
2. 右上の **Run workflow** → ブランチ **main** → 緑の **Run workflow** を押す。
3. 実行が成功したら、その実行結果画面の一番下にある **Artifacts** から `kotohogu-app-store-screenshots` をダウンロードしてZIPを展開する。
4. App Store Connectの「Appプレビューとスクリーンショット」で、それぞれのフォルダー内の画像をアップロードする。

| 対象 | 画像のフォルダー | 実寸（縦） |
| --- | --- | --- |
| Dynamic Island搭載iPhone（中型） | `iphone_dynamic_island_medium` | **1206 × 2622** |
| 13インチiPad | `ipad_13_inch` | **2064 × 2752** |

各フォルダーに `01_home.jpg`、`02_missions.jpg`、`03_town.jpg`、`04_history.jpg` の計4枚があります。アップロードしたい順番に並べてください。

**注意：審査提出前に画像を開いて確認してください。** とくにiPadでテキストが欠けないか、アニメーション中のキャラクターが不自然でないかをチェックしてください。

## 仕組み

- ワークフロー `.github/workflows/app-store-screenshots.yml` は手動実行専用で、Appleの署名証明書・App Store Connect APIキーは不要です。
- 普段の `lib/main.dart` とは別の `lib/store_screenshots.dart` を**iOS Simulator向けだけ**にビルドします。
- 本物のホーム・ミッション・まち・履歴を使い、達成履歴や住民は**撮影専用の見本データ**を読み込みます。利用者の実際の記録やGoogle Driveの情報は読み取りません。
- `KOTOHOGU_STORE_SCREENSHOTS=true` は撮影ワークフローでしか指定せず、TestFlightやApp Storeの通常ビルドに入れません。撮影ビルドではデバッグメニューも隠します。
- iPhoneは16 Pro（または指定された同サイズ機）、iPadは13インチ Pro（または同サイズ機）のSimulatorを使います。
- 画面描画の完了合図を待ってから `simctl io screenshot` で実際のシミュレーター画面を撮影します。
- 画像はアルファチャンネルを含まない高画質JPEGに変換し、Appleの規定サイズを検査します。8枚揃わないとワークフローは失敗し、不完全なセットを成功扱いにしません。

## うまくいかない場合

実行画面で失敗した **Capture and validate 8 App Store screenshots** を開いて、エラーログを確認してください。対象のSimulatorがMacランナーに存在しない場合や、アプリが指定した画面を開けなかった場合は明示的に失敗します。

**配信版アプリとスクリーンショットの内容が実質的に一致しているか**、最終的には目視でも確かめてください。見本の達成履歴は撮影のために用意したデータなので、実際のユーザーの記録ではありません。

参照：[Apple公式スクリーンショット仕様](https://developer.apple.com/jp/help/app-store-connect/reference/app-information/screenshot-specifications)
