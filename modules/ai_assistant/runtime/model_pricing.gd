@tool
extends RefCounted
## Read-only first-party rate cards. All numeric rates use the stated currency / 1M tokens.
static var Common: GDScript
static var Transport: GDScript
const TTL = 21600
const FEEDS = {
	"openai": "https://developers.openai.com/api/docs/pricing.md",
	"anthropic": "https://platform.claude.com/docs/en/about-claude/pricing.md",
	"deepseek": "https://api-docs.deepseek.com/quick_start/pricing/",
	"gemini": "https://ai.google.dev/gemini-api/docs/pricing",
	"openrouter": "https://openrouter.ai/api/v1/models",
	"qwen": "https://www.alibabacloud.com/help/en/model-studio/model-pricing",
	"qwen-cn": "https://help.aliyun.com/zh/model-studio/model-pricing",
	"kimi": "https://platform.kimi.ai/docs/pricing/chat.md",
	"mistral": "https://docs.mistral.ai/inference/pricing.md",
	"groq": "https://console.groq.com/docs/models.md",
	"xai": "https://docs.x.ai/developers/models",
	"zai": "https://docs.z.ai/guides/overview/pricing.md",
	"minimax": "https://platform.minimax.io/docs/guides/pricing-paygo.md",
	"siliconflow": "https://www.siliconflow.cn/pricing"}
var owner: Node
var transport: RefCounted
var cache: Dictionary = {}
var directory = ""
var running: Dictionary = {}
var attempted: Dictionary = {}

func _init(node: Node = null) -> void:
	owner = node
	transport = Transport.new(node)

func configure(path: String) -> void:
	directory = path
	var saved: Variant = Common.read_json(directory.path_join("model-prices.json"), {})
	cache = saved if saved is Dictionary else {}

static func key(value: String) -> String:
	var regex = RegEx.new()
	regex.compile("[^a-z0-9]+")
	return regex.sub(value.to_lower(), "", true)

static func plain(value: String) -> String:
	var regex = RegEx.new()
	regex.compile("(?is)<(?:del|s|sup)\\b[^>]*>.*?</(?:del|s|sup)>")
	value = regex.sub(value, "", true)
	regex.compile("~~.*?~~")
	value = regex.sub(value, "", true)
	regex.compile("\\[([^\\]]+)\\]\\([^)]*\\)")
	value = regex.sub(value, "$1", true)
	regex.compile("<[^>]+>")
	value = regex.sub(value, " ", true)
	for pair in [["&amp;", "&"], ["&lt;", "<"], ["&gt;", ">"], ["&nbsp;", " "], ["&#36;", "$"], ["&#165;", "¥"]]: value = value.replace(pair[0], pair[1])
	value = value.replace("\\$", "$").replace("**", "").replace("`", "").replace("↗", "")
	regex.compile("\\s+")
	return regex.sub(value, " ", true).strip_edges()

static func money(value: String, currency: String = "USD") -> Variant:
	value = plain(value)
	if value.to_lower() == "free": return 0.0
	if any_unit_mismatch(value): return null
	var regex = RegEx.new()
	regex.compile("(?:US\\$|\\$)\\s*([0-9]+(?:\\.[0-9]+)?)" if currency == "USD" else "(?:[¥￥]\\s*)?([0-9]+(?:\\.[0-9]+)?)\\s*(?:元|CNY|RMB)")
	var matches = regex.search_all(value)
	if matches.is_empty(): return null
	var amount = float(matches[0].get_string(1))
	for found in matches:
		if float(found.get_string(1)) != amount: return null
	return amount if is_finite(amount) and amount >= 0 else null

static func any_unit_mismatch(value: String) -> bool:
	var lower = value.to_lower()
	return ["/1000", "1,000", "/min", "perhour", "persecond", "/image", "/mchars", "percharacter"].any(func(unit: String) -> bool: return unit in lower.replace(" ", ""))

static func column_label(rate: Dictionary, field: String) -> String:
	if not rate.has(field): return "—"
	var low = float(rate[field])
	var high = low
	for variant in rate.get("variants", []):
		if variant.has(field): low = minf(low, float(variant[field])); high = maxf(high, float(variant[field]))
	return number(low) + ("–" + number(high) if high > low else "")

