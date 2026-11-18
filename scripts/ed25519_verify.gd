class_name Ed25519Verify
## Pure-GDScript Ed25519 signature verification (RFC 8032).
##
## Why this exists: the godot-solana-sdk only exposes verification on
## Keypair (which needs the private seed), and Godot 4.4 has no SHA-512
## in HashingContext. To verify a wallet's signMessage result against
## its public key only, both SHA-512 and the curve math are implemented
## here. Validated against the RFC 8032 test vectors plus the SDK's own
## Keypair.sign_message as a cross-check oracle.
##
## Field arithmetic: radix 2^26, 10 limbs, mod p = 2^255-19.
## All limb values stay in signed 64-bit range (products < 2^52,
## accumulations < 2^56). No constant-time guarantees are needed:
## every input to verify() is public.
##
## SHA-512 K constants were generated (not recalled) from the cube
## roots of the first 80 primes with exact integer arithmetic and
## cross-checked against the known FIPS values for K[0..7,10,40].

const MASK26 := (1 << 26) - 1

# ------------------------------------------------------------- field
static func _fe_zero() -> Array[int]:
	return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

static func _fe_one() -> Array[int]:
	return [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]

static func _p_limbs() -> Array[int]:
	# p = 2^255 - 19, as 10 uniform 26-bit limbs. Note the top limb:
	# 2^255 sits at bit 21 of limb 9, so p[9] = 2^21 - 1 = 2097151
	# (NOT 2^25 - 1; that belongs to the alternating 26/25-bit scheme).
	return [67108845, 67108863, 67108863, 67108863, 67108863, 67108863, 67108863, 67108863, 67108863, 2097151]

static func _fe_carry(h: Array[int]) -> Array[int]:
	# Repeat carry+fold until the top carry is zero, so every limb is
	# < 2^26. Fold factor: the carry out of limb 9 is c * 2^260, and
	# 2^260 = 32 * 2^255 == 32 * 19 == 608 (mod p).
	for _round in range(6):
		var c := 0
		for i in range(10):
			var v := h[i] + c
			c = v >> 26
			h[i] = v & MASK26
		if c == 0:
			break
		h[0] += c * 608
	# Full reduction to [0, p): the carry/fold steps preserve the value
	# only mod p, so the result can be r + k*p with k up to ~32. Every
	# consumer (equality, encoding, sqrt checks) needs a canonical
	# representative, so subtract p until the value is below p.
	var p := _p_limbs()
	while true:
		var ge := true
		for i in range(9, -1, -1):
			if h[i] != p[i]:
				ge = h[i] > p[i]
				break
		if not ge:
			break
		var borrow := 0
		for i in range(10):
			var v := h[i] - p[i] - borrow
			if v < 0:
				v += 1 << 26
				borrow = 1
			else:
				borrow = 0
			h[i] = v
	return h

static func _fe_add(a: Array[int], b: Array[int]) -> Array[int]:
	var h := _fe_zero()
	for i in range(10):
		h[i] = a[i] + b[i]
	return _fe_carry(h)

static func _fe_sub(a: Array[int], b: Array[int]) -> Array[int]:
	var h := _fe_zero()
	var p := _p_limbs()
	for i in range(10):
		h[i] = a[i] - b[i] + 2 * p[i]
	return _fe_carry(h)

static func _fe_neg(a: Array[int]) -> Array[int]:
	return _fe_sub(_fe_zero(), a)

static func _fe_mul(a: Array[int], b: Array[int]) -> Array[int]:
	# Schoolbook product with the wrap handled in two int64-safe steps.
	# A naive sum a_i*b_j*608 overflows signed 64-bit (10 terms of
	# ~2^52 * 608 ~= 2^64.6), so the wrap terms are accumulated
	# separately as w[k] and folded as t = 19*w[k], contribution
	# t*32 = (t mod 2^21)*32 at limb k plus (t div 2^21) at limb k+1.
	# Every intermediate stays < 2^63 (verified against a Python model
	# over 500 random limb vectors plus the full pow chain).
	var s := _fe_zero()
	var w := _fe_zero()
	for i in range(10):
		for j in range(10):
			if i + j < 10:
				s[i + j] += a[i] * b[j]
			else:
				w[i + j - 10] += a[i] * b[j]
	var h := _fe_zero()
	for k in range(10):
		var t := 19 * w[k]
		h[k] += s[k] + ((t & 0x1FFFFF) << 5)
		var hi := t >> 21
		if k < 9:
			h[k + 1] += hi
		else:
			h[0] += hi * 608  # fold 2^260 == 608 (mod p)
	return _fe_carry(h)

