# ことほぐ（Kotohogu）

> 今日できたことを、まちのみんなと「ことほぐ」。

**ことほぐ**は、日々のセルフケアや人とのつながり、小さな挑戦を、動物たちが暮らすまちで祝うアプリです。

筋力を使った、外へ出た、誰かと話した、好きなことを楽しんだ。そんな行動をミッションとして記録すると、住民たちが拍手をしてくれます。がんばりを数値で競うのではなく、**今日できたことを喜ぶ**ための仕組みです。

介護予防や Healthy Ageing（健康に年齢を重ねること）をテーマにしていますが、介護が必要になることや、休むことを失敗として扱いません。

## できること

- **ミッション**：デイリー7種類・ウィークリー4種類・マンスリー3種類。達成したら「できた！」で記録します。細かい運動量の入力は不要です。
- **言祝ぎ（ことほぎ）**：達成時に住民の拍手と祝福演出が表示され、1ミッションにつき10ことほぎを獲得します。獲得累計と、ガチャに使える残高は別に管理します。
- **みんなのまち**：住民がそれぞれのエリアを歩き、タップすると会話できます。累計獲得量に応じて行ける場所が増えます。
- **住民との出会い**：ことほぎを使う無料ガチャで住民を迎えられます。10回分の抽選には1回のおまけが付きます。課金ガチャではありません。
- **会話と小さな物語**：日付、ミッションの達成状況、既読のセリフ、同じ場所にいる住民などによって話が変わります。
- **履歴**：達成した日と行動をカレンダーなどで振り返れます。できなかった日への減点や連続記録の強制はありません。
- **施設**：条件を満たすと、つやこさんの「桜の美容室」や、とんこの薬草茶房に出会えます。

### まちのエリア

| エリア | 開放に必要な累計ことほぎ |
| --- | ---: |
| 中央ひろば | 0 |
| ふれあい公園 | 90 |
| ことほぎ商店街 | 180 |
| のんびり里 | 300 |

開放の判定には**これまでに獲得した累計**を使います。ガチャで残高を使っても、開放済みのエリアは閉じません。住民は基本的に登録されたエリアで暮らし、未開放の屋外エリアの住民は中央ひろばに一時的に集まります。

施設の開放や会話の正確な条件は [まち・住民・会話のルール](docs/town-dialogue-rules.md) にまとめています。

## 開発環境

- Flutter / Dart（CIの固定バージョン：**Flutter 3.47.6**）
- Android、iOS向けのFlutterアプリ
- Python 3（ローカルCMS、配信ツール、テスト）
- コンテンツの公開に必要な場合のみ AWS CLI v2

Flutterプロジェクトの内部名は現在も `future_lift` です（`pubspec.yaml` や一部クラス名など）。**利用者向けのアプリ名は「ことほぐ」**です。READMEでは現行のアプリ名に統一しますが、互換性に関わる内部識別子はドキュメント変更だけでは改名しません。

## アプリを起動する

リポジトリのルートで実行します。

```powershell
git clone https://github.com/kaeruko/kotohogu.git
cd kotohogu
flutter pub get
flutter devices
flutter run -t lib/main.dart
```

複数デバイスがある場合は `flutter run -d <device-id> -t lib/main.dart` で指定してください。Flutter SDKやAndroid SDK／Xcodeのセットアップは利用する環境に応じて事前に行います。

**現在の通常起動はネットワーク接続が必要です。** アプリは起動時にGoogle Driveの公開テキストからCloudFrontの接続先を特定し、そのCloudFrontの `current.json` から最新の不変リリースを確定して配信データを取得します。Drive・`current.json`・JSONの取得や検証に失敗した場合はエラーを表示して止まり、別のデータへ暗黙に切り替えません。

### アプリアイコン

**元画像は `assets/icon/icon.png` の1枚**です。Android・Web用の生成設定は `pubspec.yaml` の `flutter_launcher_icons`、iOS用は `ios_app_icon_config.yaml` にあります。

ローカルでAndroid/Webのアイコンを再生成したい場合は、リポジトリのルートで次を実行してください。