static func rate_label(rate: Dictionary) -> String:
	if rate.get("mode") == "local": return "Local"
	if rate.get("mode") == "subscription": return "Abonament"
	if not rate.has("input") or not rate.has("output"): return "Tarif nepublicat"
	return column_label(rate, "input") + " / " + column_label(rate, "output") + " " + str(rate.get("currency", "USD")) + (" · anterior" if rate.get("stale", false) else "")

static func number(value: float) -> String:
	return ("%.6f" % value).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".").replace(".", ",")

static func detail(rate: Dictionary) -> String:
	if rate.get("mode") == "local": return "Model local · fără tarif cloud public."
	if rate.get("mode") == "subscription": return "Abonament · limitele contului se aplică; fără tarif API atribuit."
	var text = "Intrare / ieșire per 1M tokeni · " + rate_label(rate)
	if rate.has("cached_input"): text += "\nCache citire: " + column_label(rate, "cached_input") + " " + str(rate.get("currency", "USD")) + " / 1M tokeni"
	for variant in rate.get("variants", []):
		if rate.get("variants", []).size() > 1: text += "\n" + str(variant.get("condition", "Variantă")) + ": " + number(float(variant["input"])) + " / " + number(float(variant["output"]))
	for field in ["cache_write_5m", "cache_write_1h"]:
		if rate.has(field): text += "\nCache scriere " + ("5m" if field.ends_with("5m") else "1h") + ": " + column_label(rate, field) + " " + str(rate.get("currency", "USD")) + " / 1M tokeni"
	if not str(rate.get("condition", "")).is_empty(): text += "\n" + str(rate["condition"])
	if rate.has("checked_at"): text += "\nVerificat: " + Time.get_datetime_string_from_unix_time(int(rate["checked_at"])) + " UTC"
	if rate.get("stale", false): text += "\nActualizarea nu a reușit; este afișat ultimul tarif cunoscut."
	if rate.has("source"): text += "\n" + str(rate["source"])
	return text

static func from_api(item: Dictionary, issuer: String, source: String) -> Dictionary:
	if issuer == "opencode":
		var cost: Variant = item.get("cost", {})
		if not cost is Dictionary: return {}
		var text: Variant = cost.get("text", {})
		if not text is Dictionary: return {}
		var input_entry: Variant = text.get("input", {})
		var output_entry: Variant = text.get("output", {})
		if not input_entry is Dictionary or not output_entry is Dictionary: return {}
		var input_value: Variant = input_entry.get("price")
		var output_value: Variant = output_entry.get("price")
		if input_value == null or output_value == null: return {}
		if not str(input_value).is_valid_float() or not str(output_value).is_valid_float(): return {}
		var incoming = float(input_value)
		var outgoing = float(output_value)
		if not is_finite(incoming) or not is_finite(outgoing) or incoming < 0 or outgoing < 0: return {}
		var rate = {"input": incoming, "output": outgoing, "currency": "USD", "source": source, "source_kind": "api", "checked_at": Time.get_unix_time_from_system()}
		var cache: Variant = input_entry.get("cache", {})
		if cache is Dictionary:
			var cached: Variant = cache.get("read")
			if cached != null and str(cached).is_valid_float() and is_finite(float(cached)) and float(cached) >= 0: rate["cached_input"] = float(cached)
		return rate
	var value: Variant = item.get("pricing", {})
	if not value is Dictionary: return {}
	# OpenRouter explicitly documents USD per token. Other unlabeled numeric fields
	# are not guessed to be per-token or per-million rates.
	var input = value.get("prompt") if issuer == "openrouter" else value.get("input_per_million")
	var output = value.get("completion") if issuer == "openrouter" else value.get("output_per_million")
	if input == null or output == null: return {}
	if not str(input).is_valid_float() or not str(output).is_valid_float(): return {}
	var multiplier = 1000000.0 if issuer == "openrouter" else 1.0
	var incoming = float(input) * multiplier
	var outgoing = float(output) * multiplier
	if not is_finite(incoming) or not is_finite(outgoing) or incoming < 0 or outgoing < 0: return {}
	var rate = {"input": incoming, "output": outgoing, "currency": "USD", "source": source, "source_kind": "api", "checked_at": Time.get_unix_time_from_system()}
	var cached: Variant = value.get("input_cache_read") if issuer == "openrouter" else value.get("cached_input_per_million")
	if cached != null and str(cached).is_valid_float() and is_finite(float(cached)) and float(cached) >= 0: rate["cached_input"] = float(cached) * multiplier
	return rate

