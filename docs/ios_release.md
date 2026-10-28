# ことほぐ iOS App Storeビルド（GitHub Actions）

正式なBundle ID: `jp.cloxs.kotohogu`

`.github/workflows/ios-app-store.yml` は、公開リポジトリの `macos-26`
ランナー上で署名付き `.ipa` を作り、App Store Connectの **TestFlightへ直接アップロードする**手動ワークフローです。
`workflow_dispatch` 専用で、外部プルリクエストから秘密鍵を利用しません。
既存の `.github/workflows/flutter.yml` の品質チェックは変更しません。

## Apple Developer（先に手動で行う）

1. Certificates, Identifiers & Profiles の Identifiers で、Explicit App ID `jp.cloxs.kotohogu` を登録。
2. WindowsならOpenSSL、MacならキーチェーンでCSRを作成し、Apple Distribution 証明書を発行。
3. 対応する秘密鍵とダウンロードした `.cer` からパスワード付き `.p12` を作成。
4. Profiles → Distribution → App Store Connect を選び、先ほどのApp IDとApple Distribution証明書を紐付けて `.mobileprovision` をダウンロード。

Windows PowerShell（作業場所は**リポジトリの外**）での例：

```powershell
mkdir "$HOME\kotohogu-ios-signing"
cd "$HOME\kotohogu-ios-signing"
openssl genrsa -aes256 -out kotohogu.key 2048
openssl req -new -sha256 -key kotohogu.key -out kotohogu.certSigningRequest -subj "/CN=Kotohogu Distribution"
# AppleにCSRを提出してApple Distribution証明書を取得後:
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey kotohogu.key -in distribution.pem -out kotohogu.p12
```

## GitHub Actions Secrets（リポジトリ Settings → Secrets and variables → Actions）

| Secret | 値 |
| --- | --- |
| `IOS_P12_BASE64` | `.p12` ファイルをBase64エンコードした内容 |
| `IOS_P12_PASSWORD` | `.p12` のエクスポート時に設定したパスワード |
| `IOS_PROFILE_BASE64` | `.mobileprovision` ファイルをBase64エンコードした内容 |

PowerShellでBase64にする例（ファイル名は置き換える）：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path '.\kotohogu.p12')))
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path '.\kotohogu.mobileprovision')))
```

表示されたBase64値はGitHub Actions Secretsのみに入力する。チャット、Issue、
コード、ワークフローログに貼り付けない。秘密鍵（`.key`）、`.p12`、パスワード、
`.p8`、プロビジョニングプロファイルをGitで管理しない。

## TestFlightへビルド・アップロードする（現行の手順）

GitHub → Actions → `iOS TestFlight (Build and Upload)` → `Run workflow`。
**必ずmainブランチから新しく実行**します（Re-runではビルド番号が重複します）。

Appleに承認されたバージョンの受付が終了した場合（例：エラー 90186 / 90062）は、
`pubspec.yaml` の `version: 1.0.1+3` のように、`+` より前のアプリバージョンを
承認済みバージョンより大きくしてから `build_and_upload` を新規実行してください。
`+` より後のビルド番号だけを増やしても、終了したバージョンへの提出はできません。
iOSのビルド番号は新しいActions実行番号で設定されます。

`upload_existing` は既存の署名済みIPAをそのまま送信するので、このエラーの修正には使えません。
現在は、IPAのバージョンが `pubspec.yaml` と一致しない場合は、Appleへのアップロード前に
エラーで止めるようにしてあります。

`enable_developer_menu` は通常 **OFF** のままです。自分の実機で開発メニューを試す
TestFlightビルドだけ **ON** にしてください。

ONのビルドでは、インストール後に下部の「メニュー」を開くと
**「開発メニュー」がそのまま表示されます**。隠しタップは必要ありません。
住民の一時表示、未所持住民のテスト表示、美容室の開放テスト、お祝い再生、
テスト用ことほぎの付与、ミッションリセットなどが使用できます。

**重要**：開発メニューの表示は認証ではありません。ONのIPAにはローカルセーブを変更する
テスト機能が含まれます。**App Storeの一般公開・審査提出にこのIPAを流用しないでください**。
公開用ビルドは必ず `enable_developer_menu` をOFFにして新しくビルドしてください。
初期値はOFFです。ON/OFFはビルド時に確定し、配布後には切り替えられません。

ビルド工程ではFlutter 3.47.6からiOS Runnerを生成し、署名とIPAを確認してから
`xcrun altool` でTestFlightへアップロードします。App Store Connectの処理が完了するまで
テスト端末に新しいバージョンが出ない場合があります。審査提出や一般公開は自動では行いません。
署名済みIPAはActionsのartifactにも7日間保存されます。

ローカルPCで実機デバッグする場合は、通常の `flutter run` を使えば
ビルドフラグ不要で従来どおり「メニュー」が表示されます。

**初回提出前の確認事項**：アプリアイコン、プライバシーポリシー、ストア用スクリーンショット、
正しいアプリ名、実機での起動とセーブ、健康Tipsの文言確認。
iOS設定を細かく変える段階では生成した `ios/` をリポジトリに確定することを推奨。
Flutter/Dartの実行テストや署名付きビルドの成功は、実際にActionsを走らせて確認してください。

## 追加で必要なApp Store Connect Secrets

| Secret | 内容 |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect APIキーの10文字のKey ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID（UUID） |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | 該当APIキー `.p8` のBase64 |

Windows PowerShellでBase64をクリップボードにコピー：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path '.\\AuthKey_XXXXXXXXXX.p8'))) | Set-Clipboard
```

APIキーは対象アプリのビルドアップロード権限を持つものを使ってください。
鍵やパスワードをコミット・チャットに貼り付けないでください。

TestFlightアップロード後はApp Store Connect → ことほぐ → TestFlightでAppleの処理を待ちます。
`enable_developer_menu` をONにしたビルドは実機テスト専用として扱います。
