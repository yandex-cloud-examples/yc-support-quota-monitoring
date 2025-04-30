## Создание мониторинга квот ресурсов

### Перед началом работы:

1. Установить и инициализировать YC CLI. Утилита потребуется далее для получения IAM-токена. Подробную инструкцию можно найти по [**этой ссылке**](https://cloud.yandex.ru/ru/docs/cli/quickstart) в нашей документации.

2. Настроить terraform для работы с  Yandex Cloud  по [инструкции](https://yandex.cloud/ru/docs/tutorials/infrastructure-management/terraform-quickstart);

3. Пользователь или сервисный аккаунт от имени которого разворачивается terraform-манифест имеет роль для выдачи ролей на уровне организации и создания ресурсов каталоге, где разворачивается решение. Не ниже `organization-manager.admin`;

### Структура:

```bash
.
├── README.md
├── vars.tf
├── main.tf
├── provider.tf
├── index.py
```

### Описание решения:

#### Создаваемые ресурсы:

* Сервисный аккаунт `quota-monitor-sa`;

* IAM binding с ролью `monitoring.editor` для сервисного аккаунта `quota-monitor-sa` на уровне каталога;

* IAM binding с ролью `quota-manager.viewer` для сервисного аккаунта `quota-monitor-sa` на уровне организации;

* Функция `quota_monitor_function`;

* IAM binding с ролью `serverless.functions.invoker` для сервисного аккаунта `quota-monitor-sa` на функцию `quota_monitor_function`;

* Триггер `quota_monitor_function_trigger` для вызова функции `quota_monitor_function` по cron-расписанию;

* Дашборды `quota_monitor_clouds`, `quota_monitor_billing` и `quota_monitor_organization_manager`.

#### Принцип работы:

1. Триггер `quota_monitor_function_trigger` вызывает функцию `quota_monitor_function` от имени сервисного аккаунта `quota-monitor-sa`;
2. При вызове функции `quota_monitor_function` получаем IAM-токен привязанного сервисного аккаунта `quota-monitor-sa` используя сервис метаданных;
3. В переменные окружения функции передаются `FOLDER_ID` и `BILLING_ID`;
4. Для каждого ресурса: организация, облако, биллинг аккаунт делаем API запрос квот `quota_limits`;
5. Все доступные метрики по квотам записываются в виде `quota.{id}._limit`/`quota.{id}._value`;
6. Собранные метрики записываются в `custom` сервис Yandex Monitoring заранее определенного каталога;
7. Логи работы функции по-умолчанию записываются в лог-группу `default` в сервисе `Cloung Logging`.

Некоторые ресурсы платные и тарифицируются согласно следующим правилам:

* Serverless Functions - <https://yandex.cloud/ru/docs/functions/pricing>

* Yandex Monitoring (запись метрик) - <https://yandex.cloud/ru/docs/monitoring/pricing>

* Cloud Logging (запись логов функции) - <https://yandex.cloud/ru/docs/logging/pricing>

### Установка:

* Клонировать код из репозитория:

```
$ git clone https://github.com/yandex-cloud-examples/yc-support-quota-monitoring.git
$ cd yc-support-quota-monitoring
```

* В конфигурации `provider.tf` изменить параметр авторизации `token` на полученный IAM-токен с помощью yc CLI `yc iam create-token` (или заменить на свой способ) и значения `cloud_id`, `folder_id`  и `zone`;

* В конфигурации `vars.tf` заменить значения для переменных: 

  * `monitoring_folder_id` - каталог, в котором будет развернута инфраструктура с Serverless Function, сервисным аккаунтом и дашбордами Yandex Monitoring. Метрики квот будут записаны в сервис `custom` этого каталога. Рекомендуем использовать уникальный каталог для этого проекта.

  * `monitoring_organization_id` - идентификатор организации для которой разворачивается мониторинг. Если вы используете больше 1 организации, то для настройки мониторинга квот, проект необходимо устанавливать для каждой организации;

  *  `monitoring_billing_account_id` - идентификатор Billing Account в котором скрипт будет проверять квоты. Если вы используете >1 Billing Account в организации, в значение переменной можно указать несколько идентификаторов, разделенных символом `,` (прим. `dn2************,dn2************`).

### Развёртывание инфраструктуры:

1. Архивировать скрипт `index.py`

```
$ zip quota-monitor.zip index.py
```

2. Инициализация Terraform

```
$ terraform init
```

3. Посмотреть план и применить конфигурацию

```
$ terraform plan
$ terraform apply
```

---
4. В каталоге `monitoring_folder_id` должны появиться созданные ресурсы. Метрики квот и дашборды будут доступны в сервисе Yandex Monitoring. Посмотреть можно по ссылке: https://monitoring.yandex.cloud/folders/{monitoring_folder_id}/dashboards

5. По желанию, вы можете настроить:

    * Алерты для оперативного реагирования на приближение квот к лимитам по [документации](https://yandex.cloud/ru/services/monitoring "title");
    * Изменить расписание (`cron_expression`) срабатывания триггера `quota_monitor_function_trigger`  в конфигурации `main.tf`.

### Дополнительные материалы:

- [**Зеркало Terraform-провайдера Yandex Cloud**](https://terraform-provider.yandexcloud.net/).
- [**Управление доступом в Resource Manager**](https://cloud.yandex.ru/ru/docs/resource-manager/security/).
- [**Роли Identity and Access Management**](https://cloud.yandex.ru/ru/docs/iam/).

---

**Актуальные версии провайдера и Terraform на момент тестирования:**

```sh
$ terraform -version
Terraform v1.4.2
on darwin_amd64
+ provider registry.terraform.io/yandex-cloud/yandex v0.140.1
```
