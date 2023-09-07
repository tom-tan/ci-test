# これなに？

Git のコミット署名周りや Github Actions でのコンテナ作成に関する調査・動作確認用のリポジトリです。

以下、覚書。

## Git の署名周り

- Git で署名に使える鍵は GPG, SSH, X509 の三種類
    - https://docs.github.com/ja/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key
    - GitHub は全てに対応 (WebUI から確認できる)

### Git でコミット署名を行う手順

- 事前に利用する鍵の登録が必要
  - Git: 事前に `git config --global user.signingkey XXXXXXXXX` などでキーID を設定しておく
    - 署名に必要
    - https://docs.github.com/ja/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key
    - コミット時に `-S` を付与すると署名付きコミットになる
    - タグにも署名できる

  - Github の場合、Settings -> SSH and GPG keys で公開鍵の登録ができる
    - 検証に必要
    - ローカルで pub key を revoke 後、Github に登録した鍵を置き換えることで Github 上でも revoke できる
    - X509 の場合、Debian の ca-certificates パッケージにあるルート証明書を使って検証を行う
      - https://docs.github.com/ja/authentication/managing-commit-signature-verification/about-commit-signature-verification

- 署名の確認
  - Git: コマンドで署名を確認する
    ```console
    $ git log -n1 --show-signature
    commit 86781f418c487ed7a13bfd23e22fae5d4d96dedc (HEAD -> main, origin/main, origin/HEAD)
    gpg: 2023年07月17日 23時19分28秒 JSTに施された署名
    gpg:                RSA鍵65799582A83EB09DBF65C79C06CB0E740C9B8978を使用
    gpg: "Tomoya Tanjo <ttanjo@gmail.com>"からの正しい署名 [究極]
    Author: Tomoya Tanjo <ttanjo@gmail.com>
    Date:   Mon Jul 17 23:19:28 2023 +0900

        Fix sample
    ```
  - Github: Web UI 上で署名を確認する
    - コミットメッセージをクリック
    - 署名済みなら "Verified" のマークが付与される
    - 簡単に調べたところ、Gitlab でも Web UI 上で署名確認ができる

### Github Actions でのコンテナのビルド・GHCR への push
- Github Actions からの push
  - push 先が ghcr なら、ワンタイムトークンが GITHUB_TOKEN として利用可能
  - Github Actions 公式から `Publish Docker Container` というテンプレートが提供されている
    - 3rd party の actions も使っている点は注意
    - コンテナの build, push, cosign を用いた署名を行う
- cosign でのコンテナ署名
  - 署名に関する情報は sig ファイルとして ghcr 上から確認できる
  - cosign はイメージの manifest ファイルに対して署名を作成するらしい
    - https://tech.isid.co.jp/entry/verify-distroless-signature-using-cosign-on-github-actions
  - Sigstore の他のシステムである Fulcio, Rekor と連携して、Github の OIDC token を使って署名を行っているっぽい
    - OIDC: OpenID Connect
    - https://dev.to/n3wt0n/sign-your-container-images-with-cosign-github-actions-and-github-container-registry-3mni
    - https://docs.github.com/ja/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect

### 懸念点
- docker build 時の環境の表示はユーザー任せ
  - アプリをコンテナ化して配布する場合、CI runner の開発環境は通常使われない
- ビジネス用途だと distroless の方が使われる場合もありそう
  - distroless: https://github.com/GoogleContainerTools/distroless
  - Alpine Linux などよりも更に尖っており、シェルやパッケージ管理システム等もなし
  - ポリシー上 latest タグしか提供していない
    - 「タグ固定して古いのを使うな。セキュリティのために常に latest を使え」という方針
- 鍵を使って署名する場合、秘密鍵をどうやって Actions に渡す？
  - [Secrets](https://docs.github.com/ja/actions/security-guides/using-secrets-in-github-actions) などに設定はできるが…
  - cosign と同様に OIDC token を使う方法を採用できるか？

---
# 開発者がコミットを作成・Github に push したときに何が起きるのか
- リポジトリの開発者は、GPG, SSH, X509 のいずれかの鍵を用いて[署名付きコミット](https://docs.github.com/ja/authentication/managing-commit-signature-verification/signing-commits)を行う
  - 署名付きコミットにより、コミットが第三者によるものではないことを検証可能にできる
- 開発者はコミットを Github に push する
- リポジトリへの push をトリガーにして Github Actions (Github 提供の CI/CD の機構) が実行される
  - push 以外をトリガーにした Actions 実行も存在するが、今回は省略
  - Github Actions の実行は [Github hosted runner](https://docs.github.com/ja/actions/using-github-hosted-runners/about-github-hosted-runners) と [self hosted runner](https://docs.github.com/ja/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners) のいずれかで行われる
    - runner の管理者についてはきちんと前提を置く必要がある
- Github Actions はコミットに含まれる設定ファイルに従って、ソースからバイナリ (or コンテナ) へのビルドおよび生成されたバイナリのバイナリリポジトリへのアップロードを行う
  - 例: [ocker-publish.yml](https://github.com/tom-tan/ci-test/blob/main/.github/workflows/docker-publish.yml)
  - 設定ファイルは本質的には bash スクリプト列
    - [PowerShell なども利用可能](https://docs.github.com/ja/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idstepsshell)だがめったに見ない
    - 第三者が作成した設定ファイル (Actions と呼ばれる) を活用する場合もある
      - [Actions の内容はリポジトリとして公開されている](https://docs.github.com/ja/actions/creating-actions/publishing-actions-in-github-marketplace#about-publishing-actions)ため確認は可能
  - ビルド環境の構築 (e.g., コンパイラのデプロイ)、ビルド、バイナリへの署名およびバイナリと署名のアップロードを行うように設定ファイルに記述しておく必要がある
    - [アップロード結果の例](https://github.com/tom-tan/ci-test/pkgs/container/ci-test)
    - `*.sig` が署名に関する情報が含まれたファイル
  - **ビルドログ中に、対応するリポジトリのコミット番号およびバイナリのハッシュ値(or コンテナイメージID)を出力するように設定ファイルを記述する必要がある**
    - [ビルドログの例](https://github.com/tom-tan/ci-test/actions/runs/6099869999)
    - Github 上のビルドログは一定期間 (デフォルトは三ヶ月) で消去されるので注意が必要

---
# ソースコードとバイナリの紐づけの確認方法・検証方法
- コミットの検証方法は[前述](#署名の確認)
- バイナリの検証方法
  - cosign の場合は `cosign verify` で行う (参考: https://tech.isid.co.jp/entry/verify-distroless-signature-using-cosign-on-github-actions)
- 紐づけの確認方法
  - 特定のコミットに紐づいたログを探す (例: https://github.com/tom-tan/ci-test/actions/runs/6099869999/job/16552977072#step:2:86)
    - 一つのコミットに複数のログが対応する場合もあるが、成功した最新のログを確認すればよい
  - ログ中で生成されたコンテナイメージ ID が、バイナリリポジトリにアップロードされたコンテナのイメージ ID と一致することを確認する
    - [ログの例](https://github.com/tom-tan/ci-test/actions/runs/6099869999/job/16552977072#step:7:178)
