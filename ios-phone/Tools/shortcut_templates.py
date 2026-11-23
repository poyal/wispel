import plistlib
import sys
from pathlib import Path

# Apple Shortcuts imports the signed result of these workflow templates.
target = Path(sys.argv[1])
target.mkdir(parents=True, exist_ok=True)
for kind, name in {"call": "전화", "sms": "문자", "kakao": "카카오톡", "slack": "Slack", "mail": "메일플러그"}.items():
    params = {"kind": kind}
    if kind == "call":
        params["text"] = {
            "WFSerializationType": "WFTextTokenString",
            "Value": {
                "string": "\ufffc",
                "attachmentsByRange": {"{0, 1}": {"Type": "ExtensionInput"}},
            },
        }
    template = {
        "WFWorkflowName": "위스펠 · " + name,
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 1440408063, "WFWorkflowIconGlyphNumber": 61440},
        "WFWorkflowClientVersion": "4000",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowHasShortcutInputVariables": kind == "call",
        "WFWorkflowTypes": ["ActionExtension"] if kind == "call" else [],
        "WFWorkflowActions": [{
            "WFWorkflowActionIdentifier": "app.wispel.phone.ForwardNotice",
            "WFWorkflowActionParameters": params,
        }],
    }
    (target / (kind + ".shortcut")).write_bytes(plistlib.dumps(template))