static func _fe_sq(a: Array[int]) -> Array[int]:
	return _fe_mul(a, a)

static func _fe_mul_small(a: Array[int], m: int) -> Array[int]:
	var h := _fe_zero()
	for i in range(10):
		h[i] = a[i] * m
	return _fe_carry(h)

# Generic square-and-multiply power. `exp` is a little-endian byte
# array holding the exponent (bit 0 = LSB of exp[0]).
static func _fe_pow(base: Array[int], exp: PackedByteArray) -> Array[int]:
	var r := _fe_one()
	var b := base.duplicate()
	var total_bits := exp.size() * 8
	for i in range(total_bits):
		if (exp[i / 8] >> (i % 8)) & 1:
			r = _fe_mul(r, b)
		b = _fe_sq(b)
	return r

static func _fe_invert(a: Array[int]) -> Array[int]:
	# p - 2 = 2^255 - 21 = 0x7FFF...FFEB (little-endian: byte 0 = 0xEB,
	# bytes 1..30 = 0xFF, byte 31 = 0x7F).
	var e := PackedByteArray()
	e.resize(32)
	for i in range(32):
		e[i] = 0xFF
	e[0] = 0xEB
	e[31] = 0x7F
	return _fe_pow(a, e)

static func _fe_is_zero(a: Array[int]) -> bool:
	var h := _fe_carry(a.duplicate())
	for i in range(10):
		if h[i] != 0:
			return false
	return true

static func _fe_equal(a: Array[int], b: Array[int]) -> bool:
	return _fe_is_zero(_fe_sub(a, b))

static func _fe_is_odd(a: Array[int]) -> bool:
	var h := _fe_carry(a.duplicate())
	return (h[0] & 1) == 1

# Decode 32 little-endian bytes as a 256-bit integer into 10x26-bit limbs.
static func _fe_from_bytes(b: PackedByteArray) -> Array[int]:
	var h := _fe_zero()
	var acc := 0
	var acc_bits := 0
	var limb := 0
	for i in range(32):
		acc |= int(b[i]) << acc_bits
		acc_bits += 8
		while acc_bits >= 26 and limb < 10:
			h[limb] = acc & MASK26
			acc >>= 26
			acc_bits -= 26
			limb += 1
	if limb < 10:
		h[limb] = acc & MASK26
	return _fe_carry(h)

static func _fe_to_bytes(a: Array[int]) -> PackedByteArray:
	var h := _fe_carry(a.duplicate())
	var p := _p_limbs()
	# Strong reduction: subtract p while h >= p (at most a couple times).
	for _t in range(3):
		var ge := true
		for i in range(9, -1, -1):
			if h[i] != p[i]:
				ge = h[i] > p[i]
				break
		if not ge:
			break
		var borrow := 0
		for i in range(10):
			var v := h[i] - p[i] - borrow
			if v < 0:
				v += 1 << 26
				borrow = 1
			else:
				borrow = 0
			h[i] = v
	var out := PackedByteArray()
	out.resize(32)
	var acc := 0
	var acc_bits := 0
	var limb := 0
	for i in range(32):
		while acc_bits < 8:
			acc |= h[limb] << acc_bits
			acc_bits += 26
			limb += 1
		out[i] = acc & 0xFF
		acc >>= 8
		acc_bits -= 8
	return out

