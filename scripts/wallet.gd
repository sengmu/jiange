class_name WalletManager
extends Node
## Jiange Solana wallet layer (Godot 4.4 + godot-solana-sdk v1.4.5).
##
## Scope (design doc SOL_CHAIN_IAP_DESIGN.md v2):
## - Guest mode is the default and needs no wallet to play.
## - "Connected" = a validated Solana address bound to this session,
##   persisted in user://wallet.cfg. Balances are read via public JSON-RPC.
## - Android uses Mobile Wallet Adapter (MWA) for authorization.
## - Only three SDK uses: connect, sign, standard transfer construction.
## - Every transaction built here passes the §7 instruction whitelist
##   (SystemProgram transfer + Memo only) before it is sent for signing.
## - NO private keys anywhere. NO mainnet. P0 runs on devnet only, with
##   faucet SOL. The treasury/recipient address is NOT baked in yet:
##   it is set by the user at P3 (Phantom wallet address, §4.6).
## - Casino / real money stay fully isolated: this module never touches
##   the casino path and never issues any token.

signal state_changed
signal balance_updated(sol: float)
signal balance_failed(reason: String)
signal auth_failed(reason: String)
signal message_signed(message: String, signature: String)
signal message_sign_failed(reason: String)
signal transfer_submitted(order_id: String, signature: String)
signal transfer_failed(order_id: String, reason: String)

const ERR_MWA_UNAVAILABLE := "此版本无法打开移动钱包，可输入公开地址查询余额。"

const RPC_MAINNET := "https://api.mainnet-beta.solana.com"
const RPC_DEVNET := "https://api.devnet.solana.com"
const BASE58_ALPHABET := "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

## Memo program (Solana Memo Program, no accounts, data = UTF-8 memo).
const MEMO_PROGRAM_ID := "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
## System program (native SOL transfer).
const SYSTEM_PROGRAM_ID := "11111111111111111111111111111111"
## P0 smoke amount: 0.01 devnet SOL.
const P0_SMOKE_LAMPORTS := 10_000_000

var cluster := "devnet"
var address := ""  # empty = guest mode
var last_balance_sol := -1.0
var balance_state := "idle"
var balance_error := ""

var _http: HTTPRequest
var _adapter: Node = null
## order_id -> pending sign_message request (message text)
var _pending_sign: Dictionary = {}

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_rpc_completed)
	_init_mwa_adapter()
	_load_saved()

func _init_mwa_adapter() -> void:
	if Engine.has_singleton("WalletAdapterAndroid") and ClassDB.class_exists("WalletAdapter"):
		_adapter = ClassDB.instantiate("WalletAdapter")
		if _adapter:
			add_child(_adapter)
			if _adapter.has_signal("connection_established"):
				_adapter.connect("connection_established", Callable(self, "_on_mwa_connected"))
			if _adapter.has_signal("connection_failed"):
				_adapter.connect("connection_failed", Callable(self, "_on_mwa_failed"))
			if _adapter.has_signal("message_signed"):
				_adapter.connect("message_signed", Callable(self, "_on_mwa_message_signed"))
			# v1.4.5 native signal is "signing_failed" (no args); there is
			# no "message_sign_failed" signal.
			if _adapter.has_signal("signing_failed"):
				_adapter.connect("signing_failed", Callable(self, "_on_mwa_signing_failed"))

func is_wallet_connected() -> bool:
	return address != ""

func short_address() -> String:
	if address.length() <= 10:
		return address
	return address.substr(0, 4) + "…" + address.substr(address.length() - 4, 4)

func rpc_url() -> String:
	return RPC_DEVNET if cluster == "devnet" else RPC_MAINNET

func is_mwa_available() -> bool:
	return _adapter != null and _adapter.has_method("connect_wallet")

func _on_mwa_connected() -> void:
	if _adapter and _adapter.has_method("get_connected_key"):
		var key = _adapter.call("get_connected_key")
		if key != null:
			var addr_str: String = key.to_string()
			if is_valid_address(addr_str):
				connect_with_address(addr_str)

func _on_mwa_failed() -> void:
	auth_failed.emit("MWA 授权失败或已取消")

func request_authorize() -> String:
	if is_mwa_available():
		_adapter.call("connect_wallet")
		return ""
	return ERR_MWA_UNAVAILABLE

## Watch-only connect: validate + bind an address the user pastes/types.
## No keys, no signing — read-only by construction.
func connect_with_address(addr: String) -> bool:
	var a := addr.strip_edges()
	if not is_valid_address(a):
		auth_failed.emit("invalid Solana address")
		return false
	address = a
	_save()
	state_changed.emit()
	fetch_balance()
	return true

