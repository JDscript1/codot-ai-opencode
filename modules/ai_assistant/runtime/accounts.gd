@tool
extends RefCounted

static var Common: GDScript
static var Transport: GDScript
const ISSUER = "https://auth.openai.com"
const TOKEN_ENDPOINT = ISSUER + "/api/accounts/oauth/token"
const RESOURCE = "https://api.openai.com/v1"
const CALLBACK_PORT = 1455
var transport: RefCounted
var vault: RefCounted
var owner: Node
var pending = false

func _init(node: Node = null, secret_store: RefCounted = null) -> void:
	owner = node
	transport = Transport.new(node)
	vault = secret_store

static func authorization_parameters(profile: Dictionary, saved_tokens: Variant, callback_uri: String, state: String, nonce: String, verifier: String) -> Dictionary:
	var client_id = str(profile.get("client_id", ""))
	if client_id.is_empty() or client_id == "dynamic_agent_client":
		if saved_tokens is Dictionary and not str(saved_tokens.get("client_id", "")).is_empty(): client_id = str(saved_tokens["client_id"])
	if client_id.is_empty(): client_id = "dynamic_agent_client"
	var parameters = {"client_id": client_id, "ext_agent_host_id": profile.get("host_id", "urn:uuid:" + Common.uid()), "response_type": "code", "redirect_uri": callback_uri, "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct", "resource": RESOURCE, "state": state, "nonce": nonce, "code_challenge": _base64url(verifier.sha256_buffer()), "code_challenge_method": "S256"}
	if client_id == "dynamic_agent_client": parameters["agent_name_hint"] = "Godot AI"
	var label = str(profile.get("name", ""))
	var email = label.get_slice(" · ", 1) if " · " in label else ""
	if email.is_empty() and saved_tokens is Dictionary: email = str(saved_tokens.get("email", ""))
	if "@" in email: parameters["login_hint"] = email
	return parameters

