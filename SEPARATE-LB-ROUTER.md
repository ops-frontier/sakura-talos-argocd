# ルータの分離

さくらのクラウドのルータにはグローバルIP16個が付属しており、これを一度確保すると月単位で3520円が課金されるため、短期間に作成と削除を繰り返すとコストが跳ね上がる仕組みとなっている。
このため、前回の修正では destroy.yml でルータを削除しないように修正したが、この方式では tfstate を喪失した場合、 terraform がルータを見失ってうまくいかない。
そこで、ルータの terraform を分離することにする。

## ルータの terraform

ルータだけをデプロイする terraform のコードを terraform-lb-router と言うディレクトリの下に作成する。

#### デプロイ方法
```
(cd terraform-lb-router && terraform apply)
```

#### 削除方法
```
(cd terraform-lb-router && terraform destroy)
```

## ルータの検出

本体の terraform ではルータ(```lb_router```)をデプロイするのをやめて代わりに```"${var.sakura_label_prefix}-lb-router"```という名前のルータを検索して利用することにする。喪失する場合のことを考慮して前項の terraform-lb-router の tfstate は利用しない。
見つからなかったり、複数見つかったりする場合はエラーとしたい。

## destroy の処理の削除

ansible/playbook/destroy.yml では terraform destroy を実行する前に tfstate から lb_router を削除し、終了後に戻す処理を記述しているがこれを削除する。