static func mode(profile: Dictionary) -> String:
	if profile.get("kind") in ["siwc", "companion"]: return "subscription"
	if profile.get("issuer") in ["ollama", "lmstudio", "llamacpp"] or profile.get("hosting") == "local": return "local"
	return "api"

func apply(profile: Dictionary, models: Array, stale: bool = false) -> void:
	var issuer = str(profile.get("issuer", ""))
	var entry: Dictionary = cache.get(issuer, {})
	var cache_stale = stale or entry.get("update_failed", false) or Time.get_unix_time_from_system() - float(entry.get("checked_at", 0)) >= TTL
	for model in models:
		var billing = mode(profile)
		if billing != "api": model["pricing"] = {"mode": billing}; continue
		if not profile.get("official_pricing", true): model["pricing"] = {"mode": "api"}; continue
		var inline: Dictionary = model.get("pricing", {})
		if inline.get("source_kind") == "api" and issuer not in ["openrouter", "opencode"]: continue
		if inline.get("source_kind") == "api" and float(inline.get("checked_at", 0)) >= float(entry.get("checked_at", 0)):
			inline["stale"] = stale or entry.get("update_failed", false) or inline.get("stale", false) or Time.get_unix_time_from_system() - float(inline.get("checked_at", 0)) >= TTL
			continue
		var rate = lookup(entry.get("rates", {}), model)
		if rate.is_empty():
			if model.get("pricing", {}).has("input"): model["pricing"]["stale"] = true
			else: model["pricing"] = {"source": FEEDS.get(issuer, ""), "mode": "api"}
			continue
		rate = rate.duplicate(true)
		rate.merge({"source": entry.get("source", ""), "checked_at": entry.get("checked_at", 0), "stale": cache_stale, "source_kind": "document"}, true)
		model["pricing"] = rate

