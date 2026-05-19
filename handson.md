# Drupal ToDo App — ハンズオン手順

このリポジトリには、Drupal 10 を用いた最小構成の **ToDo アプリ** が含まれています。
カスタムモジュール `todo_app` が `todo` コンテンツタイプと `/todos` 一覧ビューを提供し、PHPUnit による Functional テスト（TDD）でカバーされています。

---

## 0. 前提条件

| ツール | バージョン |
| ------ | -------- |
| Docker | 20.10+ |
| Docker Compose | v2.0+ |

ポート **8080** が空いていること。

---

## 1. 起動

リポジトリのルートで:

```bash
docker compose up -d
```

コンテナが起動するまで 30 秒〜1 分ほど待ちます。状態確認:

```bash
docker compose ps
```

期待する出力（両方 `Up` / `healthy`）:

```
NAME           IMAGE              STATUS                    PORTS
drupal-db      mariadb:10         Up (healthy)              3306/tcp
drupal-todo    drupal:10-apache   Up                        0.0.0.0:8080->80/tcp
```

---

## 2. Drupal 初期セットアップ（初回のみ）

### 2-1. Drush・PHPUnit・mysql クライアントのインストール

公式 Drupal イメージには Drush・PHPUnit・mysql クライアントが含まれないため、初回だけインストールします。

```bash
# mysql クライアント（drush が DB を扱うために必要）
docker compose exec drupal bash -c 'apt-get update -qq && apt-get install -y -qq default-mysql-client'

# drush
docker compose exec drupal composer require drush/drush --working-dir=/opt/drupal --no-interaction

# 開発用パッケージ（PHPUnit を含む）
docker compose exec drupal composer require --dev phpunit/phpunit drupal/core-dev:^10 \
  --working-dir=/opt/drupal --no-interaction --with-all-dependencies
```

### 2-2. Drupal をインストール

> ⚠ このコマンドは **初回のみ** 実行します。既にインストール済みの状態で再実行すると
> `AlreadyInstalledException` で失敗します。リセットしたい場合は §6「停止 / クリーンアップ」を参照してください。

```bash
docker compose exec drupal /opt/drupal/vendor/bin/drush site:install standard \
  --db-url="mysql://drupal:drupal@db/drupal" \
  --site-name="Drupal ToDo App" \
  --account-name=admin \
  --account-pass=admin \
  --yes
```

成功すると `[success] Installation complete.` と表示されます。

### 2-3. 動作確認

ブラウザで http://localhost:8080 を開く、または:

```bash
curl -sI http://localhost:8080 | head -1
# => HTTP/1.1 200 OK
```

管理者でログイン: ユーザー `admin` / パスワード `admin`

---

## 3. ToDo モジュールを有効化

```bash
docker compose exec drupal /opt/drupal/vendor/bin/drush en todo_app -y
```

成功すると `[success] Module todo_app has been installed.` と表示されます。

このコマンドだけで以下が **すべて自動で作成されます**:

- [x] `todo` コンテンツタイプ
- [x] `field_status`（Done / Not done）
- [x] `field_description`（説明文）
- [x] `/todos` 一覧ビュー

---

## 4. ToDo を操作する

### ブラウザから

| URL | できること |
| --- | ---------- |
| http://localhost:8080/todos | ToDo 一覧（タイトル + Done 状態） |
| http://localhost:8080/node/add/todo | ToDo を新規追加 |
| http://localhost:8080/node/1/edit | ID=1 の ToDo を編集（Done にチェック等） |

### CLI から（drush ev）

```bash
# 追加
docker compose exec drupal /opt/drupal/vendor/bin/drush ev '
$node = \Drupal\node\Entity\Node::create([
  "type" => "todo",
  "title" => "Buy milk",
  "field_description" => "Get 1 liter from the store.",
  "field_status" => 0,
  "status" => 1,
]);
$node->save();
print "Saved nid=" . $node->id() . PHP_EOL;'

# 一覧
docker compose exec drupal /opt/drupal/vendor/bin/drush ev '
$nodes = \Drupal::entityTypeManager()
  ->getStorage("node")
  ->loadByProperties(["type" => "todo"]);
foreach ($nodes as $n) {
  $done = (string) $n->get("field_status")->value === "1" ? "[x]" : "[ ]";
  print "$done {$n->id()}: {$n->getTitle()}" . PHP_EOL;
}'

# Done に変更（nid=1 を完了にする）
docker compose exec drupal /opt/drupal/vendor/bin/drush ev '
$n = \Drupal\node\Entity\Node::load(1);
$n->set("field_status", 1)->save();
print "marked done" . PHP_EOL;'
```

---

## 5. テストの実行（TDD）

### 5-1. 権限の準備（初回のみ）

```bash
docker compose exec drupal bash -c '
  mkdir -p /opt/drupal/web/sites/simpletest &&
  chown -R www-data:www-data /opt/drupal/web/sites &&
  chmod -R 777 /opt/drupal/web/sites/simpletest /tmp'
```