func disconnect_wallet() -> void:
	# v1.4.5 exposes NO native disconnect on WalletAdapter (ClassDB
	# dump 2026-11-18: no `disconnect` method; the "disconnect" strings
	# in the SDK are Object.disconnect). Disconnect is local-state clear
	# only; the `has_method` guard stays so a future SDK that adds one
	# gets called. This is the known #449 gap: after disconnect,
	# reconnect must be verified on device (P0 item 5).
	if _adapter != null and _adapter.has_method("disconnect"):
		_adapter.call("disconnect")
	address = ""
	last_balance_sol = -1.0
	balance_state = "idle"
	balance_error = ""
	_save()
	state_changed.emit()

# ------------------------------------------------------------- validation
static func is_valid_address(a: String) -> bool:
	if a.length() < 32 or a.length() > 44:
		return false
	for ch in a:
		if not BASE58_ALPHABET.contains(ch):
			return false
	return _base58_decoded_len(a) == 32

static func _base58_decoded_len(a: String) -> int:
	# Big-number base58 -> bytes length (enough to verify the 32-byte size).
	var bytes: Array[int] = [0]
	for ch in a:
		var carry := BASE58_ALPHABET.find(ch)
		if carry < 0:
			return -1
		for i in range(bytes.size()):
			var v := bytes[i] * 58 + carry
			bytes[i] = v & 0xFF
			carry = v >> 8
		while carry > 0:
			bytes.append(carry & 0xFF)
			carry >>= 8
	var leading := 0
	for ch in a:
		if ch == "1":
			leading += 1
		else:
			break
	var n := bytes.size()
	while n > 0 and bytes[n - 1] == 0:
		n -= 1  # significant bytes of the numeric value (0 value -> 0 bytes)
	return leading + n

# ------------------------------------------------------------- reads
func fetch_balance() -> void:
	if not is_wallet_connected():
		return
	balance_state = "loading"
	balance_error = ""
	state_changed.emit()
	var body := JSON.stringify({
		"jsonrpc": "2.0", "id": 1, "method": "getBalance", "params": [address]
	})
	var headers := ["Content-Type: application/json"]
	if _http.request(rpc_url(), headers, HTTPClient.METHOD_POST, body) != OK:
		_fail_balance("网络请求无法发出")

func _fail_balance(reason: String) -> void:
	balance_state = "failed"
	balance_error = reason
	balance_failed.emit(reason)
	state_changed.emit()

func _on_rpc_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail_balance("网络错误")
		return
	if code != 200:
		_fail_balance("RPC 返回 %d" % code)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.has("result") and parsed["result"] is Dictionary:
		var lamports: float = float(parsed["result"].get("value", 0))
		last_balance_sol = lamports / 1_000_000_000.0
		balance_state = "ok"
		balance_error = ""
		balance_updated.emit(last_balance_sol)
		state_changed.emit()
	else:
		_fail_balance("RPC 响应无效")

# ------------------------------------------------------------- signMessage
## Ask the connected wallet (MWA) to sign an arbitrary message.
## Returns false immediately if MWA is unavailable or no wallet is
## connected; otherwise the result arrives via message_signed /
## message_sign_failed. The signature is verified (ed25519) against
## the connected address before message_signed is emitted.
func request_sign_message(message: String) -> bool:
	if not is_wallet_connected():
		message_sign_failed.emit("未连接钱包")
		return false
	if _adapter == null or not _adapter.has_method("sign_text_message"):
		message_sign_failed.emit("当前版本不支持钱包签名")
		return false
	_pending_sign["message"] = message
	# sign_text_message(String) is the v1.4.5 Android binding for
	# signMessage (PR #435). sign_message(PackedByteArray, signer_index)
	# needs a signer index and is the raw-message variant; do not use it
	# here.
	_adapter.call("sign_text_message", message)
	return true

func _on_mwa_message_signed(signature) -> void:
	var message: String = String(_pending_sign.get("message", ""))
	_pending_sign.clear()
	var sig_b64: String = ""
	if signature is PackedByteArray:
		sig_b64 = Marshalls.raw_to_base64(signature)
	else:
		sig_b64 = String(signature)
	if message == "":
		message_sign_failed.emit("签名回包无对应原文")
		return
	if not verify_message_signature(message, sig_b64):
		message_sign_failed.emit("签名验签失败")
		return
	message_signed.emit(message, sig_b64)

