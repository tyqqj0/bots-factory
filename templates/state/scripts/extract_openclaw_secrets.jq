# Extract a minimal secrets file from a full openclaw.json.
# Output is intended to be written to openclaw.secrets.local.json (gitignored).
#
# Philosophy:
# - Keep only values that are secrets / credentials.
# - Use stable paths (not the keyname-based redaction fallback).
# - Arrays/objects are preserved as-is where appropriate.

{
  models: {
    providers: (
      (.models.providers // {})
      | (if type=="object" then
          with_entries(
            .value |= (
              if type=="object" then
                ({} 
                 + (if has("apiKey") then {apiKey: .apiKey} else {} end)
                 + (if has("token") then {token: .token} else {} end)
                 + (if has("key") then {key: .key} else {} end)
                )
              else . end
            )
          )
        else . end)
    )
  },
  tools: {
    web: {
      search: (
        if (.tools.web.search? and .tools.web.search.apiKey? != null) then
          { apiKey: .tools.web.search.apiKey }
        else
          {}
        end
      )
    }
  },
  channels: {
    telegram: (
      if (.channels.telegram? and .channels.telegram.botToken? != null) then
        { botToken: .channels.telegram.botToken }
      else {} end
    ),
    feishu: (
      if .channels.feishu? then
        {
          accounts: (
            (.channels.feishu.accounts // {})
            | (if type=="object" then with_entries({key: .key, value: {appSecret: .value.appSecret}}) else . end)
          )
        }
      else {} end
    )
  },
  gateway: {
    auth: (
      if (.gateway.auth? and .gateway.auth.token? != null) then
        { token: .gateway.auth.token }
      else {} end
    )
  }
}
| .channels.feishu.accounts = (
    (.channels.feishu.accounts // {})
    | (if type=="object" then
        with_entries(
          .value |= (with_entries(select(.value != null)))
        )
      else
        .
      end)
  )
| with_entries(select(.value != null))
