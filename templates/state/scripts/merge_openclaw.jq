# Merge openclaw.public.json with openclaw.secrets.local.json to produce openclaw.json.
# Secrets win.

def deepmerge(a; b):
  if (a|type)=="object" and (b|type)=="object" then
    reduce ((a|keys_unsorted) + (b|keys_unsorted) | unique[]) as $k
      ({};
        .[$k] = deepmerge(a[$k]; b[$k])
      )
  elif (a|type)=="array" and (b|type)=="array" then
    b
  else
    if b == null then a else b end
  end;

def normalize_secrets(s):
  if (s|type)=="array" then (s[0] // {}) else (s // {}) end;

deepmerge(.; normalize_secrets($secrets))
