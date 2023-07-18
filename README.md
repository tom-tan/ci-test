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
  - Secrets などに設定はできるが…
  - cosign と同様に OIDC token を使う方法を採用できるか？
