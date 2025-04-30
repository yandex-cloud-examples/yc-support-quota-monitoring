terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  token     = ""
  cloud_id                 = ""
  folder_id                = ""
  zone                     = "ru-central1-a"
}