func refresh(profile: Dictionary, models: Array, cancel: Dictionary = {}, force: bool = false) -> Dictionary:
	var issuer = str(profile.get("issuer", ""))
	if mode(profile) != "api": apply(profile, models); return Common.success({"changed": false})
	if not profile.get("official_pricing", true): apply(profile, models); return Common.success({"changed": false, "unavailable": true})
	if issuer == "opencode": apply(profile, models); return Common.success({"changed": false, "inline": true})
	if not FEEDS.has(issuer): apply(profile, models); return Common.success({"unavailable": true})
	var previous: Dictionary = cache.get(issuer, {})
	var age = Time.get_unix_time_from_system() - float(previous.get("checked_at", 0))
	if not force and not previous.is_empty() and age >= 0 and age < TTL: apply(profile, models); return Common.success({"cached": true})
	if running.has(issuer):
		while running.has(issuer) and not cancel.get("cancelled", false) and is_instance_valid(owner) and owner.is_inside_tree(): await owner.get_tree().process_frame
		if cancel.get("cancelled", false) or not is_instance_valid(owner) or not owner.is_inside_tree(): return Common.failure("Actualizare oprită.", "cancelled")
		if not attempted.has(issuer): return await refresh(profile, models, cancel, force)
		apply(profile, models)
		return Common.success({"cached": true})
	if not force and attempted.has(issuer) and Time.get_ticks_msec() - int(attempted[issuer]) < 300000:
		apply(profile, models, true)
		return Common.success({"backoff": true})
	running[issuer] = true
	attempted[issuer] = Time.get_ticks_msec()
	var response = await transport.request(FEEDS[issuer], HTTPClient.METHOD_GET, ["Accept: text/markdown,application/json,text/html;q=0.9", "User-Agent: Mozilla/5.0 Godot-AI-Pricing/1.0"], null, {"cancel": cancel, "timeout": 15, "connect_timeout": 5, "max_bytes": 8388608 if issuer == "openrouter" else 2097152, "follow_redirects": true})
	if cancel.get("cancelled", false):
		running.erase(issuer)
		attempted.erase(issuer)
		return Common.failure("Actualizare oprită.", "cancelled")
	var rates = {}
	if response.get("ok", false):
		if issuer == "openrouter" and response.get("json") is Dictionary:
			for item in response["json"].get("data", []):
				if item is Dictionary:
					var rate = from_api(item, issuer, FEEDS[issuer])
					if not rate.is_empty(): rates[key(str(item.get("id", "")))] = rate
		else:
			var document = str(response.get("text", ""))
			# Large documentation pages must not interrupt chat scrolling or typing.
			var worker = Thread.new()
			if document.length() > 65536 and worker.start(parse_document.bind(issuer, document)) == OK:
				while worker.is_alive() and is_instance_valid(owner) and owner.is_inside_tree(): await owner.get_tree().process_frame
				rates = worker.wait_to_finish()
			else: rates = parse_document(issuer, document)
	if cancel.get("cancelled", false) or not is_instance_valid(owner) or not owner.is_inside_tree():
		running.erase(issuer)
		attempted.erase(issuer)
		return Common.failure("Actualizare oprită.", "cancelled")
	if rates.is_empty():
		if not previous.is_empty():
			cache[issuer]["update_failed"] = true
			if not directory.is_empty(): Common.atomic_json(directory.path_join("model-prices.json"), cache)
		running.erase(issuer)
		apply(profile, models, true)
		return Common.failure("Tarifele nu au putut fi verificate; păstrez ultimul tarif cunoscut.", "pricing_unavailable")
	cache[issuer] = {"rates": rates, "checked_at": Time.get_unix_time_from_system(), "source": FEEDS[issuer]}
	if not directory.is_empty(): Common.atomic_json(directory.path_join("model-prices.json"), cache)
	running.erase(issuer)
	apply(profile, models)
	return Common.success({"updated": true, "rates": rates.size()})

static func lookup(rates: Dictionary, model: Dictionary) -> Dictionary:
	for value in [str(model.get("id", "")), str(model.get("name", ""))]:
		var normalized = key(value)
		if rates.has(normalized): return rates[normalized]
	return {}

static func html_tables(text: String) -> Array:
	var result = []
	var table_re = RegEx.new(); table_re.compile("(?is)<table\\b[^>]*>(.*?)</table>")
	var row_re = RegEx.new(); row_re.compile("(?is)<tr\\b[^>]*>(.*?)</tr>")
	var cell_re = RegEx.new(); cell_re.compile("(?is)<t[dh]\\b([^>]*)>(.*?)</t[dh]>")
	var span_re = RegEx.new(); span_re.compile("(?i)(rowspan|colspan)=[\"']?([0-9]+)")
	for table in table_re.search_all(text):
		var rows = []
		var spans = {}
		for row in row_re.search_all(table.get_string(1)):
			var cells = []
			var occupied = {}
			for column in spans:
				occupied[column] = spans[column]["value"]
				spans[column]["left"] -= 1
			for column in spans.keys():
				if spans[column]["left"] <= 0: spans.erase(column)
			var column = 0
			for cell in cell_re.search_all(row.get_string(1)):
				while occupied.has(column): column += 1
				var rowspan = 1
				var colspan = 1
				for span in span_re.search_all(cell.get_string(1)):
					if span.get_string(1).to_lower() == "rowspan": rowspan = clampi(int(span.get_string(2)), 1, 100)
					else: colspan = clampi(int(span.get_string(2)), 1, 30)
				var value = plain(cell.get_string(2))
				for offset in range(colspan):
					occupied[column + offset] = value
					if rowspan > 1: spans[column + offset] = {"value": value, "left": rowspan - 1}
				column += colspan
			for index in range(occupied.keys().max() + 1 if not occupied.is_empty() else 0): cells.append(str(occupied.get(index, "")))
			if not cells.is_empty(): rows.append(cells)
		result.append({"rows": rows, "offset": table.get_start()})
	return result

