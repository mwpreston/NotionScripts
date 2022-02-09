# Get authentication and configuration variables needed


#Notion Configuration
$NotionToken = Import-CliXML c:\creds\notion.token
$NotionDatabaseID = 'Notion Database Id'
$NotionHeaders = @{
    "Authorization" = "Bearer $($NotionToken)"
    "Content-type"  = "application/json"
    "Notion-Version" = "2021-08-16"
}


#Jira Configuration
$JiraURI = "https://xxxxxxx.atlassian.net"
$JiraUserEmail = "user@company.com"
$JiraToken = Import-CLIXML C:\creds\jira.token
$JiraAuthString = $JiraUserEmail + ":" + $JiraToken
$user = [System.Text.Encoding]::UTF8.GetBytes($JiraAuthString)
$JiraHeaders = @{
    "Authorization" = "Basic " + [System.Convert]::ToBase64String($user)
    "Content-type"  = "application/json"
} 
$JiraUserId = "xxxxxxxxxxxxxxxxxxxxxxxxx"
$JiraProjectId = "11185"




#Stack Rank to use to decide who wins in the event of a conflict
$stackrank = @{
    "To Do" = 10
    "In Progress" = 20
    "In Review" = 30
    "Done"  = 40
}

function Invoke-NotionAPICall
{
    param(
        [string] $Resource,
        [string] $Method,
        [string] $Body
    )
    $uri = "https://api.notion.com/$Resource"
    $results = Invoke-RestMethod -Uri $uri -Method $Method -Headers $NotionHeaders -Body $Body
    return $results
}

function Invoke-JiraAPICall
{
    param(
        [string] $Resource,
        [string] $Method,
        [string] $Body
    )
    $uri = "$JiraURI/$Resource"
    $results = Invoke-WebRequest -Uri $uri -Method $Method -Body $Body -Headers $JiraHeaders
    $results = $results.Content | ConvertFrom-Json 
    return $results
}

# Get Issues from current sprint and add if they aren't present, if present, ensure the status is set properly

# Get current board id
$results = Invoke-JiraAPICall -Resource "rest/agile/1.0/board?name=RB%20Board" -Method "Get"
$boardid = $results.values.id
# Get open sprint id for board
$results = Invoke-JiraAPICall -Resource "rest/agile/1.0/board/$boardid/sprint?state=active" -Method "Get"
$sprintid = $results.values.id
# Get all issues in current sprint - assigned to me
$results = Invoke-JiraAPICall -Resource "/rest/agile/1.0/board/$boardid/sprint/$sprintid/issue" -Method "Get"
$issues = $results.issues | where {$_.fields.assignee.emailAddress -eq "$JiraUserEmail"} 
# Loop through issues
foreach ($issue in $issues) {
    # Check if issue exists in Notion
    $resource = "v1/databases/$NotionDatabaseID/query"
    $body = '
        {
            "filter": 
            {
                "and": [
                {
                    "property": "Source",
                    "text": 
                    {
                        "contains": "Jira"
                    }
                },
                {
                    "property": "SourceId",
                    "text": 
                    {
                        "contains": "'+$($issue.key)+'"
                    }
                }
                ]
            }
        }
    '
    $NotionIssue = (Invoke-NotionAPICall -Resource $resource -Method "Post" -Body $body).results
    if ($NotionIssue.Count -gt 0){
        # Issue is already there - update it if need be
        $JiraStatus = $issue.fields.status.name
        $NotionStatus = $NotionIssue.properties.status.select.name
        if ($stackrank[$NotionStatus] -gt $stackrank[$JiraStatus]){
            if ($NotionStatus -eq "In Progress") {
                $tranid = "21"
            }
            elseif ( $NotionStatus -eq "In Review") {
                $tranid = "41"
            }
            elseif ($NotionStatus -eq "Done") {
                $tranid = "31"
            }
            $jirabodyjson = '{
                "transition": {
                    "id": "'+$tranid+'"
                }
            }'
            $JiraRes = Invoke-JiraAPICall -Method "Post" -Resource "rest/api/3/issue/$($issue.key)/transitions" -Body $jirabodyjson
        }
        elseif (($stackrank[$NotionStatus] -lt $stackrank[$JiraStatus])) {
            $bodyjson = '{
                "properties": {
                    "Status": 
                    { 
                        "select": {
                            "name": "'+$JiraStatus+'"
                        } 
                    }
                }
            }'
            $page = Invoke-NotionAPICall -Method "Patch" -Resource "v1/pages/$($NotionIssue.id)" -Body $bodyjson
        }
        else {
        }
    }
    else {
        $body = '{
            "parent": {
                "database_id": "'+$NotionDatabaseID+'"
            },
            "properties": {
                "Name": {
                    "title": [
                        {
                            "text": {
                                "content": "'+$issue.fields.summary+'"
                            }
                        }
                    ]
                },
                "Source": {
                    "rich_text": [
                        {
                            "text": {
                                "content": "Jira"
                            }
                        }
                    ]
                },
                "SourceId" : {
                    "rich_text": [
                        {
                            "text": {
                                "content": "'+$issue.key+'"
                            }
                        }
                    ]
                },
                "Status" : {
                    "select": {
                        "name": "'+$issue.fields.status.name+'"
                    }
                }
            }
        }'
        Invoke-NotionAPICall -Method "Post" -Resource "v1/pages" -Body $body
    }
}

# Now check for issues flagged within Notion to be created in Jira and add them to current sprint

# Are there any new tasks that were created in Notion that were flagged to be added to Jira?
# Get tasks with add to jira checked
# Retrieve list of tasks that were initially created in Jira inside of Notion
$resource = "v1/databases/$NotionDatabaseID/query"
# Change to actually look at done once we are ready...
$body = '
    {
        "filter": 
        {
            "property": "Add To Jira",
            "checkbox": {
                "equals": true
            }
        }
    }
'
$tasks = (Invoke-NotionAPICall -Resource $resource -Method "Post" -Body $body).results
foreach ($task in $tasks) {
    # Get status for transition in Jira
    $localstatus = $task.properties.Status.select.Name
    if ($localstatus -eq "In Progress") {
        $tranid = "21"
    } elseif ( $localstatus -eq "In Review") {
        $tranid = "41"
    } elseif ($localstatus -eq "To Do") {
        $tranid = "11"
    }


    # Build Body for add

    $body = '{

        "fields": {
            "summary": "' + $task.properties.Name.title.plain_text + '",
            "assignee": {
                "id": "'+$JiraUserId + '"
            },
            "project": {
                "id": "'+$JiraProjectId+'"
            },
            "issuetype": {
                "id": "10831"
            },
            "customfield_10006": '+$sprintid+'

        },
        "transition": {
            "id": "'+$tranid+'"
        }
    }
'


    $JiraRes = Invoke-JiraAPICall -Method "Post" -Resource "rest/api/3/issue" -Body $body
    $SourceId = $JiraRes.key

    # need to get new keys and add them to source and sourceid and remove add to jira checkbox
    $bodyjson = '{
        "properties": {
            "Source": {
                "rich_text": [
                    {
                        "text": {
                            "content": "Jira"
                        }
                    }
                ]
            },
            "SourceId" : {
                "rich_text": [
                    {
                        "text": {
                            "content": "'+$SourceId+'"
                        }
                    }
                ]
            },
            "Add To Jira": {
                "checkbox": false
            }
        }
    }'
    $page = Invoke-NotionAPICall -Method "Patch" -Resource "v1/pages/$($task.id)" -Body $bodyjson
}
