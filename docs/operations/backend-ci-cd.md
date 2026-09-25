# Backend CI/CDとCloudflare

BackendはTypeScriptとHonoで実装し、Cloudflare Workersへ配布します。
この文書では、CloudflareとGitHubが未設定の状態から、stagingの初回配布とproductionの承認付き配布を動かすまでを順番に説明します。

Terraformは環境別stateと将来の長寿命Cloudflare resourceを管理します。
WranglerはWorkerのcode、version、deployment、binding、Custom Domainを管理します。
Custom Domainに付随してCloudflareが自動作成するDNSレコードとTLS証明書もWrangler側の所有範囲とし、Terraformへ重複定義しません。

## 最初に理解すること

実装済みの関連workflowは次の4本です。

| Workflow | Trigger | 役割 |
| --- | --- | --- |
| `Backend CI` | pull request、`main` push、手動、再利用呼び出し | BackendとTerraformのsecretless検証 |
| `Supabase CI` | pull request、`main` push、手動、再利用呼び出し | migration、DB lint、pgTAPのsecretless検証 |
| `Backend CD (staging)` | `main` push | Terraform apply、stagingのDB migration、Worker deploy、health smoke |
| `Backend CD (production)` | `backend-vX.Y.Z` tag、`main`からの手動実行 | production preflight、承認、Terraform apply、DB migration、deploy、health smoke |

配布は次の順序で進みます。

```text
Pull Request
  └─ Backend CI
       ├─ pnpm frozen install
       ├─ Worker型生成差分
       ├─ TypeScript型検査
       ├─ Workers Runtimeテスト
       ├─ Wrangler dry-run
       └─ Terraform fmt / init -backend=false / validate

main push
  └─ staging
       └─ Backend/Supabase verify → Terraform plan/apply → DB migration → Wrangler deploy → /healthz

backend-vX.Y.Z tag または mainからの手動実行
  └─ production
       └─ source検証 → Supabase verify → read-only plan → 承認 → plan再計算/apply → DB migration → deploy → /healthz
```

Supabase Projectの作成、Apple provider、DB資格情報は[Supabase Auth・Database CI/CD](supabase-auth.md)を参照してください。
stagingは`himatch-staging`、productionは`himatch-production`という別Projectを使い、Supabase Branchingで環境を切り替えません。

Backend CIの`Build Worker bundle` stepは、[package.json](../../apps/backend/package.json)の`build` scriptを通じて`wrangler deploy --dry-run --outdir dist`を実行します。

Terraform stateはCloudflare R2へ保存します。
stagingは`cloudflare/staging/terraform.tfstate`、productionは`cloudflare/production/terraform.tfstate`を使います。
Supabase Terraform の宣言のみの root は別 key `supabase/staging/terraform.tfstate`、`supabase/production/terraform.tfstate` を使います。管理対象resourceとimportはまだなく、現在のCDではSupabase rootへ `plan/apply` しません。
R2 bucket自体は、そのbucketをbackendにするTerraform rootでは作成しません。

現在のTerraform rootにはCloudflare resourceがないため、最初のplanが`No changes.`になるのは正常です。
この段階のTerraformはprovider、remote state、環境分離を確立し、Worker本体は後続のWrangler deployが作成または更新します。

CloudflareはR2に対するTerraform S3 native lockfileの互換性を保証していません。
初期構成では`use_lockfile`を有効にせず、GitHub Actionsの環境別`concurrency`でapplyを直列化します。
workflow実行中は、同じstateに対する手動`terraform apply`を並行実行しません。

## 作業を始める前の確認

初回設定を行う担当者には、次の権限と道具が必要です。

- Cloudflare accountでWorkersとR2を設定できる権限。
- R2のAccount API tokenを使う場合はCloudflare accountのSuper Administrator権限。
- GitHub repositoryの`Settings`、`Environments`、`Rulesets`を変更できる管理権限。
- 発行直後にしか表示されないsecretを保存するpassword manager。
- ローカル検証用のNode.js 24、pnpm 11.0.4、Terraform 1.15.1。

R2をまだ利用していない場合は、Cloudflare Dashboardの`Storage & databases`、`R2`、`Overview`を開き、画面の案内に従ってR2 subscriptionを有効化します。
課金条件は作業前にCloudflare Dashboardで確認します。

この手順では、次の資格情報を作成します。

| 種類 | 作成数 | 用途 |
| --- | ---: | --- |
| R2 S3 credential | 3組 | staging read/write、production plan read-only、production read/write |
| Cloudflare API token | 4個 | staging plan、staging apply/deploy、production plan、production apply/deploy |
| GitHub Environment | 3個 | `staging`、`production-plan`、`production` |

### R2 S3 credentialとCloudflare API tokenの役割

R2 S3 credentialとCloudflare API tokenは、どちらもCloudflareで発行しますが、接続先と操作対象が異なります。
一方をもう一方の代わりには使えません。

| 種類 | 接続先 | 使用する処理 | 操作対象 | GitHubへ登録する名前 |
| --- | --- | --- | --- | --- |
| R2 S3 credential | R2のS3-compatible API | Terraform backend | R2 bucket内のTerraform state | `R2_STATE_ACCESS_KEY_ID`、`R2_STATE_SECRET_ACCESS_KEY` |
| Cloudflare API token | Cloudflare API | Terraform provider、Wrangler | Cloudflare resource、Worker、Custom Domain | `CLOUDFLARE_API_TOKEN_READ`、`CLOUDFLARE_API_TOKEN_WRITE` |

