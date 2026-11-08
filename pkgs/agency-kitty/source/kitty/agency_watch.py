"""Install the scoped image-drop adapter when an Agency session is tagged.

Native Kitty watcher callbacks run only on creation/session metadata changes;
there is no per-key, per-output, or timer callback.
"""
from pathlib import Path
import json
import re
import sys


def _register_cell_query():
    """Use Kitty's existing DCS query dispatch for remote Nvim UI geometry."""
    from kittens.query_terminal import main as queries
    if getattr(queries.all_queries, '_agency_nonce_queries', False):
        return

    class AgencyCellSize(queries.Query):
        name = "agency_font_cell_size"

        @staticmethod
        def get_result(opts, window_id, os_window_id):
            from kitty.fast_data_types import cell_size_for_window
            width, height = cell_size_for_window(os_window_id)
            return f"{width},{height}"

    class AgencyQueries(dict):
        # XTGETTCAP echoes the requested name in its response. A bounded nonce
        # associates a response with one native Nvim UI even on 0.12, whose
        # TermResponse event does not yet expose the source RPC channel.
        _agency_nonce_queries = True

        def get(self, name, default=None):
            if isinstance(name, str) and re.fullmatch(r'agency_font_cell_size_[0-9a-f]{16}', name):
                return AgencyCellSize
            return super().get(name, default)

    queries.all_queries[AgencyCellSize.name] = AgencyCellSize
    queries.all_queries = AgencyQueries(queries.all_queries)


def program_status_projection(records):
    """Expose bounded native status, without copying message/prompt content.

    Kitty 0.50 already parses OSC 7501. This is a lifecycle event projection,
    not another terminal parser or an inference that an agent turn completed.
    """
    if not isinstance(records, list) or len(records) > 256:
        raise ValueError("invalid native program status records")
    projected = []
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("invalid native program status record")
        identity, state = record.get("id"), record.get("state")
        if (not isinstance(identity, str) or len(identity) > 263
                or not re.fullmatch(r"[A-Za-z0-9_.+/-]*", identity)
                or state not in {"idle", "working", "done", "blocked", "error"}):
            raise ValueError("invalid native program status identity/state")
        kind, progress, app = record.get("kind"), record.get("progress"), record.get("app", "")
        if (kind not in {None, "permission", "question", "auth"}
                or (progress is not None and (type(progress) is not int or not 0 <= progress <= 100))
                or not isinstance(app, str) or len(app) > 32
                or not re.fullmatch(r"[A-Za-z0-9_.+-]*", app)):
            raise ValueError("invalid native program status attributes")
        projected.append({"id": identity, "state": state, "kind": kind, "progress": progress, "app": app})
    return json.dumps({"version": 1, "records": projected[-64:], "omitted": max(0, len(projected) - 64)},
                      separators=(",", ":"))


def on_program_status_change(boss, window, data):
    if window.user_vars.get("agency_host") != "nas" or not window.user_vars.get("agency_session"):
        return
    value = program_status_projection(data.get("program_status"))
    window.set_user_var("agency_program_status", value)


def _install(boss, window):
    if not window.user_vars.get("agency_host") or not window.user_vars.get("agency_session"):
        return
    _register_cell_query()
    # Watcher modules have __file__; custom kittens loaded with exec() do not.
    directory = str(Path(__file__).resolve().parent)
    if directory not in sys.path:
        sys.path.insert(0, directory)
    import agency
    agency.arm_drops(boss, window, quiet=True)
    agency.arm_copy_feedback(boss, window)


def on_set_user_var(boss, window, data):
    if data.get('key') == 'agency_editor_request' and data.get('value'):
        directory = str(Path(__file__).resolve().parent)
        if directory not in sys.path:
            sys.path.insert(0, directory)
        import agency_editor
        agency_editor.open_request(boss, window, data['value'])
    if data.get("key") == "agency_harness_event" and data.get("value"):
        directory = str(Path(__file__).resolve().parent)
        if directory not in sys.path:
            sys.path.insert(0, directory)
        import agency
        agency.apply_harness_event(boss, window, data["value"])
    if data.get("key") in {"agency_harness_bind", "agency_harness_unbind"} and data.get("value"):
        directory = str(Path(__file__).resolve().parent)
        if directory not in sys.path:
            sys.path.insert(0, directory)
        import agency
        agency.apply_harness_binding(boss, window, data["value"], unbind=data["key"] == "agency_harness_unbind")
        _install(boss, window)  # rebind target snapshots to the new occupant
    if data.get("key") in {"agency_host", "agency_session"}:
        _install(boss, window)


def on_resize(boss, window, data):
    if not getattr(window, "agency_drop_adapter", False):
        _install(boss, window)


def on_close(boss, window, data):
    directory = str(Path(__file__).resolve().parent)
    if directory not in sys.path:
        sys.path.insert(0, directory)
    import agency
    agency.disarm_copy_feedback(boss, window)


# An independently launched local Nvim UI may not have session tags yet. This
# read-only native query must already exist when that UI requests geometry.
if "kitty.fast_data_types" in sys.modules:
    _register_cell_query()
