# Talos Linux

OS を Flatcar Container Linux から Talos Linux へ変更することにした。この文書ではその変更点を述べる。

## ディスクイメージの作成方法

boot 時に flatcar-install コマンドの利用をやめて talosctl image (Imager) を使用するように変更する。主に ansible/playbooks/boot.yml とそこから呼び出される role を修正する必要があると推測される。

### k3s の廃止

Talos に組み込まれている k8s を使用するため、 k3s はインストールしない。 README.md の ```k3s``` は ```k8s``` に置換したが、 ```k3s.service``` （置換したので```k8s.service```になっている）に関する記述が残っており、削除する必要がある。

### butane の廃止

butane は使用いないため、 butane のコードと参照する ansible のコードは削除する必要がある。

## Cilimum, ArgoCD のデプロイ

Cilimum, ArgoCD のインストールは push_infra_apps role から外して SIDELO Talos Omni から設定するように変更する。OSの起動時に SIDELO Talos Omni に能動的に接続し、コンフィグレーションを取得してCilimum, ArgoCD を自動的にデプロイするように前節のディスクイメージ作成時に設定する。


### Terraform の設定
SIDELO Talos Omni のコンフィグレーションファイルの作成も Terraform から行う。

### README.md の修正

README.md の「事前準備」に SIDELO Talos で事前に Web UI から実施すべき内容を記載する。
必要に応じてトークンなどの認証情報のための環境変数を追加する。

## SideloLink の導入

AWS SSM Agent は廃止し、SideloLink を導入する。OSの起動時に SIDELO Talos Omni に能動的に接続し、SideloLink を有効化するように設定する。

### README.md の修正

README.md の「事前準備」に SIDELO Talos で事前に Web UI から実施すべき内容を記載する。
必要に応じてトークンなどの認証情報のための環境変数を追加する。
AWS関連の記載は削除する。

### SSH 接続の廃止

Codespaces から boot 後の Linux への SSH 接続は廃止する。SideloLink 経由でも SSH 接続はしない。 boot 後の Linux での sshd や .ssh の設定もやめる。 ansible での設定もできなくなるため、boot 後に ansible でリモート接続して実行しているタスクについては廃止するか、API呼び出しに変更する必要がある。