Terraformは、一回のplanまたはapplyで2種類の接続を使います。
Terraform backendはR2 S3 credentialを使ってstateを読み書きし、Cloudflare providerはCloudflare API tokenを使って実際のCloudflare resourceを参照または変更します。

workflow内での使い分けは次のとおりです。

1. `terraform init`では、R2 S3 credentialを使って対象環境のstateへ接続する。
2. `terraform plan`では、R2 S3 credentialでstateを読み、read用Cloudflare API tokenでCloudflare resourceを参照する。
3. `terraform apply`では、R2 S3 credentialでstateを読み書きし、write用Cloudflare API tokenでCloudflare resourceを変更する。
4. `wrangler deploy`では、write用Cloudflare API tokenを使ってWorkerとCustom Domainを配布する。

R2 S3 credentialを3組に分ける目的は、state bucketと読み書き権限を環境ごとに隔離することです。

- stagingはplanとapplyで同じread/write credentialを使うため、1組です。
- productionの承認前planはstateを読むだけなので、read-only credentialを1組作成します。
- productionの承認後applyはstateを更新するため、read/write credentialを1組作成します。

Cloudflare API tokenを4個に分ける目的は、stagingとproductionのそれぞれで、参照権限と変更権限を分離することです。

- staging Terraform plan用のread tokenを1個作成します。
- staging Terraform applyとWrangler deploy用のwrite tokenを1個作成します。
- production Terraform plan用のread tokenを1個作成します。
- production Terraform applyとWrangler deploy用のwrite tokenを1個作成します。

現在のTerraform rootにはCloudflare resourceがないため、Cloudflare read tokenが参照する実resourceはまだありません。
それでもplanとapplyの資格情報を分けておくと、将来resourceを追加したときに承認前のplanへ変更権限を渡さずに済みます。

secretの実値をissue、pull request、チャット、repository内のファイルへ貼り付けません。
以降の表へ値を控える場合も、secretはpassword managerにだけ保存します。

## 初回セットアップ

### 1. Cloudflare account、zone、DNS競合を確認する

最初に、Workerを配布するaccountと`beyond-labo.com`を管理するaccountが同一であることを確認します。
Custom Domainは、WorkerとActiveなzoneが同じCloudflare accountにある場合だけ作成できます。
この時点ではtoken、Worker、DNSレコードを作成または変更しません。

#### Account IDを控える

