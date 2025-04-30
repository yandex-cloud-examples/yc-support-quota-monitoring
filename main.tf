resource "yandex_iam_service_account" "quota_monitor_sa" {
  name        = "quota-monitor-sa"
  description = "service account for quota monitoring function"
}

resource "yandex_resourcemanager_folder_iam_binding" "quota-monitor-sa-monitoring" {
  depends_on = [yandex_iam_service_account.quota_monitor_sa]
  folder_id = var.monitoring_folder_id

  role = "monitoring.editor"

  members = [
    "serviceAccount:${yandex_iam_service_account.quota_monitor_sa.id}",
  ]
}

resource "yandex_organizationmanager_organization_iam_binding" "quota-monitor-sa-quota-manager" {
  organization_id = var.monitoring_organization_id

  role = "quota-manager.viewer"

  members = [
    "serviceAccount:${yandex_iam_service_account.quota_monitor_sa.id}",
  ]
}

resource "yandex_function" "quota_monitor_function" {
  name               = "quotamonitor"
  description        = "Quota monitoring serverless function"
  entrypoint		 = "index.handler"
  
  environment = {
    FOLDER_ID = var.monitoring_folder_id
	BILLING_ID = var.monitoring_billing_account_id
  }
  execution_timeout  = "30"
  service_account_id = yandex_iam_service_account.quota_monitor_sa.id
  runtime            = "python312"
  memory 			 = 128
  user_hash			 = ""
  
  content {
    zip_filename = "quota-monitor.zip"
  }
 
  
}

resource "yandex_function_iam_binding" "quota_monitor_function_iam" {
  depends_on = [yandex_function.quota_monitor_function]
  function_id = yandex_function.quota_monitor_function.id
  role        = "serverless.functions.invoker"

  members = [
    "serviceAccount:${yandex_iam_service_account.quota_monitor_sa.id}",
  ]
}

resource "yandex_function_trigger" "quota_monitor_function_trigger" {
  depends_on = [yandex_function_iam_binding.quota_monitor_function_iam]
  name        = "quotamonitortrigger"
  timer {
    cron_expression = "*/30 * ? * * *"
  }
  
  function {
    id = yandex_function.quota_monitor_function.id
	service_account_id = yandex_iam_service_account.quota_monitor_sa.id
	tag = "$latest"
  }
}

resource "yandex_monitoring_dashboard" "quota_monitor_clouds" {
  name        = ""
  description = "Dashboard for monitoring Clouds quota usage"
  title       = "Quota monitor (Clouds)"

  parametrization {
    selectors = "{cloud_id=\"*\"}"
    
    parameters {
      id          = "cloud_id"
      title       = "Cloud ID"
      description = "Select cloud to monitor"
      hidden      = false
      label_values {
        label_key       = "cloud_id"
        selectors       = "{}"
        multiselectable = false
        default_values  = []
      }
    }
    
    parameters {
      id          = "service"
      title       = "Service"
      description = "Select service to monitor"
      hidden      = false
      label_values {
        label_key       = "_service"
        selectors       = "{}"
        multiselectable = false
        default_values  = []
      }
    }
  }

  widgets {
    chart {
      title          = "Quotas"
      description    = "Current usage vs quota limits"
      chart_id       = "quotas_chart"
      display_legend = false
      freeze         = "FREEZE_DURATION_UNSPECIFIED"
      
      queries {
        downsampling {
          disabled         = true
          gap_filling      = "GAP_FILLING_UNSPECIFIED"
          grid_aggregation = "GRID_AGGREGATION_UNSPECIFIED"
        }
        
        target {
          query     = <<-EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}",
              service = "custom",
              _service = "{{service}}",
              cloud_id = "{{cloud_id}}",
			  _quota_name = "*",
			  _quota_type = "value"
            },
			"Value: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false

        }
        
        target {
          query     = <<-EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}",
              service = "custom",
              _service = "{{service}}",
              cloud_id = "{{cloud_id}}",
			  _quota_name = "*",
			  _quota_type = "limit"
            },
			"Limit: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false

        }
      }
      
      visualization_settings {
        type        = "VISUALIZATION_TYPE_LINE"
        interpolate = "INTERPOLATE_LINEAR"
        aggregation = "SERIES_AGGREGATION_AVG"
        normalize   = false
        show_labels = false
        

        
        yaxis_settings {
          left {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
          right {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
        }
      }
      
      
    }
    
    position {
      x = 0
      y = 0
      w = 36
      h = 15
    }
  }
}

