# ことほぐ Google Play AAB リリース

初回リリースのAndroid applicationIdは `jp.cloxs.kotohogu`。
iOSのBundle IDと文字列は同じですが、ストア登録と署名はそれぞれ独立しています。
同じIDで既存のGoogle Playアプリがないことを初回登録時に確認してください。

## 1. アップロード用の鍵をWindowsで作成する

**まだAndroidのアップロード鍵を作っていない場合だけ**、PowerShellで作成：

```powershell
cd "$HOME\Downloads\keys"
keytool -genkeypair -v -keystore kotohogu-upload.jks -alias kotohogu -keyalg RSA -keysize 4096 -validity 10000
```

鍵ファイル、ストアパスワード、鍵パスワードを**安全な場所にバックアップ**。
将来のアップデートでも同じ署名鍵が必要です。
`.jks` はGitHubにコミットしないでください。

## 2. GitHub Secrets

GitHub → kotohogu → Settings → Secrets and variables → Actions →
`New repository secret` で登録：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `kotohogu-upload.jks` をBase64化した文字列 |
| `ANDROID_KEYSTORE_PASSWORD` | 作成時のキーストアのパスワード |
| `ANDROID_KEY_ALIAS` | `kotohogu`（作成時に設定したalias） |
| `ANDROID_KEY_PASSWORD` | 秘密鍵のパスワード |

Base64はPowerShellでクリップボードにコピー：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path '.\kotohogu-upload.jks'))) | Set-Clipboard
```

この4つが揃っていない場合はビルドを中断し、デバッグ用鍵にフォールバックしません。

## 3. GitHub ActionsでAABを作成

Actions → `Android signed AAB` → `Run workflow`（main）を実行。

- `pubspec.yaml` の `version: 1.0.0+1` なら `1.0.0+2` のAABを作ります。
- AABの署名を確認し、Artifactsに `kotohogu-android-1.0.0-2` を保存します。
- 成功した場合**だけ** `pubspec.yaml` のビルド番号を+1してmainにコミット。
- ビルド失敗時はバージョン変更をコミットしません。
- コード更新と同時進行で `pubspec.yaml` が変わっていたら、上書きせずエラーにします。

`versionName`（1.0.0）は維持し、`versionCode`（+1 → +2）を増やす方式。
新しい公開バージョン名（1.0.1等）は別途変更してください。
初回登録時はGoogle Playのアプリを作成して、アップロード鍵を設定する必要があります。
**このワークフローはAAB作成だけ**で、Google Playへのアップロード・公開は行いません。

## Windowsでローカルにビルドする場合

リポジトリ外に置いた `.jks` を参照する `android/key.properties` を作ります。

```properties
storeFile=C:/Users/YourUser/Downloads/keys/kotohogu-upload.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=kotohogu
keyPassword=YOUR_KEY_PASSWORD
```

上記は説明用の値なので、本物の値をGitHubにコミットしないでください。
`android/key.properties` は `.gitignore` 対象です。

```powershell
.\scripts\build_aab.ps1
```

ローカルビルド前に `jarsigner` を確認します。PATHから見つからない場合は、
`JAVA_HOME\bin\jarsigner.exe` を使用します。いずれにも存在しない場合は、
ビルド前に停止します（署名検証のスキップや別方式への自動切り替えはしません）。
Flutterのビルドだけが成功する場合は `flutter doctor -v` で使用中のJavaを確認し、
`jarsigner.exe` を含むJDKのルートディレクトリを `JAVA_HOME` に設定してください。

```powershell
$env:JAVA_HOME = 'C:\path\to\your\jdk'
if (-not (Test-Path (Join-Path $env:JAVA_HOME 'bin\jarsigner.exe') -PathType Leaf)) {
    throw 'The selected JAVA_HOME does not contain jarsigner.exe'
}
.\scripts\build_aab.ps1
```

**すでにGoogle Playへ公開済みの場合、新しいキーストアを作り直さないでください。**
初回公開に使用したアップロード鍵で署名する必要があります。

署名検証とAAB生成が成功した場合だけ `pubspec.yaml` を+1します。
複数PCやGitHub Actionsで同時にAABを作ると番号の衝突が起きるため、
公開ビルドは片方ずつ実行してください。