1. [Cloudflare Dashboard](https://dash.cloudflare.com/)へログインする。
2. 対象のaccountを選択する。
3. 左メニューの`Build`、`Compute`、`Workers & Pages`を順に開く。
4. `Account Details`に表示される`Account ID`のcopyボタンを押す。
5. 値を作業メモへ`CLOUDFLARE_ACCOUNT_ID`として控える。

`Account ID`は機密情報ではありませんが、別accountへ誤配布しないように対象account名と一緒に記録します。
Dashboard上部の検索から`Copy account ID`を実行しても同じ値を取得できます。

#### `beyond-labo.com`が同じaccountにあることを確認する

1. 左上のCloudflare logoから`Account home`を開く。
2. 左メニューの`Domains`、`Overview`を開く。
3. 先ほど選択したaccount名のまま、zone一覧に`beyond-labo.com`が表示されることを確認する。
4. `beyond-labo.com`行のzone statusが`Active`であることを確認する。
5. `beyond-labo.com`を開く。
6. `Overview`下部の`Account ID`が、先ほど控えた`CLOUDFLARE_ACCOUNT_ID`と一致することを確認する。

`Domain Registration`の`Status: Active`はregistrar上の登録状態であり、zone statusの確認結果として代用しません。

`beyond-labo.com`が一覧にない、`Active`でない、またはAccount IDが異なる場合は作業を停止します。
その場合は、zoneをWorker配布accountへ移管するか、Workerをzone所有accountへ配布する構成へ変更するかを決定してから、repository設定を見直します。
account間をまたぐ構成を推測で作成しません。

#### `api-staging`と`api`の既存DNSレコードを確認する

1. `beyond-labo.com`の左メニューから`DNS`、`Records`を開く。
2. 検索欄へ`api-staging`を入力する。
3. 名前が`api-staging.beyond-labo.com`のA、AAAA、CNAMEレコードがないことを確認する。
4. 検索欄を`api`へ変更する。
5. 名前が`api.beyond-labo.com`のA、AAAA、CNAMEレコードがないことを確認する。

既存レコードがある場合は、用途と所有者を確認するまで削除しません。
特に既存CNAMEはCustom Domainと競合し、同じ名前のAまたはAAAAとも併存できません。
旧originから移行する場合は、停止手順と切替承認を別途用意してから既存レコードを削除します。

正式な公開先は次の2つです。

| Environment | Worker | Custom Domain |
| --- | --- | --- |
| staging | `himatch-backend-staging` | `api-staging.beyond-labo.com` |
| production | `himatch-backend-production` | `api.beyond-labo.com` |

[wrangler.jsonc](../../apps/backend/wrangler.jsonc)は各hostnameを`routes[].pattern`へ指定し、Worker自身をoriginにする`custom_domain: true`を設定しています。
通常のRouteを表す`/*`は付けません。
正式なCustom Domainだけを公開するため、両環境の`workers_dev`は`false`です。

参考資料は[CloudflareのAccount IDとZone ID確認手順](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/)、[Workers Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)、[Wrangler configuration](https://developers.cloudflare.com/workers/wrangler/configuration/)です。

### 2. Terraform state用のR2 bucketを2つ作成する

stagingとproductionのstateを別々のbucketへ保存します。
分離すると、production planにread-only credentialを与えやすく、stagingの資格情報からproduction stateへアクセスできなくなります。

bucket名の例は次のとおりです。

```text
himatch-terraform-state-staging
himatch-terraform-state-production
```

実際の名前はCloudflare account内で識別できる名前に変更して構いません。
作成後の名前をそれぞれ`staging TF_STATE_BUCKET`と`production TF_STATE_BUCKET`として控えます。

各bucketを次の手順で作成します。

1. Cloudflare Dashboardで`Storage & databases`、`R2`、`Overview`を開く。
2. `Create bucket`を押す。
3. staging用bucket名を入力する。
4. `Location`と`Default storage class`を組織のデータ配置方針に合わせて選ぶ。
5. `Create bucket`を押す。
6. bucket一覧にstaging用bucketが表示されることを確認する。
7. 同じ操作をproduction用bucketでも繰り返す。

Terraform state bucketをpublicにはしません。
R2 bucketは初期状態でprivateなので、`Public Development URL`やcustom domainを有効にしないまま使用します。

location hintは性能上の配置希望であり、法的な保存地域を保証する設定ではありません。
データ所在地の制約がある場合はjurisdictionを選び、そのjurisdiction用としてDashboardに表示されるS3 API endpointを使います。

bucketの作成手順と命名制約は[Cloudflare R2のbucket作成手順](https://developers.cloudflare.com/r2/buckets/create-buckets/)を参照してください。

### 3. R2 S3 credentialを3組作成する

TerraformはR2のS3-compatible APIを使ってstateを読み書きします。
ここで作るAccess Key IDとSecret Access Keyは、Cloudflare providerやWranglerに使うAPI tokenとは別物です。

次の3組を作成します。

| 推奨token名 | Permission | 対象bucket | 後で登録するEnvironment |
| --- | --- | --- | --- |
| `himatch-terraform-staging-rw` | Object Read & Write | staging bucketだけ | `staging` |
| `himatch-terraform-production-plan-ro` | Object Read | production bucketだけ | `production-plan` |
| `himatch-terraform-production-rw` | Object Read & Write | production bucketだけ | `production` |

stagingではcredential管理数を抑えるため、planとapplyが同じread/write R2 credentialを使います。
productionでは誤変更の影響が大きいため、承認前planをread-only、承認後applyをread/writeとして分離します。

各credentialを次の手順で作成します。

1. Cloudflare Dashboardで`Storage & databases`、`R2`を開く。
2. `Account Details`の`API Tokens`にある`Manage`を押す。
3. `Create Account API token`または利用可能なR2 API token作成ボタンを押す。
4. 表の推奨token名を入力する。
5. 表に従って`Object Read`または`Object Read & Write`を選ぶ。
6. bucketの範囲を`Apply to specific buckets only`にし、表に記載した1つのbucketだけを選ぶ。
7. 必要なら有効期限と送信元IP制限を組織方針に合わせて設定する。
8. 内容を確認してtokenを作成する。
9. 表示された`Access Key ID`と`Secret Access Key`をpassword managerへ保存する。
10. どのEnvironment用のcredentialかをpassword managerの項目名へ含める。

`Secret Access Key`は作成画面を離れると再表示できません。
保存に失敗した場合は同じtokenを使い続けず、削除して新しく発行します。

同じ画面に表示される`Token value`は、現在のTerraform remote stateでは使用しないため保存不要です。
TerraformのS3 backendが使うのは`Access Key ID`と`Secret Access Key`であり、GitHub Environmentにもこの2値だけを登録します。
`Token value`を`CLOUDFLARE_API_TOKEN_READ`または`CLOUDFLARE_API_TOKEN_WRITE`へ転用しません。
将来、R2 Temporary Credentials APIなど、Bearer tokenとして`Token value`を直接使う機能を導入する場合は、その時点で専用credentialとして発行し、保存先とローテーション手順を別途定めます。

R2のAccount API tokenはSuper Administratorが作成します。
User API tokenを代わりに使う場合は、発行ユーザーがaccountから削除されるとtokenも無効になるため、個人に依存する運用になることを記録します。

R2画面に表示されるS3 API endpointも控えます。
通常のendpointは次の形式です。

```text
https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com
```

jurisdictionを指定した場合は形式が異なるため、上の文字列を組み立てず、Dashboardに表示されたendpointをそのまま`TF_STATE_ENDPOINT`として使います。
endpointの末尾へbucket名、state key、`/healthz`などのpathを追加しません。

R2 tokenの作成と権限は[Cloudflare R2 API token手順](https://developers.cloudflare.com/r2/api/tokens/)を参照してください。

### 4. Cloudflare API tokenを4個作成する

Terraform providerはCloudflare resourceの参照と変更にCloudflare API tokenを使います。
WranglerはWorkerの作成と配布に同じ種類のtokenを使います。
Global API Keyは使用しません。

次の4個を分けて作成します。

| 推奨token名 | 用途 | 初期構成で必要な権限 | 後で登録するEnvironment |
| --- | --- | --- | --- |
| `himatch-staging-plan-read` | staging Terraform plan | Account Settings Read | `staging` |
| `himatch-staging-deploy-write` | staging apply、Worker deploy、Custom Domain | 初回はWorkers product-level Admin、Account Settings Read、`beyond-labo.com`のWorkers Routes Edit | `staging` |
| `himatch-production-plan-read` | production Terraform preflight | Account Settings Read | `production-plan` |
| `himatch-production-deploy-write` | production apply、Worker deploy、Custom Domain | 初回はWorkers product-level Admin、Account Settings Read、`beyond-labo.com`のWorkers Routes Edit | `production` |

現在のTerraform rootにはCloudflare resourceがないため、read tokenが読む実resourceはまだありません。
将来Terraform resourceを追加したら、そのresourceに対応するRead権限をplan tokenへ、Write権限をdeploy tokenへ追加します。

現在のAccount API token作成画面では、権限設定の単位を`Permission policies`と呼びます。
1個のpolicyは、対象範囲とPermission groupの権限を組み合わせたものです。
対象範囲には、account全体を表す`Entire Account`、account内の全domainを表す`All Domains`、個別domainだけを表す`Specified Domains`、個別Workerだけを表す`Specified Workers`などがあります。
Cloudflare公式資料の`Workers product-level`は、この対象範囲プルダウンの選択肢名ではありません。
現在のDashboardでは対象範囲を`Entire Account`にし、`Developer Platform`カテゴリの`Workers` Permission groupで`Admin`または`Editor`を選ぶと、account内のWorkers製品全体に対するproduct-level権限になります。

今回のwrite tokenで`All Domains`は選びません。
`Workers Routes Edit`の対象を`beyond-labo.com`だけに限定するため、`Specified Domains`を使います。

各tokenを次の手順で作成します。

1. Cloudflare Dashboardで対象accountの`Manage Account`、`Account API Tokens`を開く。
2. `Create Token`を押す。
3. `Token name`へ上表の推奨token名を入力する。
4. `Permission policies`で、作成するtokenに応じて次のpolicyを設定する。

| 対象token | Policyの対象範囲 | Permission groupと権限 |
| --- | --- | --- |
| read token | `Entire Account` | `Account Settings`の`Read` |
| write token | `Entire Account` | `Account Settings`の`Read` |
| write token | `Entire Account` | 初回配布までは`Workers`の`Admin`。初回配布後は`Editor`へ縮小する |
| write token | `Specified Domains`で`beyond-labo.com`を選択 | `Workers Routes`の`Edit` |

5. policyを追加する場合は`Add policy`を押し、表の1行ごとに対象範囲とPermission groupを設定する。
6. `All Domains`は選択せず、domain用policyの対象が`Specified Domains`、`beyond-labo.com`になっていることを確認する。
7. `Specified Workers`は選択しない。
8. `DNS Write`は追加しない。
9. 必要なら`Token expiration`と`Client IP address filtering`を組織方針に合わせて設定する。
10. `Review token`を押す。
11. review画面で、token名、各policyの対象範囲、Permission groupと権限を確認する。
12. `Create Token`を押し、表示されたtoken文字列をpassword managerへ保存する。

旧画面の`Edit Cloudflare Workers` templateや`Account Resources`、`Zone Resources`という表現は、現在のAccount API token画面の`Permission policies`とは対応が異なります。
現在の画面では上表のpolicyを個別に設定し、Workerの作成・配布、Account Settingsの読み取り、`beyond-labo.com`のWorkers Routes変更に必要な範囲へ絞ります。
最初の配布ではWorker自体がまだ存在しないため、Workers product-levelの`Admin`が必要です。
初回配布後はWorkers product-levelの`Editor`へ縮小し、`beyond-labo.com`だけを対象にしたWorkers Routes Editは維持して、GitHub Environment secretをローテーションします。
Custom Domainは現在per-Worker roleをサポートしないため、Custom Domainを管理するtokenを特定Workerだけの`Editor`へ縮小しません。
Custom Domainの自動DNS作成にDNS Writeは不要です。

Cloudflareはtokenの値を作成直後にしか表示しません。
保存に失敗した場合はtokenを削除し、作り直します。

詳しい画面遷移は[Cloudflare Account API tokenの作成手順](https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/)を参照してください。
権限名は[Cloudflare API token permissions](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)で確認できます。
WorkersとCustom Domainの権限要件は[Workers roles and permissions](https://developers.cloudflare.com/workers/authorization/workers/)で確認できます。

### 5. GitHub Environmentを3つ作成する

GitHub repositoryの`Settings`から、`staging`、`production-plan`、`production`を作成します。
workflowを先に実行すると、存在しないEnvironmentが保護なしで自動作成される場合があるため、初回実行より前に手動で3つとも作成します。

各Environmentを次の手順で作成します。

1. GitHubで対象repositoryを開く。
2. `Settings`を開く。
3. 左メニューの`Environments`を開く。
4. `New environment`を押す。
5. Environment名を正確に入力する。
6. `Configure environment`を押す。
7. 残りのEnvironmentも同じ手順で作成する。

名前のhyphenをworkflowの記述と一致させます。

```text
staging
production-plan
production
```

### 6. Environmentの配布元と承認を設定する

3つのEnvironmentで`Deployment branches and tags`を`Selected branches and tags`へ変更します。
その後、`Add deployment branch or tag rule`から次の規則を追加します。

| Environment | Branch rule | Tag rule | Required reviewer |
| --- | --- | --- | --- |
| `staging` | `main` | なし | 任意 |
| `production-plan` | `main` | `backend-v*` | なし |
| `production` | `main` | `backend-v*` | 必須 |

`staging`では`Branch`を選び、patternへ`main`を入力します。
`production-plan`と`production`では、`Branch: main`と`Tag: backend-v*`を別々のruleとして追加します。
`main`はGitHub Actions画面からの手動production配布、`backend-v*`は通常のtag配布に必要です。

`production`の`Deployment protection rules`では次の設定を行います。

1. `Required reviewers`を有効にする。
2. production配布を承認できる個人またはteamを選ぶ。
3. 実行者本人による承認を禁止する場合は`Prevent self-review`を有効にする。
4. 管理者による無断回避を禁止する場合は`Allow administrators to bypass configured protection rules`を無効にする。
5. 設定を保存する。

少人数運用で実行者と承認者を分けられない場合は、`Prevent self-review`を有効にすると配布できなくなります。
組織の承認方針を決めてから設定します。

GitHub planによってrequired reviewerを使えない場合は、repository secretへ代替して承認を省略しません。
承認付きEnvironmentを利用できるplanまたは別の承認基盤を用意するまでproduction workflowを実行しません。

GitHubの操作方法は[Environmentの作成と管理](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)を参照してください。

### 7. Environment variablesとsecretsを登録する

各Environmentの設定画面で、非機密値は`Environment variables`、資格情報は`Environment secrets`へ登録します。
同名のrepository secretやorganization secretへ複製しません。

variableは`Add variable`を押し、表の名前と値を入力して`Add variable`で保存します。
secretは`Add secret`を押し、password managerから値を貼り付けて`Add secret`で保存します。

#### staging

| 種類 | 名前 | 登録する値 |
| --- | --- | --- |
| Variable | `CLOUDFLARE_ACCOUNT_ID` | 手順1で控えたaccount ID |
| Variable | `TF_STATE_BUCKET` | 手順2で作ったstaging bucket名 |
| Variable | `TF_STATE_ENDPOINT` | 手順3で控えたR2 S3 endpoint |
| Variable | `BACKEND_HEALTH_URL` | `https://api-staging.beyond-labo.com` |
| Variable | `SUPABASE_PROJECT_REF` | staging Project ref |
| Variable | `SUPABASE_URL` | staging Project URL |
| Variable | `SUPABASE_PUBLISHABLE_KEY` | staging publishable key |
| Variable | `APPLE_CLIENT_ID` | native App ID／Bundle ID |
| Secret | `CLOUDFLARE_API_TOKEN_READ` | `himatch-staging-plan-read`のtoken |
| Secret | `CLOUDFLARE_API_TOKEN_WRITE` | `himatch-staging-deploy-write`のtoken |
| Secret | `R2_STATE_ACCESS_KEY_ID` | staging read/write credentialのAccess Key ID |
| Secret | `R2_STATE_SECRET_ACCESS_KEY` | staging read/write credentialのSecret Access Key |
| Secret | `SUPABASE_ACCESS_TOKEN` | stagingだけに到達できるCI identityのaccess token |
| Secret | `SUPABASE_DB_PASSWORD` | staging database password |
| Secret | `SUPABASE_SECRET_KEY` | staging server secret key |
| Secret | `APPLE_TEAM_ID` | Apple Team ID |
| Secret | `APPLE_KEY_ID` | Sign in with Apple Key ID |
| Secret | `APPLE_PRIVATE_KEY` | `.p8`のPEM全文 |
| Secret | `ACCOUNT_DELETION_STATUS_SECRET` | staging専用のランダム値 |

`BACKEND_HEALTH_URL`には次の値をそのまま登録します。

```text
https://api-staging.beyond-labo.com
```

#### production-plan

| 種類 | 名前 | 登録する値 |
| --- | --- | --- |
| Variable | `CLOUDFLARE_ACCOUNT_ID` | 手順1で控えたaccount ID |
| Variable | `TF_STATE_BUCKET` | 手順2で作ったproduction bucket名 |
| Variable | `TF_STATE_ENDPOINT` | 手順3で控えたR2 S3 endpoint |
| Secret | `CLOUDFLARE_API_TOKEN_READ` | `himatch-production-plan-read`のtoken |
| Secret | `R2_STATE_ACCESS_KEY_ID` | production read-only credentialのAccess Key ID |
| Secret | `R2_STATE_SECRET_ACCESS_KEY` | production read-only credentialのSecret Access Key |

`production-plan`へwrite tokenや`BACKEND_HEALTH_URL`は登録しません。
このEnvironmentは承認前にstateを読み、Terraform planの要約を作るだけです。

#### production

| 種類 | 名前 | 登録する値 |
| --- | --- | --- |
| Variable | `CLOUDFLARE_ACCOUNT_ID` | 手順1で控えたaccount ID |
| Variable | `TF_STATE_BUCKET` | 手順2で作ったproduction bucket名 |
| Variable | `TF_STATE_ENDPOINT` | 手順3で控えたR2 S3 endpoint |
| Variable | `BACKEND_HEALTH_URL` | `https://api.beyond-labo.com` |
| Variable | `SUPABASE_PROJECT_REF` | production Project ref |
| Variable | `SUPABASE_URL` | production Project URL |
| Variable | `SUPABASE_PUBLISHABLE_KEY` | production publishable key |
| Variable | `APPLE_CLIENT_ID` | native App ID／Bundle ID |
| Secret | `CLOUDFLARE_API_TOKEN_WRITE` | `himatch-production-deploy-write`のtoken |
| Secret | `R2_STATE_ACCESS_KEY_ID` | production read/write credentialのAccess Key ID |
| Secret | `R2_STATE_SECRET_ACCESS_KEY` | production read/write credentialのSecret Access Key |
| Secret | `SUPABASE_ACCESS_TOKEN` | productionだけに到達できる別CI identityのaccess token |
| Secret | `SUPABASE_DB_PASSWORD` | production database password |
| Secret | `SUPABASE_SECRET_KEY` | production server secret key |
| Secret | `APPLE_TEAM_ID` | Apple Team ID |
| Secret | `APPLE_KEY_ID` | Sign in with Apple Key ID |
| Secret | `APPLE_PRIVATE_KEY` | `.p8`のPEM全文 |
| Secret | `ACCOUNT_DELETION_STATUS_SECRET` | production専用のランダム値 |

`BACKEND_HEALTH_URL`には次の値をそのまま登録します。

```text
https://api.beyond-labo.com
```

productionのread-only Cloudflare tokenとR2 credentialは`production-plan`だけに置きます。
productionのwrite tokenとread/write R2 credentialは`production`だけに置きます。

secretの実値はsource、`.tfvars`、backend config、artifact、job summaryへ書きません。
Terraform planとapplyの詳細はephemeral runnerの`$RUNNER_TEMP`にだけ保存し、要約と成否だけをjob summaryへ出します。

### 8. GitHub Rulesetsを設定する

`main`への未検証変更と、production tagの不正な作成や更新を防ぎます。

#### main branchを保護する

1. repositoryの`Settings`を開く。
2. 左メニューの`Rules`、`Rulesets`を開く。
3. `New ruleset`、`New branch ruleset`を選ぶ。
4. ruleset名へ`protect-main`など識別可能な名前を入力する。
5. `Enforcement status`を`Active`にする。
6. `Target branches`でdefault branch、またはpattern `main`を指定する。
7. `Require a pull request before merging`を有効にする。
8. 必要な承認数を1以上にする。
9. `Require status checks to pass`を有効にする。
10. `Verify backend and Cloudflare configuration`をrequired checkへ追加する。
11. `Block force pushes`と`Restrict deletions`を有効にする。
12. 内容を確認して`Create`を押す。

required checkが候補に表示されない場合は、secretを使わない`Backend CI`をpull requestで一度成功させてから設定します。
reusable workflowではcheck名が`親job / 子job`形式で表示される場合があるため、GitHub画面に表示された完全一致の名前を選びます。

現在のrepositoryにはpath別の`CODEOWNERS`がありません。
`.github/workflows/**`、`infra/cloudflare/**`、`scripts/terraform/**`の変更は、main rulesetのpull request reviewで必ず確認します。
将来担当teamを固定するときは`CODEOWNERS`を追加し、`Require review from Code Owners`を有効にします。

#### production tagを保護する

1. 同じ`Rulesets`画面で`New ruleset`、`New tag ruleset`を選ぶ。
2. ruleset名へ`protect-backend-release-tags`などを入力する。
3. `Enforcement status`を`Active`にする。
4. `Target tags`へpattern `backend-v*`を追加する。
5. `Restrict creations`、`Restrict updates`、`Restrict deletions`、`Block force pushes`を有効にする。
6. release担当者またはrelease teamだけをbypass対象へ追加する。
7. 内容を確認して`Create`を押す。

通常のproduction releaseではrelease担当者がannotated tagを作成します。
tag更新を許可せず、誤ったtagは削除して同名を付け直すのではなく、新しいversionで再発行します。

Rulesetsの画面と設定項目は[GitHubのrepository ruleset作成手順](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)を参照してください。

pull requestの`Backend CI`はCloudflare token、R2 credential、runtime secret、protected Environmentを参照しません。
公開repositoryでもこの境界を維持すれば、外部pull requestから配布資格情報を取得する経路を作らずに運用できます。

### 9. ローカルでsecretless検証を実行する

CloudflareとGitHubの設定後、配布前にrepository rootで次のコマンドを実行します。

```sh
pnpm install --frozen-lockfile
pnpm --dir apps/backend run types
pnpm --dir apps/backend run typecheck
pnpm --dir apps/backend run test
pnpm --dir apps/backend run build

npx -y supabase@2.117.0 db start
npx -y supabase@2.117.0 db lint --local --schema public --level error --fail-on error
npx -y supabase@2.117.0 test db --local
npx -y supabase@2.117.0 stop --no-backup

terraform fmt -check -recursive infra/cloudflare
terraform -chdir=infra/cloudflare/environments/staging init -backend=false
terraform -chdir=infra/cloudflare/environments/staging validate
terraform -chdir=infra/cloudflare/environments/production init -backend=false
terraform -chdir=infra/cloudflare/environments/production validate
terraform -chdir=infra/supabase/environments/staging init -backend=false
terraform -chdir=infra/supabase/environments/staging validate
terraform -chdir=infra/supabase/environments/production init -backend=false
terraform -chdir=infra/supabase/environments/production validate

node scripts/verify.mjs
```

`init -backend=false`はR2へ接続せず、Terraform構成とprovider lockだけを検査します。
このローカル検証にCloudflare token、Supabase Management API token、R2 credentialは不要です。

すべて成功したらpull requestを作成し、GitHub上の`Backend CI`も成功することを確認します。
失敗した検証をrulesetのbypassで回避しません。

### 10. stagingへ初回配布する

pull requestを`main`へmergeすると、`Backend CD (staging)`が自動的に開始します。
Actions画面でworkflowを開き、次の順序で成功することを確認します。

1. `Verify backend and Cloudflare configuration`が成功する。
2. `Verify Supabase migrations and RLS`が成功する。
3. `Initialize Terraform remote state`がstaging bucketへ接続する。
4. read tokenによるTerraform planが成功する。
5. write tokenによるTerraform applyが成功する。
6. staging Projectへのmigration dry-run、非対話適用、linked履歴表示が成功する。
7. `wrangler deploy --env staging`がruntime variables/secretsを含めてWorkerとCustom Domainを作成または更新する。
8. `https://api-staging.beyond-labo.com/healthz`へのsmoke testが成功する。

最初のTerraform planが`No changes.`でも正常です。
現在のTerraform rootには実resourceがなく、続くWrangler deployがWorker本体とCustom Domainを作成します。

#### WranglerによるCustom Domain作成を確認する

Custom Domainの正本は[wrangler.jsonc](../../apps/backend/wrangler.jsonc)です。
Cloudflare Dashboardの`Add`ボタンから同じhostnameを手動作成せず、最初の`wrangler deploy`に作成させます。

`wrangler deploy`は次の処理を行います。

1. `himatch-backend-staging`を作成または更新する。
2. `api-staging.beyond-labo.com`をWorkerのCustom Domainとして接続する。
3. Cloudflareが必要なDNSレコードを自動作成する。
4. Cloudflareがhostname用のTLS証明書を自動発行する。

Dashboardで手動操作を行う場合の画面は、`Workers & Pages`、`himatch-backend-staging`、`Settings`、`Domains & Routes`、`Add`、`Custom Domain`です。
入力値は`api-staging.beyond-labo.com`ですが、このrepositoryではWranglerを正本にするため、確認画面から保存しません。

deploy後は次の順序で完了を確認します。

1. Cloudflare Dashboardの`Workers & Pages`を開く。
2. `himatch-backend-staging`を開く。
3. `Settings`、`Domains & Routes`を開く。
4. `api-staging.beyond-labo.com`がCustom Domainとして表示されることを確認する。
5. `beyond-labo.com`、`DNS`、`Records`を開く。
6. Cloudflare管理の`api-staging`レコードが作成されていることを確認する。
7. `SSL/TLS`、`Edge Certificates`を開く。
8. `api-staging.beyond-labo.com`を含む証明書の状態が`Active`になることを確認する。

証明書は`Initializing`、`Pending Validation`、`Pending Issuance`、`Pending Deployment`を経て`Active`になります。
そのため、Worker deployが成功しても直後のHTTPS接続は一時的に失敗する場合があります。
workflowのsmokeは1回5秒のtimeout、最大12回、各試行間5秒で再試行し、上限を超えた場合だけ失敗します。
Cloudflareは固定の反映時間を保証しないため、再試行中の失敗を直ちに権限エラーと判断しません。

workflow成功後は次の項目を確認します。

1. Cloudflare Dashboardの`Workers & Pages`に`himatch-backend-staging`が表示される。
2. workflow summaryのWorker versionとrun URLを記録する。
3. ブラウザまたは`curl`でhealth endpointを確認する。

```sh
curl --fail-with-body \
  https://api-staging.beyond-labo.com/healthz
```

正常なresponseは次のとおりです。

```json
{"status":"ok"}
```

`Initialize Terraform remote state`が失敗した場合は、`TF_STATE_BUCKET`、`TF_STATE_ENDPOINT`、R2 credentialのbucket範囲を確認します。
`Deploy Worker to staging`が失敗した場合は、Cloudflare account ID、Workers権限、`beyond-labo.com`限定のWorkers Routes Edit、既存DNS競合を確認します。
最後のsmokeだけが失敗した場合は、`BACKEND_HEALTH_URL`に`/healthz`を重複して付けていないか、DNSレコードとTLS証明書がActiveかを確認します。

### 11. productionへ初回配布する

stagingのhealth確認後、検証済みの`main` commitへannotated tagを付けます。

```sh
git switch main
git pull --ff-only origin main
git tag -a backend-v0.1.0 -m "Backend 0.1.0"
git push origin backend-v0.1.0
```

versionは`backend-vX.Y.Z`の形式にします。
workflowはtag形式、annotated tagであること、対象commitが`origin/main`に含まれることを検査します。

GitHubの`Actions`から`Backend CD (production)`を開き、次の順序で確認します。

1. `Validate release ref`がtagとcommitを検証する。
2. `Verify backend and Cloudflare configuration`が同じcommitを検証する。
3. `Verify Supabase migrations and RLS`が同じcommitを検証する。
4. `Production Terraform preflight plan`が`production-plan`のread-only資格情報でplan要約を作る。
5. `Apply and deploy production`が`Waiting`になり、`production` Environmentの承認を要求する。
6. reviewerがpreflight要約、commit SHA、tagを確認して承認する。
7. workflowがplanを再計算してTerraform applyを実行する。
8. production ProjectへDB migrationを非対話で適用し、linked履歴を表示する。
9. Wranglerがruntime variables/secretsを含めてWorkerとCustom Domainを作成または更新する。
10. `https://api.beyond-labo.com/healthz`のsmoke testが成功する。

承認前のsaved planはproduction applyへ引き渡しません。
承認後に同じcommitからplanを再計算します。

workflow成功後は`Workers & Pages`、`himatch-backend-production`、`Settings`、`Domains & Routes`を開き、`api.beyond-labo.com`がCustom Domainとして表示されることを確認します。
続けて`beyond-labo.com`の`DNS`、`Records`でCloudflare管理の`api`レコードを確認し、`SSL/TLS`、`Edge Certificates`で証明書が`Active`であることを確認します。
Dashboardから手動作成する画面の入力値は`api.beyond-labo.com`ですが、stagingと同様にWrangler deployを正本にします。

```sh
curl --fail-with-body \
  https://api.beyond-labo.com/healthz
```

GitHub Actionsから手動実行する場合は、workflow画面の`Run workflow`でbranchに`main`を選びます。
手動実行時のcommitが現在の`origin/main`と一致しなければworkflowは停止します。

## 初回セットアップ完了チェックリスト

- [ ] `beyond-labo.com`がWorker配布account内にあり、zoneと登録状態がActiveであることを確認した。
- [ ] `api-staging`と`api`に競合するA、AAAA、CNAMEレコードがないことを確認した。
- [ ] privateなR2 bucketをstaging用とproduction用に1つずつ作成した。
- [ ] staging read/write、production read-only、production read/writeのR2 credentialを作成した。
- [ ] stagingとproductionのread token、write tokenを分離して作成した。
- [ ] write tokenを`beyond-labo.com`のWorkers Routes Editへ限定した。
- [ ] `staging`、`production-plan`、`production` Environmentを作成した。
- [ ] Environmentごとのbranchとtag ruleを設定した。
- [ ] `production`へrequired reviewerを設定した。
- [ ] すべてのvariablesとsecretsを対応するEnvironmentへ登録した。
- [ ] `main`と`backend-v*`のrulesetを有効にした。
- [ ] ローカル検証とpull requestの`Backend CI`、`Supabase CI`が成功した。
- [ ] stagingのCustom Domain、TLS証明書、`/healthz`が成功した。
- [ ] productionの承認、Custom Domain、TLS証明書、`/healthz`が成功した。

## 失敗時に復旧する

Terraform planまたはapplyが失敗した場合は、後続のWorker deployを実行しません。
job summaryとCloudflare Dashboardを確認し、資格情報、state、resource設定のどこで失敗したかを切り分けます。
Terraformが失敗した場合はDB migrationを開始しません。
DB migration後にWorker deployまたはsmokeが失敗した場合、DBは適用済みのままで、job summaryに復旧案内が表示されます。
旧Workerと互換なmigrationであることを前提に、原因を直して同じreleaseを再実行します。
互換性が崩れた場合は、適用済みmigrationを削除せずcorrective migrationを追加します。

deploy後のsmokeが失敗した場合は、該当workflowを失敗のまま保持し、直前の安定version IDへ戻します。

```sh
pnpm --dir apps/backend exec wrangler rollback <VERSION_ID> --env staging
pnpm --dir apps/backend exec wrangler rollback <VERSION_ID> --env production
```

rollbackを実行する端末では、対象環境のwrite tokenを`CLOUDFLARE_API_TOKEN`、account IDを`CLOUDFLARE_ACCOUNT_ID`へ一時的に設定します。
shell historyや共有ログへtokenを残さない方法で環境変数を設定します。

staging rollbackはstaging権限を持つ開発担当者または運用担当者が実行します。
production rollbackはproduction権限を持つリリース担当者が実行します。
環境、version ID、workflow run、実行者、理由をrelease記録へ残します。

Worker version rollbackはTerraform stateやSupabase DB migrationを戻しません。
DB不具合は適用済みmigrationを削除せず、旧Workerとも互換なcorrective migrationを追加します。
destructive変更はexpand / contractと後方互換期間を設けます。

資格情報が漏えいした場合は、該当するCloudflare API tokenまたはR2 tokenを直ちにrevokeします。
新しい資格情報を発行し、対応するGitHub Environment secretだけを更新してからworkflowを再実行します。

## Terraform resourceを追加するとき

現在のTerraform rootには、未決定のD1、KV、R2、Queue、DNS、WAFを宣言していません。
長寿命resourceを追加する場合は、要件と所有者を確定し、TerraformまたはWranglerの一方だけで管理します。
`api-staging.beyond-labo.com`と`api.beyond-labo.com`のCustom Domain、DNSレコード、Workers Route、TLS証明書はWrangler側の所有範囲です。
これらと同じresourceをTerraformへ追加しません。

resource追加後は、Cloudflare API tokenのscope、planの出力、rollback時のデータ影響を再評価します。
R2 native lockを有効にする場合は、実R2上で並行plan/applyの排他とstale lock回復を検証してから設定を変更します。

Terraformのディレクトリ構成とremote backendの手動初期化は[Cloudflare Terraform](../../infra/cloudflare/README.md)も参照してください。
Supabaseの既存Projectと今後の設定をTerraformへ取り込む前には、[Supabase Terraform](../../infra/supabase/README.md)と[具体的な移行手順](supabase-terraform-adoption.md)に従い、実資産の棚卸しとimport-only planを確認してください。
