-- Minimal JSON encoder for the snapshot (strings, numbers, booleans, arrays and objects).
-- A table with only 1..n keys (or no keys) is written as an array, anything else as an object
-- with sorted keys, so the same data always produces the same text.

local M = {};

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' };

local function str(s)
    return '"' .. s:gsub('[%c"\\]', function (c)
        return escapes[c] or ('\\u%04x'):format(c:byte());
    end) .. '"';
end

local function isArray(t)
    local n = 0;
    for _ in pairs(t) do n = n + 1; end
    for i = 1, n do if t[i] == nil then return false; end end
    return true;
end

local function encode(v, out)
    local kind = type(v);
    if kind == 'nil' then
        out[#out + 1] = 'null';
    elseif kind == 'boolean' then
        out[#out + 1] = v and 'true' or 'false';
    elseif kind == 'number' then
        out[#out + 1] = (v == math.floor(v)) and ('%d'):format(v) or tostring(v);
    elseif kind == 'string' then
        out[#out + 1] = str(v);
    elseif kind == 'table' then
        if isArray(v) then
            out[#out + 1] = '[';
            for i = 1, #v do
                if i > 1 then out[#out + 1] = ','; end
                encode(v[i], out);
            end
            out[#out + 1] = ']';
        else
            local keys = {};
            for k in pairs(v) do keys[#keys + 1] = tostring(k); end
            table.sort(keys);
            out[#out + 1] = '{';
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = ','; end
                out[#out + 1] = str(k) .. ':';
                local val = v[k];
                if val == nil then val = v[tonumber(k)]; end
                encode(val, out);
            end
            out[#out + 1] = '}';
        end
    else
        out[#out + 1] = 'null';
    end
end

function M.encode(v)
    local out = {};
    encode(v, out);
    return table.concat(out);
end

return M;
