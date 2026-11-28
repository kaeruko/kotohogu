# コトホグル対戦API（試験用）

CMS配信とは別スタック。API Gateway HTTP API / Lambda / DynamoDB。
4×4の human-mini-v1 のみ。先手後手はサーバーがランダムに決める。
8文字の待ち合わせ番号（紛らわしい文字を除いた32種類、約40ビット）を
共有する。端末ごとに暗号学的乱数32バイトを小文字16進数64文字にして
生成・安全に保存し、全リクエストの Authorization: Bearer に付ける。
番号だけでは参加後の盤面参照・操作はできない。参加時は番号を知る最初の
相手が入室するので、公開投稿には載せない。アカウント・名前・健康情報は送らない。

## API

全POSTの本文はJSONオブジェクト。GETは本文なし。レスポンスは最新の状態
（code, rules, status, revision, expiresAt, givens, board, bonusRoom,
flags, turn, targetRoom, lastCell, winner, finishReason, yourSide,
playerCount, scores）。board/givensは16文字、cellは0始まり、部屋は1始まり。
turnは終了時・準備中null。targetRoomのnullは自由選択（playingのとき）。
解答・認証トークン・ハッシュは応答に含めない。

| HTTP | パス | JSON |
|---|---|---|
| POST | /v1/rooms | {} |
| POST | /v1/rooms/{code}/join | {} |
| GET | /v1/rooms/{code} | なし |
| POST | /v1/rooms/{code}/bonus | {"revision":1,"room":3} |
| POST | /v1/rooms/{code}/move | {"revision":2,"cell":1,"digit":2} |
| POST | /v1/rooms/{code}/resign | {"revision":2} |

waiting → choosing_bonus → playing → finished。
入室の再送は同じトークンなら状態を返す。その他の更新はrevisionと
内部generationをDynamoDBの条件付き書き込みで照合。
誤答（422 wrong_digit）・不正マス（422 illegal_cell）は手番と盤面を保持。
409 stale_revision はGETで確認し、ユーザーの操作なしに別手を再送しない。
作成結果が通信切断で失われた場合は部屋番号を復元できない（24時間で期限切れ）。
作成の暗黙再試行はしない。入室済みの端末は番号とトークンでGET再開できる。
期限は作成から24時間、TTL物理削除が遅れてもAPIは期限を厳守。
制限時間・ランキング・マッチング・通知・ブラウザCORSはまだ未実装。
現盤面は試験用1種のみ、完全公平ではない。公開ランキングには使わない。

## AWSへの初回試験デプロイ

既存のCMS配信スタックとは分離する。AWSリソースには利用料金が生じる。
利用アカウントを確認し、まずユニットテストを実行する。

~~~powershell
cd C:\Users\mail\work\kotohogu
git pull --ff-only origin main
python -m unittest discover -s tools/aws -p "test_duel_api.py" -v
if ($LASTEXITCODE -ne 0) { throw "対戦APIテスト失敗" }
aws sts get-caller-identity --profile kotohogu
if ($LASTEXITCODE -ne 0) { throw "AWS認証失敗" }
python tools/aws/deploy_duel.py --profile kotohogu --region ap-northeast-1 --stack kotohogu-duel
if ($LASTEXITCODE -ne 0) { throw "対戦APIデプロイ失敗" }
~~~

profileは既に設定済みのAWSプロファイルを明示する。
表示されたDuelApiUrlが接続先。CloudFormationの操作権限が必要。
リポジトリへのAWSアクセスキー登録やCMSのDrive URL変更は不要。
GitHubへのpushだけではAWSを作成・変更しない。

API Gatewayの全体スロットルは毎秒10、バースト20、ログ保持7日。
これは小規模試験用の初期値で、公開前には悪用対策（作成・入室の
個別制限、監視、予算アラーム、負荷検証）を追加する。
端末側の安全なトークン保存、待ち合わせ画面、ポーリング、通信エラー表示は次の工程。
