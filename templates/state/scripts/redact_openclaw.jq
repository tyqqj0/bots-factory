# Generate openclaw.public.json from openclaw.json by redacting secrets.
#
# Notes:
# - Prefer explicit paths for known secrets.
# - Add a recursive key-name based fallback for other *key/token/secret* fields.

def redact_value:
  "__REDACTED__";

# Redact by key name (fallback)
def redact_by_keyname:
  walk(
    if type == "object" then
      with_entries(
        if (.key|test("(?i)(secret|token|api[_-]?key|access[_-]?key|private[_-]?key)$")) then
          .value = redact_value
        else
          .
        end
      )
    else . end
  );

.
# Feishu app secrets
| (.channels.feishu.accounts[]? | .appSecret) = redact_value
# Gateway token
| (.gateway.auth.token?) = (if . == null then . else redact_value end)
# Providers: common fields (keep object shape; only replace scalar secret fields)
| (.models.providers[]? | select(type=="object") | .apiKey? ) |= (if . == null then . else redact_value end)
| (.models.providers[]? | select(type=="object") | .token?  ) |= (if . == null then . else redact_value end)
| (.models.providers[]? | select(type=="object") | .key?    ) |= (if . == null then . else redact_value end)
# Fallback
| redact_by_keyname