static func parse_document(issuer: String, text: String) -> Dictionary:
	if issuer == "deepseek": return parse_deepseek(text)
	var tables: Array = html_tables(text)
	var lines = text.split("\n")
	var rows = []
	var offset = 0
	var table_offset = 0
	for line in lines:
		if line.strip_edges().begins_with("|"):
			if rows.is_empty(): table_offset = offset
			var row = []
			for cell in line.strip_edges().trim_prefix("|").trim_suffix("|").split("|"): row.append(plain(cell))
			rows.append(row)
		elif not rows.is_empty():
			tables.append({"rows": rows, "offset": table_offset})
			rows = []
		offset += line.length() + 1
	if not rows.is_empty(): tables.append({"rows": rows, "offset": table_offset})
	var rates = {}
	for table in tables:
		var context = text.substr(0, int(table["offset"]))
		if issuer == "gemini": parse_gemini_table(table["rows"], context, rates); continue
		var local = parse_table(table["rows"], issuer)
		for id in local:
			# First table wins: standard rates precede batch/priority/discount sections.
			if not rates.has(id): rates[id] = local[id]
	return rates

static func parse_table(rows: Array, issuer: String) -> Dictionary:
	var result = {}
	var columns = {}
	for row in rows:
		# Only an explicit header can define columns. A price cell containing the
		# words input/output is data, never a header.
		var is_header = row.any(func(cell: Variant) -> bool: return str(cell).to_lower() in ["model", "model id", "name", "模型", "模型名称", "模型名", "模型 id（model id）"])
		if is_header:
			columns = {}
			for index in range(row.size()):
				var header = str(row[index]).to_lower()
				if header in ["model", "model id", "name", "模型", "模型名称", "模型名", "模型 id（model id）"]: columns["model"] = index
				if header == "api name": columns["api"] = index
				if "deployment scope" in header or "部署范围" in header: columns["region"] = index
				if header == "price" or "price per 1m tokens" in header: columns["combined"] = index
				if ("input" in header and not "cache" in header and not "tokens per request" in header) or "输入单价" in header:
					if not columns.has("input"): columns["input"] = index
					elif "long context" in header: columns["long_input"] = index
				if "output" in header or "输出单价" in header:
					if not columns.has("output"): columns["output"] = index
					elif "long context" in header: columns["long_output"] = index
				if "cached input" in header or "cache hits" in header or "caching read" in header:
					if "long context" in header: columns["long_cached_input"] = index
					elif not columns.has("cached_input"): columns["cached_input"] = index
				if "5m cache writes" in header: columns["cache_write_5m"] = index
				if "1h cache writes" in header: columns["cache_write_1h"] = index
			continue
		if not columns.has("model") or int(columns["model"]) >= row.size(): continue
		var title = str(row[columns["model"]])
		if title.begins_with(":") or title.begins_with("-"): continue
		if columns.has("region") and issuer == "qwen" and not "international" in str(row[columns["region"]]).to_lower(): continue
		var currency = "CNY" if issuer == "qwen-cn" else "USD"
		var rate = {"currency": currency, "condition": title}
		for field in ["input", "output", "cached_input", "cache_write_5m", "cache_write_1h", "long_input", "long_output", "long_cached_input"]:
			if columns.has(field) and int(columns[field]) < row.size():
				var amount = money(str(row[columns[field]]), currency)
				if amount != null: rate[field] = amount
		if columns.has("combined") and int(columns["combined"]) < row.size():
			var value = str(row[columns["combined"]])
			var patterns = {"input": "(?i)(?<!cached )input \\$([0-9.]+)", "output": "(?i)output \\$([0-9.]+)", "cached_input": "(?i)cached input \\$([0-9.]+)"} if issuer == "mistral" else {"input": "(?i)\\$([0-9.]+)\\s*input", "output": "(?i)\\$([0-9.]+)\\s*output"}
			for field in patterns:
				var regex = RegEx.new(); regex.compile(patterns[field])
				var found = regex.search(value)
				if found != null: rate[field] = float(found.get_string(1))
		if not rate.has("input") or not rate.has("output"): continue
		var name = str(row[columns["api"]]) if columns.has("api") else title.split(" (")[0].split(" ≤")[0].split(" >")[0]
		if name.begins_with("qwen"): name = name.get_slice(" ", 0)
		if issuer == "groq":
			var regex = RegEx.new(); regex.compile("(?:openai|meta-llama|qwen|llama|moonshotai|minimaxai)[/a-zA-Z0-9._-]+$")
			var found = regex.search(title)
			if found != null: name = found.get_string()
		add_variant(result, key(name), rate)
		if rate.has("long_input") and rate.has("long_output"):
			var long_rate = {"input": rate["long_input"], "output": rate["long_output"], "currency": currency, "condition": "Context lung"}
			if rate.has("long_cached_input"): long_rate["cached_input"] = rate["long_cached_input"]
			add_variant(result, key(name), long_rate)
	return result

