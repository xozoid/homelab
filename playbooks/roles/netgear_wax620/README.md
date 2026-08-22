# Netgear WAX620 role handoff

This local role configures standalone Netgear WAX620 access points through the
undocumented JSON API. It runs on the Ansible controller and does not use SSH
to the access point.

## Current scope

The role idempotently manages these basic settings:

- `apName`
- `sysCountryRegion`, fixed to the US enum `840`
- Time zone, currently `USA-Pacific` (WAX620 enum `265`)
- Custom NTP server, defaulting to `ntp.{{ domain_lan }}`
- Declared MAC access-control groups
- Static management LAN, DNS, and VLAN settings from `netgear_wax620_lan_settings`

Run it with:

```sh
ansible-playbook -i hosts.yaml playbooks/wireless.yaml
```

`linda` is in `wireless_access_points`. Its non-secret settings are in
`host_vars/linda/vars.yaml`; its WAP password is `vault_password` in the
host-specific vault.

## Verified session protocol

The API returns HTTP 200 for both success and application errors. Every API
response must therefore be parsed with `from_json` and checked for `status: 0`.
Responses do not advertise a JSON content type, so `uri` does not provide a
`json` result field.

1. `GET /` creates the `lhttpdsid` cookie.
2. `POST /socketCommunication` with `system.basicSettings.adminName` and
   `adminPasswd`, including that cookie, returns `system.security_token`.
3. Each authenticated request sends:
   - `Cookie: lhttpdsid=...; ssid=<Base64 security_token>`
   - `security: <raw security_token>`
   - `Content-Type: application/json`
   - `X-Requested-With: XMLHttpRequest`
   - same-host `Origin` and `Referer`
4. `POST /logout` with `{"admin": "admin"}` and the authenticated headers
   must return `status: 0`.

The AP has a simultaneous-login limit. Keep the browser logged out while the
playbook runs. A failed unauthenticated sequence can consume a session, so do
not add automatic authentication retries.

## Implementation pattern

For every configuration section:

1. Use the UI-captured blank-value getter payload to read current state.
2. Extract only fields owned by the role into an explicit current dictionary.
3. Build the explicit desired dictionary from documented role variables.
4. Post the UI-captured setter payload only when current and desired differ.
5. Check the response body application status, not just the HTTP status.

Avoid comparing an entire API response. Responses commonly include UI-only or
appliance-owned fields that the role should leave unchanged.

## Access-control groups

Access-control groups are `group0` through `group7` under
`system.accessControlSettings.wlanAccessControlLocalTable`. Model a managed
group with an explicit slot, policy, and full desired host list. The supported
getters return group metadata and MAC lists separately. The role combines them
for a full comparison, then updates only declared groups that differ. Unrelated
default or custom groups remain unchanged. Configure access-control groups
before SSIDs that refer to them. SSID access control is separate: set an SSID's
`access_control_group` to `group0` through `group7`; the default `None` disables
filtering while retaining any configured group for later use.

## Remaining work

### Shared system and LAN settings

`configure-wap.py` contains known payloads for time, advanced system, and LAN
settings. Advanced system settings remain to be ported using the implementation
pattern. LAN settings are applied last because management IP or VLAN changes can
disconnect the active API session; the role then skips logout.

The LAN capture contains `fqdn: "0"`, the appliance's disabled value, not a
valid FQDN example. The role intentionally does not manage FQDN until a capture
shows a successful non-empty value.

### Radios

The radio getter is:

```json
{"system":{"wlanSettings":{"wlanSettingTable":{"getRadioDetails":""}}}}
```

Radio saves use `wlan0` for 2.4 GHz and `wlan1` for 5 GHz. Channels are the
actual channel numbers, but transmit power is a vendor enum. The capture shows
enum `3` on 2.4 GHz and `0` on 5 GHz; map every desired percentage from UI
captures before exposing a human-readable `tx_power` role variable. Keep
channel and transmit-power overrides in each WAP's host vars, with shared
radio defaults in the role.

### SSIDs

Use the existing `ssidGetDetails` and `ssidSetDetails` endpoints. Model SSIDs
as a list with an explicit `slot`, rather than a mapping whose ordering selects
`vapN`. The role should manage only declared slots and build each desired
setting for both `wlan0` and `wlan1`.

## Validation checklist

After each new section, run the playbook twice with the browser logged out:

1. First run reports a change only when the setting differs.
2. Second run reports no changes.
3. Both runs complete the logout task successfully.
4. Confirm the setting in the WAP UI and capture its traffic if the API result
   differs from the UI.