# sqrt(u): returns x with x^2 == u, or [] if u is not a square.
static func _fe_sqrt(u: Array[int]) -> Array:
	# x = u^((p+3)/8); (p+3)/8 = 2^252 - 2.
	var e := PackedByteArray()
	e.resize(32)
	for i in range(32):
		e[i] = 0xFF
	e[0] = 0xFE
	e[31] = 0x0F  # 2^252-2: top byte 0x0F, low byte 0xFE, middle 0xFF
	var x := _fe_pow(u, e)
	if _fe_equal(_fe_sq(x), u):
		return [x]
	# Try x * sqrt(-1); sqrt(-1) = 2^((p-1)/4).
	var e2 := PackedByteArray()
	e2.resize(32)
	for i in range(32):
		e2[i] = 0xFF
	e2[0] = 0xFB  # (p-1)/4 = 2^253-5: low byte 0xFB
	e2[31] = 0x1F  # top byte 0x1F
	var two := _fe_one()
	two[0] = 2
	var sqrt_m1 := _fe_pow(two, e2)
	x = _fe_mul(x, sqrt_m1)
	if _fe_equal(_fe_sq(x), u):
		return [x]
	return []

# d = -121665/121666 mod p, computed at runtime (no transcription).
static func _d() -> Array[int]:
	var n := _fe_zero()
	n[0] = 121665
	var d := _fe_zero()
	d[0] = 121666
	return _fe_mul(_fe_neg(n), _fe_invert(d))

# ------------------------------------------------------------- SHA-512
# 64-bit words as (hi, lo) 32-bit pairs; all values stay non-negative.
const _K_HI: Array[int] = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, 0xca273ece, 0xd186b8c7, 0xeada7dd6, 0xf57d4f7f, 0x06f067aa, 0x0a637dc5, 0x113f9804, 0x1b710b35, 0x28db77f5, 0x32caab7b, 0x3c9ebe0a, 0x431d67c4, 0x4cc5d4be, 0x597f299c, 0x5fcb6fab, 0x6c44198c]
const _K_LO: Array[int] = [0xd728ae22, 0x23ef65cd, 0xec4d3b2f, 0x8189dbbc, 0xf348b538, 0xb605d019, 0xaf194f9b, 0xda6d8118, 0xa3030242, 0x45706fbe, 0x4ee4b28c, 0xd5ffb4e2, 0xf27b896f, 0x3b1696b1, 0x25c71235, 0xcf692694, 0x9ef14ad2, 0x384f25e3, 0x8b8cd5b5, 0x77ac9c65, 0x592b0275, 0x6ea6e483, 0xbd41fbd4, 0x831153b5, 0xee66dfab, 0x2db43210, 0x98fb213f, 0xbeef0ee4, 0x3da88fc2, 0x930aa725, 0xe003826f, 0x0a0e6e70, 0x46d22ffc, 0x5c26c926, 0x5ac42aed, 0x9d95b3df, 0x8baf63de, 0x3c77b2a8, 0x47edaee6, 0x1482353b, 0x4cf10364, 0xbc423001, 0xd0f89791, 0x0654be30, 0xd6ef5218, 0x5565a910, 0x5771202a, 0x32bbd1b8, 0xb8d2d0c8, 0x5141ab53, 0xdf8eeb99, 0xe19b48a8, 0xc5c95a63, 0xe3418acb, 0x7763e373, 0xd6b2b8a3, 0x5defb2fc, 0x43172f60, 0xa1f0ab72, 0x1a6439ec, 0x23631e28, 0xde82bde9, 0xb2c67915, 0xe372532b, 0xea26619c, 0x21c0c207, 0xcde0eb1e, 0xee6ed178, 0x72176fba, 0xa2c898a6, 0xbef90dae, 0x131c471b, 0x23047d84, 0x40c72493, 0x15c9bebc, 0x9c100d4c, 0xcb3e42b6, 0xfc657e2a, 0x3ad6faec, 0x4a475817]

static func _rotr64(hi: int, lo: int, n: int) -> Array[int]:
	if n == 0:
		return [hi, lo]
	if n < 32:
		var nhi := (hi >> n) | ((lo << (32 - n)) & 0xFFFFFFFF)
		var nlo := (lo >> n) | ((hi << (32 - n)) & 0xFFFFFFFF)
		return [nhi & 0xFFFFFFFF, nlo & 0xFFFFFFFF]
	if n == 32:
		return [lo, hi]
	var m := n - 32
	var nhi := (lo >> m) | ((hi << (32 - m)) & 0xFFFFFFFF)
	var nlo := (hi >> m) | ((lo << (32 - m)) & 0xFFFFFFFF)
	return [nhi & 0xFFFFFFFF, nlo & 0xFFFFFFFF]

