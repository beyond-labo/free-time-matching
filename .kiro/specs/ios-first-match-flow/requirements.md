---
type: Requirements
title: "iOS はじめてのお誘い動線要件"
description: "起動から友達の参加OKを受け取るまでの案内、誘う入力、返事、結果表示"
status: draft
sources:
  - id: user-first-match
    resource: conversation://2026-11-08/first-match-flow
    title: 起動しただけでは分かりにくい初回マッチング体験の改善依頼と方針決定
  - id: prototype-first-match
    resource: ../../../docs/prototypes/first-match-flow.html
    title: はじめてのお誘い動線プロトタイプ
  - id: current-app-review
    resource: ./research.md
    title: 現行アプリの動線調査
kiro:
  depends_on:
    - .kiro/steering/product.md
    - .kiro/specs/ios-app-foundation/requirements.md
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-app-integration/requirements.md
---

# Requirements Document

## Introduction
初めて起動した利用者が、何をすれば友達と遊ぶ予定に近づくかを画面から読み取り、友達とつながる、時間を選んで誘う、参加OKを受け取る、までを迷わず進められるようにする。[^user-first-match]
暇は非公開のまま選んだ友達全員へお誘いを送り、相手が参加できる時間を返す、という現行の製品契約は変えない。変えるのは画面の構成、入力の量、表示の言葉、到達経路である。[^prototype-first-match]

