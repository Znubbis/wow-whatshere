local ffi = require("ffi")
local bit = require("bit")
ffi.cdef[[
typedef struct z_stream_s { const unsigned char *next_in; unsigned avail_in; unsigned long total_in;
  unsigned char *next_out; unsigned avail_out; unsigned long total_out; const char *msg; void *state;
  void *zalloc; void *zfree; void *opaque; int data_type; unsigned long adler; unsigned long reserved; } z_stream;
int inflateInit2_(z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(z_stream *strm, int flush); int inflateEnd(z_stream *strm); const char *zlibVersion(void);
]]
local z = ffi.load("z")
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local dec = {} for i = 1, 64 do dec[B64:byte(i)] = i - 1 end
local function DecodeBase64(s)
  local out, n, acc, bits = {}, 0, 0, 0
  for i = 1, #s do
    local v = dec[s:byte(i)]
    if v then
      acc = bit.bor(bit.lshift(acc, 6), v); bits = bits + 6
      if bits >= 8 then bits = bits - 8; n = n + 1; out[n] = string.char(bit.band(bit.rshift(acc, bits), 255)) end
      acc = bit.band(acc, 0xFFFF)
    end
  end
  return table.concat(out)
end
local function DecompressString(s, method)
  local wb = (method == 0) and -15 or 47 -- 0 = raw deflate, else zlib/gzip auto
  local strm = ffi.new("z_stream")
  assert(z.inflateInit2_(strm, wb, z.zlibVersion(), ffi.sizeof(strm)) == 0)
  strm.next_in, strm.avail_in = s, #s
  local chunks, buf = {}, ffi.new("unsigned char[?]", 65536)
  repeat
    strm.next_out, strm.avail_out = buf, 65536
    local r = z.inflate(strm, 0)
    chunks[#chunks + 1] = ffi.string(buf, 65536 - strm.avail_out)
    if r ~= 0 and r ~= 1 then z.inflateEnd(strm) error("inflate " .. r) end
  until r == 1
  z.inflateEnd(strm)
  return table.concat(chunks)
end
local function DeserializeCBOR(s)
  local pos = 1
  local function byte() local b = s:byte(pos); pos = pos + 1; return b end
  local function uint(n) local v = 0 for _ = 1, n do v = v * 256 + byte() end return v end
  local item
  local function arg(info)
    if info < 24 then return info elseif info == 24 then return uint(1) elseif info == 25 then return uint(2)
    elseif info == 26 then return uint(4) elseif info == 27 then return uint(8) end
    return nil -- indefinite
  end
  function item()
    local ib = byte(); local major, info = bit.rshift(ib, 5), bit.band(ib, 31)
    if major == 0 then return arg(info)
    elseif major == 1 then return -1 - arg(info)
    elseif major == 2 or major == 3 then local n = arg(info); local v = s:sub(pos, pos + n - 1); pos = pos + n; return v
    elseif major == 4 then local n = arg(info); local t = {}
      if n then for i = 1, n do t[i] = item() end else local i = 1 while s:byte(pos) ~= 0xFF do t[i] = item(); i = i + 1 end pos = pos + 1 end
      return t
    elseif major == 5 then local n = arg(info); local t = {}
      if n then for _ = 1, n do local k = item(); t[k] = item() end else while s:byte(pos) ~= 0xFF do local k = item(); t[k] = item() end pos = pos + 1 end
      return t
    elseif major == 6 then arg(info); return item()
    else
      if info == 20 then return false elseif info == 21 then return true elseif info == 22 or info == 23 then return nil
      elseif info == 25 then local h = uint(2); local e, m = bit.band(bit.rshift(h,10),31), bit.band(h,1023); local sgn = h >= 32768 and -1 or 1
        if e == 0 then return sgn * m * 2^-24 elseif e == 31 then return sgn * math.huge end return sgn * (1 + m/1024) * 2^(e-15)
      elseif info == 26 then local b = ffi.new("uint8_t[4]"); for i = 3, 0, -1 do b[i] = byte() end return ffi.cast("float*", b)[0]
      elseif info == 27 then local b = ffi.new("uint8_t[8]"); for i = 7, 0, -1 do b[i] = byte() end return ffi.cast("double*", b)[0] end
    end
  end
  return item()
end
C_EncodingUtil = { DecodeBase64 = DecodeBase64, DecompressString = DecompressString, DeserializeCBOR = DeserializeCBOR }
