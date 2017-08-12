## Building blocks

Before starting working on custom developer portal, let's learn basic building blocks.

### Obtaining Dashboard API token

To run queries against Tyk API you need get credentials, which you can find on user page:

1. Select “Users” from the “System Management” section.
2. In the Users list, click “Edit” for your user.
3. The API key is the Tyk Dashboard API Access Credentials, copy this somewhere you can reference it. API key location

Let's save it to the environment variable to simplify code examples in this guide. All the commands should be run in your terminal.

```
# NOTE! Do not forget to replace with your own value
export TYK_API_KEY=1efdefd6c93046bc4102f7bf77f17f4e
```

### Creating a developer

```
curl https://admin.cloudv2.tyk.io/api/portal/developers \
    -X POST \
    -H "authorization: $TYK_API_KEY" \
    -d \
'{
    "email": "apidev@example.com",
    "password": "supersecret",
    "fields": {
        "Name": "John Snow"
    }
}'

# {"Status":"OK","Message":"598d4a33ac42130001c1257c","Meta":null}
```

Where `Message` contains developer internal ID., You do not have to remember it, since you can find a developer by his email, using API.

### Developer by Email

```
curl https://admin.cloudv2.tyk.io/api/portal/developers/email/apidev%40example.com \
    -X GET \
    -H "authorization: $TYK_API_KEY"

# {"id":"598d4a33ac42130001c1257c","email":"apidev@example.com","date_created":"2017-08-11T06:09:55.654Z","inactive":false,"org_id":"59368a6b5eeba30001786baf","api_keys":{},"subscriptions":{},"fields":{"Name":"John Snow","source":"google search"},"nonce":"","sso_key":""}
```

### Developer validation
Default Tyk Developer portal, automatically accepts all developer registrations, if they are not completely disabled in the portal configuration. 

NOTE: Do not confuse developer registration with key access, if they are registered to the portal, it does not mean they automatically have access to your APIs.

If you want to allow developer registration but add an additional layer of verification, you can use developer `inactive` attribute to handle it. By default, it is `false`, and you can set it to `true`if additional verification needed. To make this work, you need to add additional logic to your custom portal code.

### Updating developer. Example: Adding custom fields

Let's say we want to add new custom "field" to the developer, to store some internal meta information. Tyk so far does not support PATCH semantics, e.g. you cannot update only single field, you need to provide the full modified record.

Lets created updated developer record, based example response provided in `Developer by Email` section. Let's add new "traffic_source" custom field.

```
curl https://admin.cloudv2.tyk.io/api/portal/developers/598d4a33ac42130001c1257c \
    -X PUT \
    -H "authorization: $TYK_API_KEY" \
    -d \
    '{
        "id":"598d4a33ac42130001c1257c",
        "email":"apidev@example.com",
        "date_created":"2017-08-11T06:09:55.654Z",
        "inactive":false,
        "org_id":"59368a6b5eeba30001786baf",
        "api_keys":{},
        "subscriptions":{},
        "fields":{
            "Name":"John Snow",
            "traffic_source":"google search"
        }
    }'

# {"Status":"OK","Message":"Data updated","Meta":null}
```

Note that all non-empty custom fields are shown in Tyk Dashboard Developer view. Besides, all the keys created for this developer inherit his custom fields, if they are specified in Portal settings 'Signup fields' list.

### Login workflow: Checking user credentials

If you need to implement own login workflow, you need be able to validate user password.

NOTE: This is currently in the works

### Listing available APIs
Inside admin dashboard, in the portal menu, you define catalogues with the list of APIs available to developers. Each defined API is identified by its policy id field.

```
curl https://admin.cloudv2.tyk.io/api/portal/catalogue \
    -X GET \
    -H "authorization: $TYK_API_KEY"

#  {
#   "id":"5940e3d29ba5330001647b21",
#   "org_id":"59368a6b5eeba30001786baf",
#   "apis":[
#      {
#         "name":"asdasd",
#         "short_description":"",
#         "long_description":"",
#         "show":true,
#         "api_id":"",
#         "policy_id":"59527b8c375f1e000146556b",
#         "documentation":"",
#         "version":"v2"
#      },
#      {
#         "name":"asdaszczxczx",
#         "short_description":"",
#         "long_description":"",
#         "show":true,
#         "api_id":"",
#         "policy_id":"5944267f8b8e5500013082a5",
#         "documentation":"",
#         "version":"v2"
#      }
#   ]
#}
```

### Issuing keys

To generate a key for the developer, first he should send a request to the administrator of the API, and if needed provide details of key usage.
By default, all keys requests are approved automatically, and the user immediately receives his API key, but you can turn on "Review all key requests before approving them" option in portal settings, to add additional verification step, and approve all keys manually.
Once key is issued, the user receives email with Key details.

```
curl https://admin.cloudv2.tyk.io/api/portal/requests \
    -X PUT \
    -H "authorization: $TYK_API_KEY" \
    -d \
    '{
        "by_user":"<developer-id>",
        "for_plan": "<api-policy-id>"
        "version": "v2",
        "fields":{
            "custom_field":"value",
        }
    }'

# {"Status":"OK","Message":"Data updated","Meta":null}
```

### Checking user subscriptions and keys
Developer object contains field `subscriptions` which contains information about user API keys, and associtated API's (policies). Example field value:
```
"subscriptions":{"<policy-id-1>": "<api-key-1>", "<policy-id-2>": "<api-key-2>"},
```

### Analytics

You can get aggregate statistics for 1 key or all developer keys (need to specify a list of all keys). Also, you can group by day (hour or month), and by API (policy id).

API Endpoint: `/api/activity/keys/aggregate/#{keys}/#{from}/#{to}?p=-1&res=day`

* `keys` should be specified separated by ',' delimiter.
* `from` and `to` values must be in <day>/<month>/<year> format.
* resolution specified `res` attribute: 'day', 'hour' or 'month'
* `api_id` - policy id associated with developer portal API. If ommited return stats for all APIs.

```
curl "https://admin.cloudv2.tyk.io/api/activity/keys/aggregate/add2b342,5f1d9603,/5/8/2017/13/8/2017?api_id=8e4d983609c044984ecbb286b8d25cd9&api_version=Non+Versioned&p=-1&res=day" \
    -X GET \
    -H "authorization: $TYK_API_KEY"

# { "data":[
#    {
#        "id":{"day":9,"month":8,"year":2017,"hour":0,"code":200},
#        "hits":13,
#        "success":10,
#        "error":3,
#        "last_hit":"2017-08-09T12:31:02Z"
#    },
#    ...
#  ],"pages":0}
```
In example above `add2b342,5f1d9603,` is 2 users keys. Note that this example shows hashed key values as described here https://tyk.io/docs/security/concepts/key-hashing/. Key hashing  is turned on for the Cloud, but for Hybrid and On-premise you can turn it off. Hash keys means that API administrator do not have access to real user keys, but he still can use this hashed values for showing analytics.

## Building a portal

This guide includes implementation of full featured developer portal written in Ruby in just 250 lines of code. This portal implementation does not utilize any database and uses Tyk API to store and fetch all the data.

To run it, you need to have Ruby 2.3+ (latest version). Older versions may work but do not tested.

First, you need to install dependencies by running `gem install sinatra excon --no-ri` in your terminal.

After, run it like this: `TYK_PORTAL_PORT=8080 TYK_API_KEY=<your-api-key-here> ruby portal.rb`

You can also specify `TYK_DASHBOARD_URL` if you are trying this portal against On-premise version. By default, it configured to work with Cloud or Hybrid.