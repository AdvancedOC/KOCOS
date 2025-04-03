local deflate = require("tools.LibDeflate")

local input = io.stdin:read("a")

local compressed = deflate:CompressDeflate(input)
assert(compressed, "LibDeflate failed bruh")

assert(deflate:DecompressDeflate(compressed) == input, "bad deflate")

local out = ""

do
    local nesting = 0
    while string.find(compressed, "]" .. string.rep("=", nesting) .. "]", nil, true) do
        nesting = nesting + 1
    end

    local rep = string.rep("=", nesting)

    --out = "local s=[" .. rep .. "[" .. compressed .. "]" .. rep .. "]"
    out = string.format("local s=%q", compressed)
end

-- Taken from https://github.com/SafeteeWoW/LibDeflate/blob/main/LibDeflate.lua, gonna be code-golfed

local decomp = [========[
local _rle_codes_huffman_bitlen_order = {
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
}

_reverse_bits_tbl = {}

for i = 1, 9 do
  _reverse_bits_tbl[i] = {}
  for j = 0, 2 ^ (i + 1) - 1 do
    local reverse = 0
    local value = j
    for _ = 1, i do
      -- The following line is equivalent to "res | (code %2)" in C.
      reverse = reverse - reverse % 2 +
                  (((reverse % 2 == 1) or (value % 2) == 1) and 1 or 0)
      value = (value - value % 2) / 2
      reverse = reverse * 2
    end
    _reverse_bits_tbl[i][j] = (reverse - reverse % 2) / 2
  end
end

local _literal_deflate_code_to_base_len =
{
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
    83, 99, 115, 131, 163, 195, 227, 258
}

local _dist_deflate_code_to_base_dist = {
    [0] = 1,
    2,
    3,
    4,
    5,
    7,
    9,
    13,
    17,
    25,
    33,
    49,
    65,
    97,
    129,
    193,
    257,
    385,
    513,
    769,
    1025,
    1537,
    2049,
    3073,
    4097,
    6145,
    8193,
    12289,
    16385,
    24577
}

local _dist_deflate_code_to_extra_bitlen =
{
    [0] = 0,
    0,
    0,
    0,
    1,
    1,
    2,
    2,
    3,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    8,
    9,
    9,
    10,
    10,
    11,
    11,
    12,
    12,
    13,
    13
}

local _literal_deflate_code_to_extra_bitlen =
  {
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5,
    5, 5, 5, 0
  }

local function CreateReader(input_string)
  local input = input_string
  local input_strlen = #input_string
  local input_next_byte_pos = 1
  local cache_bitlen = 0
  local cache = 0

  -- Read some bits.
  -- To improve speed, this function does not
  -- check if the input has been exhausted.
  -- Use ReaderBitlenLeft() < 0 to check it.
  -- @param bitlen the number of bits to read
  -- @return the data is read.
  local function ReadBits(bitlen)
    local rshift_mask = 2^bitlen
    local code
    if bitlen <= cache_bitlen then
      code = cache % rshift_mask
      cache = (cache - code) / rshift_mask
      cache_bitlen = cache_bitlen - bitlen
    else -- Whether input has been exhausted is not checked.
      local lshift_mask = 2^cache_bitlen
      local byte1, byte2, byte3, byte4 =
        string.byte(input, input_next_byte_pos, input_next_byte_pos + 3)
      -- This requires lua number to be at least double ()
      cache = cache +
                ((byte1 or 0) + (byte2 or 0) * 256 + (byte3 or 0) * 65536 +
                  (byte4 or 0) * 16777216) * lshift_mask
      input_next_byte_pos = input_next_byte_pos + 4
      cache_bitlen = cache_bitlen + 32 - bitlen
      code = cache % rshift_mask
      cache = (cache - code) / rshift_mask
    end
    return code
  end

  -- Read some bytes from the reader.
  -- Assume reader is on the byte boundary.
  -- @param bytelen The number of bytes to be read.
  -- @param buffer The byte read will be stored into this buffer.
  -- @param buffer_size The buffer will be modified starting from
  --	buffer[buffer_size+1], ending at buffer[buffer_size+bytelen-1]
  -- @return the new buffer_size
  local function ReadBytes(bytelen, buffer, buffer_size)
    assert(cache_bitlen % 8 == 0)

    local byte_from_cache =
      (cache_bitlen / 8 < bytelen) and (cache_bitlen / 8) or bytelen
    for _ = 1, byte_from_cache do
      local byte = cache % 256
      buffer_size = buffer_size + 1
      buffer[buffer_size] = string.char(byte)
      cache = (cache - byte) / 256
    end
    cache_bitlen = cache_bitlen - byte_from_cache * 8
    bytelen = bytelen - byte_from_cache
    if (input_strlen - input_next_byte_pos - bytelen + 1) * 8 + cache_bitlen < 0 then
      return -1 -- out of input
    end
    for i = input_next_byte_pos, input_next_byte_pos + bytelen - 1 do
      buffer_size = buffer_size + 1
      buffer[buffer_size] = string.sub(input, i, i)
    end

    input_next_byte_pos = input_next_byte_pos + bytelen
    return buffer_size
  end

  -- Decode huffman code
  -- To improve speed, this function does not check
  -- if the input has been exhausted.
  -- Use ReaderBitlenLeft() < 0 to check it.
  -- Credits for Mark Adler. This code is from puff:Decode()
  -- @see puff:Decode(...)
  -- @param huffman_bitlen_count
  -- @param huffman_symbol
  -- @param min_bitlen The minimum huffman bit length of all symbols
  -- @return The decoded deflate code.
  --	Negative value is returned if decoding fails.
  local function Decode(huffman_bitlen_counts, huffman_symbols, min_bitlen)
    local code = 0
    local first = 0
    local index = 0
    local count
    if min_bitlen > 0 then
      if cache_bitlen < 15 and input then
        local lshift_mask = 2^cache_bitlen
        local byte1, byte2, byte3, byte4 =
          string.byte(input, input_next_byte_pos, input_next_byte_pos + 3)
        -- This requires lua number to be at least double ()
        cache = cache +
                  ((byte1 or 0) + (byte2 or 0) * 256 + (byte3 or 0) * 65536 +
                    (byte4 or 0) * 16777216) * lshift_mask
        input_next_byte_pos = input_next_byte_pos + 4
        cache_bitlen = cache_bitlen + 32
      end

      local rshift_mask = 2^min_bitlen
      cache_bitlen = cache_bitlen - min_bitlen
      code = cache % rshift_mask
      cache = (cache - code) / rshift_mask
      -- Reverse the bits
      code = _reverse_bits_tbl[min_bitlen][code]

      count = huffman_bitlen_counts[min_bitlen]
      if code < count then return huffman_symbols[code] end
      index = count
      first = count * 2
      code = code * 2
    end

    for bitlen = min_bitlen + 1, 15 do
      local bit
      bit = cache % 2
      cache = (cache - bit) / 2
      cache_bitlen = cache_bitlen - 1

      code = (bit == 1) and (code + 1 - code % 2) or code
      count = huffman_bitlen_counts[bitlen] or 0
      local diff = code - first
      if diff < count then return huffman_symbols[index + diff] end
      index = index + count
      first = first + count
      first = first * 2
      code = code * 2
    end
    -- invalid literal/length or distance code
    -- in fixed or dynamic block (run out of code)
    return -10
  end

  local function ReaderBitlenLeft()
    return (input_strlen - input_next_byte_pos + 1) * 8 + cache_bitlen
  end

  local function SkipToByteBoundary()
    local skipped_bitlen = cache_bitlen % 8
    local rshift_mask = 2^skipped_bitlen
    cache_bitlen = cache_bitlen - skipped_bitlen
    cache = (cache - cache % rshift_mask) / rshift_mask
  end

  return ReadBits, ReadBytes, Decode, ReaderBitlenLeft, SkipToByteBoundary
end

-- Create a deflate state, so I can pass in less arguments to functions.
-- @param str the whole string to be decompressed.
-- @param dictionary The preset dictionary. nil if not provided.
--		This dictionary should be produced by LibDeflate:CreateDictionary(str)
-- @return The decomrpess state.
local function CreateDecompressState(str, dictionary)
  local ReadBits, ReadBytes, Decode, ReaderBitlenLeft, SkipToByteBoundary =
    CreateReader(str)
  local state = {
    ReadBits = ReadBits,
    ReadBytes = ReadBytes,
    Decode = Decode,
    ReaderBitlenLeft = ReaderBitlenLeft,
    SkipToByteBoundary = SkipToByteBoundary,
    buffer_size = 0,
    buffer = {},
    result_buffer = {},
    dictionary = dictionary
  }
  return state
end

-- Get the stuffs needed to decode huffman codes
-- @see puff.c:construct(...)
-- @param huffman_bitlen The huffman bit length of the huffman codes.
-- @param max_symbol The maximum symbol
-- @param max_bitlen The min huffman bit length of all codes
-- @return zero or positive for success, negative for failure.
-- @return The count of each huffman bit length.
-- @return A table to convert huffman codes to deflate codes.
-- @return The minimum huffman bit length.
local function GetHuffmanForDecode(huffman_bitlens, max_symbol, max_bitlen)
  local huffman_bitlen_counts = {}
  local min_bitlen = max_bitlen
  for symbol = 0, max_symbol do
    local bitlen = huffman_bitlens[symbol] or 0
    min_bitlen = (bitlen > 0 and bitlen < min_bitlen) and bitlen or min_bitlen
    huffman_bitlen_counts[bitlen] = (huffman_bitlen_counts[bitlen] or 0) + 1
  end

  if huffman_bitlen_counts[0] == max_symbol + 1 then -- No Codes
    return 0, huffman_bitlen_counts, {}, 0 -- Complete, but decode will fail
  end

  local left = 1
  for len = 1, max_bitlen do
    left = left * 2
    left = left - (huffman_bitlen_counts[len] or 0)
    if left < 0 then
      return left -- Over-subscribed, return negative
    end
  end

  -- Generate offsets info symbol table for each length for sorting
  local offsets = {}
  offsets[1] = 0
  for len = 1, max_bitlen - 1 do
    offsets[len + 1] = offsets[len] + (huffman_bitlen_counts[len] or 0)
  end

  local huffman_symbols = {}
  for symbol = 0, max_symbol do
    local bitlen = huffman_bitlens[symbol] or 0
    if bitlen ~= 0 then
      local offset = offsets[bitlen]
      huffman_symbols[offset] = symbol
      offsets[bitlen] = offsets[bitlen] + 1
    end
  end

  -- Return zero for complete set, positive for incomplete set.
  return left, huffman_bitlen_counts, huffman_symbols, min_bitlen
end

-- Decode a fixed or dynamic huffman blocks, excluding last block identifier
-- and block type identifer.
-- @see puff.c:codes()
-- @param state decompression state that will be modified by this function.
--	@see CreateDecompressState
-- @param ... Read the source code
-- @return 0 on success, other value on failure.
local function DecodeUntilEndOfBlock(state, lcodes_huffman_bitlens,
                                     lcodes_huffman_symbols,
                                     lcodes_huffman_min_bitlen,
                                     dcodes_huffman_bitlens,
                                     dcodes_huffman_symbols,
                                     dcodes_huffman_min_bitlen)
  local buffer, buffer_size, ReadBits, Decode, ReaderBitlenLeft, result_buffer =
    state.buffer, state.buffer_size, state.ReadBits, state.Decode,
    state.ReaderBitlenLeft, state.result_buffer
  local dictionary = state.dictionary
  local dict_string_table
  local dict_strlen

  local buffer_end = 1
  if dictionary and not buffer[0] then
    -- If there is a dictionary, copy the last 258 bytes into
    -- the string_table to make the copy in the main loop quicker.
    -- This is done only once per decompression.
    dict_string_table = dictionary.string_table
    dict_strlen = dictionary.strlen
    buffer_end = -dict_strlen + 1
    for i = 0, (-dict_strlen + 1) < -257 and -257 or (-dict_strlen + 1), -1 do
      buffer[i] = string.char(dict_string_table[dict_strlen + i])
    end
  end

  repeat
    local symbol = Decode(lcodes_huffman_bitlens, lcodes_huffman_symbols,
                          lcodes_huffman_min_bitlen)
    if symbol < 0 or symbol > 285 then
      -- invalid literal/length or distance code in fixed or dynamic block
      return -10
    elseif symbol < 256 then -- Literal
      buffer_size = buffer_size + 1
      buffer[buffer_size] = string.char(symbol)
    elseif symbol > 256 then -- Length code
      symbol = symbol - 256
      local bitlen = _literal_deflate_code_to_base_len[symbol]
      bitlen = (symbol >= 8) and
                 (bitlen +
                   ReadBits(_literal_deflate_code_to_extra_bitlen[symbol])) or
                 bitlen
      symbol = Decode(dcodes_huffman_bitlens, dcodes_huffman_symbols,
                      dcodes_huffman_min_bitlen)
      if symbol < 0 or symbol > 29 then
        -- invalid literal/length or distance code in fixed or dynamic block
        return -10
      end
      local dist = _dist_deflate_code_to_base_dist[symbol]
      dist = (dist > 4) and
               (dist + ReadBits(_dist_deflate_code_to_extra_bitlen[symbol])) or
               dist

      local char_buffer_index = buffer_size - dist + 1
      if char_buffer_index < buffer_end then
        -- distance is too far back in fixed or dynamic block
        return -11
      end
      if char_buffer_index >= -257 then
        for _ = 1, bitlen do
          buffer_size = buffer_size + 1
          buffer[buffer_size] = buffer[char_buffer_index]
          char_buffer_index = char_buffer_index + 1
        end
      else
        char_buffer_index = dict_strlen + char_buffer_index
        for _ = 1, bitlen do
          buffer_size = buffer_size + 1
          buffer[buffer_size] =
            _byte_to_char[dict_string_table[char_buffer_index]]
          char_buffer_index = char_buffer_index + 1
        end
      end
    end

    if ReaderBitlenLeft() < 0 then
      return 2 -- available inflate data did not terminate
    end

    if buffer_size >= 65536 then
      result_buffer[#result_buffer + 1] = table.concat(buffer, "", 1, 32768)
      for i = 32769, buffer_size do buffer[i - 32768] = buffer[i] end
      buffer_size = buffer_size - 32768
      buffer[buffer_size + 1] = nil
      -- NOTE: buffer[32769..end] and buffer[-257..0] are not cleared.
      -- This is why "buffer_size" variable is needed.
    end
  until symbol == 256

  state.buffer_size = buffer_size

  return 0
end

-- Decompress a store block
-- @param state decompression state that will be modified by this function.
-- @return 0 if succeeds, other value if fails.
local function DecompressStoreBlock(state)
  local buffer, buffer_size, ReadBits, ReadBytes, ReaderBitlenLeft,
        SkipToByteBoundary, result_buffer = state.buffer, state.buffer_size,
                                            state.ReadBits, state.ReadBytes,
                                            state.ReaderBitlenLeft,
                                            state.SkipToByteBoundary,
                                            state.result_buffer

  SkipToByteBoundary()
  local bytelen = ReadBits(16)
  if ReaderBitlenLeft() < 0 then
    return 2 -- available inflate data did not terminate
  end
  local bytelenComp = ReadBits(16)
  if ReaderBitlenLeft() < 0 then
    return 2 -- available inflate data did not terminate
  end

  if bytelen % 256 + bytelenComp % 256 ~= 255 then
    return -2 -- Not one's complement
  end
  if (bytelen - bytelen % 256) / 256 + (bytelenComp - bytelenComp % 256) / 256 ~=
    255 then
    return -2 -- Not one's complement
  end

  -- Note that ReadBytes will skip to the next byte boundary first.
  buffer_size = ReadBytes(bytelen, buffer, buffer_size)
  if buffer_size < 0 then
    return 2 -- available inflate data did not terminate
  end

  -- memory clean up when there are enough bytes in the buffer.
  if buffer_size >= 65536 then
    result_buffer[#result_buffer + 1] = table.concat(buffer, "", 1, 32768)
    for i = 32769, buffer_size do buffer[i - 32768] = buffer[i] end
    buffer_size = buffer_size - 32768
    buffer[buffer_size + 1] = nil
  end
  state.buffer_size = buffer_size
  return 0
end

-- Decompress a fixed block
-- @param state decompression state that will be modified by this function.
-- @return 0 if succeeds other value if fails.
local function DecompressFixBlock(state)
  return DecodeUntilEndOfBlock(state, _fix_block_literal_huffman_bitlen_count,
                               _fix_block_literal_huffman_to_deflate_code, 7,
                               _fix_block_dist_huffman_bitlen_count,
                               _fix_block_dist_huffman_to_deflate_code, 5)
end

-- Decompress a dynamic block
-- @param state decompression state that will be modified by this function.
-- @return 0 if success, other value if fails.
local function DecompressDynamicBlock(state)
  local ReadBits, Decode = state.ReadBits, state.Decode
  local nlen = ReadBits(5) + 257
  local ndist = ReadBits(5) + 1
  local ncode = ReadBits(4) + 4
  if nlen > 286 or ndist > 30 then
    -- dynamic block code description: too many length or distance codes
    return -3
  end

  local rle_codes_huffman_bitlens = {}

  for i = 1, ncode do
    rle_codes_huffman_bitlens[_rle_codes_huffman_bitlen_order[i]] = ReadBits(3)
  end

  local rle_codes_err, rle_codes_huffman_bitlen_counts,
        rle_codes_huffman_symbols, rle_codes_huffman_min_bitlen =
    GetHuffmanForDecode(rle_codes_huffman_bitlens, 18, 7)
  if rle_codes_err ~= 0 then -- Require complete code set here
    -- dynamic block code description: code lengths codes incomplete
    return -4
  end

  local lcodes_huffman_bitlens = {}
  local dcodes_huffman_bitlens = {}
  -- Read length/literal and distance code length tables
  local index = 0
  while index < nlen + ndist do
    local symbol -- Decoded value
    local bitlen -- Last length to repeat

    symbol = Decode(rle_codes_huffman_bitlen_counts, rle_codes_huffman_symbols,
                    rle_codes_huffman_min_bitlen)

    if symbol < 0 then
      return symbol -- Invalid symbol
    elseif symbol < 16 then
      if index < nlen then
        lcodes_huffman_bitlens[index] = symbol
      else
        dcodes_huffman_bitlens[index - nlen] = symbol
      end
      index = index + 1
    else
      bitlen = 0
      if symbol == 16 then
        if index == 0 then
          -- dynamic block code description: repeat lengths
          -- with no first length
          return -5
        end
        if index - 1 < nlen then
          bitlen = lcodes_huffman_bitlens[index - 1]
        else
          bitlen = dcodes_huffman_bitlens[index - nlen - 1]
        end
        symbol = 3 + ReadBits(2)
      elseif symbol == 17 then -- Repeat zero 3..10 times
        symbol = 3 + ReadBits(3)
      else -- == 18, repeat zero 11.138 times
        symbol = 11 + ReadBits(7)
      end
      if index + symbol > nlen + ndist then
        -- dynamic block code description:
        -- repeat more than specified lengths
        return -6
      end
      while symbol > 0 do -- Repeat last or zero symbol times
        symbol = symbol - 1
        if index < nlen then
          lcodes_huffman_bitlens[index] = bitlen
        else
          dcodes_huffman_bitlens[index - nlen] = bitlen
        end
        index = index + 1
      end
    end
  end

  if (lcodes_huffman_bitlens[256] or 0) == 0 then
    -- dynamic block code description: missing end-of-block code
    return -9
  end

  local lcodes_err, lcodes_huffman_bitlen_counts, lcodes_huffman_symbols,
        lcodes_huffman_min_bitlen = GetHuffmanForDecode(lcodes_huffman_bitlens,
                                                        nlen - 1, 15)
  -- dynamic block code description: invalid literal/length code lengths,
  -- Incomplete code ok only for single length 1 code
  if (lcodes_err ~= 0 and
    (lcodes_err < 0 or nlen ~= (lcodes_huffman_bitlen_counts[0] or 0) +
      (lcodes_huffman_bitlen_counts[1] or 0))) then return -7 end

  local dcodes_err, dcodes_huffman_bitlen_counts, dcodes_huffman_symbols,
        dcodes_huffman_min_bitlen = GetHuffmanForDecode(dcodes_huffman_bitlens,
                                                        ndist - 1, 15)
  -- dynamic block code description: invalid distance code lengths,
  -- Incomplete code ok only for single length 1 code
  if (dcodes_err ~= 0 and
    (dcodes_err < 0 or ndist ~= (dcodes_huffman_bitlen_counts[0] or 0) +
      (dcodes_huffman_bitlen_counts[1] or 0))) then return -8 end

  -- Build buffman table for literal/length codes
  return DecodeUntilEndOfBlock(state, lcodes_huffman_bitlen_counts,
                               lcodes_huffman_symbols,
                               lcodes_huffman_min_bitlen,
                               dcodes_huffman_bitlen_counts,
                               dcodes_huffman_symbols, dcodes_huffman_min_bitlen)
end

-- Decompress a deflate stream
-- @param state: a decompression state
-- @return the decompressed string if succeeds. nil if fails.
local function Inflate(state)
  local ReadBits = state.ReadBits

  local is_last_block
  while not is_last_block do
    is_last_block = (ReadBits(1) == 1)
    local block_type = ReadBits(2)
    local status
    if block_type == 0 then
      status = DecompressStoreBlock(state)
    elseif block_type == 1 then
      status = DecompressFixBlock(state)
    elseif block_type == 2 then
      status = DecompressDynamicBlock(state)
    else
      return nil, -1 -- invalid block type (type == 3)
    end
    if status ~= 0 then return nil, status end
  end

  state.result_buffer[#state.result_buffer + 1] =
    table.concat(state.buffer, "", 1, state.buffer_size)
  local result = table.concat(state.result_buffer)
  return result
end

-- @see LibDeflate:DecompressDeflate(str)
-- @see LibDeflate:DecompressDeflateWithDict(str, dictionary)
local function DecompressDeflateInternal(str, dictionary)
  local state = CreateDecompressState(str, dictionary)
  local result, status = Inflate(state)
  if not result then return nil, status end

  local bitlen_left = state.ReaderBitlenLeft()
  local bytelen_left = (bitlen_left - bitlen_left % 8) / 8
  return result, bytelen_left
end

local code = assert(DecompressDeflateInternal(s), "decompress failed bruh")
assert(load(code, "=decompressed"))(...)
]========]

out = out .. "\n" .. decomp

print(out)
