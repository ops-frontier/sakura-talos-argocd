# Talos スタンドアロンインストール

現在の実装では SIDELO Talos Omni に依存しているが、これを脱却する。

## ディスクイメージの作成方法

boot 時のイメージ作成に omnictl media download talos-install コマンドの利用するのをやめて Sidero Labs 公式の imager ツール（Docker コンテナ）を使用する。BIOS ブートに対応した metal 用の RAW イメージ（.raw）を作成する。主に ansible/playbooks/boot.yml とそこから呼び出される role を修正する必要があると推測される。

Imager の起動イメージは以下のようなものであると推測される。
```
# カレントディレクトリの controlplane.yaml を組み込んで metal 用 RAW イメージを作成
docker run --rm --privileged -v /dev:/dev -v $(pwd):/secure -v $(pwd)/_out:/out \
  ghcr.io/siderolabs/imager:v1.13.8 metal \
  --arch amd64 \
  --extra-kernel-arg "net.ifnames=0" \
  --extra-kernel-arg "{{ _talos_network_kernel_args[0] }}" \
  --extra-kernel-arg "{{ _talos_network_kernel_args[1] }}" \
  --embedded-config-path /secure/controlplane.yaml
```

install_talos_deps ロールでは、omnictl のインストールをやめて、Sidero Labs 公式の imager ツール（Docker コンテナ）の起動に必要なパッケージをインストールするようにする。

### config ファイルの作成

config ファイルは ```talosctl config new```コマンドで作成するのと同等のものを ansible のテンプレートで作成する。terraform/omni.tf（削除予定）が参考にできるかもしれない。
config ファイルは sv1, sv2, sv3 それぞれに固有のものを作成する必要があるかもしれないが、 machine.ca の証明書と秘密鍵は共通のものを設定する必要がある。Codespaces の talosctl から各サーバへは mTLS 認証で接続するため、クライアント証明書を同時に作成しておく必要がある。

## SIDELO Talos Omni クラスタの削除

SIDELO Talos Omni を作成する Terraform (omni.tf)を削除する。

### README.md の修正

README.md の「事前準備」の SIDELO Talos でトークンを取得する記述は削除する。
必要に応じてトークンなどの認証情報のための環境変数を削除する。

## SideloLink の廃止

SideloLink は使用せず、 talos API には mTLSで接続する。Kubernetes API への接続は talos API で　kubeconfig を取得することでやはり mTLS で接続する。

## destory 時の処理の削除

destroy.yml で SIDELO Talos Omni クラスタを破棄するための処理が入っているがこれを削除する。

## post-create.sh の修正

omnictl は使用しなくなるので削除する。