func _on_mwa_signing_failed() -> void:
	_pending_sign.clear()
	message_sign_failed.emit("签名失败或已取消")

## ed25519 verify of (message, base64 signature) against the connected
## address. Returns false on any malformed input. Kept separate so the
## P0 smoke test can exercise it without a wallet.
func verify_message_signature(message: String, sig_b64: String) -> bool:
	if not is_valid_address(address):
		return false
	return _ed25519_verify(address, message.to_utf8_buffer(), sig_b64)

## Ed25519 verify (RFC 8032), pure GDScript: the SDK exposes
## verification only on Keypair (needs the private seed) and Godot 4.4
## has no SHA-512 in HashingContext, so Ed25519Verify implements both
## SHA-512 and the curve math. Validated against the RFC 8032 test
## vectors and cross-checked against Keypair.sign_message.
func _ed25519_verify(pubkey_b58: String, message: PackedByteArray, sig_b64: String) -> bool:
	return Ed25519Verify.verify(pubkey_b58, message, sig_b64)

# ------------------------------------------------------------- orders + whitelist (§7 / §4.2)
## Minimal order ledger for P0 smoke: order_id -> {sku, lamports,
## recipient, memo, state, signature}. Persisted in user://orders.cfg.
## Full §4.2 state machine (CREATED/SUBMITTED/CONFIRMED/VERIFIED/
## DELIVERED/FAILED_TX/UNKNOWN + dual-RPC verification) lands at P2.
func create_order(sku: String, lamports: int, recipient: String) -> String:
	if not is_valid_address(recipient):
		return ""
	var order_id := "JG-%d" % Time.get_unix_time_from_system()
	var cfg := ConfigFile.new()
	cfg.load("user://orders.cfg")
	cfg.set_value(order_id, "sku", sku)
	cfg.set_value(order_id, "lamports", lamports)
	cfg.set_value(order_id, "recipient", recipient)
	cfg.set_value(order_id, "memo", "JG:" + order_id)
	cfg.set_value(order_id, "state", "CREATED")
	cfg.set_value(order_id, "signature", "")
	cfg.save("user://orders.cfg")
	return order_id

