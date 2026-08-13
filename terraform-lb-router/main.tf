resource "sakuracloud_internet" "lb_router" {
  name        = "${var.sakura_label_prefix}-lb-router"
  netmask     = 28
  band_width  = 100
  description = "LB 用 グローバル IP ルータ"
}