func login_chatgpt(profile: Dictionary, cancel: Dictionary, on_status: Callable = Callable()) -> Dictionary:
	if pending: return Common.failure("Există deja o autentificare în curs.")
	pending = true
	var saved_tokens: Variant = Common.parse_json(vault.read(str(profile["id"])))
	var callback_listener := _listen_callback(saved_tokens)
	if not callback_listener.get("ok", false):
		pending = false
		return callback_listener
	var listener = callback_listener["listener"]
	var callback_uri = "http://127.0.0.1:%s/auth/callback" % int(callback_listener["port"])
	var verifier = _base64url(Crypto.new().generate_random_bytes(48))
	var state = _base64url(Crypto.new().generate_random_bytes(32))
	var nonce = _base64url(Crypto.new().generate_random_bytes(32))
	var parameters = authorization_parameters(profile, saved_tokens, callback_uri, state, nonce, verifier)
	var client_id = str(parameters["client_id"])
	if on_status.is_valid(): on_status.call("Continuă autentificarea în browser. Revino aici după autorizare.")
	var opened = OS.shell_open(ISSUER + "/api/accounts/authorize?" + _form(parameters))
	if opened != OK:
		listener.stop()
		pending = false
		return Common.failure("Browserul nu a putut fi deschis.")
	var deadline = Time.get_ticks_msec() + 300000
	var callback = {}
	var warned_slow := false
	while not cancel.get("cancelled", false) and Time.get_ticks_msec() < deadline:
		if listener.is_connection_available():
			var peer = listener.take_connection()
			var raw = PackedByteArray()
			var peer_deadline = Time.get_ticks_msec() + 3000
			while Time.get_ticks_msec() < peer_deadline and raw.size() < 16384 and not cancel.get("cancelled", false):
				peer.poll()
				if peer.get_available_bytes() > 0: raw.append_array(peer.get_data(peer.get_available_bytes())[1])
				if "\r\n\r\n" in raw.get_string_from_utf8(): break
				await owner.get_tree().process_frame
			var line = raw.get_string_from_utf8().get_slice("\r\n", 0)
			var target = line.get_slice(" ", 1)
			var valid_path = line.begins_with("GET ") and target.get_slice("?", 0) == "/auth/callback"
			var parsed = _parse_query(target.get_slice("?", 1)) if valid_path else {}
			var valid_state = parsed.has("state") and Crypto.new().constant_time_compare(str(parsed["state"]).to_utf8_buffer(), state.to_utf8_buffer())
			var page = "Autentificare primită. Revino în Godot AI." if valid_state else "Callback invalid. Revino în Godot AI."
			var response = "HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: %s\r\n\r\n%s" % ["200 OK" if valid_state else "400 Bad Request", page.to_utf8_buffer().size(), page]
			peer.put_data(response.to_utf8_buffer())
			peer.disconnect_from_host()
			if valid_state:
				callback = parsed
				break
		if not warned_slow and Time.get_ticks_msec() > deadline - 255000:
			warned_slow = true
			if on_status.is_valid(): on_status.call("Browserul OpenAI nu a finalizat consentul. Încearcă Chrome Incognito, dezactivează adblock/VPN și verifică planul Plus/Pro. Aștept încă 4 minute.")
		await owner.get_tree().process_frame
	listener.stop()
	pending = false
	if callback.is_empty(): return Common.failure("Autentificare oprită sau expirată.", "cancelled")
	if callback.has("error"): return Common.failure("Autorizarea ChatGPT a fost refuzată: " + str(callback["error"]), "consent_denied")
	var issued_id = str(callback.get("client_id", client_id))
	if issued_id == "dynamic_agent_client" or (client_id != "dynamic_agent_client" and issued_id != client_id): return Common.failure("Înregistrarea OAuth nu a returnat clientul așteptat.")
	if not callback.has("code"): return Common.failure("Lipsește codul de autorizare.")
	var registration: Dictionary = saved_tokens.duplicate(true) if saved_tokens is Dictionary else {}
	registration["client_id"] = issued_id
	registration["redirect_uri"] = callback_uri
	if not vault.store(str(profile["id"]), JSON.stringify(registration)): return Common.failure("Înregistrarea OAuth nu a putut fi salvată.")
	var result = await transport.request(TOKEN_ENDPOINT, HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), _form({"grant_type": "authorization_code", "client_id": issued_id, "code": callback["code"], "code_verifier": verifier, "redirect_uri": callback_uri, "resource": RESOURCE}), {"cancel": cancel})
	if not result.get("ok", false): return Common.failure("Schimbul codului OAuth nu a reușit (" + _oauth_failure(result) + "). Pornește o autentificare nouă.", "oauth_exchange_failed")
	var tokens: Variant = result.get("json")
	if not tokens is Dictionary or not tokens.has("id_token") or not tokens.has("access_token"): return Common.failure("Răspuns OAuth incomplet.")
	var identity = await validate_id_token(str(tokens["id_token"]), issued_id, nonce, cancel)
	if not identity.get("ok", false): return identity
	if profile.has("subject") and profile["subject"] != identity["result"]["sub"]: return Common.failure("Contul autorizat diferă de profilul selectat.")
	if not "chatgpt.tokens.use.direct" in str(tokens.get("scope", "")).split(" "): return Common.failure("Contul nu a acordat utilizarea planului ChatGPT.", "plan_permission_missing")
	tokens["client_id"] = issued_id
	tokens["redirect_uri"] = callback_uri
	tokens["ext_agent_host_id"] = parameters["ext_agent_host_id"]
	tokens["email"] = str(identity["result"].get("email", ""))
	tokens["expires_at"] = Time.get_unix_time_from_system() + float(tokens.get("expires_in", 3600))
	tokens["subject"] = identity["result"]["sub"]
	if not vault.store(str(profile["id"]), JSON.stringify(tokens)): return Common.failure("Tokenurile nu au putut fi salvate în seiful dispozitivului.")
	var connected = profile.duplicate(true)
	connected["client_id"] = issued_id
	connected["subject"] = identity["result"]["sub"]
	connected["host_id"] = parameters["ext_agent_host_id"]
	connected["email"] = str(identity["result"].get("email", ""))
	connected["name"] = "ChatGPT · " + str(identity["result"].get("email", "Cont conectat"))
	connected["kind"] = "siwc"
	connected["url"] = RESOURCE
	return Common.success(connected)