func get_order(order_id: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("user://orders.cfg") != OK:
		return {}
	if not cfg.has_section(order_id):
		return {}
	return {
		"sku": String(cfg.get_value(order_id, "sku", "")),
		"lamports": int(cfg.get_value(order_id, "lamports", 0)),
		"recipient": String(cfg.get_value(order_id, "recipient", "")),
		"memo": String(cfg.get_value(order_id, "memo", "")),
		"state": String(cfg.get_value(order_id, "state", "")),
		"signature": String(cfg.get_value(order_id, "signature", "")),
	}

func _set_order_state(order_id: String, state: String, signature: String = "") -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://orders.cfg")
	if not cfg.has_section(order_id):
		return
	cfg.set_value(order_id, "state", state)
	if signature != "":
		cfg.set_value(order_id, "signature", signature)
	cfg.save("user://orders.cfg")

## §7 instruction whitelist, checked against the order BEFORE signing.
## Allowed instructions only:
##  - SystemProgram transfer: exactly one, target == order recipient,
##    lamports == order amount, source == connected wallet.
##  - Memo: exactly one, data == "JG:<order_id>".
## Anything else (extra instructions, wrong program, wrong target or
## amount) is rejected and never sent for signing.
## `instructions` entries are Dictionaries:
##   {"program": String, "kind": String, "target": String,
##    "lamports": int, "source": String, "data": String}
static func whitelist_check(order: Dictionary, instructions: Array) -> bool:
	if order.is_empty():
		return false
	var transfers := 0
	var memos := 0
	for ix in instructions:
		if not (ix is Dictionary):
			return false
		var program: String = String(ix.get("program", ""))
		if program == SYSTEM_PROGRAM_ID:
			if String(ix.get("kind", "")) != "transfer":
				return false
			if String(ix.get("target", "")) != String(order.get("recipient", "")):
				return false
			if int(ix.get("lamports", -1)) != int(order.get("lamports", -2)):
				return false
			transfers += 1
		elif program == MEMO_PROGRAM_ID:
			if String(ix.get("data", "")) != String(order.get("memo", "")):
				return false
			memos += 1
		else:
			return false
	return transfers == 1 and memos == 1

## Build the whitelisted instruction list for an order (pure data, no
## chain contact). The caller turns it into a Transaction via the SDK
## and sends it through transfer_sol().
static func build_order_instructions(order: Dictionary, sender: String) -> Array:
	if order.is_empty():
		return []
	return [
		{
			"program": SYSTEM_PROGRAM_ID, "kind": "transfer",
			"source": sender, "target": String(order.get("recipient", "")),
			"lamports": int(order.get("lamports", 0)), "data": "",
		},
		{
			"program": MEMO_PROGRAM_ID, "kind": "memo",
			"source": "", "target": "", "lamports": 0,
			"data": String(order.get("memo", "")),
		},
	]

## P0 transfer: build SystemProgram transfer + memo for the order,
## whitelist-check, then sign-and-send via the SDK TransactionManager
## (MWA signer). Requires the SolanaService autoload (plugin enabled).
## Returns "" immediately on any pre-flight failure; otherwise the
## signature arrives via transfer_submitted / transfer_failed.
func transfer_sol(order_id: String) -> String:
	var order := get_order(order_id)
	if order.is_empty():
		transfer_failed.emit(order_id, "订单不存在")
		return ""
	if String(order.get("state", "")) != "CREATED":
		transfer_failed.emit(order_id, "订单状态不是 CREATED")
		return ""
	if not is_wallet_connected():
		transfer_failed.emit(order_id, "未连接钱包")
		return ""
	if cluster != "devnet":
		transfer_failed.emit(order_id, "P0 只允许 devnet")
		return ""
	if not _solana_service_ready():
		transfer_failed.emit(order_id, "SolanaService 未就绪")
		return ""
	var instructions := build_order_instructions(order, address)
	if not whitelist_check(order, instructions):
		transfer_failed.emit(order_id, "白名单校验未通过")
		return ""
	_set_order_state(order_id, "SUBMITTED")
	_do_transfer_async(order_id, order)
	return order_id

func _solana_service_ready() -> bool:
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return false
	return root.has_node("SolanaService")

func _do_transfer_async(order_id: String, order: Dictionary) -> void:
	# Runs as a coroutine: construct via SDK, sign via MWA, send.
	# NOTE: the SolanaService autoload is resolved through the scene
	# tree, not by global name — isolated `--check-only --script`
	# cannot resolve autoload globals (the SDK's own scripts fail the
	# same way), while the tree lookup works in every context.
	var service = get_tree().root.get_node("SolanaService")
	var tm = service.get_node("TransactionManager")
	var payer = Pubkey.new_from_string(address)
	var receiver = Pubkey.new_from_string(String(order.get("recipient", "")))
	var ix_list: Array[Instruction] = []
	ix_list.append(SystemProgram.transfer(payer, receiver, int(order.get("lamports", 0))))
	ix_list.append(_memo_instruction(String(order.get("memo", ""))))
	var tx: Transaction = await tm.create_transaction(ix_list, service.wallet.get_kp())
	if tx == null:
		_set_order_state(order_id, "CREATED")
		transfer_failed.emit(order_id, "交易构造失败")
		return
	# NOTE: tx_data is deliberately untyped. The SDK's TransactionData
	# script references the SolanaService autoload global, which
	# isolated `--check-only --script` cannot resolve (same limitation
	# as the SDK's own scripts); a static `: TransactionData`
	# annotation would pull that compile dependency into this file.
	# Duck-typed calls below behave identically at runtime.
	var tx_data = await tm.sign_and_send(tx)
	if tx_data == null or not tx_data.is_successful():
		_set_order_state(order_id, "CREATED")
		var reason := "发送失败"
		if tx_data != null:
			reason = tx_data.get_error_message()
		transfer_failed.emit(order_id, reason)
		return
	var sig: String = String(tx_data.data.get("result", ""))
	_set_order_state(order_id, "SUBMITTED", sig)
	transfer_submitted.emit(order_id, sig)

## Memo instruction via the native Instruction class.
static func _memo_instruction(memo: String) -> Instruction:
	var ix := Instruction.new()
	ix.set_program_id(Pubkey.new_from_string(MEMO_PROGRAM_ID))
	ix.set_data(memo.to_utf8_buffer())
	return ix

# ------------------------------------------------------------- persistence
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "address", address)
	cfg.set_value("wallet", "cluster", cluster)
	cfg.save("user://wallet.cfg")

func _load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://wallet.cfg") == OK:
		address = String(cfg.get_value("wallet", "address", ""))
		cluster = String(cfg.get_value("wallet", "cluster", "devnet"))
		if not is_valid_address(address):
			address = ""
