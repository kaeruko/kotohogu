# ことほぎ CMS 配信（AWS CLI）

**配信データの準備とAWSへの転送はAWS CLI v2 + Python標準ライブラリのみ。** boto3やAWSキーのリポジトリ登録は不要です。
CloudFormationで **非公開S3 + CloudFront（Origin Access Control / HTTPS）** を作ります。CloudFront/S3には通常の利用料金が発生します。
ローカルCMSと本編のセーブデータは変更しません。

## 1. AWS CLIの準備

PowerShellでリポジトリのルートから実行します。使用するAWSアカウントは、実行前に必ず確認してください。

```powershell
cd C:\Users\mail\work\kotohogu
git pull --ff-only origin main
aws --version
aws configure --profile kotohogu
aws sts get-caller-identity --profile kotohogu
```

既にIAM Identity Center（SSO）を利用しているなら `aws configure sso --profile kotohogu` と `aws sso login --profile kotohogu` を使ってください。
**長期アクセスキーをGitに保存しないこと。** CloudFormation/S3/CloudFrontを操作できる権限が必要です。

## 2. 非公開バケット・CloudFrontを作成

```powershell
aws cloudformation deploy --template-file tools/aws/content-stack.yaml --stack-name kotohogu-content --region ap-northeast-1 --profile kotohogu
aws cloudformation describe-stacks --stack-name kotohogu-content --region ap-northeast-1 --profile kotohogu --query "Stacks[0].Outputs" --output table
```

表示される `ContentBucketName`, `ContentDistributionId`, `ContentDomain` を確認してください。
S3はすべてのパブリックアクセスをブロックし、**公開はCloudFront経由のみ**です。バケット削除防止のためCloudFormationではS3に `Retain` を指定しています。独自ドメインは不要で `https://<ContentDomain>/` を使えます。

CloudFront作成直後はDNS/証明書反映に時間がかかります。必要に応じて次のコマンドで配信の準備完了を待てます。

```powershell
$distribution = aws cloudformation describe-stacks --stack-name kotohogu-content --region ap-northeast-1 --profile kotohogu --query "Stacks[0].Outputs[?OutputKey=='ContentDistributionId'].OutputValue | [0]" --output text
if ($LASTEXITCODE -ne 0 -or -not $distribution -or $distribution -eq "None") { throw "CloudFront distribution ID を取得できません" }
aws cloudfront wait distribution-deployed --id $distribution --profile kotohogu
if ($LASTEXITCODE -ne 0) { throw "CloudFront distribution のデプロイを確認できません" }
```

## 3. アセット・キャラ・セリフをアップロード

```powershell
python tools/aws/publish_content.py --stack kotohogu-content --region ap-northeast-1 --profile kotohogu
```

実行前にCMSのキャラ・セリフ・画像を検証します。不足・不整合があればAWSに書き込む前に停止します。

- `releases/<sha256>/api/runtime/catalog` : キャラ14人などの**公開用**JSON（CMS管理UIや個人データは含みません）
- `releases/<sha256>/api/runtime/sprites/<folder>/*.png` : 実際に使うPNGのみ（元のスプライトシート、プレビューGIFなどはアップしません）
- `releases/<sha256>/manifest.json` : 全ファイルのSHA-256とサイズ一覧
- `current.json` : 最新の確定したリリースへの参照先（**最後に**更新）

S3への転送後はキーとサイズを照合し、最新版ポインタを更新するまで以前の配信を維持します。同じ内容の再実行では同じリリースIDになります。アップロード失敗時は例外と診断情報を出して停止し、自動の経路切り替えはしません。

**重要**：新しいアプリはGoogle Driveの `kotohogu_api.txt` に記載されたURLからCloudFrontドメインを特定し、そのドメインの `/current.json` を毎回取得して最新版リリースを確定します。新しいCMSデータを公開するときは、上記 `publish_content.py` だけでよく、**Google Driveファイルは書き換えないでください**。更新されたリリースは次回の起動・再読み込み時に反映されます。古いアプリは従来の固定リリースURLを直接使うため、最新版への自動追従にはアプリの更新が必要です。