func _listen_callback(saved_tokens: Variant) -> Dictionary:
	var ports := [CALLBACK_PORT]
	if saved_tokens is Dictionary:
		var saved_uri := str(saved_tokens.get("redirect_uri", ""))
		var parsed: Dictionary = Common.parse_url(saved_uri, true)
		var saved_port: int = int(parsed.get("port", 0)) if parsed.get("ok", false) else 0
		if saved_port > 0 and saved_port <= 65535 and not saved_port in ports: ports.push_front(saved_port)
	for requested in ports:
		var listener = TCPServer.new()
		if listener.listen(int(requested), "127.0.0.1") == OK:
			return {"ok": true, "listener": listener, "port": listener.get_local_port()}
	var fallback = TCPServer.new()
	if fallback.listen(0, "127.0.0.1") == OK:
		return {"ok": true, "listener": fallback, "port": fallback.get_local_port()}
	return Common.failure("Callbackul local nu poate fi pornit. Închide alt program care folosește portul 1455 și reîncearcă.", "callback_unavailable")

static func _oauth_failure(result: Dictionary) -> String:
	var payload: Variant = result.get("json")
	if payload is Dictionary:
		var error: Variant = payload.get("error")
		var text := ""
		if error is Dictionary:
			text = str(error.get("message", error.get("code", "")))
		else:
			text = str(error)
		var description := str(payload.get("error_description", ""))
		if not description.is_empty(): text += (": " if not text.is_empty() else "") + description
		if not text.is_empty(): return text.left(400)
	var status := int(result.get("status", 0))
	if status > 0: return "HTTP %d" % status
	return str(result.get("error", "răspuns necunoscut")).left(400)

func ensure_access(profile: Dictionary, cancel: Dictionary) -> Dictionary:
	var tokens: Variant = Common.parse_json(vault.read(str(profile["id"])))
	if not tokens is Dictionary: return Common.failure("Conectează contul ChatGPT.", "login_required")
	if float(tokens.get("expires_at", 0)) > Time.get_unix_time_from_system() + 60: return Common.success()
	if not tokens.has("refresh_token"): return Common.failure("Reconectează contul ChatGPT.", "login_required")
	var result = await transport.request(TOKEN_ENDPOINT, HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), _form({"grant_type": "refresh_token", "client_id": tokens["client_id"], "refresh_token": tokens["refresh_token"], "resource": RESOURCE}), {"cancel": cancel})
	if not result.get("ok", false): return Common.failure("Sesiunea ChatGPT nu poate fi reînnoită. Reconectează contul.", "login_required")
	var refreshed: Variant = result.get("json")
	if not refreshed is Dictionary or not refreshed.has("access_token"): return Common.failure("Răspuns de reînnoire invalid.")
	if refreshed.has("id_token"):
		var identity = await validate_id_token(str(refreshed["id_token"]), str(tokens["client_id"]), "", cancel)
		if not identity.get("ok", false) or identity.get("result", {}).get("sub") != tokens.get("subject"): return Common.failure("Identitatea reînnoită nu corespunde contului.")
	tokens.merge(refreshed, true)
	tokens["expires_at"] = Time.get_unix_time_from_system() + float(refreshed.get("expires_in", 3600))
	if not vault.store(str(profile["id"]), JSON.stringify(tokens)): return Common.failure("Sesiunea reînnoită nu a putut fi salvată.")
	return Common.success()