# SHR n of a 64-bit (hi, lo) word.
static func _shr64(hi: int, lo: int, n: int) -> Array[int]:
	if n == 0:
		return [hi, lo]
	if n < 32:
		return [hi >> n, (lo >> n) | ((hi << (32 - n)) & 0xFFFFFFFF)]
	if n == 32:
		return [0, hi]
	return [0, hi >> (n - 32)]

static func _add64(a_hi: int, a_lo: int, b_hi: int, b_lo: int) -> Array[int]:
	var lo := a_lo + b_lo
	var carry := lo >> 32
	lo &= 0xFFFFFFFF
	var hi := (a_hi + b_hi + carry) & 0xFFFFFFFF
	return [hi, lo]

static func _xor64(a: Array[int], b: Array[int]) -> Array[int]:
	return [a[0] ^ b[0], a[1] ^ b[1]]

static func sha512(data: PackedByteArray) -> PackedByteArray:
	var h_hi: Array[int] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
	var h_lo: Array[int] = [0xf3bcc908, 0x84caa73b, 0xfe94f82b, 0x5f1d36f1, 0xade682d1, 0x2b3e6c1f, 0xfb41bd6b, 0x137e2179]
	var msg := data.duplicate()
	var bitlen := data.size() * 8
	msg.append(0x80)
	while (msg.size() % 128) != 112:
		msg.append(0)
	for _i in range(8):
		msg.append(0)
	for i in range(8):
		msg.append((bitlen >> (56 - 8 * i)) & 0xFF)
	var blocks := msg.size() / 128
	for b in range(blocks):
		var w_hi: Array[int] = []
		var w_lo: Array[int] = []
		w_hi.resize(80)
		w_lo.resize(80)
		for t in range(16):
			var o := b * 128 + t * 8
			w_hi[t] = (int(msg[o]) << 24) | (int(msg[o + 1]) << 16) | (int(msg[o + 2]) << 8) | int(msg[o + 3])
			w_lo[t] = (int(msg[o + 4]) << 24) | (int(msg[o + 5]) << 16) | (int(msg[o + 6]) << 8) | int(msg[o + 7])
		for t in range(16, 80):
			var s0 := _xor64(_xor64(_rotr64(w_hi[t - 15], w_lo[t - 15], 1), _rotr64(w_hi[t - 15], w_lo[t - 15], 8)), _shr64(w_hi[t - 15], w_lo[t - 15], 7))
			var s1 := _xor64(_xor64(_rotr64(w_hi[t - 2], w_lo[t - 2], 19), _rotr64(w_hi[t - 2], w_lo[t - 2], 61)), _shr64(w_hi[t - 2], w_lo[t - 2], 6))
			var tmp := _add64(w_hi[t - 16], w_lo[t - 16], s0[0], s0[1])
			tmp = _add64(tmp[0], tmp[1], w_hi[t - 7], w_lo[t - 7])
			tmp = _add64(tmp[0], tmp[1], s1[0], s1[1])
			w_hi[t] = tmp[0]
			w_lo[t] = tmp[1]
		var a_hi := h_hi[0]; var a_lo := h_lo[0]
		var b_hi := h_hi[1]; var b_lo := h_lo[1]
		var c_hi := h_hi[2]; var c_lo := h_lo[2]
		var d_hi := h_hi[3]; var d_lo := h_lo[3]
		var e_hi := h_hi[4]; var e_lo := h_lo[4]
		var f_hi := h_hi[5]; var f_lo := h_lo[5]
		var g_hi := h_hi[6]; var g_lo := h_lo[6]
		var hh_hi := h_hi[7]; var hh_lo := h_lo[7]
		for t in range(80):
			var big_s1 := _xor64(_xor64(_rotr64(e_hi, e_lo, 14), _rotr64(e_hi, e_lo, 18)), _rotr64(e_hi, e_lo, 41))
			var ch := [(e_hi & f_hi) ^ ((~e_hi & 0xFFFFFFFF) & g_hi), (e_lo & f_lo) ^ ((~e_lo & 0xFFFFFFFF) & g_lo)]
			var t1 := _add64(hh_hi, hh_lo, big_s1[0], big_s1[1])
			t1 = _add64(t1[0], t1[1], ch[0], ch[1])
			t1 = _add64(t1[0], t1[1], _K_HI[t], _K_LO[t])
			t1 = _add64(t1[0], t1[1], w_hi[t], w_lo[t])
			var big_s0 := _xor64(_xor64(_rotr64(a_hi, a_lo, 28), _rotr64(a_hi, a_lo, 34)), _rotr64(a_hi, a_lo, 39))
			var maj := [(a_hi & b_hi) ^ (a_hi & c_hi) ^ (b_hi & c_hi), (a_lo & b_lo) ^ (a_lo & c_lo) ^ (b_lo & c_lo)]
			var t2 := _add64(big_s0[0], big_s0[1], maj[0], maj[1])
			hh_hi = g_hi; hh_lo = g_lo
			g_hi = f_hi; g_lo = f_lo
			f_hi = e_hi; f_lo = e_lo
			var ne := _add64(d_hi, d_lo, t1[0], t1[1])
			e_hi = ne[0]; e_lo = ne[1]
			d_hi = c_hi; d_lo = c_lo
			c_hi = b_hi; c_lo = b_lo
			b_hi = a_hi; b_lo = a_lo
			var na := _add64(t1[0], t1[1], t2[0], t2[1])
			a_hi = na[0]; a_lo = na[1]
		var nh0 := _add64(h_hi[0], h_lo[0], a_hi, a_lo)
		var nh1 := _add64(h_hi[1], h_lo[1], b_hi, b_lo)
		var nh2 := _add64(h_hi[2], h_lo[2], c_hi, c_lo)
		var nh3 := _add64(h_hi[3], h_lo[3], d_hi, d_lo)
		var nh4 := _add64(h_hi[4], h_lo[4], e_hi, e_lo)
		var nh5 := _add64(h_hi[5], h_lo[5], f_hi, f_lo)
		var nh6 := _add64(h_hi[6], h_lo[6], g_hi, g_lo)
		var nh7 := _add64(h_hi[7], h_lo[7], hh_hi, hh_lo)
		h_hi = [nh0[0], nh1[0], nh2[0], nh3[0], nh4[0], nh5[0], nh6[0], nh7[0]]
		h_lo = [nh0[1], nh1[1], nh2[1], nh3[1], nh4[1], nh5[1], nh6[1], nh7[1]]
	var out := PackedByteArray()
	out.resize(64)
	for i in range(8):
		out[i * 8 + 0] = (h_hi[i] >> 24) & 0xFF
		out[i * 8 + 1] = (h_hi[i] >> 16) & 0xFF
		out[i * 8 + 2] = (h_hi[i] >> 8) & 0xFF
		out[i * 8 + 3] = h_hi[i] & 0xFF
		out[i * 8 + 4] = (h_lo[i] >> 24) & 0xFF
		out[i * 8 + 5] = (h_lo[i] >> 16) & 0xFF
		out[i * 8 + 6] = (h_lo[i] >> 8) & 0xFF
		out[i * 8 + 7] = h_lo[i] & 0xFF
	return out

