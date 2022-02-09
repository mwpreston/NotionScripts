# Welcome
Hi there and welcome to my random Notion scripts repository!  My plan is to share any automation I create around the Notion API for everyone to use here!

## Scripts Included

### SyncJira.ps1
This is a simple PowerShell script which executes the following process
1.  Retrieves a list of issues within Jira assigned to a specific user (Issues are limited to a specified project and only the includes issues assigned to the current sprint)
2.  The issues are then looped through one by one. It checks to see if the issue exists within a specified database inside Notion (matches on properties source and sourceId, where source == Jira and sourceId == Jira Issue Key)
3.  If the issue exists, the script will update its' status (To Do, In Progress, In Review, or Done) within Notion and Jira. Which ever status is closest to "Done" is used as the source of truth.
4.  If the issue doesn't exist, it's created within the Notion database.
5.  The script then checks all issues (tasks) within the Notion Database, looking for any that have a property of "Add To Jira" set to true. If some are found, they are created in Jira and the "Add To Jira" is subsequently set to false so they aren't parsed on the next run. Source and SourceId are updated.

That's pretty much it!  I'm sure you will find some nuances as I didn't spend a lot of time making this script portable, but here are some points to get you started
* Near the beginning of the script you will see a number of variables, these need to be populated.
* To create the token for Notion, head to `Settings & Members` -> `Integrations` -> `Develop your own Integrations` and follow the prompts
* Once you have your token, you can store it encrypted for the script to read by running `"NotionTokenString" | Export-CLIXML -Path C:\path_to_token_file`, then just modify Line 5 ($NotionToken=) to import from that file.
* You can get your Notion Database Id by looking at the URL
* To create the token for Jira go to `Account Settings`->`Security`->`Api token`->`Create and manage API tokens`, again, save to encrypted file once you have it just as you did with Notion
* As far as I can tell, the Jira Issues API needs to have your user id (not email) in order to properly assign it to you. To get this, go to your icon in Jira, select Profile.  In the URL, right after /people/, you will see your user id
* To get the Project ID within Jira, browse to `https://xxxxxxx.atlassian.net/rest/api/latest/project/<project_key>`, you should see the project ID on the first line
* Be sure to modify the code to include whatever Statuses you may have setup, by default, it looks for To Do, In Progress, In Review and Done
* You will also need to manually figure out your transition Ids that match those statuses. These can be found by sending a `Get` request to `/rest/api/3/issue/{issueIdOrKey}/transitions`
* Finally, you will need to specify your board name on Line 67
* If an issue is moved out of the current sprint, it's no longer managed by this script.
  
Thats all!  Have fun!  If you build anything cool, fire it back my way!