### 5-2. テスト実行

```bash
docker compose exec -u www-data \
  -e SIMPLETEST_BASE_URL=http://localhost \
  -e SIMPLETEST_DB=mysql://drupal:drupal@db/drupal \
  -e BROWSERTEST_OUTPUT_DIRECTORY=/tmp \
  drupal bash -c 'cd /opt/drupal/web && ../vendor/bin/phpunit \
    -c core/phpunit.xml.dist \
    modules/custom/todo_app/tests/'
```

期待される結果:

```
OK (6 tests, 30 assertions)
```

### 5-3. テスト内容

`custom_modules/todo_app/tests/src/Functional/TodoAppTest.php` に 6 つのケース:

- [x] `testTodoContentTypeExists` — `todo` コンテンツタイプが存在する
- [x] `testTodoHasStatusField` — `field_status`（boolean）が存在する
- [x] `testTodoHasDescriptionField` — `field_description`（text_long）が存在する
- [x] `testCanCreateTodo` — Todo ノードを作成・保存できる
- [x] `testCanMarkTodoDone` — `field_status` を 1 に更新できる
- [x] `testTodosListViewExists` — View `todos` が存在し `/todos` で 200 を返す

---

## 6. 停止 / クリーンアップ

### 一時停止（データは残る）

```bash
docker compose stop
```

再開:

```bash
docker compose start
```

### 完全削除（DB・モジュール・テーマも消える）

```bash
docker compose down -v
```

`-v` を付けないと named volumes（DB データ等）が残るので、完全リセットしたいときは必ず `-v` を付けます。

---

## 7. トラブルシューティング

### `docker compose up -d` 後にすぐ Drupal がエラー
DB の起動を待ち切れていない可能性があります。30 秒待ってから再度アクセスしてください。
`drupal-db` の status が `(healthy)` になるまで待つのが確実です。

### `[preflight] Package "drupal/core" is not installed`
Drush は `/opt/drupal/composer.json` を見ます。コマンドの `--working-dir=/opt/drupal` を付け忘れていないか確認してください。

### `Drush was unable to drop all tables because 'mysql' was not found`
mysql クライアントがコンテナにインストールされていません。§2-1 のコマンドで導入してください:
```bash
docker compose exec drupal bash -c 'apt-get update -qq && apt-get install -y -qq default-mysql-client'
```

### `AlreadyInstalledException` / `To start over, you must empty your existing database`
既に Drupal がインストール済みの状態で `drush site:install` を再実行するとこのエラーになります。

- **そのまま使う場合**: 何もせず http://localhost:8080 にアクセス（既に動作中）
- **完全リセットしたい場合**:
  ```bash
  docker compose down -v   # ボリュームごと削除
  docker compose up -d     # 起動し直し
  # その後、§2-1 と §2-2 を順に実行
  ```

### テストが `Permission Denied (mkdir)` で失敗
ステップ 5-1 の chmod を実行してください。テストランナーは `www-data` で動作する必要があります（`docker compose exec -u www-data` を忘れずに）。

### `/todos` に Todo が表示されない
- [ ] そのノードは「公開済み（published）」か（編集画面の Published チェック）
- [ ] そのノードのコンテンツタイプは `todo` か
- [ ] キャッシュをクリア: `docker compose exec drupal /opt/drupal/vendor/bin/drush cr`

### 設定変更したのに反映されない
モジュールの `config/install/` の YAML を変更しても、既にインストール済みのサイトには反映されません。確実に反映するには:

```bash
docker compose exec drupal /opt/drupal/vendor/bin/drush pm:uninstall todo_app -y
docker compose exec drupal /opt/drupal/vendor/bin/drush en todo_app -y
```

---

## 付録: ディレクトリ構成

```
.
├── docker-compose.yml                  # Drupal 10 + MariaDB
├── handson.md                          # このファイル
├── CLAUDE.md                           # TDD グランドルール
└── custom_modules/
    └── todo_app/
        ├── todo_app.info.yml           # モジュール定義
        ├── config/install/
        │   ├── node.type.todo.yml
        │   ├── field.storage.node.field_status.yml
        │   ├── field.field.node.todo.field_status.yml
        │   ├── field.storage.node.field_description.yml
        │   ├── field.field.node.todo.field_description.yml
        │   ├── core.entity_form_display.node.todo.default.yml
        │   ├── core.entity_view_display.node.todo.default.yml
        │   └── views.view.todos.yml
        └── tests/src/Functional/
            └── TodoAppTest.php         # PHPUnit Functional テスト
```

## 付録: 認証情報まとめ

| 項目 | 値 |
| ---- | -- |
| Drupal URL | http://localhost:8080 |
| 管理者 | `admin` / `admin` |
| DB ホスト | `db`（コンテナ内）/ コンテナ外からは未公開 |
| DB 名 | `drupal` |
| DB ユーザー | `drupal` / `drupal` |
| DB root | `root` / `rootpw` |

> ⚠ これはローカル開発用です。本番では絶対に使わないでください。
