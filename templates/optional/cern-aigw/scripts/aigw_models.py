# Lists the model IDs this CERN AI Gateway key can call. Uses the cern-aigw wrapper settings; never prints the key.
import sys
import urllib.error

from cern_aigw_wrapper import gatewaymodels as gm
from cern_aigw_wrapper import settings as st

s = st.load()
root = gm.gateway_root(s.base_url)
if not root:
    sys.exit("aigw: unexpected gateway base URL")
try:
    data = gm.fetch(root + "/v1/models", s.api_key)
except urllib.error.HTTPError as e:
    sys.exit("aigw: model list refused (HTTP %d)" % e.code)
except OSError as e:
    sys.exit("aigw: gateway unreachable (%s)" % type(e).__name__)
for model in sorted(m.get("id", "") for m in data.get("data", []) if isinstance(m, dict)):
    print(model)
