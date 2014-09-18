Opsmatic Webhook Fast Setup For PagerDuty
=========================================

A tool to quickly check your PagerDuty account's services and
find any services that are missing an Opsmatic Webhook. Optionally
installs your webhook on all services. Leaves all other webhooks
alone.

Requirements
------------

* Ruby 1.9.x (1.9.3), 2.0.0, 2.1.x
* pager_duty_setup.rb script
* Opsmatic Organization Integration Token (Found in the Opsmatic dashboard under Org Settings | Team)
* PagerDuty Subdomain (your custom URL subdomain for PagerDuty)
* PagerDuty API Access Key (Found in PagerDuty dashboard, under the API Access menu)

Running the script
------------------

To generate a quick report showing what services have an Opsmatic
webhook installed, run the following from your command line in the
same directory as the script (be sure to substitute your information
in the appropriate places:

    ruby pager_duty_setup.rb -s my-pagerduty-subdomain --pdkey my-pagerduty-api-key --okey my-opsmatic-token

To add your Opsmatic webhook to all of your services, run:

    ruby pager_duty_setup.rb -s my-pagerduty-subdomain --pdkey my-pagerduty-api-key --okey my-opsmatic-token --addhooks

