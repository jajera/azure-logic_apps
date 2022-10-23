resource "azurerm_resource_group" "main" {
  name     = "azure-logic_apps"
  location = "southeastasia"
  tags = {
    usage = "azure-logic_apps"
  }
}

resource "azurerm_storage_account" "storageacct" {
  name                     = "ajstorageacct1"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_storage_container" "sc" {
  name                  = "log-analytics-data"
  storage_account_name  = azurerm_storage_account.storageacct.name
  container_access_type = "private"
}

data "azurerm_managed_api" "azuremonitorlogs" {
  name     = "azuremonitorlogs"
  location = azurerm_resource_group.main.location
}

data "azurerm_managed_api" "azureblob" {
  name     = "azureblob"
  location = azurerm_resource_group.main.location
}

data "azurerm_client_config" "current" {}

# note: manual authorization is required for this connector
resource "azurerm_api_connection" "azuremonitorlogs" {
  name                = "azuremonitorlogs1"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = data.azurerm_managed_api.azuremonitorlogs.id
  display_name        = "azuremonitorlogs"

  parameter_values = {
    "token:TenantId"  = data.azurerm_client_config.current.tenant_id,
    "token:grantType" = "code"
  }

  lifecycle {
    ignore_changes = [
      parameter_values
    ]
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_api_connection" "azureblob" {
  name                = "azureblob1"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = data.azurerm_managed_api.azureblob.id
  display_name        = "azureblob"

  parameter_values = {
    "accountName" = azurerm_storage_account.storageacct.name,
    "accessKey"   = azurerm_storage_account.storageacct.primary_access_key
  }

  lifecycle {
    ignore_changes = [
      parameter_values
    ]
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_logic_app_workflow" "la" {
  name                = "logicapp1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  identity {
    type = "SystemAssigned"
  }

  workflow_parameters = {
    "$connections" = jsonencode({
      "defaultValue" : {},
      "type" : "Object"
    })
  }

  parameters = {
    "$connections" : jsonencode({
      "azuremonitorlogs" : {
        "connectionId" : "${azurerm_api_connection.azuremonitorlogs.id}",
        "connectionName" : "${azurerm_api_connection.azuremonitorlogs.name}",
        "id" : "${azurerm_api_connection.azuremonitorlogs.managed_api_id}"
      },
      "azureblob" : {
        "connectionId" : "${azurerm_api_connection.azureblob.id}",
        "connectionName" : "${azurerm_api_connection.azureblob.name}",
        "id" : "${azurerm_api_connection.azureblob.managed_api_id}"
      }
    })

  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_logic_app_trigger_recurrence" "trigger" {
  name         = "run-every-day"
  logic_app_id = azurerm_logic_app_workflow.la.id
  frequency    = "Day"
  interval     = 1
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "loganalytics1"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 365
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_logic_app_action_custom" "action1" {
  name         = "run-query-and-list-results"
  logic_app_id = azurerm_logic_app_workflow.la.id

  body = <<BODY
  {
    "inputs": {
      "body": "let dt = now();\nlet year = datetime_part('year', dt);\nlet month = datetime_part('month', dt);\nlet day = datetime_part('day', dt);\nlet hour = datetime_part('hour', dt);\nlet startTime = make_datetime(year,month,day,hour,0)-1h;\nlet endTime = startTime + 1h - 1tick;\nAzureActivity\n| where ingestion_time() between(startTime .. endTime)\n| project \n    TimeGenerated,\n    BlobTime = startTime, \n    OperationName ,\n    OperationNameValue ,\n    Level ,\n    ActivityStatus ,\n    ResourceGroup ,\n    SubscriptionId ,\n    Category ,\n    EventSubmissionTimestamp ,\n    ClientIpAddress = parse_json(HTTPRequest).clientIpAddress ,\n    ResourceId = _ResourceId",
      "host": {
        "connection": {
          "name": "@parameters('$connections')['azuremonitorlogs']['connectionId']"
        }
      },
      "method": "post",
      "path": "/queryData",
      "queries": {
        "resourcegroups": "${azurerm_resource_group.main.name}",
        "resourcename": "${azurerm_log_analytics_workspace.main.name}",
        "resourcetype": "Log Analytics Workspace",
        "subscriptions": "${data.azurerm_client_config.current.subscription_id}",
        "timerange": "Last 4 hours"
      }
    },
    "runAfter": {},
    "type": "ApiConnection"
  }
  BODY
}

resource "azurerm_logic_app_action_custom" "action2" {
  name         = "parse-json"
  logic_app_id = azurerm_logic_app_workflow.la.id

  body = <<BODY
  {
    "inputs": {
      "content": "@body('run-query-and-list-results')",
      "schema": {
        "type": "object",
        "properties": {
          "TenantId": {
            "type": "string"
          },
          "SourceSystem": {
            "type": "string"
          },
          "TimeGenerated": {
            "type": "string"
          },
          "Source": {
            "type": "string"
          },
          "EventLog": {
            "type": "string"
          },
          "Computer": {
            "type": "string"
          },
          "EventLevel": {
            "type": "integer"
          },
          "EventLevelName": {
            "type": "string"
          },
          "ParameterXml": {
            "type": "string"
          },
          "EventData": {
            "type": "string"
          },
          "EventID": {
            "type": "integer"
          },
          "RenderedDescription": {
            "type": "string"
          },
          "AzureDeploymentID": {
            "type": "string"
          },
          "Role": {
            "type": "string"
          },
          "EventCategory": {
            "type": "integer"
          },
          "UserName": {
            "type": "string"
          },
          "Message": {
            "type": "string"
          },
          "MG": {
            "type": "string"
          },
          "ManagementGroupName": {
            "type": "string"
          },
          "Type": {
            "type": "string"
          },
          "_ResourceId": {
            "type": "string"
          }
        }
      }
    },
    "runAfter": {
      "${azurerm_logic_app_action_custom.action1.name}": [
        "Succeeded"
      ]
    },
    "type": "ParseJson"
  }
  BODY
}

resource "azurerm_logic_app_action_custom" "action3" {
  name         = "compose"
  logic_app_id = azurerm_logic_app_workflow.la.id

  body = <<BODY
  {
    "inputs": "@body('parse-json')",
    "runAfter": {
      "${azurerm_logic_app_action_custom.action2.name}": [
        "Succeeded"
      ]
    },
    "type": "Compose"
  }
  BODY
}

resource "azurerm_logic_app_action_custom" "action4" {
  name         = "create-blob"
  logic_app_id = azurerm_logic_app_workflow.la.id

  body = <<BODY
  {
    "inputs": {
      "host": {
        "connection": {
          "name": "@parameters('$connections')['azureblob']['connectionId']"
        }
      },
      "method": "post",
      "body": "@outputs('compose')",
      "headers": {
        "ReadFileMetadataFromServer": true
      },
      "path": "/v2/datasets/@{encodeURIComponent(encodeURIComponent('AccountNameFromSettings'))}/files",
      "queries": {
        "folderPath": "${azurerm_storage_container.sc.name}",
        "name": "@{subtractFromTime(formatDateTime(utcNow(), 'yyyy-MM-ddTHH:00:00'), 1, 'Hour')}",
        "queryParametersSingleEncoded": true
      }
    },
    "runtimeConfiguration": {
      "contentTransfer": {
        "transferMode": "Chunked"
      }
    },
    "runAfter": {
      "${azurerm_logic_app_action_custom.action3.name}": [
        "Succeeded"
      ]
    },
    "type": "ApiConnection"
  }
  BODY
}
