"""Stack config API routes."""

import copy

from flask import jsonify, request

from stack.apply import apply_config
from stack.schema import get_schema_response
from stack.store import get_config_metadata, read_apply_status, read_config, write_config


def register_stack_routes(app, require_auth, require_operator, fetch_icecast_stats, parse_stats):
    @app.route("/api/stack/schema")
    @require_auth
    def api_stack_schema():
        return jsonify(get_schema_response())

    @app.route("/api/stack/config")
    @require_auth
    def api_stack_config_get():
        config, metadata = get_config_metadata()
        return jsonify({"config": config, "metadata": metadata})

    @app.route("/api/stack/config", methods=["PUT"])
    @require_operator
    def api_stack_config_put():
        payload = request.get_json() or {}
        config = payload.get("config", payload)
        try:
            saved = write_config(config)
            return jsonify({"ok": True, "config": saved})
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/stack/ingests/<ingest_id>", methods=["PATCH"])
    @require_operator
    def api_stack_ingest_patch(ingest_id):
        data = request.get_json() or {}
        config = read_config()
        ingests = config.get("ingests", [])
        target = next((item for item in ingests if item.get("id") == ingest_id), None)

        if data.get("enabled") is False:
            enabled_count = sum(1 for item in ingests if item.get("enabled"))
            if target and target.get("enabled") and enabled_count <= 1:
                return jsonify({"error": "Cannot disable the last enabled ingest"}), 400

        if target is None:
            if data.get("create"):
                ingests.append({
                    "id": ingest_id,
                    "type": "harbor",
                    "port": data["port"],
                    "priority": data.get("priority", len(ingests) + 1),
                    "enabled": data.get("enabled", True),
                })
            else:
                return jsonify({"error": f"Ingest not found: {ingest_id}"}), 404
        else:
            for key, value in data.items():
                if key != "create":
                    target[key] = value

        updated = copy.deepcopy(config)
        updated["ingests"] = ingests
        try:
            saved = write_config(updated)
            return jsonify({"ok": True, "config": saved})
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/stack/ingests/<ingest_id>", methods=["DELETE"])
    @require_operator
    def api_stack_ingest_delete(ingest_id):
        config = read_config()
        ingests = config.get("ingests", [])
        enabled = [item for item in ingests if item.get("enabled")]
        target = next((item for item in ingests if item.get("id") == ingest_id), None)
        if target is None:
            return jsonify({"error": f"Ingest not found: {ingest_id}"}), 404
        if target.get("enabled") and len(enabled) <= 1:
            return jsonify({"error": "Cannot remove the last enabled ingest"}), 400

        updated = copy.deepcopy(config)
        updated["ingests"] = [item for item in ingests if item.get("id") != ingest_id]
        try:
            saved = write_config(updated)
            return jsonify({"ok": True, "config": saved})
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/stack/outputs/<output_id>", methods=["PATCH"])
    @require_operator
    def api_stack_output_patch(output_id):
        data = request.get_json() or {}
        config = read_config()
        outputs = config.get("outputs", [])
        target = next((item for item in outputs if item.get("id") == output_id), None)
        if target is None:
            return jsonify({"error": f"Output not found: {output_id}"}), 404

        for key, value in data.items():
            target[key] = value

        updated = copy.deepcopy(config)
        updated["outputs"] = outputs
        try:
            saved = write_config(updated)
            return jsonify({"ok": True, "config": saved})
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/stack/outputs", methods=["POST"])
    @require_operator
    def api_stack_output_create():
        data = request.get_json() or {}
        required = ("id", "mount", "codec", "bitrate")
        missing = [field for field in required if field not in data]
        if missing:
            return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400

        config = read_config()
        outputs = config.get("outputs", [])
        if any(item.get("id") == data["id"] for item in outputs):
            return jsonify({"error": f"Output already exists: {data['id']}"}), 400

        outputs.append({
            "id": data["id"],
            "type": "icecast",
            "mount": data["mount"],
            "codec": data["codec"],
            "bitrate": data["bitrate"],
            "samplerate": data.get("samplerate", 44100),
            "channels": data.get("channels", 2),
            "enabled": data.get("enabled", True),
        })

        updated = copy.deepcopy(config)
        updated["outputs"] = outputs
        try:
            saved = write_config(updated)
            return jsonify({"ok": True, "config": saved})
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/stack/outputs/<output_id>", methods=["DELETE"])
    @require_operator
    def api_stack_output_delete(output_id):
        config = read_config()
        outputs = config.get("outputs", [])
        hls_enabled = config.get("hls", {}).get("enabled") and config.get("hls", {}).get("variants")
        enabled_outputs = [item for item in outputs if item.get("enabled")]
        target = next((item for item in outputs if item.get("id") == output_id), None)
        if target is None:
            return jsonify({"error": f"Output not found: {output_id}"}), 404
        if target.get("enabled") and len(enabled_outputs) <= 1 and not hls_enabled:
            return jsonify({"error": "Cannot remove the last enabled output"}), 400

        updated = copy.deepcopy(config)
        updated["outputs"] = [item for item in outputs if item.get("id") != output_id]
        try:
            saved = write_config(updated)
            return jsonify({"ok": True, "config": saved})
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/stack/apply", methods=["POST"])
    @require_operator
    def api_stack_apply():
        payload = request.get_json() or {}
        config = payload.get("config")
        try:
            if config is not None:
                write_config(config)
            status = apply_config()
            return jsonify({"ok": True, "status": status})
        except ValueError as exc:
            return jsonify({"ok": False, "error": str(exc), "status": read_apply_status()}), 400
        except Exception as exc:
            app.logger.warning("Stack apply failed: %s", exc)
            return jsonify({
                "ok": False,
                "error": str(exc),
                "status": read_apply_status(),
            }), 502

    @app.route("/api/stack/apply/status")
    @require_auth
    def api_stack_apply_status():
        return jsonify(read_apply_status())

    @app.route("/api/stack/health")
    @require_auth
    def api_stack_health():
        config = read_config()
        desired_mounts = {
            output["mount"]
            for output in config.get("outputs", [])
            if output.get("enabled")
        }

        stats = fetch_icecast_stats()
        parsed = parse_stats(stats)
        effective_mounts = {mount["mount"] for mount in parsed.get("mounts", [])}

        missing = sorted(desired_mounts - effective_mounts)
        extra = sorted(effective_mounts - desired_mounts)

        healthy = not missing and parsed.get("status") == "ok"
        return jsonify({
            "healthy": healthy,
            "desired_mounts": sorted(desired_mounts),
            "effective_mounts": sorted(effective_mounts),
            "missing_mounts": missing,
            "extra_mounts": extra,
            "apply_status": read_apply_status(),
            "icecast_status": parsed.get("status"),
        })
