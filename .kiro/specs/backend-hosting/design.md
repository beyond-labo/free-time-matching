---
type: Design
title: "Backend 友達招待設計"
description: "Hosting のAPI、DBトランザクション、公開投影"
status: stable
sources:
  - id: backend-hosting-requirements
    resource: ./requirements.md
    title: Backend 友達招待要件
kiro:
  depends_on:
    - .kiro/specs/backend-hosting/requirements.md
    - .kiro/specs/backend-availability/design.md
    - .kiro/specs/backend-friendship/design.md
---

# Design Document

## Overview

Hosting は募集と受信者別の回答を所有する。Worker は JWT を検証し、利用者 JWT で Supabase RPC を呼ぶ。DB 関数が本人暇のOR統合、友達関係、招待保存を一つのトランザクションにまとめる。

## Boundary Commitments

- **Owns**: 募集、招待先、回答、取消、役割別投影、再送とversion競合。
- **Out**: 予定確定、Push、グループの定義、友達の暇の公開。
- **Dependencies**: Availability の本人区間操作、Friendship の承認済み関係、Auth のJWT本人境界。
- **Revalidation**: Availability RPC、Friendship の成立条件、iOS受信箱の契約が変わった場合。

## API and Data Flow

- `POST /v1/hostings` は `{ start, end, mode, area?, category?, targets: [{type:"friend",id}], availabilityMetadata: {category,visibility}, operationId }` を受ける。返却は `{ hosting }` で、募集ID、状態、候補区間、versionを含む。回答期限は候補開始時刻 `start` から導く。本人暇の更新結果は別レスポンスへ含めず、iOS が作成成功後に暇一覧を再取得する。
- `GET /v1/hostings` と `GET /v1/hostings/{id}` は本人の役割に応じた投影を返す。ホスト向けは参加OK回答だけ、受信者向けは本人の回答だけを含む。
- `PUT /v1/hostings/{id}/response` は `{status, intervals, operationId, expectedVersion}`、`POST /v1/hostings/{id}/cancel` は `{operationId, expectedVersion}` を受ける。状態変更は DB が判定する。
- `targets` の variant は現時点で friend のみ。将来 group を追加するときはサーバーが認可して個人へ展開し、一意な招待先へ正規化する。

## Persistence and Privacy

- `hostings` はホスト、候補半開区間、開催条件、状態、versionを保持し、`hosting_invitations` は受信者、本人回答、versionを保持する。操作IDは actor と処理内容に結び、同じIDの再送を一回の効果にする。
- 作成RPCは本人行を直列化し、Availability の `availability_union_interval` を同一トランザクションで呼ぶ。友達関係の全件検証後に募集と招待を保存し、失敗時は全体をロールバックする。
- RLSとRPCの本人判定を重ねる。ホスト投影は参加OK以外の受信者行を返さず、未回答・辞退・友達の暇を推測できる件数も返さない。
- 募集の有効期限は候補開始とし、読取時にも期限切れとして扱う。募集中の候補に触れる Availability 減算はDBで拒否する。

## Testing

- Worker: JSON/時刻/target検証、role別投影、認証失敗、競合と依存障害。
- DB: 原子的作成、別actor拒否、友達全員への保存、辞退秘匿、部分回答、操作ID再送、version競合、取消と削除guard。
- Staging: 配備後に独立した2アカウントで送信・受信・回答を確認し、未実施なら成功と記録しない。