## 4. 配信確認

発行された CloudFront ドメインとリリースIDを使用します。

```powershell
# 発行後の表示にある URL を使う
$domain = "<ContentDomain>"
curl.exe --fail-with-body "https://$domain/current.json"
if ($LASTEXITCODE -ne 0) { throw "CloudFront current.json が取得できません" }
```

ローカルの配信テストと同様に、Flutterデバッグ起動で **固定のリリースURL** を指定して確認できます（末尾の `/` を必ず付ける）。AWSのHTTPSから読みます。

```powershell
flutter run -t lib/main.dart --dart-define=KOTOHOGU_LOCAL_CONTENT_URL=https://<ContentDomain>/releases/<releaseId>/
```

`KOTOHOGU_LOCAL_CONTENT_URL` はデバッグ専用です。通常のリリースアプリではこの指定を受け付けません。CMSからの新キャラは現在「配信テストの来訪者」としてまちへ登場します。ガチャ・所有データのAWS連携はまだ行っていません。

## テスト

```powershell
python -m unittest discover -s tools/dialogue_cms -p "test_*.py"
python -m unittest discover -s tools/aws -p "test_*.py"
flutter test test/local_content_preview_test.dart test/local_town_visitors_test.dart test/local_town_integration_test.dart
flutter analyze
```


## Google DriveからCloudFrontの接続先を管理する（固定URL方式）

ことほぐのCloudFront接続先はGoogle Driveの公開テキスト `kotohogu_api.txt` に記載した1行のURLで管理します。新しいアプリはそのURLを**CloudFrontの接続先情報**として扱い、AWSの `/current.json` で最新版を確定します。アプリにCloudFrontのURLはハードコードしていません。

- DriveのファイルIDはアプリに登録します。ファイル共有は「リンクを知っている全員：閲覧者」を設定します。アクセストークン・AWS認証情報を入れないでください。
- 通常起動ではDriveの `/uc?export=download&id=...&t=...` を取得し、その1行を検証後、CloudFrontの `/current.json` を1回取得してリリースIDを確定します。続いてその不変リリースのキャラ・セリフ・PNGのみを読みます。`current.json` の取得・検証に失敗した場合は、古いデータへの自動切り替えをせず停止します。
- 現在のDriveファイルは `https://<CloudFrontドメイン>/releases/<SHA-256>/` の形式です。新しいアプリはこのURLの**ドメイン部分を利用して `/current.json` を読む**ため、Driveの値を変更する必要はありません。将来 `https://<CloudFrontドメイン>/current.json` と直接書く形式も新しいアプリで認識できますが、古いアプリとの互換性のため、今は変更しないでください。
- CMS更新時には `python tools/aws/publish_content.py --stack kotohogu-content --region ap-northeast-1 --profile new-aws` を実行するだけで、新しいリリースと `/current.json` が更新されます。`Pinned release base URL` のコピーやGoogle Driveの編集は不要です。リリース成功の表示とCloudFrontの `/current.json` の取得確認をしてください。
- アプリがDriveを再取得する場面では、CloudFrontの `/current.json` も改めて読んで最新リリースを確定します。Drive/CloudFront/JSONが失敗したらエラーを表示し、バンドル済みのキャラへ暗黙には切り替えません。切り替わったリリースの画像とセリフは同じハッシュの場所から読みます。
- `--dart-define=KOTOHOGU_LOCAL_CONTENT_URL=http://10.0.2.2:8765` のデバッグ上書きは維持します。リリースビルドでこの上書きを指定するとエラーで停止します。

Google Drive経由の本編起動（URLを直接指定する必要なし）：

```powershell
flutter run -t lib/main.dart
```

Driveの共有設定を確認したうえで、アプリが再起動時に最新URLを読み込むか確認します。ネットワーク不可時は初期画面で処理を停止します。

**現在の実装範囲**：サーバー由来のキャラはまだ「来訪者」（まちでの表示と通常セリフのみ）です。ガチャ・所持・正式な会話条件は従来の同梱データで動作しています。Drive経由のURL管理は導入されましたが、完全な動的住民への移行は次段階です。
