"""Run the real Godot HTTP adapters against deterministic local protocol fixtures."""
import argparse
import base64
import http.server
import io
import zipfile
import json
from pathlib import Path
import os
import shutil
import struct
import subprocess
import tempfile
import threading
import time
import urllib.parse
import zlib


def png(cutout=False):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    row = b"\x00" + b"\xff\x30\x20\xff" + (b"\x00\x00\x00\x00" if cutout else b"\xff\x30\x20\xff")
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(row * 2)) + chunk(b"IEND", b"")


def glb():
    binary = struct.pack("<9f3H", -1, 0, 0, 1, 0, 0, 0, 2, 0, 0, 1, 2) + b"\x00\x00"
    document = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(binary)}], "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 6}], "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, 0, 0], "max": [1, 2, 0]}, {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}], "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}], "nodes": [{"mesh": 0}], "scenes": [{"nodes": [0]}], "scene": 0}
    encoded = json.dumps(document).encode()
    encoded += b" " * (-len(encoded) % 4)
    return b"glTF" + struct.pack("<II", 2, 12 + 8 + len(encoded) + 8 + len(binary)) + struct.pack("<II", len(encoded), 0x4e4f534a) + encoded + struct.pack("<II", len(binary), 0x004e4942) + binary


class Fixtures(http.server.BaseHTTPRequestHandler):
    generation_submissions = {}
    conversion_posts = {}
    conversion_polls = {}
    background_jobs = set()
    recovered_jobs = set()
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def handle(self):
        try:
            super().handle()
        except (ConnectionResetError, BrokenPipeError):
            pass

    def reply(self, value, status=200, content_type="application/json", headers=None):
        body = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        location = urllib.parse.urlparse(self.path)
        if location.path in ["/drip", "/idle-drip"]:
            chunks = [("data: " + json.dumps({"tick": index}) + "\n\n").encode() for index in range(4)]
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(sum(map(len, chunks))))
            self.end_headers()
            try:
                for chunk in chunks:
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    time.sleep(0.7 if location.path == "/idle-drip" else 0.12)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if location.path == "/deepseek/models":
            valid = self.headers.get("Authorization") == "Bearer deepseek-fixture-token"
            self.reply({"data": [{"id": "deepseek-flash", "name": "DeepSeek-V4.1-Flash", "context_window": 1048576, "input_modalities": ["text", "image"], "effort": {"supported_levels": ["low", "high", "max"]}}, {"id": "deepseek-v4-pro", "name": "DeepSeek-V4-Pro", "context_window": 1048576, "input_modalities": ["text"], "effort": {"supported_levels": ["low", "high", "max"]}}]} if valid else {"error": "Unauthorized"}, 200 if valid else 401)
            return
        if location.path == "/omniroute/v1/models":
            valid = self.headers.get("Authorization") == "Bearer omniroute-fixture-key"
            self.reply({"data": [
                {"id": "fixture-route-chat", "name": "Fixture OmniRoute", "context_window": 262144, "input_modalities": ["text", "image"], "supported_parameters": ["tools"]},
                {"id": "fixture-route-embedding", "type": "embedding"},
            ]} if valid else {"error": "Unauthorized"}, 200 if valid else 401)
            return
        if location.path == "/opencode/zen/v1/models":
            valid = self.headers.get("Authorization") == "Bearer opencode-fixture-token"
            models = [
                {"id": "fixture-open-chat", "name": "Fixture OpenChat", "type": "chat", "modalities": {"input": ["text", "image/png"]}, "capabilities": {"tools": {"supported": True}, "reasoning": {"supported": True, "effort": ["low", "high"]}}, "limit": {"context": 200000, "output": 32000}, "cost": {"text": {"input": {"price": 1.5, "cache": {"read": 0.15}}, "output": {"price": 9}}}, "api": {"chat-completions": {"base_url": "https://opencode.ai/inference/openai/v1", "compatibility": {"reasoning_field": "reasoning_content"}}}},
                {"id": "fixture-open-responses", "name": "Fixture OpenResponses", "type": "chat", "modalities": {"input": ["text"]}, "capabilities": {"tools": {"supported": True}, "reasoning": {"supported": True, "effort": ["medium", "high"]}}, "limit": {"context": 400000, "output": 64000}, "cost": {"text": {"input": {"price": 2, "cache": {"read": 0.2}}, "output": {"price": 10}}}, "api": {"responses": {"base_url": "https://opencode.ai/inference/openai/v1"}}},
                {"id": "fixture-open-messages", "name": "Fixture OpenMessages", "type": "chat", "modalities": {"input": ["text", "image/jpeg"]}, "capabilities": {"tools": {"supported": True}, "reasoning": {"supported": True, "effort": ["low", "medium", "high"]}}, "limit": {"context": 1000000, "output": 128000}, "cost": {"text": {"input": {"price": 3, "cache": {"read": 0.3}}, "output": {"price": 15}}}, "api": {"messages": {"base_url": "https://opencode.ai/inference/anthropic/v1"}}},
                {"id": "fixture-open-gemini", "name": "Fixture OpenGemini", "type": "chat", "modalities": {"input": ["text", "image/webp"]}, "capabilities": {"tools": {"supported": True}, "reasoning": {"supported": True, "effort": ["minimal", "high"]}}, "limit": {"context": 1048576, "output": 65536}, "cost": {"text": {"input": {"price": 1}, "output": {"price": 4}}}, "api": {"generate-content": {"base_url": "https://opencode.ai/inference/google/v1beta"}}},
                {"id": "fixture-open-embedding", "name": "Fixture Embedding", "type": "embedding", "api": {"chat-completions": {"base_url": "https://opencode.ai/inference/openai/v1"}}},
                {"id": "fixture-open-unknown", "name": "Fixture Unknown Protocol", "type": "chat", "api": {"future-protocol": {"base_url": "https://opencode.ai/inference/future/v1"}}},
            ]
            self.reply({"object": "list", "data": models} if valid else {"error": "Unauthorized"}, 200 if valid else 401)
            return
        if location.path == "/local-lm/v1/models":
            self.reply({"data": [{"id": "local-code"}, {"id": "local-embedding"}]})
            return
        if location.path == "/local-lm/api/v0/models":
            self.reply({"data": [{"id": "local-code", "type": "llm", "state": "loaded", "loaded_context_length": 4096, "max_context_length": 262144}, {"id": "local-embedding", "type": "embeddings", "state": "not-loaded", "loaded_context_length": None}]})
            return
        if location.path == "/local-ollama/api/tags":
            self.reply({"models": [{"name": "local-code:latest"}, {"name": "unloaded-code:latest"}]})
            return
        if location.path == "/local-ollama/api/ps":
            self.reply({"models": [{"name": "local-code:latest", "context_length": 4096}]})
            return
        if location.path == "/auth-lm/v1/models":
            valid = self.headers.get("Authorization") == "Bearer local-fixture-token"
            self.reply({"data": [{"id": "authorized-code"}]} if valid else {"error": "Authentication required"}, 200 if valid else 401)
            return
        if location.path == "/fixture-submissions":
            self.reply(self.generation_submissions)
            return
        if location.path == "/user":
            valid = self.headers.get("Authorization") == "Bearer github-fixture-token"
            self.reply({"login": "fixture", "id": 42, "name": "Fixture user"} if valid else {"error": "unauthorized"}, 200 if valid else 401)
            return
        if location.path == "/user/repos":
            valid = self.headers.get("Authorization") == "Bearer github-fixture-token"
            self.reply([{"full_name": "fixture/project", "private": False}, {"full_name": "fixture/private", "private": True}] if valid else {"error": "unauthorized"}, 200 if valid else 401)
            return
        if location.path == "/store/search/query/":
            valid = urllib.parse.parse_qs(location.query).get("query") == ["fixture"]
            self.reply({"count": 1, "hits": [{"asset": {"slug": "fixture-addon", "name": "Fixture addon", "publisher": {"name": "Fixture publisher", "slug": "fixture"}, "license_type": "MIT"}}]} if valid else {"error": "query missing"}, 200 if valid else 400)
            return
        if location.path == "/store/assets/fixture/fixture-addon/":
            self.reply({"slug": "fixture-addon", "name": "Fixture addon", "publisher": {"name": "Fixture publisher", "slug": "fixture"}, "license_type": "MIT"})
            return
        if location.path == "/store/releases/fixture/fixture-addon/":
            self.reply([{"version": "1.0", "stable": True, "min_godot_version": "4.0", "max_godot_version": "4.99", "download_url": f"http://127.0.0.1:{self.server.server_port}/store/redirect"}, {"version": "2.0", "stable": True, "min_godot_version": "9.0"}])
            return
        if location.path in ["/store/redirect", "/store/loop"]:
            self.reply(b"", 302, headers={"Location": "/artifact/image.png" if location.path.endswith("redirect") else "/store/loop"})
            return
        if location.path.startswith("/catalog/"):
            if self.headers.get("Authorization"):
                self.reply({"error": "credentials sent to public catalog"}, 403)
                return
            if location.path.endswith("index.json"):
                root = f"http://127.0.0.1:{self.server.server_port}/catalog/"
                self.reply([
                    {"air": "fixture:image@1", "name": "Fixture Image", "status": "live", "capabilities": ["text-to-image"], "schema": root + "image.json"},
                    {"air": "fixture:mesh@1", "name": "Fixture Mesh", "status": "live", "capabilities": ["image-to-3d"], "schema": root + "mesh.json"},
                    {"air": "fixture:retired@1", "status": "retired", "capabilities": ["text-to-image"]}])
            else:
                self.reply({"info": {"x-pricing": {"currency": "USD", "rates": [{"amount": 0.04, "unit": "output", "label": "1K"}, {"amount": 0.08, "unit": "output", "label": "2K"}]}}})
            return
        if location.path.startswith(("/meshy/", "/tripo/", "/openai_image/")):
            if self.headers.get("Authorization") != "Bearer generation-fixture-key":
                self.reply({"error": "missing fixture authorization"}, 401)
                return
            if "/convert/" in location.path or "/tasks/convert-" in location.path:
                task = location.path.rsplit("/", 1)[-1]
                fmt = task.removeprefix("convert-")
                url = f"http://127.0.0.1:{self.server.server_port}/artifact/model.{fmt}"
                self.conversion_polls[task] = self.conversion_polls.get(task, 0) + 1
                if fmt == "3mf" and self.conversion_polls[task] == 1:
                    self.reply({"status": "IN_PROGRESS", "progress": 50})
                    return
                if location.path.startswith("/meshy/"):
                    self.reply({"status": "SUCCEEDED", "model_urls": {fmt: url}, "consumed_credits": 1})
                else:
                    self.reply({"code": 0, "data": {"status": "success", "output": {"model_url": url}, "credits_consumed": 1}})
                return
            if location.path.endswith("/balance"):
                self.reply({"code": 0, "data": {"balance": 100}} if location.path.startswith("/tripo/") else {"balance": 100})
            elif location.path.endswith("/models"):
                self.reply({"data": [{"id": "gpt-image-2.5-flare"}, {"id": "fixture-code"}]})
            else:
                task = location.path.rsplit("/", 1)[-1]
                output_url = f"http://127.0.0.1:{self.server.server_port}/artifact/" + ("image.png" if task == "image-task" else "model.glb")
                if task == "foreign-task": output_url = "https://attacker.example/model.glb"
                status = "failed" if task == "failed-task" else "success"
                data = {"status": status, "progress": 100, "output": {"model_url": output_url, "generated_image_url": output_url}, "credits_consumed": 4}
                self.reply({"code": 0, "data": data} if location.path.startswith("/tripo/") else {"status": "FAILED" if status == "failed" else "SUCCEEDED", "progress": 100, "model_urls": {"glb": output_url}, "image_urls": [output_url]})
            return
        if location.path.startswith("/artifact/"):
            if self.headers.get("Authorization"):
                self.reply({"error": "credentials sent to CDN"}, 403)
            else:
                if location.path.endswith(".fbx"):
                    self.reply(b"; FBX 7.4.0 project file\nObjects: {}\n", content_type="application/octet-stream")
                    return
                fmt = location.path.rsplit(".", 1)[-1]
                if fmt in ["usdz", "3mf", "blend"]:
                    if fmt == "blend":
                        self.reply(b"BLENDER-v400" + b"\x00" * 32, content_type="application/octet-stream")
                    else:
                        data = io.BytesIO()
                        with zipfile.ZipFile(data, "w") as archive:
                            archive.writestr("model.usda" if fmt == "usdz" else "3D/3dmodel.model", "#usda 1.0" if fmt == "usdz" else "<model/>")
                        self.reply(data.getvalue(), content_type="application/octet-stream")
                    return
                mesh = location.path.endswith(".glb")
                self.reply(glb() if mesh else png(cutout=location.path.endswith("cutout.png")), content_type="model/gltf-binary" if mesh else "image/png")
        elif location.path == "/repos/fixture/project":
            self.reply({"full_name": "fixture/project", "default_branch": "main", "private": False})
        elif location.path == "/repos/fixture/project/contents/script.gd":
            self.reply({"type": "file", "path": "script.gd", "size": 13, "sha": "fixture-sha", "encoding": "base64", "content": base64.b64encode(b"extends Node\n").decode()})
        elif location.path in ["/repos/fixture/project/issues", "/repos/fixture/project/pulls", "/repos/fixture/project/branches"]:
            self.reply([{"name": "main", "number": 3, "title": "Fixture issue", "state": "open", "body": "not copied into list"}])
        elif location.path.endswith("/models"):
            self.reply({"data": [{"id": "fixture-code", "name": "Fixture coding model", "context_window": 8192, "effort": {"supported_levels": ["high", "max"]}}]})
        elif location.path == "/object_info":
            self.reply({"FixturePrompt": {}, "SaveImage": {}, "SaveGLB": {}})
        elif location.path.startswith("/history/"):
            self.reply({"fixture-job": {"status": {"status_str": "success"}, "outputs": {"1": {"images": [{"filename": "image.png", "type": "output"}], "3d": [{"filename": "mesh.glb", "type": "output"}]}}}})
        elif location.path == "/view":
            mesh = urllib.parse.parse_qs(location.query).get("filename") == ["mesh.glb"]
            self.reply(glb() if mesh else png(), content_type="model/gltf-binary" if mesh else "image/png")
        elif location.path == "/truncated.glb":
            self.reply(glb()[:-4], content_type="model/gltf-binary")
        else:
            self.reply({"error": "not found"}, 404)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/tripo/files":
            valid = self.headers.get("Authorization") == "Bearer generation-fixture-key" and b'name="file"' in raw and png() in raw
            self.reply({"code": 0, "data": {"file_token": "file_fixture"}} if valid else {"code": 1004, "message": "invalid multipart upload"})
            return
        payload = ({key: values[0] for key, values in urllib.parse.parse_qs(raw.decode()).items()} if self.headers.get("Content-Type", "").startswith("application/x-www-form-urlencoded") else json.loads(raw or b"{}"))
        location = urllib.parse.urlparse(self.path)
        if location.path == "/runware":
            authorized = self.headers.get("Authorization") == "Bearer generation-fixture-key"
            task = payload[0] if isinstance(payload, list) and len(payload) == 1 else {}
            if authorized and task.get("taskType") == "getResponse" and task.get("taskUUID") in self.recovered_jobs:
                self.reply({"data": [{"taskUUID": task["taskUUID"], "taskType": "imageInference", "status": "success", "imageURL": f"http://127.0.0.1:{self.server.server_port}/artifact/image.png", "cost": 0.02}]}, 500)
                return
            if authorized and task.get("taskType") == "removeBackground":
                self.generation_submissions["remove_background"] = self.generation_submissions.get("remove_background", 0) + 1
                valid = task.get("model") == "runware:109@1" and task.get("outputFormat") == "PNG" and task.get("inputs", {}).get("image", "").startswith("data:image/png;base64,") and task.get("settings", {}).get("rgba") == [255, 255, 255, 0]
                if valid:
                    self.background_jobs.add(task["taskUUID"])
                self.reply({"data": [{"taskUUID": task.get("taskUUID"), "status": "processing"}]} if valid else {"errors": [{"message": "wrong background removal schema"}]})
                return
            if authorized and task.get("taskType") == "getResponse" and task.get("taskUUID") in self.background_jobs:
                self.reply({"data": [{"taskUUID": task["taskUUID"], "status": "success", "imageURL": f"http://127.0.0.1:{self.server.server_port}/artifact/cutout.png"}]})
                return
            if isinstance(payload, list) and payload and payload[0].get("taskType") in ["imageInference", "3dInference"]:
                prompt = payload[0].get("positivePrompt", "")
                self.generation_submissions[prompt] = self.generation_submissions.get(prompt, 0) + 1
                if authorized and prompt == "http500-result":
                    self.recovered_jobs.add(task["taskUUID"])
                    self.reply({"data": [{"taskUUID": task["taskUUID"], "taskType": "imageInference"}]}, 500)
                    return
                if prompt == "lost-runware-submit":
                    self.close_connection = True
                    return
            valid = self.headers.get("Authorization") == "Bearer generation-fixture-key" and isinstance(payload, list) and payload == [{"taskType": "ping", "ping": True}]
            self.reply({"data": [{"taskType": "ping", "pong": True}]} if valid else {"errors": [{"code": "invalidApiKey", "message": "Invalid API key"}]}, 200 if valid else 401)
            return
        if location.path in ["/meshy/openapi/v1/convert", "/tripo/models/convert"]:
            valid = self.headers.get("Authorization") == "Bearer generation-fixture-key"
            fmt = payload.get("target_formats", [""])[0] if location.path.startswith("/meshy/") else str(payload.get("format", "")).lower()
            valid = valid and fmt in ["fbx", "usdz", "3mf", "blend"] and bool(payload.get("input_task_id") or payload.get("input"))
            counter = location.path + ":" + fmt
            self.conversion_posts[counter] = self.conversion_posts.get(counter, 0) + 1
            valid = valid and self.conversion_posts[counter] <= 1
            self.reply(({"result": "convert-" + fmt} if location.path.startswith("/meshy/") else {"code": 0, "data": {"task_id": "convert-" + fmt}}) if valid else {"error": "invalid or duplicate paid conversion"}, 200 if valid else 400)
            return
        if location.path.startswith(("/meshy/", "/tripo/", "/openai_image/")):
            if self.headers.get("Authorization") != "Bearer generation-fixture-key":
                self.reply({"error": "missing fixture authorization"}, 401)
                return
            prompt = payload.get("prompt", "")
            self.generation_submissions[prompt] = self.generation_submissions.get(prompt, 0) + 1
            if prompt == "lost-submit":
                self.close_connection = True
                return
            task = "failed-task" if payload.get("prompt") == "fail" else ("foreign-task" if payload.get("prompt") == "foreign" else "mesh-task")
            if location.path.startswith("/openai_image/"):
                valid = payload.get("output_format") == "png" and "response_format" not in payload and payload.get("n") == 1
                image = b"invalid" if payload.get("prompt") == "invalid" else png()
                self.reply({"data": [{"b64_json": base64.b64encode(image).decode()}]} if valid else {"error": "wrong image schema"}, 200 if valid else 400)
            elif location.path == "/meshy/openapi/v1/text-to-image":
                valid = payload.get("ai_model") == "nano-banana-2" and payload.get("aspect_ratio") == "1:1" and bool(payload.get("prompt"))
                self.reply({"result": "image-task"} if valid else {"error": "wrong image schema"}, 200 if valid else 400)
            elif location.path.startswith("/meshy/"):
                valid = payload.get("target_formats") == ["glb"] and (payload.get("mode") == "preview" if "text-to-3d" in location.path else payload.get("image_url", "").startswith("data:image/png;base64,"))
                self.reply({"result": task} if valid else {"error": "wrong mesh schema"}, 200 if valid else 400)
            else:
                if location.path.endswith("text-to-image"): task = "image-task"
                valid = payload.get("input") == "file_fixture" if location.path.endswith("image-to-model") else bool(payload.get("prompt"))
                self.reply({"code": 0, "data": {"task_id": task}} if valid else {"code": 1004, "message": "wrong tripo schema"})
        elif location.path == "/repos/fixture/project/issues":
            self.reply({"number": 4, "title": payload["title"], "state": "open", "html_url": "https://github.com/fixture/project/issues/4"}, 201)
        elif location.path == "/mcp":
            method = payload.get("method")
            if method == "notifications/initialized":
                self.reply(b"", 202)
                return
            if method == "initialize":
                result = {"protocolVersion": "2025-11-25", "capabilities": {"tools": {}}, "serverInfo": {"name": "fixture", "version": "1"}}
            elif method == "tools/list":
                name = "second" if payload.get("params", {}).get("cursor") else "first"
                result = {"tools": [{"name": name, "description": "Fixture", "inputSchema": {"type": "object", "properties": {}}, "annotations": {"readOnlyHint": True}}]}
                if name == "first": result["nextCursor"] = "next-page"
            else:
                failed = payload.get("params", {}).get("arguments", {}).get("fail", False)
                result = {"content": [{"type": "text", "text": "fixture tool execution failed" if failed else "real fixture tool result"}], "isError": failed}
            self.reply({"jsonrpc": "2.0", "id": payload["id"], "result": result}, headers={"Mcp-Session-Id": "fixture-session"})
        elif location.path == "/prompt":
            self.reply({"prompt_id": "fixture-job", "number": 0})
        elif location.path.endswith("/chat/completions"):
            if location.path.startswith("/omniroute/"):
                if self.headers.get("Authorization") != "Bearer omniroute-fixture-key":
                    self.reply({"error": "Unauthorized"}, 401)
                    return
                self.sse([{"choices": [{"delta": {"content": "OmniRoute chat"}, "finish_reason": "stop"}]}])
                return
            if location.path.startswith("/bounded/"):
                if payload.get("max_tokens") != 512:
                    self.reply({"error": "Missing bounded summary output allowance"}, 400)
                    return
                self.sse([{"choices": [{"delta": {"content": "Bounded summary verified"}, "finish_reason": "stop"}]}])
                return
            has_result = any(message.get("role") == "tool" for message in payload.get("messages", []))
            if location.path.startswith("/thinking/"):
                if not payload.get("tools") or payload.get("reasoning_effort") != "high":
                    self.reply({"error": "Fixture requires the thinking/tool continuation path"}, 400)
                    return
                assistants = [m for m in payload.get("messages", []) if m.get("role") == "assistant"]
                if any("reasoning_content" not in m for m in assistants):
                    self.reply({"error": {"message": "The reasoning_content in thinking mode must be passed back to the API."}}, 400)
                    return
                valid = len(assistants) == 1 and assistants[0].get("reasoning_content") == "fixture reasoning"
                valid = valid and any(m.get("role") == "system" and "Stopped; changes preserved" in m.get("content", "") for m in payload.get("messages", []))
                if not valid:
                    self.reply({"error": "Resume context lost confirmed reasoning or application state"}, 400)
                    return
                self.sse([{"choices": [{"delta": {"reasoning_content": "fixture continuation", "content": "Resume verified"}, "finish_reason": "stop"}]}])
                return
            if location.path.startswith("/replay/"):
                assistants = [m for m in payload.get("messages", []) if m.get("role") == "assistant"]
                if not payload.get("tools") or any("reasoning_content" not in m for m in assistants):
                    self.reply({"error": {"message": "The reasoning_content in the thinking mode must be passed back to the API."}}, 400)
                    return
                self.sse([{"choices": [{"delta": {"content": "Replay verified"}, "finish_reason": "stop"}]}])
                return
            if location.path.startswith("/json/"):
                message = {"role": "assistant", "content": "JSON verified"} if has_result else {"role": "assistant", "content": None, "tool_calls": [{"id": "json-call-a", "function": {"name": "godot_project", "arguments": "{}"}}, {"id": "json-call-b", "function": {"name": "godot_files", "arguments": "{}"}}]}
                self.reply({"choices": [{"message": message, "finish_reason": "stop" if has_result else "tool_calls"}]})
                return
            if has_result:
                events = [{"choices": [{"delta": {"content": "Verificat: română 🐦"}, "finish_reason": None}]}, {"choices": [{"delta": {}, "finish_reason": "stop"}]}]
            else:
                events = [{"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "fixture-call", "function": {"name": "godot_project", "arguments": "{"}}]}, "finish_reason": None}]}, {"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "}"}}]}, "finish_reason": "tool_calls"}]}]
            if location.path.startswith("/incomplete/"): events = events[:1]
            if location.path.startswith("/slow/"): time.sleep(0.3)
            self.sse(events)
        elif location.path == "/v1/responses":
            self.sse([{"type": "response.output_text.delta", "delta": "Responses verified"}, {"type": "response.completed", "response": {"output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Responses verified"}]}]}}])
        elif location.path == "/v1/messages":
            self.sse([{"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}, {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Anthropic verified"}}, {"type": "content_block_stop", "index": 0}, {"type": "message_stop"}])
        elif ":streamGenerateContent" in location.path:
            self.sse([{"candidates": [{"content": {"parts": [{"text": "Gemini verified"}]}, "finishReason": "STOP"}]}])
        else:
            self.reply({"error": "not found"}, 404)

    def sse(self, events):
        data = "".join("data: " + json.dumps(event, ensure_ascii=False) + "\n\n" for event in events) + "data: [DONE]\n\n"
        self.reply(data.encode(), content_type="text/event-stream")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--proot", action="store_true")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixtures)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="godot-ai-qa-") as scratch:
            fixture = Path(scratch) / "project"
            shutil.copytree(source / "tests/fixture", fixture,
                            ignore=shutil.ignore_patterns(".godot", "ai_test_*"))
            command = [args.godot, "--headless", "--path", str(fixture), "--script", str(source / "tests/test_runtime.gd"), "--", "--source=" + str(source), f"--mock-url=http://127.0.0.1:{server.server_port}"]
            env = dict(os.environ, XDG_CONFIG_HOME=scratch, XDG_DATA_HOME=scratch, XDG_CACHE_HOME=scratch)
            if args.proot:
                prefix = ["proot-distro", "login", "--shared-home", "debian", "--", "env",
                          "XDG_CONFIG_HOME=" + scratch, "XDG_DATA_HOME=" + scratch, "XDG_CACHE_HOME=" + scratch]
                if os.environ.get("GODOT_AI_TERRAIN3D_ZIP"):
                    prefix += ["GODOT_AI_TERRAIN3D_ZIP=" + os.environ["GODOT_AI_TERRAIN3D_ZIP"]]
                command = prefix + command
            result = subprocess.run(command, env=env, check=False, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            print(result.stdout, end="")
            # GDScript can abort one coroutine while SceneTree still exits 0.
            # Such a run must not be reported as a passed test suite.
            return result.returncode or (1 if "SCRIPT ERROR:" in result.stdout else 0)
    finally:
        server.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