resource "yandex_monitoring_dashboard" "quota_monitor_billing" {
  name        = ""
  description = "Dashboard for monitoring billing accounts quota usage"
  title       = "Quota monitor (Billing)"

  parametrization {
    selectors = "{billing_account_id=\"*\"}"
    
    parameters {
      id          = "billing_account_id"
      title       = "Billing Account ID"
      description = "Select billing account to monitor"
      hidden      = false
      label_values {
        label_key       = "billing_account_id"
        selectors       = "{}"
        multiselectable = false
        default_values  = []
      }
    }
  }

  widgets {
    chart {
      title          = "Quotas"
      description    = "Current usage vs quota limits for billing account"
      chart_id       = "billing_quotas_chart"
      display_legend = false
      freeze         = "FREEZE_DURATION_UNSPECIFIED"
      
      queries {
        downsampling {
          disabled         = true
          gap_filling      = "GAP_FILLING_UNSPECIFIED"
          grid_aggregation = "GRID_AGGREGATION_UNSPECIFIED"
        }
        
        target {
          query     = <<-EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}",
              service = "custom",
              billing_account_id = "{{billing_account_id}}",
			  _quota_name = "*",
			  _quota_type = "value"
            }, 
			"Value: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false
        }
        
        target {
          query     = <<-EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}",
              service = "custom",
              billing_account_id = "{{billing_account_id}}",
			  _quota_name = "*",
			  _quota_type = "limit"
            }, 
			"Limit: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false
        }
      }
      
      visualization_settings {
        type        = "VISUALIZATION_TYPE_LINE"
        interpolate = "INTERPOLATE_LINEAR"
        aggregation = "SERIES_AGGREGATION_AVG"
        normalize   = false
        show_labels = false
        
        yaxis_settings {
          left {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
          right {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
        }
      }
      
    }
    
    position {
      x = 0
      y = 0
      w = 36
      h = 15
    }
  }
}

resource "yandex_monitoring_dashboard" "quota_monitor_organization_manager" {
  name        = ""
  description = "Dashboard for monitoring Orginization Manager quota usage"
  title       = "Quota monitor (Orginization Manager)"
  
   parametrization {
    selectors = "{org_id=\"*\"}"
    
    parameters {
      id          = "organizaion_id"
      title       = "Organization ID"
      description = "Select organization to monitor"
      hidden      = false
      label_values {
        label_key       = "org_id"
        selectors       = "{}"
        multiselectable = false
        default_values  = []
      }
    }
  }

  widgets {
    chart {
      title          = "Resource Manager"
      description    = "Resource Manager quotas for organization"
      chart_id       = "resource_manager_chart"
      display_legend = false
      freeze         = "FREEZE_DURATION_UNSPECIFIED"
      
      queries {
        downsampling {
          disabled         = true
          gap_filling      = "GAP_FILLING_UNSPECIFIED"
          grid_aggregation = "GRID_AGGREGATION_UNSPECIFIED"
        }
        
        target {
          query     = <<EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}", 
              service = "custom", 
              org_id = "{{organizaion_id}}", 
              _service = "resource-manager", 
			  _quota_name = "*",
			  _quota_type = "value"
            }, 
			"Value: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false
        }
        
        target {
          query     = <<EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}", 
              service = "custom", 
              org_id = "{{organizaion_id}}", 
              _service = "resource-manager",
			  _quota_name = "*",
			  _quota_type = "limit"
            }, 
			"Limit: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false
        }
      }
      
      visualization_settings {
        type        = "VISUALIZATION_TYPE_LINE"
        interpolate = "INTERPOLATE_LINEAR"
        aggregation = "SERIES_AGGREGATION_AVG"
        normalize   = false
        show_labels = false
        
    
        
        yaxis_settings {
          left {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
          right {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
        }
      }
      
    }
    
    position {
      x = 0
      y = 0
      w = 36
      h = 15
    }
  }

  widgets {
    chart {
      title          = "Organization Manager"
      description    = "Organization Manager quotas"
      chart_id       = "org_manager_chart"
      display_legend = false
      freeze         = "FREEZE_DURATION_UNSPECIFIED"
      
      queries {
        downsampling {
          disabled         = true
          gap_filling      = "GAP_FILLING_UNSPECIFIED"
          grid_aggregation = "GRID_AGGREGATION_UNSPECIFIED"
        }
        
        target {
          query     = <<EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}", 
              service = "custom", 
              org_id = "{{organizaion_id}}", 
              _service = "organization-manager",
			  _quota_name = "*",
			  _quota_type = "value"
            }, 
			"Value: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false
        }
        
        target {
          query     = <<EOT
            alias("*"{
              folderId = "${var.monitoring_folder_id}", 
              service = "custom", 
              org_id = "{{organizaion_id}}", 
              _service = "organization-manager",
			  _quota_name = "*",
			  _quota_type = "limit"
            },
			"Limit: {{_quota_name}}")
          EOT
		  text_mode = false
          hidden    = false
        }
      }
      
      visualization_settings {
        type        = "VISUALIZATION_TYPE_LINE"
        interpolate = "INTERPOLATE_LINEAR"
        aggregation = "SERIES_AGGREGATION_AVG"
        normalize   = false
        show_labels = false
        
        
        yaxis_settings {
          left {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
          right {
            type        = "YAXIS_TYPE_LINEAR"
            unit_format = "UNIT_FORMAT_UNSPECIFIED"
          }
        }
      }
      

    }
    
    position {
      x = 0
      y = 15
      w = 36
      h = 15
    }
  }
}