# ------------------------------------------------------------- points
# Extended coordinates (X, Y, Z, T) with X = x*Z, Y = y*Z, T = x*y*Z.
# A point is Array[Array[int]] of 4 field elements.

static func _pt_identity() -> Array:
	return [_fe_zero(), _fe_one(), _fe_one(), _fe_zero()]

static func _pt_add(p: Array, q: Array) -> Array:
	var d := _d()
	var a := _fe_mul(_fe_sub(p[1], p[0]), _fe_sub(q[1], q[0]))
	var b := _fe_mul(_fe_add(p[1], p[0]), _fe_add(q[1], q[0]))
	var c := _fe_mul(_fe_mul(p[3], q[3]), _fe_mul_small(d, 2))
	var dd := _fe_mul_small(_fe_mul(p[2], q[2]), 2)
	var e := _fe_sub(b, a)
	var f := _fe_sub(dd, c)
	var g := _fe_add(dd, c)
	var h := _fe_add(b, a)
	return [_fe_mul(e, f), _fe_mul(g, h), _fe_mul(f, g), _fe_mul(e, h)]

static func _pt_double(p: Array) -> Array:
	var a := _fe_sq(p[0])
	var b := _fe_sq(p[1])
	var c := _fe_mul_small(_fe_sq(p[2]), 2)
	var dd := _fe_neg(a)
	var e := _fe_sub(_fe_sub(_fe_sq(_fe_add(p[0], p[1])), a), b)
	var g := _fe_add(dd, b)
	var f := _fe_sub(g, c)
	var h := _fe_sub(dd, b)
	return [_fe_mul(e, f), _fe_mul(g, h), _fe_mul(f, g), _fe_mul(e, h)]

