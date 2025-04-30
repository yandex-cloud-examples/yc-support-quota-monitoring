import requests
import json
import os
from typing import Dict, List, Optional

# Конфигурация
FOLDER_ID = os.environ['FOLDER_ID']
METADATA_URL = "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token"
API_ENDPOINTS = {
    "organizations": "https://organization-manager.api.cloud.yandex.net/organization-manager/v1/organizations",
    "billing_accounts": "https://billing.api.cloud.yandex.net/billing/v1/billingAccounts",
    "clouds": "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds",
    "quota_services": "https://quota-manager.api.cloud.yandex.net/quota-manager/v1/quotaLimits/services",
    "quota_limits": "https://quota-manager.api.cloud.yandex.net/quota-manager/v1/quotaLimits",
    "monitoring": "https://monitoring.api.cloud.yandex.net/monitoring/v2/data/write"
}

def get_iam_token() -> Optional[str]:
    """Получение IAM-токена из метаданных"""
    try:
        response = requests.get(METADATA_URL, headers={"Metadata-Flavor": "Google"}, timeout=5)
        response.raise_for_status()
        return response.json().get("access_token")
    except requests.exceptions.RequestException as e:
        print(f"Ошибка получения токена: {e}")
        return None

def api_request(url: str, headers: Dict, params: Optional[Dict] = None) -> Optional[Dict]:
    """Универсальный метод для API-запросов"""
    try:
        response = requests.get(url, headers=headers, params=params, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        error_message = f"API ошибка ({url}): {e}"
        if hasattr(e, 'response') and e.response is not None:
            try:
                error_message += f" {e.response.json()}"
            except Exception:
                error_message += f" {e.response.text}"
        print(error_message)
        return None
def process_quotas(resources: List[Dict], resource_type: str, service_list: List[str], metrics: List[Dict], headers: Dict):
    """Обработка квот для ресурсов"""
    for resource in resources:
        resource_id = resource.get("id")
        for service in service_list:
            params = {
                "resource.id": resource_id,
                "service": service,
                "resource.type": resource_type
            }
            data = api_request(API_ENDPOINTS["quota_limits"], headers, params)

            if data and "quotaLimits" in data:
                for quota in data["quotaLimits"]:
                    if quota.get("usage") is None or quota.get("limit") is None:
                        continue
                    # Выбор корректного ключа для метки
                    if resource_type == "resource-manager.cloud":
                        label_key = "cloud_id"
                    elif resource_type == "organization-manager.organization":
                        label_key = "org_id"
                    elif resource_type == "billing.account":
                        label_key = "billing_account_id"
                    else:
                        label_key = "resource_id"  # fallback

                    metric_labels = {
                        label_key: resource_id,
                        "_service": service,
                        "_quota_name": quota['quotaId']
                    }
                    # значения метрик отправляются с заданными префиксами для удобства выборки
                    metrics.extend([
                        {
                            "name": f"quota.{quota['quotaId']}_value",
                            "labels": {
                            **metric_labels,
                            "_quota_type": "value"
                            },
                            "value": quota["usage"]
                        },
                        {
                            "name": f"quota.{quota['quotaId']}_limit",
                            "labels": {
                            **metric_labels,
                            "_quota_type": "limit"
                            },
                            "value": quota["limit"]
                        }
                    ])

def send_monitoring_data(metrics: List[Dict], headers: Dict):
    """Отправка метрик в Monitoring API"""
    if not metrics:
        print("Нет метрик для отправки")
        return

    data = {"metrics": metrics}
    try:
        response = requests.post(
            API_ENDPOINTS["monitoring"],
            headers={**headers, "Content-Type": "application/json"},
            params={"folderId": FOLDER_ID, "service": "custom"},
            json=data,
            timeout=30
        )
        response.raise_for_status()
        print(f"Метрики успешно отправлены: {response.text}")
    except requests.exceptions.RequestException as e:
        return {
            'statusCode': 500,
            'body': f"Ошибка отправки метрик в Yandex Monitoring: {e}"
        }

def handler(event, context):
    """Точка входа в function"""
    # Получаем IAM-токен
    iam_token = get_iam_token()
    if not iam_token:
        return {
            'statusCode': 500,
            'body': 'Ошибка получения IAM-токена'
        }

    headers = {"Authorization": f"Bearer {iam_token}"}
    metrics = []

    # Обработка organizations
    org_data = api_request(API_ENDPOINTS["organizations"], headers)
    organizations = org_data.get("organizations", []) if org_data else []

    # Получаем сервисы для организаций
    org_services_data = api_request(API_ENDPOINTS["quota_services"], headers, {"resource_type": "organization-manager.organization"})
    org_services = [s["id"] for s in org_services_data.get("services", [])] if org_services_data else []

    process_quotas(organizations, "organization-manager.organization", org_services, metrics, headers)

    # Обработка clouds
    clouds_data = api_request(API_ENDPOINTS["clouds"], headers)
    clouds = clouds_data.get("clouds", []) if clouds_data else []

    cloud_services_data = api_request(API_ENDPOINTS["quota_services"], headers, {"resource_type": "resource-manager.cloud"})
    cloud_services = [s["id"] for s in cloud_services_data.get("services", [])] if cloud_services_data else []

    process_quotas(clouds, "resource-manager.cloud", cloud_services, metrics, headers)

    # Обработка billing accounts
    if 'BILLING_ID' in os.environ:
        # Получаем значения из переменной окружения и разбиваем по запятым
        billing_accounts = [bid.strip() for bid in os.environ['BILLING_ID'].split(',') if bid.strip()]
    else:
        # Если переменной нет, получаем данные через API
        billing_data = api_request(API_ENDPOINTS["billing_accounts"], headers)
        billing_accounts = [acc.get("id") for acc in billing_data.get("billingAccounts", [])] if billing_data else []
    for acc_id in billing_accounts:
        process_quotas(
            [{"id": acc_id}],
            "billing.account",
            ["billing"],
            metrics,
            headers
        )

    # Отправка метрик
    send_monitoring_data(metrics, headers)

    return {
        'statusCode': 200,
        'body': 'Метрики успешно обработаны и отправлены в Yandex Monitoring API'
    }