## Boundary Context
- **In scope**: 登録前の説明、ホームの構成と案内、時間候補からの開始、お誘い作成画面の入力構成、送信結果、届いたお誘いと返事の画面、参加OKの受け取り表示、画面上の用語、DEBUG デモでの体験経路。
- **Out of scope**: 友達の暇の公開・照合、予定の最終確定、Push 配信、Backend API と保存形式の変更、Siri・ショートカットの語句、Android、カレンダー時間軸そのものの操作仕様。
- **Adjacent expectations**: 暇の検証・OR統合・区間削除と時間軸の操作は Availability、招待コードと申請は Friendship、募集の作成・回答・取消・競合・非公開表示の契約は Hosting、セッションと Composition と Prototype シナリオは App Foundation と App Integration の既存契約を使う。この仕様と矛盾する既存の受け入れ条件は、要件承認後に所有仕様へ反映する（[調査記録](research.md#既存仕様への反映対象)）。

## Requirements

### Requirement 1: 登録前の説明
**Objective:** As a 初回利用者, I want アプリで何ができるかを先に知りたい, so that 登録する理由と最初にやることが分かる
#### Acceptance Criteria
1. When 未登録状態でアプリを起動した, the iOS app shall 「時間を選ぶ」「友達を誘う」「参加OKで集まる」の3段階を、各段階で利用者がすることの短い説明とともに認証ボタンより前に表示する
2. The iOS app shall 暇は友達に公開されず、伝わるのはお誘いの内容と参加OKした時間だけであることを登録前画面に表示する
3. The iOS app shall 登録前画面の既存の認証、規約・プライバシー・問い合わせへの到達、DEBUG デモ開始の導線を維持する

### Requirement 2: ホームの構成と次の行動
**Objective:** As a 利用者, I want ホームを開いたら今やるべきことが分かる, so that 時間軸を読み解かずに次の操作へ進める
#### Acceptance Criteria
1. The iOS app shall ホームを、対応が必要な友達申請、返事が必要な届いたお誘い、はじめてのお誘いの案内、自分のお誘い、時間候補、自分の暇の順に構成し、該当がない区分は表示しない
2. The iOS app shall 14日分の時間軸をホームの主表示にせず、ホームから1回の操作で開ける画面として提供し、時間軸での暇の登録・区間削除・範囲選択からの誘いを従来どおり利用できるようにする
3. While 承認済み友達が1人以上いる, the iOS app shall 「友達を誘う」をホームの主操作として常に表示する
4. While 承認済み友達がいない, the iOS app shall 主操作を「友達を招待する」にし、押したときに自分の招待コードの表示と共有、相手のコード入力へ進める
5. The iOS app shall 自分の暇の区分に今後の暇を日時順に表示し、各暇から「この時間で誘う」と暇の追加へ進めるようにする
6. The iOS app shall お知らせの入口に、未対応の友達申請、未回答のお誘い、未読の参加OKの合計件数を表示する

### Requirement 3: はじめてのお誘いの案内
**Objective:** As a 初回利用者, I want 最初のお誘いまでの進み具合を知りたい, so that 途中で何をすればよいか迷わない
#### Acceptance Criteria
1. The iOS app shall 「友達とつながる」「いつ遊ぶか決めて誘う」「参加OKを受け取る」の3段階と完了数をホームに表示する
2. The iOS app shall 現在の段階だけに操作を表示し、完了した段階には完了の表示を、未到達の段階には名称だけを表示する
3. When 招待コードを共有した後で承認済み友達がまだいない, the iOS app shall 相手からの申請を待っていることを表示する
4. When 利用者がホストとして初めて参加OKを受け取った、または招待された側として初めて参加OKを送った, the iOS app shall 案内を表示しなくなる
5. The iOS app shall 案内を利用者が閉じられるようにし、完了または閉じた案内を同じアカウントで再表示しない
6. The iOS app shall 案内に友達の暇登録状況、招待の配信人数、未回答者を表示しない

### Requirement 4: 時間候補からお誘いを始める
**Objective:** As a ホスト, I want よく使う時間をすぐ選びたい, so that 時間軸で範囲を作らずに誘える
#### Acceptance Criteria
1. The iOS app shall 時間候補として、今夜（19:00〜22:00）、明日の夜（19:00〜22:00）、当日を含む直近の土曜日の午後（13:00〜17:00）、自分の今後の暇のうち募集中と重ならない最大2件、日時を選ぶ、を表示する
2. If 候補の開始時刻が現在より前である, the iOS app shall 開始を現在の次の15分境界へ繰り下げ、残りが1時間未満の候補は表示しない
3. The iOS app shall 時間候補を端末の現在のタイムゾーンで表示し、今後14日の範囲外の候補を表示しない
4. When 時間候補を選んだ, the iOS app shall その開始・終了を選択済みにしてお誘い作成画面を開き、時間を再入力させない
5. When 友達一覧または友達プロフィールから誘う操作を選んだ, the iOS app shall その友達を選択済みにしてお誘い作成画面を開く
6. When 時間軸の範囲選択または暇の詳細から誘う操作を選んだ, the iOS app shall 選択した範囲を引き継いでお誘い作成画面を開く

### Requirement 5: お誘いの作成入力
**Objective:** As a ホスト, I want 必要なことだけ決めて送りたい, so that 内部の設定項目に迷わずお誘いを送れる
#### Acceptance Criteria
1. The iOS app shall お誘い作成画面を「いつ」「だれと」「会い方」「なにする（任意）」の順に1画面で構成する
2. The iOS app shall 「いつ」で時間候補と、今後14日の日付・15分単位の開始と終了の選択を提供し、選んだ日時を文で表示する
3. The iOS app shall 「だれと」で承認済み友達を個別に選択・解除でき、全員の選択と解除を1回の操作で行えるようにする
4. The iOS app shall 「会い方」でオンラインと会うを選ばせ、会うを選んだときだけ定義済みエリアまたは「あとで相談」を選ばせる
5. The iOS app shall 初回の会い方を未選択にし、2回目以降は本人が前回送ったお誘いの会い方とエリアを初期値にする
6. The iOS app shall カテゴリを任意とし、未選択のまま送れるようにする
7. The iOS app shall 本人の暇へ追加される範囲のカテゴリと公開設定の入力を常時表示せず、新しく追加される範囲を未選択カテゴリ・「参加OKするまで非公開」とする
8. If 候補範囲が属性の異なる既存の暇と重なるまたは接する, the iOS app shall 統合後の暇のカテゴリと公開設定を送信前に選ばせ、選ぶまで送信を無効にする
9. While 必須項目が不足している, the iOS app shall 送信ボタンを無効にし、不足している項目を文で表示する
10. The iOS app shall 送信ボタンを画面下部に固定し、送信先の友達の名前を送信前に表示する
11. The iOS app shall 送信前に、選んだ友達全員へ相手の暇登録の有無に関係なく届くことと、候補時間が本人の非公開の暇にも入ることを表示する

### Requirement 6: 送信結果と返事待ち
**Objective:** As a ホスト, I want 送った内容とこの後に起きることを知りたい, so that 返事を待つ間に不安にならない
#### Acceptance Criteria
1. When お誘いの作成が成功した, the iOS app shall 「お誘いを送りました」と、参加OKの返事が届くとホームに名前と時間が表示されることを、送った日時と内容とともに表示する
2. The iOS app shall 送信結果と返事待ちの表示に、配信人数、届かなかった相手、友達の暇登録状況、未回答者、見送った人を表示しない
3. While お誘いが募集中で参加OKがない, the iOS app shall ホームの自分のお誘いに日時、内容、返事待ちの状態、候補時間の帯を表示する
4. The iOS app shall 自分のお誘いから取消へ進めるようにし、取消前に友達の返事が無効になり本人の暇は残ることを表示して確認させる
5. If お誘いの作成に失敗した, the iOS app shall 成功表示へ進まず、入力を保持して再試行できるようにする

### Requirement 7: 届いたお誘いと返事
**Objective:** As a 招待された人, I want 届いたお誘いにすぐ気づき、来られる時間を簡単に返したい, so that 細かい操作なしで参加OKできる
#### Acceptance Criteria
1. When 未回答のお誘いがある, the iOS app shall ホームの最上部の区分に主催者、内容、会い方、候補日時、具体的な回答期限を表示する
2. The iOS app shall 返事画面で参加できる時間の選択肢として、候補全体と、候補が2時間以上の場合の前半・後半（15分境界で2分割）、時間を指定、を表示し、どれも初期選択しない
3. When 時間を指定を選んだ, the iOS app shall 候補範囲内の15分単位の開始と終了を選ばせる
4. The iOS app shall 選んだ時間を候補時間の帯の上に表示し、参加OKの送信ボタンに選んだ時刻を表示する
5. The iOS app shall 参加OKの送信前に、選んだ時間と表示名が主催者に伝わり、期限まで変更・取り消しできることを表示する
6. When 参加OKを選んだ, the iOS app shall 1回の送信操作で参加OKを送り、別の確認段階を求めない
7. The iOS app shall 見送る操作を参加OKより目立たない形で提供し、見送っても主催者に通知されないことを表示する
8. While 募集中で期限前である, the iOS app shall 送った返事の時間の変更と参加OKの取消をホームのお誘いから行えるようにする
9. If 期限切れまたは取消済みである, the iOS app shall 返事の操作を表示せず、その状態を表示する
10. If 返事の送信に失敗した, the iOS app shall 選んだ時間を保持して再試行できるようにする

### Requirement 8: 参加OKの受け取り
**Objective:** As a ホスト, I want 参加OKが届いたことと誰がいつ来られるかをすぐ知りたい, so that 次の連絡に進める
#### Acceptance Criteria
1. When 最新状態の取得で前回の表示以降の参加OKを検出した, the iOS app shall アプリ内で参加した友達の名前と時間を一時的に表示し、お知らせの件数に加える
2. The iOS app shall ホームの自分のお誘いに参加OKの人数、各参加者の名前と参加できる時間、候補時間の帯に重ねた参加時間を表示する
3. When 参加OKが2人以上ある, the iOS app shall 全員の参加時間と候補が重なる時間を「全員そろう時間」として表示し、重ならない場合は表示しない
4. The iOS app shall 参加OKがある自分のお誘いに、場所や集合はいつもの連絡手段で相談するよう案内し、予定の確定操作を表示しない
5. The iOS app shall 参加者が時間を変更または参加OKを取り消したとき、次の最新状態の取得で表示を更新する

### Requirement 9: 画面上の用語
**Objective:** As a 利用者, I want 画面の言葉が一貫していてほしい, so that 同じものを別のものと誤解しない
#### Acceptance Criteria
1. The iOS app shall 利用者に見えるアプリ内の文言で、ホストが友達を誘う行為と送られたものを「お誘い」、招待された側の回答を「返事」、開催形態を「会い方」と表記し、お誘いに関する表示で「募集」「招待」「回答」「開催形態」を使わない。友達追加の「招待コード」「友達を招待する」はこの対象に含めない
2. The iOS app shall 暇を「あなたの暇（非公開）」として表示し、参加OKや予定確定と区別する
3. The iOS app shall 時刻を端末のタイムゾーンで表示し、時間軸画面では現在のタイムゾーンを表示する

### Requirement 10: DEBUG デモでの体験
**Objective:** As a 開発者・評価者, I want 実際の友達がいなくても最初の参加OKまでを体験したい, so that 動線を端末上で確認できる
#### Acceptance Criteria
1. Where DEBUG デモで開始した, the iOS app shall プロフィール保存からホーム、お誘いの作成、届いたお誘いへの返事、参加OKの受け取りまでを Prototype シナリオで完了できるようにする
2. Where DEBUG デモで開始した, the iOS app shall 友達0人の状態と承認済み友達がいる状態を選んで始められるようにする
3. Where DEBUG デモでお誘いを送った, the iOS app shall デモ用の友達が参加OKを返す操作を提供し、その結果を Requirement 8 と同じ表示で確認できるようにする
4. The iOS app shall Release 構成にデモの開始導線と Prototype シナリオを含めない

### Requirement 11: アクセシビリティと状態表示
**Objective:** As a 利用者, I want 文字サイズや読み上げを使っても同じ操作ができる, so that 誰でも最初の参加OKまで進める
#### Acceptance Criteria
1. The iOS app shall 時間候補、友達の選択、返事の選択肢、送信ボタンに44×44pt以上のタップ領域を提供する
2. The iOS app shall 候補時間の帯と参加時間を VoiceOver で開始・終了時刻の文として読み上げられるようにする
3. The iOS app shall 返事待ち、参加OK、見送り、取消済み、期限切れを色だけでなく文字で区別する
4. While ホームの各区分を読み込み中である, the iOS app shall 空状態を表示せず、失敗時は区分ごとに再試行を提供する

[^user-first-match]: 2026-11-08 の依頼。体験の軸は現行仕様のまま画面と動線を洗練し、動線プロトタイプ → 仕様 → 実装の順で進め、壊れているデモは改善と一緒に直す、と決定した。
[^prototype-first-match]: 2台の端末で起動から参加OKまでを操作できる HTML プロトタイプ。要件の表示順と入力構成の元にした。