```powershell
flutter pub get
dart run flutter_launcher_icons -f pubspec.yaml
```

`main` の画像・設定変更時には GitHub Actions の **Sync launcher icons** が Android の `mipmap-*/ic_launcher.png` と Web のアイコン／favicon を生成し、差分があればコミットします。これにより開発中のAndroidアプリも生成済みのアイコンを使えます。

iOSの `ios/` プロジェクトはリポジトリに含まず、**iOS App Store IPA** の実行時に `flutter create` で作成してから `dart run flutter_launcher_icons -f ios_app_icon_config.yaml` を実行します。したがって、iOS用画像をGitへ保存する必要はありません。既に端末にインストール済みのアイコンが古い場合は、新しいビルドを再インストールして確認してください。

### ローカルCMSを起動する

住民のプロフィール、居住エリア、セリフ、表示条件などを編集するCMSは、Python標準ライブラリで動く**ローカル専用**のツールです。

```powershell
python tools/dialogue_cms/server.py
```

ブラウザで **http://127.0.0.1:8765** を開きます。停止するにはターミナルで `Ctrl+C` を押します。

CMSでは、主に次の内容を扱えます。

- 住民の登録・設定（名前、プロフィール、画像フォルダ、居住エリア、ガチャ登場など）
- セリフの作成と自動採番、優先順位、初回限定表示
- 累計ミッション・達成当日・日付・曜日・ことほぎ・既読セリフ・同席住民などの条件
- 条件のAND/OR、掛け合い、仮の条件でのプレビュー

保存すると、`assets/characters/characters.json` と `assets/dialogues/dialogues.json` に加えて、必要な場合は `lib/resident_collection.dart` と `pubspec.yaml` のCMS管理領域を更新します。

**CMSで保存してもGitHubや公開アプリは自動更新されません。** 変更ファイルを確認し、テストしてからGitへコミットしてください。既存キャラのID・セリフIDは保存データや既読判定に関係するため、安易に変更しないでください。

住民追加時のスプライト規約、検証方法、ローカル配信プレビューは [セリフCMSの詳しい使い方](tools/dialogue_cms/README.md) を参照してください。

### ローカルの配信データを本編で確認する

Androidエミュレーターなら、CMSを起動したまま別のターミナルで次を実行します。

```powershell
flutter run -t lib/main.dart --dart-define=KOTOHOGU_LOCAL_CONTENT_URL=http://10.0.2.2:8765
```

`10.0.2.2` はAndroidエミュレーターからホストPCへ接続するためのアドレスです。実機用のURLではありません。この上書き指定は**非リリースビルド専用**で、リリースビルドに指定するとエラーになります。

現時点でサーバーから取得する追加住民は、主に**まちを訪れる「来訪者」**として表示されます。来訪者の会話・表示はガチャの所持状態や既読セーブには反映しません。既存のガチャ・所持・条件付き会話はアプリに同梱された住民定義を使っています。**すべての住民をサーバー側だけで自由に更新できる設計には、まだ移行していません。**

## コンテンツ配信（AWS + Google Drive）

アプリのコンテンツ公開は、ローカルCMSと次の仕組みを組み合わせています。

```text
ローカルCMS（住民・セリフ・画像）
          ↓
tools/aws/publish_content.py
          ↓
非公開S3 → CloudFront（固定リリースURL）
          ↑
Google Driveの kotohogu_api.txt に接続先URLを記載
          ↑
アプリがDriveの接続先からCloudFront /current.jsonを読み、最新リリースを取得
```

配信するJSON・スプライトは検証後に**内容に基づく不変のリリースパス**へアップロードされます。`current.json` は最新版を指し、新しいアプリはGoogle Driveに保存した接続先URLからこのポインタを取得して参照するリリースを決めます。これにより、**普段のCMS更新ではAWSへのアップロードだけでよく、Google Driveの変更は不要**です。旧アプリは従来の固定リリースを参照し続けるため、最新版に追従するにはアプリ更新が必要です。

既にCloudFormationスタックがある場合の発行例：