# Scalar mult by a 32-byte little-endian scalar (double-and-add, MSB first).
static func _pt_scalarmult(scalar: PackedByteArray, pt: Array) -> Array:
	var r := _pt_identity()
	for i in range(255, -1, -1):
		r = _pt_double(r)
		if (scalar[i / 8] >> (i % 8)) & 1:
			r = _pt_add(r, pt)
	return r

static func _pt_encode(pt: Array) -> PackedByteArray:
	var zinv := _fe_invert(pt[2])
	var x := _fe_mul(pt[0], zinv)
	var y := _fe_mul(pt[1], zinv)
	var out := _fe_to_bytes(y)
	if _fe_is_odd(x):
		out[31] |= 0x80
	return out

static func _base_point() -> Array:
	# By = 4/5, Bx = sqrt((By^2-1)/(d*By^2+1)), sign +.
	var four := _fe_zero()
	four[0] = 4
	var five := _fe_zero()
	five[0] = 5
	var by := _fe_mul(four, _fe_invert(five))
	var d := _d()
	var u := _fe_sub(_fe_sq(by), _fe_one())
	# v = d*By^2 + 1
	var v := _fe_add(_fe_mul(d, _fe_sq(by)), _fe_one())
	var xx := _fe_mul(u, _fe_invert(v))
	var sq := _fe_sqrt(xx)
	if sq.is_empty():
		return []
	var bx: Array[int] = sq[0]
	if _fe_is_odd(bx):
		bx = _fe_neg(bx)
	var t := _fe_mul(bx, by)
	return [bx, by, _fe_one(), t]

# Decode a 32-byte compressed point. Returns [] on failure.
static func _pt_decode(b: PackedByteArray) -> Array:
	if b.size() != 32:
		return []
	var sign := (b[31] >> 7) & 1
	var yb := b.duplicate()
	yb[31] &= 0x7F
	var y := _fe_from_bytes(yb)
	var d := _d()
	var u := _fe_sub(_fe_sq(y), _fe_one())
	var v := _fe_add(_fe_mul(d, _fe_sq(y)), _fe_one())
	var xx := _fe_mul(u, _fe_invert(v))
	var sq := _fe_sqrt(xx)
	if sq.is_empty():
		return []
	var x: Array[int] = sq[0]
	if _fe_is_odd(x) != (sign == 1):
		x = _fe_neg(x)
	# Reject x == 0 with sign set, and verify the point is on the curve:
	# -x^2 + y^2 == 1 + d*x^2*y^2.
	if _fe_is_zero(x) and sign == 1:
		return []
	var x2 := _fe_sq(x)
	var y2 := _fe_sq(y)
	var lhs := _fe_sub(y2, x2)
	var rhs := _fe_add(_fe_one(), _fe_mul(_fe_mul(d, x2), y2))
	if not _fe_equal(lhs, rhs):
		return []
	var t := _fe_mul(x, y)
	return [x, y, _fe_one(), t]

# ------------------------------------------------------------- scalars
# L = 2^252 + 27742317777372353535851937790883648493, little-endian bytes.
static func _l_bytes() -> PackedByteArray:
	return PackedByteArray([0xED, 0xD3, 0xF5, 0x5C, 0x1A, 0x63, 0x12, 0x58, 0xD6, 0x9C, 0xF7, 0xA2, 0xDE, 0xF9, 0xDE, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10])