func validate_id_token(token: String, audience: String, nonce: String, cancel: Dictionary) -> Dictionary:
	var parts = token.split(".")
	if parts.size() != 3: return Common.failure("ID token invalid.")
	var header: Variant = Common.parse_json(_unbase64url(parts[0]).get_string_from_utf8())
	var claims: Variant = Common.parse_json(_unbase64url(parts[1]).get_string_from_utf8())
	if not header is Dictionary or not claims is Dictionary or header.get("alg") != "RS256": return Common.failure("Algoritmul semnăturii ID token nu este acceptat.")
	var discovery = await transport.request(ISSUER + "/.well-known/openid-configuration", HTTPClient.METHOD_GET, [], null, {"cancel": cancel})
	if not discovery.get("ok", false) or not discovery.get("json") is Dictionary: return Common.failure("Configurația OIDC nu este disponibilă.")
	var jwks_url = str(discovery["json"].get("jwks_uri", ""))
	if not jwks_url.begins_with(ISSUER + "/"): return Common.failure("Adresă JWKS nevalidată.")
	var jwks = await transport.request(jwks_url, HTTPClient.METHOD_GET, [], null, {"cancel": cancel})
	if not jwks.get("ok", false) or not jwks.get("json") is Dictionary: return Common.failure("Cheile de verificare OIDC nu sunt disponibile.")
	var verified = false
	for jwk in jwks["json"].get("keys", []):
		if jwk.get("kid") != header.get("kid") or jwk.get("kty") != "RSA": continue
		var key = CryptoKey.new()
		if key.load_from_string(_jwk_pem(jwk), true) != OK: continue
		verified = Crypto.new().verify(HashingContext.HASH_SHA256, (str(parts[0]) + "." + str(parts[1])).sha256_buffer(), _unbase64url(parts[2]), key)
		if verified: break
	var aud: Variant = claims.get("aud", "")
	var correct_audience = audience in aud if aud is Array else str(aud) == audience
	if not verified or claims.get("iss") != ISSUER or not correct_audience or float(claims.get("exp", 0)) <= Time.get_unix_time_from_system() or str(claims.get("sub", "")).is_empty(): return Common.failure("Identitatea OAuth nu a trecut verificarea semnăturii și a cererilor.")
	if not nonce.is_empty() and not Crypto.new().constant_time_compare(str(claims.get("nonce", "")).to_utf8_buffer(), nonce.to_utf8_buffer()): return Common.failure("Nonce OAuth invalid.")
	return Common.success(claims)

func companion_request(connection: Dictionary, path: String, method: int = HTTPClient.METHOD_GET, body: Variant = null, cancel: Dictionary = {}) -> Dictionary:
	var headers = PackedStringArray()
	var token = vault.read(str(connection.get("id", "companion")))
	if not token.is_empty(): headers.append("Authorization: Bearer " + token)
	return await transport.request(str(connection["url"]).trim_suffix("/") + path, method, headers, body, {"allow_http": connection.get("allow_http", false), "cancel": cancel})

static func _form(values: Dictionary) -> String:
	var parts: Array[String] = []
	for key in values: parts.append(str(key).uri_encode() + "=" + str(values[key]).uri_encode())
	return "&".join(parts)

static func _parse_query(query: String) -> Dictionary:
	var output = {}
	for part in query.split("&"):
		var position = part.find("=")
		if position >= 0: output[part.substr(0, position).uri_decode()] = part.substr(position + 1).replace("+", " ").uri_decode()
	return output

static func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("==").trim_suffix("=")

static func _unbase64url(value: String) -> PackedByteArray:
	var padded = value.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0: padded += "="
	return Marshalls.base64_to_raw(padded)

static func _der(tag: int, content: PackedByteArray) -> PackedByteArray:
	var output = PackedByteArray([tag])
	if content.size() < 128: output.append(content.size())
	else:
		var length = content.size()
		var bytes = PackedByteArray()
		while length > 0:
			bytes.insert(0, length & 255)
			length >>= 8
		output.append(128 | bytes.size())
		output.append_array(bytes)
	output.append_array(content)
	return output

static func _jwk_pem(jwk: Dictionary) -> String:
	var modulus = _unbase64url(str(jwk.get("n", "")))
	var exponent = _unbase64url(str(jwk.get("e", "")))
	if modulus.is_empty() or exponent.is_empty(): return ""
	if modulus[0] & 128: modulus.insert(0, 0)
	if exponent[0] & 128: exponent.insert(0, 0)
	var integers = _der(2, modulus)
	integers.append_array(_der(2, exponent))
	var bit_string = PackedByteArray([0])
	bit_string.append_array(_der(48, integers))
	var public_key = PackedByteArray([48, 13, 6, 9, 42, 134, 72, 134, 247, 13, 1, 1, 1, 5, 0])
	public_key.append_array(_der(3, bit_string))
	var base64 = Marshalls.raw_to_base64(_der(48, public_key))
	var lines: Array[String] = []
	for offset in range(0, base64.length(), 64): lines.append(base64.substr(offset, 64))
	return "-----BEGIN PUBLIC KEY-----\n" + "\n".join(lines) + "\n-----END PUBLIC KEY-----\n"
