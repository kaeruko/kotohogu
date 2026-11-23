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
aws cloudformation deploy --template-file tools/aws/content-stack.yaml --stack-name kotohogu-content --region ap-northeast-1 --profile kotohogu --capabilities CAPABILITY_IAM
aws cloudformation describe-stacks --stack-name kotohogu-content --region ap-northeast-1 --profile kotohogu --query "Stacks[0].Outputs" --output table
```

表示される `ContentBucketName`, `ContentDistributionId`, `ContentDomain`, `GitHubContentDeployRoleArn` を確認してください。
S3はすべてのパブリックアクセスをブロックし、**公開はCloudFront経由のみ**です。バケット削除防止のためCloudFormationではS3に `Retain` を指定しています。独自ドメインは不要で `https://<ContentDomain>/` を使えます。

このテンプレートは、AWSアカウントに `token.actions.githubusercontent.com` のGitHub OIDCプロバイダーが既にあることを前提にします。発行ロールはGitHubの不変ID付きsubject `repo:kaeruko@4452841/kotohogu@1373321581:ref:refs/heads/main` だけを信頼し、このスタックの参照と配信バケットの読み書きだけを許可します。GitHubリポジトリ設定の `use_immutable_subject` を変更した場合は、CloudTrailで実際のsubjectを確認して `GitHubRepositoryIdentity` も同時に更新してください。

## GitHub Actionsから発行

初回だけ、スタック出力のロールARNをリポジトリ変数へ登録します（値はシークレットではありません）。

```powershell
$roleArn = aws cloudformation describe-stacks --stack-name kotohogu-content --region ap-northeast-1 --profile kotohogu --query "Stacks[0].Outputs[?OutputKey=='GitHubContentDeployRoleArn'].OutputValue | [0]" --output text
if ($LASTEXITCODE -ne 0 -or -not $roleArn -or $roleArn -eq "None") { throw "GitHub発行ロールを取得できません" }
gh variable set AWS_CONTENT_DEPLOY_ROLE_ARN --body $roleArn
```

以後は `assets/characters/`、`assets/dialogues/dialogues.json`、`assets/events/oyasumi_club.json`、`assets/story/`、CMS／AWS発行ツールの変更を `main` へpushすると自動発行します。再発行したい場合は GitHub の **Actions** → **Publish AWS content** → **Run workflow** でブランチ `main` を選んで手動実行もできます。ワークフローはCMS／発行ツールとFlutter側の配信契約テスト、S3への不変リリース発行、`current.json` 更新、CloudFrontからの公開確認を順番に行います。同時発行は直列化され、AWS認証はOIDCの短期セッションだけを使います。READMEだけの変更など、配信内容に影響しないpushでは実行しません。

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

- `releases/<sha256>/api/runtime/catalog` : 公開用住民カタログ（CMS管理UIや個人データは含みません）
- `releases/<sha256>/api/runtime/oyasumi` : おやすみクラブの配信設定（章・出演者・会話・解放条件）
- `releases/<sha256>/api/runtime/story` と `api/runtime/story-images/` : 数独ストーリーと参照する挿絵
- `releases/<sha256>/api/runtime/sprites/<folder>/*.png` : 実際に使うPNGのみ（元のスプライトシート、プレビューGIFなどはアップしません）
- `releases/<sha256>/manifest.json` : 全ファイルのSHA-256とサイズ一覧
- `current.json` : 最新の確定したリリースへの参照先（**最後に**更新）

S3への転送後はキーとサイズを照合し、最新版ポインタを更新するまで以前の配信を維持します。同じ内容の再実行では同じリリースIDになります。アップロード失敗時は例外と診断情報を出して停止し、自動の経路切り替えはしません。

**重要**：新しいアプリはGoogle Driveの `kotohogu_api.txt` に記載されたURLからCloudFrontドメインを特定し、そのドメインの `/current.json` を毎回取得して最新版リリースを確定します。新しいCMSデータを公開するときは、上記 `publish_content.py` だけでよく、**Google Driveファイルは書き換えないでください**。更新されたリリースは次回の起動・再読み込み時に反映されます。古いアプリは従来の固定リリースURLを直接使うため、最新版への自動追従にはアプリの更新が必要です。

### 数独ストーリーを更新する

初回は **数独入りのAWSリリースを先に発行し、その後で対応版アプリを配布**します。対応版は住民・おやすみクラブと同じリリースから数独を読み込みます。以降は `assets/story/story.json` と参照先のPNGを更新して発行すると、対応版の次回起動・再読み込みに反映されます。

- `title`、`clue`、`result`、会話の本文、クリア後の会話、挿絵は更新できます。`coverImage`・各話の `image`・任意の `resultImage` には `assets/story/` 直下のPNGファイル名を指定します。会話の `speaker` は同じリリースの住民IDです。
- 新しい話は `episodes` の末尾へ追加し、重複しない `id` と累計ことほぎの `unlockAt` を設定します。`puzzle` と `solution` は4×4または6×6を左上から行順に並べた文字列で、空欄は `0` です。解が一意であることを発行前に検証します。
- 途中セーブを保つため、公開済みの話のID・順番・場所・解放条件・問題・解答・解く前の会話の件数は固定です。公開済みの話を削除したり、これらを変更したりすると発行が停止します。
- 手元では既存のローカルCMSを起動し、`KOTOHOGU_LOCAL_CONTENT_URL` を指定した本編のホームから数独を確認できます。

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

`KOTOHOGU_LOCAL_CONTENT_URL` はデバッグ専用です。通常のリリースアプリではこの指定を受け付けません。**対応版アプリ**はCloudFrontの公開カタログからガチャ対象を選び、ガチャで迎えた未コンパイル住民IDも所持台帳・住民一覧・屋外のまちに表示します。未所持住民の「配信テストの来訪者」表示はデバッグ専用のままです。

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

**現在の実装範囲**：ガチャ抽選・所持回数・住民一覧・屋外のお出かけ・基本的な挨拶は動的ID対応です。ガチャOFFの住民も所持セーブが残る限り公開カタログへ維持してください。特別な施設配置、既存のネームドイベント参加、条件付き複数人会話などの追加は現時点では個別のアプリ改修が必要です。**初回の対応バイナリ公開が必要**で、現在のストア版へAWS配信するだけではガチャ動的化されません。