```powershell
$awsProfile = 'kotohogu' # 実際に設定したAWS CLIプロファイル名に変更
python tools/aws/publish_content.py --stack kotohogu-content --region ap-northeast-1 --profile $awsProfile
```

発行後、CloudFrontの `/current.json` が更新されます。**既存の `kotohogu_api.txt` は書き換えないでください**。新しいアプリではそこに記載されたURLのCloudFrontドメインから最新版を取得します。発行時に出る `Pinned release base URL` は特定のリリースを手動確認するためにも利用できます。

初回のインフラ構築、AWS権限、公開内容の検証、Drive共有設定については [AWS配信の手順](tools/aws/README.md) を参照してください。認証情報、署名鍵、パスワードはGitへコミットしないでください。

## テスト

リポジトリのルートで実行します。

```powershell
flutter pub get
flutter analyze
flutter test
python -m unittest discover -s tools/dialogue_cms -p "test_*.py"
python -m unittest discover -s tools/aws -p "test_*.py"
python -m unittest discover -s tools/android -p "test_*.py"
```

GitHub Actionsでは、Flutterの解析・テスト・WebビルドやPythonのテストを実行します。ローカルCMSによるJSON更新や住民追加の後は、少なくともCMSテスト・`flutter analyze`・`flutter test` を確認してください。

## 主なディレクトリ

| パス | 内容 |
| --- | --- |
| `lib/` | Flutterアプリ本体、ミッション、ガチャ、会話、まち、セーブ処理 |
| `assets/characters/` | 住民台帳とスプライト |
| `assets/dialogues/` | CMSで編集するセリフと条件 |
| `assets/kotohogu/` | まち・施設背景、UI素材 |
| `tools/dialogue_cms/` | ローカルCMSとそのテスト |
| `tools/aws/` | CloudFormation、コンテンツ発行ツール |
| `tools/android/`、`tools/ios/` | 配布ビルド支援 |
| `test/` | Flutterのユニット／Widgetテスト |
| `docs/` | 開発・公開・仕様の詳細ドキュメント |

## 配布ビルド

- **Android（AAB）**：GitHub Actionsの `Android signed AAB`、または `scripts/build_aab.ps1`。署名確認後にビルド番号を更新します。詳しくは [Androidリリース手順](docs/android_release.md)。
- **iOS（IPA / TestFlight）**：GitHub Actionsの `iOS TestFlight (Build and Upload)` で署名付きIPAを生成し、そのままTestFlightへアップロードします。`enable_developer_menu` をONにしたテスト専用ビルドでは、「メニュー」内に開発メニューへの入口が表示されます。公開版は必ずOFFでビルドしてください。詳しくは [iOSリリース手順](docs/ios_release.md)。

ストアへの公開・審査提出は自動では行いません。

## 設計で大切にしていること

**「できなかった日」ではなく、「できた行動」を祝うこと。**

- できなかった日を責めたり、記録が途切れたことで罰を与えたりしない。
- 誰かの体力や生活状況と競わせない。少しだけできたことも尊重する。
- 介護が必要な状態を「努力不足」とみなさない。
- 健康情報は根拠と不確実性を区別し、効果を保証しない。
- 保存や配信データが壊れたときは、勝手に別の値や別のデータへ差し替えず、原因を確認できるようにする。

ことほぐは、疾病の診断・治療や、個人の医療費・介護費削減を予測するアプリではありません。アプリ内に表示する研究由来の参考推計も、**その人が今回のミッションによって削減した金額**を表すものではありません（実装・前提は `lib/social_security_estimate.dart`）。

健康情報の考え方の参考：

- [WHO: Healthy ageing and functional ability](https://www.who.int/news-room/questions-and-answers/item/healthy-ageing-and-functional-ability)
- [NICE NG16: Dementia, disability and frailty in later life](https://www.nice.org.uk/guidance/ng16/chapter/Recommendations)
- [Lancet Commission (2024): Dementia prevention, intervention, and care](https://pubmed.ncbi.nlm.nih.gov/39096926/)

---

**自分を大切にした今日を、まちのみんなと祝おう。**