static func add_variant(rates: Dictionary, id: String, rate: Dictionary) -> void:
	if id.is_empty(): return
	if not rates.has(id): rates[id] = rate.duplicate(true); rates[id]["variants"] = []
	rates[id]["variants"].append(rate)
	rates[id]["input"] = minf(float(rates[id]["input"]), float(rate["input"]))
	rates[id]["output"] = minf(float(rates[id]["output"]), float(rate["output"]))

static func parse_deepseek(text: String) -> Dictionary:
	var rates = {}
	for table in html_tables(text):
		var columns = {}
		var values = {}
		for row in table["rows"]:
			for index in range(row.size()):
				if str(row[index]) in ["deepseek-flash", "deepseek-v4-pro"]: columns[index] = str(row[index])
			var label = " ".join(row).to_lower()
			var stage = "OFF-PEAK" if "off-peak" in label else ("PEAK" if "peak" in label else "Standard")
			var field = "cached_input" if "cache hit" in label else ("input" if "cache miss" in label else ("output" if "1m output" in label else ""))
			if field.is_empty(): continue
			for column in columns:
				if column >= row.size(): continue
				var amount = money(str(row[column]))
				if amount == null: continue
				var id = columns[column]
				if not values.has(id): values[id] = {}
				if not values[id].has(stage): values[id][stage] = {"currency": "USD", "condition": stage + " · condițiile orare / sărbătorile furnizorului"}
				values[id][stage][field] = amount
		for id in values:
			for stage in values[id]:
				if values[id][stage].has("input") and values[id][stage].has("output"): add_variant(rates, key(id), values[id][stage])
	if rates.has(key("deepseek-flash")):
		for alias in ["deepseek-v4-flash", "deepseek-v4-flash-vision-exp"]: rates[key(alias)] = rates[key("deepseek-flash")].duplicate(true)
	return rates

static func parse_gemini_table(rows: Array, context: String, rates: Dictionary) -> void:
	var heading_re = RegEx.new(); heading_re.compile("(?is)<h2[^>]*id=[\"']([^\"']+)[\"'][^>]*>")
	var headings = heading_re.search_all(context)
	if headings.is_empty(): return
	var id = headings[-1].get_string(1)
	var last_h3 = context.rfind("<h3")
	if last_h3 >= 0 and ["batch", "flex", "priority"].any(func(tier: String) -> bool: return tier in context.substr(last_h3).to_lower()): return
	if not id.begins_with("gemini"): return
	var rate = {"currency": "USD", "condition": "Tarif standard; opțiunile / contextul pot modifica tariful."}
	for row in rows:
		if row.size() < 3: continue
		var label = str(row[0]).to_lower()
		var amount = money(str(row[-1]))
		if amount == null: continue
		if label.begins_with("input price"): rate["input"] = amount
		elif label.begins_with("output price"): rate["output"] = amount
		elif label.begins_with("context caching"): rate["cached_input"] = amount
	if rate.has("input") and rate.has("output") and not rates.has(key(id)): add_variant(rates, key(id), rate)
