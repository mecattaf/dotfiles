"""Versioned reply validation and useful read-only queries. No transport side effects."""
import json
import math
import re

PROTOCOL = "agency.domicile.snapshot"
MAX_BYTES = 2 * 1024 * 1024

class ProtocolError(ValueError):
    pass

def require(condition, message):
    if not condition:
        raise ProtocolError(message)

def typed(value, kind):
    require(isinstance(value, dict) and set(value) == {"kind", "value"}
            and value["kind"] == kind and isinstance(value["value"], str)
            and 0 < len(value["value"]) <= 4096, "invalid typed identity")
    return value["value"]

def validate_reply(raw, request_id, desktop_id):
    try:
        return _validate_reply(raw,request_id,desktop_id)
    except (KeyError,TypeError,IndexError,RecursionError,OverflowError) as error:
        raise ProtocolError("invalid snapshot schema") from error

def _validate_reply(raw, request_id, desktop_id):
    require(len(raw) <= MAX_BYTES, "oversized snapshot")
    try:
        reply = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise ProtocolError("invalid snapshot JSON") from error
    require(isinstance(reply, dict) and reply.get("protocol") == PROTOCOL and reply.get("version") == 1, "unsupported snapshot protocol")
    require(set(reply)=={"protocol","version","requestId","desktopId","epoch","revision","capturedAt","source","ok", "snapshot" if reply.get("ok") is True else "error"},"unknown envelope fields")
    require(isinstance(reply["capturedAt"],str) and len(reply["capturedAt"])<=40,"invalid capture timestamp")
    require(isinstance(reply["source"],dict) and set(reply["source"])=={"shell","adapter","imagine","sdk"} and all(isinstance(v,str) and 0<len(v)<=256 for v in reply["source"].values()),"invalid source identity")
    require(reply.get("requestId") == request_id and reply.get("desktopId") == desktop_id, "response identity mismatch")
    require(isinstance(reply.get("epoch"), str) and re.fullmatch(r"[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}", reply["epoch"]), "invalid mount epoch")
    require(type(reply.get("revision")) is int and reply["revision"] >= 1, "invalid revision")
    if reply.get("ok") is False:
        require(isinstance(reply.get("error"),dict) and set(reply["error"])=={"code"},"unknown failure fields")
        require(reply.get("error", {}).get("code") in {"wrong-desktop", "locked-or-unavailable", "epoch-changed", "stale-revision", "not-ready"}, "unknown failure")
        require("snapshot" not in reply, "failure exposed a snapshot")
        return reply
    require(reply.get("ok") is True and isinstance(reply.get("snapshot"), dict), "invalid success envelope")
    data = reply["snapshot"]
    def fields(value, allowed):
        require(isinstance(value,dict) and set(value)==set(allowed.split()),"unknown or missing object fields")
    def number(value):
        require(type(value) in (int,float) and math.isfinite(value),"invalid numeric field")
    def rectangle(value):
        fields(value,"x y width height")
        for item in value.values():number(item)
        require(value["width"]>=0 and value["height"]>=0,"negative geometry")
    def maybe_id(value,kind):
        if value is not None:typed(value,kind)
    # Fail closed if a future serializer adds data outside this privacy contract.
    require(set(data) == {"capabilities","coordinates","containerIdentity","outputs","focus","workspaces","windows","scratchpad","background","unplaced","popups"}, "unknown snapshot fields")
    forbidden = {"url", "title", "description", "content", "environment", "syncedFrame", "frameCounter"}
    def scan(value):
        if isinstance(value, dict):
            require(not forbidden.intersection(value), "private/content fields in snapshot")
            for item in value.values(): scan(item)
        elif isinstance(value, list):
            for item in value: scan(item)
    scan(data)
    windows = [typed(w.get("id"), "window") for w in data["windows"]]
    require(len(windows) == len(set(windows)), "duplicate window IDs")
    known = set(windows)
    owners = {}
    def walk(node,path=(),depth=0):
        require(depth<=64,"tree exceeds bounded depth")
        if node is None: return []
        require(isinstance(node, dict), "invalid tree")
        if node.get("kind") == "window":
            fields(node,"kind window focusedAt")
            number(node["focusedAt"])
            window = typed(node.get("window"), "window")
            require(window in known, "tree names unknown window")
            return [window]
        require(node.get("kind") == "container" and node.get("layout") in {"split-horizontal","split-vertical","stacking","tabbed"}, "invalid container")
        fields(node,"kind path layout focusedChild fractions children")
        require(node["path"]==list(path),"invalid container path")
        children = node.get("children")
        require(isinstance(children, list) and len(children) > 0, "empty container")
        require(type(node.get("focusedChild")) is int and 0 <= node["focusedChild"] < len(children), "invalid focused child")
        require(isinstance(node.get("fractions"), list) and len(node["fractions"]) == len(children), "invalid split fractions")
        for fraction in node["fractions"]:
            number(fraction)
            require(fraction>=0,"negative split fraction")
        require(abs(sum(node["fractions"])-1)<1e-6,"split fractions do not sum to one")
        return [window for index,child in enumerate(children) for window in walk(child,(*path,index),depth+1)]
    workspaces = set()
    for workspace in data["workspaces"]:
        fields(workspace,"id name homeOutput visibleOn tiling floats floatFocus fullscreen enclosedWindows")
        name = typed(workspace.get("id"), "workspace")
        require(name not in workspaces and workspace.get("name") == name, "duplicate/mismatched workspace")
        workspaces.add(name)
        maybe_id(workspace["homeOutput"],"output")
        for output in workspace["visibleOn"]:typed(output,"output")
        fields(workspace["tiling"],"depth root")
        number(workspace["tiling"]["depth"])
        maybe_id(workspace["floatFocus"],"window")
        if workspace["fullscreen"] is not None:
            fields(workspace["fullscreen"],"window up global bare byPage")
            typed(workspace["fullscreen"]["window"],"window")
        for index,floating in enumerate(workspace["floats"]):
            fields(floating,"index coordinates rect bare scratchpad depth root")
            require(floating["index"]==index and floating["coordinates"]=="output-local-logical","invalid float identity")
            rectangle(floating["rect"])
        enclosed = walk(workspace["tiling"]["root"]) + [window for floating in workspace["floats"] for window in walk(floating["root"])]
        require(enclosed == [typed(w, "window") for w in workspace["enclosedWindows"]], "tree/membership mismatch")
        for window in enclosed:
            require(window not in owners, "window enclosed twice")
            owners[window] = name
    outputs=set()
    visible_workspaces=set()
    for output in data["outputs"]:
        fields(output,"id logicalGeometry scale visibleWorkspace focused")
        output_id=typed(output["id"], "output")
        require(output_id not in outputs,"duplicate output ID")
        outputs.add(output_id)
        rectangle(output["logicalGeometry"])
        if output["scale"] is not None:number(output["scale"])
        require(typed(output["visibleWorkspace"], "workspace") in workspaces, "output names unknown workspace")
        visible=output["visibleWorkspace"]["value"]
        require(visible not in visible_workspaces,"workspace visible on duplicate outputs")
        visible_workspaces.add(visible)
    for workspace in data["workspaces"]:
        if workspace["homeOutput"] is not None:require(workspace["homeOutput"]["value"] in outputs,"home output absent")
        visible_on=[item["value"] for item in workspace["visibleOn"]]
        require(len(set(visible_on))==len(visible_on) and set(visible_on)<=outputs,"visible output absent or duplicated")
        require(set(visible_on)=={o["id"]["value"] for o in data["outputs"] if o["visibleWorkspace"]["value"]==workspace["name"]},"workspace/output visibility disagrees")
        for focus_key in ("floatFocus",):
            if workspace[focus_key] is not None:require(workspace[focus_key]["value"] in known,"workspace focus window absent")
        if workspace["fullscreen"] is not None:require(workspace["fullscreen"]["window"]["value"] in known,"fullscreen window absent")
    for field in (data["scratchpad"]["windows"], data["unplaced"]):
        for window in field:
            key = typed(window, "window")
            require(key in known and key not in owners, "hidden/unplaced window also enclosed")
            owners[key] = "hidden"
    # background names managed apps, including ones currently shown.
    for window in data["background"]:
        key=typed(window,"window")
        require(key in known,"unknown background window")
        owners.setdefault(key,"background")
    require(set(owners) == known, "unaccounted window")
    for window in data["windows"]:
        if window.get("kind")=="native":
            fields(window,"id kind nativeId desktopAppId placements")
            typed(window["nativeId"],"native-window");maybe_id(window["desktopAppId"],"desktop-app")
        else:
            require(window.get("kind")=="browser","unknown window kind")
            fields(window,"id kind browserId appId isApp isPrivate placements")
            typed(window["browserId"],"browser-window");maybe_id(window["appId"],"browser-app")
        for placement in window["placements"]:
            fields(placement,"output frame surface bar bare depth selected")
            typed(placement["output"],"output")
            require(placement["output"]["value"] in outputs,"placement output absent")
            rectangle(placement["frame"]);rectangle(placement["bar"])
            if placement["surface"] is not None:rectangle(placement["surface"])
            number(placement["depth"])
    fields(data["focus"],"output workspace shellWindow nativeWindow replayed")
    for key,kind in [("output","output"),("workspace","workspace"),("shellWindow","window"),("nativeWindow","native-window")]:maybe_id(data["focus"][key],kind)
    native_ids={w["nativeId"]["value"] for w in data["windows"] if w["kind"]=="native"}
    for key,known_ids in [("output",outputs),("workspace",workspaces),("shellWindow",known),("nativeWindow",native_ids)]:
        if data["focus"][key] is not None:require(data["focus"][key]["value"] in known_ids,"focus target absent")
    fields(data["scratchpad"],"semantics windows")
    for popup in data["popups"]:
        fields(popup,"id parent position size coordinates")
        typed(popup["id"],"native-popup");typed(popup["parent"],"native-window-or-popup")
        for key in ("position","size"):
            require(isinstance(popup[key],list) and len(popup[key])==2,"invalid popup geometry")
            for value in popup[key]:number(value)
    capabilities=data["capabilities"]
    fields(capabilities,"snapshot workspaceQuery pollSnapshots eventReplay focus layout closeViewer terminateDshSession windowTitles windowUrls windowContents")
    require(capabilities.get("snapshot") is True and all(capabilities.get(k) is False for k in ["focus","layout","closeViewer","terminateDshSession","windowTitles","windowUrls","windowContents","eventReplay"]), "unexpected privilege")
    return reply

def workspace_query(reply, name):
    require(reply.get("ok") is True, "snapshot unavailable")
    workspace = next((w for w in reply["snapshot"]["workspaces"] if w["name"] == name), None)
    require(workspace is not None, "unknown workspace")
    members = {w["value"] for w in workspace["enclosedWindows"]}
    return {key:reply[key] for key in ("protocol","version","desktopId","epoch","revision","capturedAt","source")} | {
        "ok":True,"workspace":workspace,"windows":[w for w in reply["snapshot"]["windows"] if w["id"]["value"] in members]}
