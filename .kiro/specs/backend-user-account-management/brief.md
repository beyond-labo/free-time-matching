---
type: Brief
title: "Backend ユーザーアカウント管理"
description: "Supabase Auth、プロフィール、アカウント削除をCloudflare Workerから安全に提供する"
status: stable
sources:
  - id: user-auth-management
    resource: conversation://2026-09-21/user-auth-management
    title: iOS初版のユーザー情報管理方針
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
---

# Backend ユーザーアカウント管理

iOS初版の認証をSign in with Appleに限定し、Supabase Authのセッション、ニックネームとプリセットアイコンのプロフィール、アプリ内アカウント削除を本番Backendへ接続する。
Cloudflare WorkerはSupabase access tokenを検証するResource Serverとして動作し、通常のプロフィール操作と削除時だけ必要な特権を分離する。