static func _scalar_lt_l(s: PackedByteArray) -> bool:
	var l := _l_bytes()
	for i in range(31, -1, -1):
		if s[i] != l[i]:
			return s[i] < l[i]
	return false  # equal -> not less

# Reduce a 64-byte little-endian integer mod L (shift-and-subtract;
# simple and obviously correct; runs once per verify).
static func _scalar_mod_l(h: PackedByteArray) -> PackedByteArray:
	# limbs of 26 bits, little-endian
	var n := (h.size() * 8 + 25) / 26
	var limbs: Array[int] = []
	limbs.resize(n)
	var acc := 0
	var acc_bits := 0
	var li := 0
	for i in range(h.size()):
		acc |= int(h[i]) << acc_bits
		acc_bits += 8
		while acc_bits >= 26 and li < n:
			limbs[li] = acc & MASK26
			acc >>= 26
			acc_bits -= 26
			li += 1
	if li < n:
		limbs[li] = acc & MASK26
	var lbytes := _l_bytes()
	var llimbs: Array[int] = []
	llimbs.resize(10)
	acc = 0
	acc_bits = 0
	li = 0
	for i in range(32):
		acc |= int(lbytes[i]) << acc_bits
		acc_bits += 8
		while acc_bits >= 26 and li < 10:
			llimbs[li] = acc & MASK26
			acc >>= 26
			acc_bits -= 26
			li += 1
	if li < 10:
		llimbs[li] = acc & MASK26
	# bit length of the value
	var top := n - 1
	while top > 0 and limbs[top] == 0:
		top -= 1
	var bits := top * 26
	var t := limbs[top]
	while t > 0:
		bits += 1
		t >>= 1
	# L is 253 bits; shift L left by (bits-253) down to 0.
	for shift in range(bits - 253, -1, -1):
		# shifted L limbs
		var sh: Array[int] = []
		sh.resize(n)
		var limb_shift := shift / 26
		var bit_shift := shift % 26
		for i in range(10):
			var v := llimbs[i] << bit_shift
			sh[i + limb_shift] |= v & MASK26
			if i + limb_shift + 1 < n:
				sh[i + limb_shift + 1] |= v >> 26
		# compare limbs >= sh ?
		var ge := true
		for i in range(n - 1, -1, -1):
			if limbs[i] != sh[i]:
				ge = limbs[i] > sh[i]
				break
		if ge:
			var borrow := 0
			for i in range(n):
				var v := limbs[i] - sh[i] - borrow
				if v < 0:
					v += 1 << 26
					borrow = 1
				else:
					borrow = 0
				limbs[i] = v
	var out := PackedByteArray()
	out.resize(32)
	acc = 0
	acc_bits = 0
	li = 0
	for i in range(32):
		while acc_bits < 8:
			acc |= limbs[li] << acc_bits
			acc_bits += 26
			li += 1
		out[i] = acc & 0xFF
		acc >>= 8
		acc_bits -= 8
	return out

# ------------------------------------------------------------- verify
## Verify an Ed25519 signature. pubkey_b58 is the base58 address,
## message the raw bytes that were signed, sig_b64 the base64 signature
## as returned by the wallet. Returns false on any malformed input.
static func verify(pubkey_b58: String, message: PackedByteArray, sig_b64: String) -> bool:
	var sig := Marshalls.base64_to_raw(sig_b64)
	if sig.size() != 64:
		return false
	var pub := SolanaUtils.bs58_decode(pubkey_b58)
	if pub.size() != 32:
		return false
	var r_bytes := sig.slice(0, 32)
	var s_bytes := sig.slice(32, 64)
	if not _scalar_lt_l(s_bytes):
		return false
	var a_pt := _pt_decode(pub)
	if a_pt.is_empty():
		return false
	var r_pt := _pt_decode(r_bytes)
	if r_pt.is_empty():
		return false
	var h_input := r_bytes + pub + message
	var h := sha512(h_input)
	var h_scalar := _scalar_mod_l(h)
	var b_pt := _base_point()
	if b_pt.is_empty():
		return false
	var left := _pt_scalarmult(s_bytes, b_pt)
	var right := _pt_add(r_pt, _pt_scalarmult(h_scalar, a_pt))
	return _pt_encode(left) == _pt_encode(right)
