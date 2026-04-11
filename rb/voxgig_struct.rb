require 'json'
require 'uri'

module VoxgigStruct
  # --- Debug Logging Configuration ---
  DEBUG = false
  
  def self.log(msg)
    puts "[DEBUG] #{msg}" if DEBUG
  end

  # --- Helper to convert internal undefined marker to Ruby nil ---
  def self.conv(val)
    val.equal?(UNDEF) ? nil : val
  end

  # --- Constants ---
  S_MKEYPRE  = 'key:pre'
  S_MKEYPOST = 'key:post'
  S_MVAL     = 'val'
  S_MKEY     = 'key'

  S_DKEY   = '`$KEY`'
  S_DMETA  = '`$META`'
  S_DTOP   = '$TOP'
  S_DERRS  = '$ERRS'

  S_any      = 'any'
  S_array    = 'array'
  S_boolean  = 'boolean'
  S_decimal  = 'decimal'
  S_function = 'function'
  S_instance = 'instance'
  S_integer  = 'integer'
  S_list     = 'list'
  S_map      = 'map'
  S_nil      = 'nil'
  S_node     = 'node'
  S_number   = 'number'
  S_null     = 'null'
  S_object   = 'object'
  S_scalar   = 'scalar'
  S_string   = 'string'
  S_symbol   = 'symbol'
  S_MT       = ''       # empty string constant (used as a prefix)
  S_BT       = '`'
  S_DS       = '$'
  S_DT       = '.'      # delimiter for key paths
  S_CN       = ':'      # colon for unknown paths
  S_SP       = ' '
  S_VIZ      = ': '
  S_KEY      = 'KEY'

  # Types - bitfield integers matching TypeScript canonical
  _t = 31
  T_any      = (1 << _t) - 1;     _t -= 1
  T_noval    = 1 << _t;           _t -= 1
  T_boolean  = 1 << _t;           _t -= 1
  T_decimal  = 1 << _t;           _t -= 1
  T_integer  = 1 << _t;           _t -= 1
  T_number   = 1 << _t;           _t -= 1
  T_string   = 1 << _t;           _t -= 1
  T_function = 1 << _t;           _t -= 1
  T_symbol   = 1 << _t;           _t -= 1
  T_null     = 1 << _t;           _t -= 8
  T_list     = 1 << _t;           _t -= 1
  T_map      = 1 << _t;           _t -= 1
  T_instance = 1 << _t;           _t -= 5
  T_scalar   = 1 << _t;           _t -= 1
  T_node     = 1 << _t

  TYPENAME = [
    S_any, S_nil, S_boolean, S_decimal, S_integer, S_number, S_string,
    S_function, S_symbol, S_null,
    '', '', '', '', '', '', '',
    S_list, S_map, S_instance,
    '', '', '', '',
    S_scalar, S_node,
  ]

  SKIP = { '`$SKIP`' => true }
  DELETE = { '`$DELETE`' => true }

  # Unique undefined marker.
  UNDEF = Object.new.freeze

  # Mode constants (bitfield) matching TypeScript canonical
  M_KEYPRE = 1
  M_KEYPOST = 2
  M_VAL = 4

  MODENAME = { M_VAL => 'val', M_KEYPRE => 'key:pre', M_KEYPOST => 'key:post' }.freeze
  PLACEMENT = { M_VAL => 'value', M_KEYPRE => S_MKEY, M_KEYPOST => S_MKEY }.freeze

  MAXDEPTH = 32

  # --- Utility functions ---

  def self.sorted(val)
    case val
    when Hash
      sorted_hash = {}
      val.keys.sort.each { |k| sorted_hash[k] = sorted(val[k]) }
      sorted_hash
    when Array
      val.map { |elem| sorted(elem) }
    else
      val
    end
  end

  def self.clone(val)
    return nil if val.nil? || val.equal?(UNDEF)
    if isfunc(val)
      val
    elsif islist(val)
      val.map { |v| clone(v) }
    elsif ismap(val)
      result = {}
      val.each { |k, v| result[k] = isfunc(v) ? v : clone(v) }
      result
    else
      val
    end
  end

  def self.escre(s)
    s = s.nil? ? "" : s
    Regexp.escape(s)
  end

  def self.escurl(s)
    s = s.nil? ? "" : s
    URI::DEFAULT_PARSER.escape(s, /[^A-Za-z0-9\-\.\_\~]/)
  end

  # --- Internal getprop ---
  # Returns the value if found; otherwise returns alt (default is UNDEF)
  def self._getprop(val, key, alt = UNDEF)
    log("(_getprop) called with val=#{val.inspect} and key=#{key.inspect}")
    return alt if val.nil? || key.nil?
    if islist(val)
      key = (key.to_s =~ /\A\d+\z/) ? key.to_i : key
      unless key.is_a?(Numeric) && key >= 0 && key < val.size
        log("(_getprop) index #{key.inspect} out of bounds; returning alt")
        return alt
      end
      result = val[key]
      log("(_getprop) returning #{result.inspect} from array for key #{key}")
      return result
    elsif ismap(val)
      key_str = key.to_s
      if val.key?(key_str)
        result = val[key_str]
        log("(_getprop) found key #{key_str.inspect} in hash, returning #{result.inspect}")
        return result
      elsif key.is_a?(String) && val.key?(key.to_sym)
        result = val[key.to_sym]
        log("(_getprop) found symbol key #{key.to_sym.inspect} in hash, returning #{result.inspect}")
        return result
      else
        log("(_getprop) key #{key.inspect} not found; returning alt")
        return alt
      end
    else
      log("(_getprop) value is not a node; returning alt")
      alt
    end
  end

  # --- Public getprop ---
  # Wraps _getprop. If the result equals UNDEF, returns the provided alt.
  def self.getprop(val, key, alt = nil)
    result = _getprop(val, key, alt.nil? ? UNDEF : alt)
    result.equal?(UNDEF) ? alt : result
  end

  def self.isempty(val)
    return true if val.nil? || val.equal?(UNDEF) || val == ""
    return true if islist(val) && val.empty?
    return true if ismap(val) && val.empty?
    false
  end

  def self.iskey(key)
    (key.is_a?(String) && !key.empty?) || key.is_a?(Numeric)
  end

  def self.islist(val)
    val.is_a?(Array)
  end

  def self.ismap(val)
    val.is_a?(Hash)
  end

  def self.isnode(val)
    ismap(val) || islist(val)
  end

  def self.items(val, apply = nil)
    if ismap(val)
      pairs = val.keys.sort.map { |k| [k, val[k]] }
    elsif islist(val)
      pairs = val.each_with_index.map { |v, i| [i.to_s, v] }
    else
      return []
    end
    apply ? pairs.map { |item| apply.call(item) } : pairs
  end

  def self.setprop(parent, key, val = :no_val_provided)
    log(">>> setprop called with parent=#{parent.inspect}, key=#{key.inspect}, val=#{val.inspect}")
    return parent unless iskey(key)
    if ismap(parent)
      key_str = key.to_s
      if val == :no_val_provided
        parent.delete(key_str)
      else
        parent[key_str] = val
      end
    elsif islist(parent)
      begin
        key_i = Integer(key)
      rescue ArgumentError
        return parent
      end
      if val == :no_val_provided
        parent.delete_at(key_i) if key_i >= 0 && key_i < parent.length
      else
        if key_i >= 0
          index = key_i >= parent.length ? parent.length : key_i
          parent[index] = val
        else
          parent.unshift(val)
        end
      end
    end
    log("<<< setprop result: #{parent.inspect}")
    parent
  end

  def self.stringify(val, maxlen = nil, pretty = nil)
    return '' if val.equal?(UNDEF)
    return 'null' if val.nil?

    if val.is_a?(String)
      valstr = val
    else
      begin
        v = val.is_a?(Hash) ? sorted(val) : val
        valstr = JSON.generate(v)
        valstr = valstr.gsub('"', '')
      rescue StandardError
        valstr = val.to_s
      end
    end

    if !maxlen.nil? && maxlen >= 0
      if valstr.length > maxlen
        valstr = valstr[0, maxlen - 3] + '...'
      end
    end

    valstr
  end

  def self.pathify(val, startin = nil, endin = nil)
    pathstr = nil

    path = if islist(val)
      val
    elsif val.is_a?(String)
      [val]
    elsif val.is_a?(Numeric)
      [val]
    else
      nil
    end

    start = startin.nil? ? 0 : startin < 0 ? 0 : startin
    end_idx = endin.nil? ? 0 : endin < 0 ? 0 : endin

    if path && start >= 0
      path = path[start..-end_idx-1]
      if path.empty?
        pathstr = '<root>'
      else
        pathstr = path
          .select { |p| iskey(p) }
          .map { |p|
            if p.is_a?(Numeric)
              S_MT + p.floor.to_s
            else
              p.gsub('.', S_MT)
            end
          }
          .join(S_DT)
      end
    end

    if pathstr.nil?
      pathstr = '<unknown-path' + (val.equal?(UNDEF) ? '' : S_CN + stringify(val, 47)) + '>'
    end

    pathstr
  end

  def self.strkey(key = nil)
    return "" if key.nil?
    return key if key.is_a?(String)
    return key.floor.to_s if key.is_a?(Numeric)
    ""
  end

  def self.isfunc(val)
    val.respond_to?(:call)
  end

  def self.getdef(val, alt)
    val.nil? ? alt : val
  end

  def self.size(val)
    return 0 if val.nil? || val.equal?(UNDEF)
    return val.length if val.is_a?(String) || islist(val)
    return val.keys.length if ismap(val)
    return (val == true ? 1 : 0) if val == true || val == false
    return val.to_i if val.is_a?(Numeric)
    0
  end

  def self.slice(val, start_idx = nil, end_idx = nil, mutate = false)
    return val if val.nil? || val.equal?(UNDEF)

    if val.is_a?(Numeric) && !val.is_a?(TrueClass) && !val.is_a?(FalseClass)
      s = start_idx.nil? ? (-Float::INFINITY) : start_idx
      e = end_idx.nil? ? Float::INFINITY : (end_idx - 1)
      return [[val, s].max, e].min
    end

    vlen = size(val)

    start_idx = 0 if !end_idx.nil? && start_idx.nil?

    if !start_idx.nil?
      s = start_idx
      e = end_idx

      if s < 0
        e = vlen + s
        e = 0 if e < 0
        s = 0
      elsif !e.nil?
        if e < 0
          e = vlen + e
          e = 0 if e < 0
        elsif vlen < e
          e = vlen
        end
      else
        e = vlen
      end

      s = vlen if vlen < s

      if islist(val)
        result = val[s...e] || []
        if mutate
          val.replace(result)
          return val
        end
        return result
      elsif val.is_a?(String)
        return val[s...e] || ''
      end
    end

    val
  end

  def self.pad(str, padding = nil, padchar = nil)
    str = str.is_a?(String) ? str : stringify(str)
    padding = padding.nil? ? 44 : padding
    padchar = padchar.nil? ? ' ' : (padchar.to_s + ' ')[0]
    if padding >= 0
      str.ljust(padding, padchar)
    else
      str.rjust(-padding, padchar)
    end
  end

  def self.getelem(val, key, alt = UNDEF)
    out = UNDEF
    if islist(val) && !key.nil? && !key.equal?(UNDEF)
      begin
        nkey = key.to_i
        if key.to_s.strip.match?(/\A-?\d+\z/)
          nkey = val.length + nkey if nkey < 0
          out = (0 <= nkey && nkey < val.length) ? val[nkey] : UNDEF
        end
      rescue
      end
    end
    if out.equal?(UNDEF)
      return isfunc(alt) ? alt.call : (alt.equal?(UNDEF) ? nil : alt)
    end
    out
  end

  def self.flatten(lst, depth = nil)
    depth = 1 if depth.nil?
    return lst unless islist(lst)
    out = []
    lst.each do |item|
      if islist(item) && depth > 0
        out.concat(flatten(item, depth - 1))
      else
        out << item unless item.nil? || item.equal?(UNDEF)
      end
    end
    out
  end

  def self.filter(val, check)
    return [] unless isnode(val)
    items(val).select { |item| check.call(item) }.map { |item| item[1] }
  end

  def self.delprop(parent, key)
    return parent unless iskey(key)
    if ismap(parent)
      ks = strkey(key)
      parent.delete(ks)
    elsif islist(parent)
      begin
        ki = key.to_i
        if 0 <= ki && ki < parent.length
          parent.delete_at(ki)
        end
      rescue
      end
    end
    parent
  end

  def self.join(arr, sep = nil, url = nil)
    return '' unless islist(arr)
    sepdef = sep.nil? ? ',' : sep.to_s
    sepre = (sepdef.length == 1) ? Regexp.escape(sepdef) : nil

    # Filter to non-empty strings only
    parts = arr.select { |n| n.is_a?(String) && n != '' }

    parts = parts.map.with_index { |s, i|
      if sepre
        if url && i == 0
          s = s.sub(/#{sepre}+$/, '')
        end
        if i > 0
          s = s.sub(/^#{sepre}+/, '')
        end
        if i < parts.length - 1
          s = s.sub(/#{sepre}+$/, '')
        end
      end
      s
    }.reject(&:empty?)

    parts.join(sepdef)
  end

  def self.joinurl(sarr)
    join(sarr, '/', true)
  end

  def self.jsonify(val, flags = nil)
    return 'null' if val.nil?
    begin
      indent = flags.is_a?(Hash) ? (flags['indent'] || flags[:indent] || 2) : 2
      JSON.generate(val, indent: ' ' * indent, space: ' ', object_nl: "\n", array_nl: "\n")
    rescue
      val.to_s
    end
  end

  def self.jm(*kv)
    result = {}
    i = 0
    while i < kv.length - 1
      result[kv[i].to_s] = kv[i + 1]
      i += 2
    end
    result
  end

  def self.jt(*v)
    v.to_a
  end

  def self.replace(s, from, to)
    return s.to_s unless s.is_a?(String)
    if from.is_a?(Regexp)
      s.gsub(from, to.to_s)
    else
      s.gsub(from.to_s, to.to_s)
    end
  end

  def self.keysof(val)
    return [] unless isnode(val)
    if ismap(val)
      val.keys.sort
    elsif islist(val)
      (0...val.length).map(&:to_s)
    else
      []
    end
  end

  # Public haskey uses getprop (so that missing keys yield nil)
  def self.haskey(val = UNDEF, key = UNDEF)
    _getprop(val, key, UNDEF) != UNDEF
  end

  def self.joinurl(parts)
    parts.compact.map.with_index do |s, i|
      s = s.to_s
      if i.zero?
        s.sub(/\/+$/, '')
      else
        s.sub(/([^\/])\/+/, '\1/').sub(/^\/+/, '').sub(/\/+$/, '')
      end
    end.reject { |s| s.empty? }.join('/')
  end

  # Get type name string from type bitfield value.
  def self._clz32(n)
    return 32 if n <= 0
    31 - (n.bit_length - 1)
  end

  def self.typename(t)
    t = t.to_i
    idx = _clz32(t)
    return TYPENAME[0] if idx < 0 || idx >= TYPENAME.length
    r = TYPENAME[idx]
    (r.nil? || r == S_MT) ? TYPENAME[0] : r
  end

  # Determine the type of a value as a bitfield integer.
  def self.typify(value = UNDEF)
    return T_noval if value.equal?(UNDEF)
    return T_scalar | T_null if value.nil?

    if value == true || value == false
      return T_scalar | T_boolean
    end

    if isfunc(value)
      return T_scalar | T_function
    end

    if value.is_a?(Integer)
      return T_scalar | T_number | T_integer
    end

    if value.is_a?(Float)
      return value.nan? ? T_noval : (T_scalar | T_number | T_decimal)
    end

    if value.is_a?(String)
      return T_scalar | T_string
    end

    if value.is_a?(Symbol)
      return T_scalar | T_symbol
    end

    if islist(value)
      return T_node | T_list
    end

    if ismap(value)
      return T_node | T_map
    end

    T_any
  end

  def self.walk(val, before = nil, after = nil, maxdepth = nil, key: nil, parent: nil, path: nil)
    path = [] if path.nil?

    _before = before
    _after = after

    out = _before.nil? ? val : _before.call(key, val, parent, path)

    md = (maxdepth.is_a?(Numeric) && maxdepth >= 0) ? maxdepth : MAXDEPTH
    if md == 0 || (!path.empty? && md > 0 && md <= path.length)
      return out
    end

    if isnode(out)
      items(out).each do |ckey, child|
        new_path = flatten([path, ckey.to_s])
        result = walk(child, _before, _after, md, key: ckey, parent: out, path: new_path)
        if ismap(out)
          out[ckey.to_s] = result
        elsif islist(out)
          out[ckey.to_i] = result
        end
      end
    end

    out = _after.call(key, out, parent, path) unless _after.nil?

    out
  end

  # --- Deep Merge Helpers for merge ---
  #
  # deep_merge recursively combines two nodes.
  # For hashes, keys in b override those in a.
  # For arrays, merge index-by-index; b's element overrides a's at that position,
  # while preserving items that b does not provide.
  def self.deep_merge(a, b)
    if ismap(a) && ismap(b)
      merged = a.dup
      b.each do |k, v|
        if merged.key?(k)
          merged[k] = deep_merge(merged[k], v)
        else
          merged[k] = v
        end
      end
      merged
    elsif islist(a) && islist(b)
      max_len = [a.size, b.size].max
      merged = []
      (0...max_len).each do |i|
        if i < a.size && i < b.size
          merged[i] = deep_merge(a[i], b[i])
        elsif i < b.size
          merged[i] = b[i]
        else
          merged[i] = a[i]
        end
      end
      merged
    else
      # For non-node values, b wins.
      b
    end
  end

  # --- Merge function ---
  #
  # Accepts an array of nodes and deep merges them (later nodes override earlier ones).
  def self.merge(val, maxdepth = nil)
    return val unless islist(val)
    list = val.reject { |v| v.nil? || v.equal?(UNDEF) }
    return nil if list.empty?
    result = list[0]
    (1...list.size).each do |i|
      result = deep_merge(result, list[i])
    end
    result
  end

  # Get value at a key path deep inside a store.
  # Matches TS canonical: getpath(store, path, injdef?)
  def self.getpath(store, path, injdef = nil)
    # Operate on a string array.
    if islist(path)
      parts = path.dup
    elsif path.is_a?(String)
      parts = path.split(S_DT)
    elsif path.is_a?(Numeric)
      parts = [strkey(path)]
    else
      return nil
    end

    val = store

    # Extract injdef properties (support both Hash and object with accessors)
    if injdef.is_a?(Hash)
      base = injdef['base'] || injdef[:base]
      dparent = injdef['dparent'] || injdef[:dparent]
      inj_meta = injdef['meta'] || injdef[:meta]
      inj_key = injdef['key'] || injdef[:key]
      dpath = injdef['dpath'] || injdef[:dpath]
      handler = injdef['handler'] || injdef[:handler]
    elsif injdef.respond_to?(:base)
      base = injdef.base
      dparent = injdef.dparent
      inj_meta = injdef.meta
      inj_key = injdef.key
      dpath = injdef.dpath
      handler = injdef.handler
    else
      base = nil; dparent = nil; inj_meta = nil; inj_key = nil; dpath = nil; handler = nil
    end

    src = base ? _getprop(store, base, store) : store
    numparts = parts.length

    # An empty path (incl empty string) just finds the src.
    if path.nil? || store.nil? || (numparts == 1 && parts[0] == S_MT) || numparts == 0
      val = src
    elsif numparts > 0
      # Check for $ACTIONs
      if numparts == 1
        val = _getprop(store, parts[0], UNDEF)
      end

      if !isfunc(val)
        val = src

        # Check for meta path syntax
        if parts[0].is_a?(String) && (m = parts[0].match(/^([^$]+)\$([=~])(.+)$/)) && inj_meta
          val = _getprop(inj_meta, m[1], UNDEF)
          parts[0] = m[3]
        end

        pI = 0
        while !val.equal?(UNDEF) && !val.nil? && pI < numparts
          part = parts[pI]

          if injdef && part == '$KEY'
            part = inj_key || part
          elsif part.is_a?(String) && part.start_with?('$GET:')
            part = stringify(getpath(src, part[5..-2]))
          elsif part.is_a?(String) && part.start_with?('$REF:')
            part = stringify(getpath(_getprop(store, '$SPEC', UNDEF), part[5..-2]))
          elsif injdef && part.is_a?(String) && part.start_with?('$META:')
            part = stringify(getpath(inj_meta, part[6..-2]))
          end

          # $$ escapes $
          part = part.gsub('$$', '$') if part.is_a?(String)

          if part == S_MT
            ascends = 0
            while pI + 1 < parts.length && parts[pI + 1] == S_MT
              ascends += 1
              pI += 1
            end

            if injdef && ascends > 0
              ascends -= 1 if pI == parts.length - 1
              if ascends == 0
                val = dparent
              else
                fullpath = flatten([slice(dpath, 0 - ascends), parts[(pI + 1)..-1]])
                if dpath.is_a?(Array) && ascends <= dpath.length
                  val = getpath(store, fullpath)
                else
                  val = UNDEF
                end
                break
              end
            else
              val = dparent || src
            end
          else
            val = _getprop(val, part, UNDEF)
          end
          pI += 1
        end
      end
    end

    # Injdef may provide a custom handler to modify found value.
    if handler && isfunc(handler)
      ref = pathify(path)
      val = handler.call(injdef, val.equal?(UNDEF) ? nil : val, ref, store)
    end

    val.equal?(UNDEF) ? nil : val
  end


  # In your VoxgigStruct module, add the following methods (e.g., at the bottom):

  def self._injectstr(val, store, current = nil, state = nil)
    log("(_injectstr) called with val=#{val.inspect}, store=#{store.inspect}, current=#{current.inspect}, state=#{state.inspect}")
    return S_MT unless val.is_a?(String) && val != S_MT
  
    out = val
    m = val.match(/^`(\$[A-Z]+|[^`]+)[0-9]*`$/)
    log("(_injectstr) regex match result: #{m.inspect}")
  
    if m
      state[:full] = true if state
      pathref = m[1]
      pathref.gsub!('$BT', S_BT)
      pathref.gsub!('$DS', S_DS)
      out = getpath(pathref, store, current, state)
      out = out.is_a?(String) ? out : JSON.generate(out) unless state&.dig(:full)
    else
      out = val.gsub(/`([^`]+)`/) do |match|
        ref = match[1..-2]  # remove the backticks
        ref.gsub!('$BT', S_BT)
        ref.gsub!('$DS', S_DS)
        state[:full] = false if state
        found = getpath(ref, store, current, state)
        if found.nil?
          # If the key exists (even with nil), substitute "null";
          # otherwise, use an empty string.
          (store.is_a?(Hash) && store.key?(ref)) ? "null" : S_MT
        else
          # If the found value is a Hash or Array, use JSON.generate.
          if found.is_a?(Hash) || found.is_a?(Array)
            JSON.generate(found)
          else
            found.to_s
          end
        end
      end
      
        
  
      if state && state[:handler] && state[:handler].respond_to?(:call)
        state[:full] = true
        out = state[:handler].call(state, out, current, val, store)
      end
    end
    
    log("(_injectstr) returning #{out.inspect}")
    out
  end  

  # --- inject: Recursively inject store values into a node ---
  def self.inject(val, store, modify = nil, current = nil, state = nil, flag = nil)
    log("inject: called with val=#{val.inspect}, store=#{store.inspect}, modify=#{modify.inspect}, current=#{current.inspect}, state=#{state.inspect}, flag=#{flag.inspect}") 
    # If state is not provided, create a virtual root.
    if state.nil?
      parent = { S_DTOP => val }  # virtual parent container
      state = {
        mode: S_MVAL,           # current phase: value injection
        full: false,
        key: S_DTOP,            # the key this state represents
        parent: parent,         # the parent container (virtual root)
        path: [S_DTOP],
        handler: method(:_injecthandler), # default injection handler
        base: S_DTOP,
        modify: modify,
        errs: getprop(store, S_DERRS, []),
        meta: {}
      }
    end

    # If no current container is provided, assume one that wraps the store.
    current ||= { "$TOP" => store }

    # Process based on the type of node.
    if ismap(val)
      # For hashes, iterate over each key/value pair.
      val.each do |k, v|
        # Build a new state for this child based on the parent's state.
        child_state = state.merge({
          key: k.to_s,
          parent: val,
          path: state[:path] + [k.to_s]
        })
        # Recursively inject into the value.
        val[k] = inject(v, store, modify, current, child_state, flag)
      end
    elsif islist(val)
      # For arrays, iterate by index.
      val.each_with_index do |item, i|
        child_state = state.merge({
          key: i.to_s,
          parent: val,
          path: state[:path] + [i.to_s]
        })
        val[i] = inject(item, store, modify, current, child_state, flag)
      end
    elsif val.is_a?(String)
      val = _injectstr(val, store, current, state)
      setprop(state[:parent], state[:key], val) if state[:parent]      
      log("+++ after setprop: parent now = #{state[:parent].inspect}")
    end
    

    # Call the modifier if provided.
    if modify
      mkey   = state[:key]
      mparent = state[:parent]
      mval   = getprop(mparent, mkey)
      modify.call(mval, mkey, mparent, state, current, store)
    end

    log("inject: returning #{val.inspect} for key #{state[:key].inspect}")

        # Return transformed value
    if state[:key] == S_DTOP
      getprop(state[:parent], S_DTOP)
    else
      getprop(state[:parent], state[:key])
    end

  end

  # --- _injecthandler: The default injection handler ---
  def self._injecthandler(state, val, current, ref, store)
    out = val
    if isfunc(val) && (ref.nil? || ref.start_with?(S_DS))
      out = val.call(state, val, current, ref, store)
    elsif state[:mode] == S_MVAL && state[:full]
      log("(_injecthandler) setting parent key #{state[:key]} to #{val.inspect} (full=#{state[:full]})")
      _setparentprop(state, val)
    end
    out
  end

  # Helper to update the parent's property.
  def self._setparentprop(state, val)
    log("(_setparentprop) writing #{val.inspect} to #{state[:key]} in #{state[:parent].inspect}")
    setprop(state[:parent], state[:key], val)
  end

  # The transform_* functions are special command inject handlers (see Injector).

  # Delete a key from a map or list.
  def self.transform_delete(state, _val = nil, _current = nil, _ref = nil, _store = nil)
    _setparentprop(state, nil)
    nil
  end

  # Copy value from source data.
  def self.transform_copy(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    key = state[:key]

    out = key
    unless mode.start_with?('key')
      out = getprop(current, key)
      _setparentprop(state, out)
    end

    out
  end

  # As a value, inject the key of the parent node.
  # As a key, defined the name of the key property in the source object.
  def self.transform_key(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    path = state[:path]
    parent = state[:parent]

    # Do nothing in val mode.
    return nil unless mode == 'val'

    # Key is defined by $KEY meta property.
    keyspec = getprop(parent, '`$KEY`')
    if keyspec != nil
      setprop(parent, '`$KEY`', nil)
      return getprop(current, keyspec)
    end

    # Key is defined within general purpose $META object.
    getprop(getprop(parent, '`$META`'), 'KEY', getprop(path, path.length - 2))
  end

  # Store meta data about a node. Does nothing itself, just used by
  # other injectors, and is removed when called.
  def self.transform_meta(state, _val = nil, _current = nil, _ref = nil, _store = nil)
    parent = state[:parent]
    setprop(parent, '`$META`', nil)
    nil
  end

  # Merge a list of objects into the current object.
  # Must be a key in an object. The value is merged over the current object.
  # If the value is an array, the elements are first merged using `merge`.
  # If the value is the empty string, merge the top level store.
  # Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
  def self.transform_merge(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    key = state[:key]
    parent = state[:parent]

    return key if mode == 'key:pre'

    # Operate after child values have been transformed.
    if mode == 'key:post'
      args = getprop(parent, key)
      args = args == '' ? [current['$TOP']] : args.is_a?(Array) ? args : [args]

      # Remove the $MERGE command from a parent map.
      _setparentprop(state, nil)

      # Literals in the parent have precedence, but we still merge onto
      # the parent object, so that node tree references are not changed.
      mergelist = [parent, *args, clone(parent)]

      merge(mergelist)

      return key
    end

    # Ensures $MERGE is removed from parent list.
    nil
  end

  # Convert a node to a list.
  def self.transform_each(state, val, current, ref, store)
    out = nil
    if ismap(val)
      out = val.values
    elsif islist(val)
      out = val
    end
    out
  end

  # Convert a node to a map.
  def self.transform_pack(state, val, current, ref, store)
    out = nil
    if islist(val)
      out = {}
      val.each_with_index do |v, i|
        k = v[S_KEY]
        if k.nil?
          k = i.to_s
        end
        out[k] = v
      end
    end
    out
  end

  # Transform data using spec.
  def self.transform(data, spec, extra = nil, modify = nil)
    # Clone the spec so that the clone can be modified in place as the transform result.
    spec = clone(spec)

    extra_transforms = {}
    extra_data = if extra.nil?
      nil
    else
      items(extra).reduce({}) do |a, n|
        if n[0].start_with?(S_DS)
          extra_transforms[n[0]] = n[1]
        else
          a[n[0]] = n[1]
        end
        a
      end
    end

    data_clone = merge([
      isempty(extra_data) ? nil : clone(extra_data),
      clone(data)
    ])

    # Define a top level store that provides transform operations.
    store = {
      # The inject function recognises this special location for the root of the source data.
      # NOTE: to escape data that contains "`$FOO`" keys at the top level,
      # place that data inside a holding map: { myholder: mydata }.
      '$TOP' => data_clone,

      # Escape backtick (this also works inside backticks).
      '$BT' => -> { S_BT },

      # Escape dollar sign (this also works inside backticks).
      '$DS' => -> { S_DS },

      # Insert current date and time as an ISO string.
      '$WHEN' => -> { Time.now.iso8601 },

      '$DELETE' => method(:transform_delete),
      '$COPY' => method(:transform_copy),
      '$KEY' => method(:transform_key),
      '$META' => method(:transform_meta),
      '$MERGE' => method(:transform_merge),
      '$EACH' => method(:transform_each),
      '$PACK' => method(:transform_pack),

      # Custom extra transforms, if any.
      **extra_transforms
    }

    out = inject(spec, store, modify, store)
    out
  end

  # Update all references to target in state.nodes.
  def self._update_ancestors(_state, target, tkey, tval)
    # SetProp is sufficient in Ruby as target reference remains consistent even for lists.
    setprop(target, tkey, tval)
  end

  # Build a type validation error message.
  def self._invalid_type_msg(path, needtype, vt, v, _whence = nil)
    vs = v.nil? ? 'no value' : stringify(v)

    'Expected ' +
      (path.length > 1 ? ('field ' + pathify(path, 1) + ' to be ') : '') +
      needtype + ', but found ' +
      (v.nil? ? '' : typename(vt) + S_VIZ) + vs +
      # Uncomment to help debug validation errors.
      # ' [' + _whence + ']' +
      '.'
  end

  # A required string value. NOTE: Rejects empty strings.
  def self.validate_string(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = getprop(current, state[:key])

    t = typify(out)
    if 0 == (T_string & t)
      msg = _invalid_type_msg(state[:path], S_string, t, out, 'V1010')
      state[:errs].push(msg)
      return nil
    end

    if out == S_MT
      msg = 'Empty string at ' + pathify(state[:path], 1)
      state[:errs].push(msg)
      return nil
    end

    out
  end

  # A required number value (int or float).
  def self.validate_number(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = getprop(current, state[:key])

    t = typify(out)
    if 0 == (T_number & t)
      state[:errs].push(_invalid_type_msg(state[:path], S_number, t, out, 'V1020'))
      return nil
    end

    out
  end

  # A required boolean value.
  def self.validate_boolean(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = getprop(current, state[:key])

    t = typify(out)
    if 0 == (T_boolean & t)
      state[:errs].push(_invalid_type_msg(state[:path], S_boolean, t, out, 'V1030'))
      return nil
    end

    out
  end

  # A required object (map) value (contents not validated).
  def self.validate_object(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = getprop(current, state[:key])

    t = typify(out)
    if 0 == (T_map & t)
      state[:errs].push(_invalid_type_msg(state[:path], S_object, t, out, 'V1040'))
      return nil
    end

    out
  end

  # A required array (list) value (contents not validated).
  def self.validate_array(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = getprop(current, state[:key])

    t = typify(out)
    if 0 == (T_list & t)
      state[:errs].push(_invalid_type_msg(state[:path], S_array, t, out, 'V1050'))
      return nil
    end

    out
  end

  # A required function value.
  def self.validate_function(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = getprop(current, state[:key])

    t = typify(out)
    if 0 == (T_function & t)
      state[:errs].push(_invalid_type_msg(state[:path], S_function, t, out, 'V1060'))
      return nil
    end

    out
  end

  # Allow any value.
  def self.validate_any(state, _val = nil, current = nil, _ref = nil, _store = nil)
    getprop(current, state[:key])
  end

  # Specify child values for map or list.
  # Map syntax: {'`$CHILD`': child-template }
  # List syntax: ['`$CHILD`', child-template ]
  def self.validate_child(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    key = state[:key]
    parent = state[:parent]
    keys = state[:keys]
    path = state[:path]

    # Map syntax.
    if mode == S_MKEYPRE
      childtm = getprop(parent, key)

      # Get corresponding current object.
      pkey = getprop(path, path.length - 2)
      tval = getprop(current, pkey)

      if tval.nil?
        tval = {}
      elsif !ismap(tval)
        state[:errs].push(_invalid_type_msg(
          state[:path][0..-2], S_object, typify(tval), tval, 'V0220'))
        return nil
      end

      ckeys = keysof(tval)
      ckeys.each do |ckey|
        setprop(parent, ckey, clone(childtm))

        # NOTE: modifying state! This extends the child value loop in inject.
        keys.push(ckey)
      end

      # Remove $CHILD to cleanup output.
      _setparentprop(state, nil)
      return nil
    end

    # List syntax.
    if mode == S_MVAL
      if !islist(parent)
        # $CHILD was not inside a list.
        state[:errs].push('Invalid $CHILD as value')
        return nil
      end

      childtm = getprop(parent, 1)

      if current.nil?
        # Empty list as default.
        parent.clear
        return nil
      end

      if !islist(current)
        msg = _invalid_type_msg(
          state[:path][0..-2], S_array, typify(current), current, 'V0230')
        state[:errs].push(msg)
        state[:keyI] = parent.length
        return current
      end

      # Clone children and reset state key index.
      # The inject child loop will now iterate over the cloned children,
      # validating them against the current list values.
      current.each_with_index { |_n, i| parent[i] = clone(childtm) }
      parent.replace(current.map { |_n| clone(childtm) })
      state[:keyI] = 0
      out = getprop(current, 0)
      return out
    end

    nil
  end

  # Match at least one of the specified shapes.
  # Syntax: ['`$ONE`', alt0, alt1, ...]
  def self.validate_one(state, _val = nil, current = nil, _ref = nil, store = nil)
    mode = state[:mode]
    parent = state[:parent]
    path = state[:path]
    keyI = state[:keyI]
    nodes = state[:nodes]

    # Only operate in val mode, since parent is a list.
    if mode == S_MVAL
      if !islist(parent) || keyI != 0
        state[:errs].push('The $ONE validator at field ' +
          pathify(state[:path], 1) +
          ' must be the first element of an array.')
        return
      end

      state[:keyI] = state[:keys].length

      grandparent = nodes[nodes.length - 2]
      grandkey = path[path.length - 2]

      # Clean up structure, replacing [$ONE, ...] with current
      setprop(grandparent, grandkey, current)
      state[:path] = state[:path][0..-2]
      state[:key] = state[:path][state[:path].length - 1]

      tvals = parent[1..-1]
      if tvals.empty?
        state[:errs].push('The $ONE validator at field ' +
          pathify(state[:path], 1) +
          ' must have at least one argument.')
        return
      end

      # See if we can find a match.
      tvals.each do |tval|
        # If match, then errs.length = 0
        terrs = []

        vstore = store.dup
        vstore['$TOP'] = current
        vcurrent = validate(current, tval, vstore, terrs)
        setprop(grandparent, grandkey, vcurrent)

        # Accept current value if there was a match
        return if terrs.empty?
      end

      # There was no match.
      valdesc = tvals
        .map { |v| stringify(v) }
        .join(', ')
        .gsub(/`\$([A-Z]+)`/, &:downcase)

      state[:errs].push(_invalid_type_msg(
        state[:path],
        (tvals.length > 1 ? 'one of ' : '') + valdesc,
        typify(current), current, 'V0210'))
    end
  end

  def self.validate_exact(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    parent = state[:parent]
    key = state[:key]
    keyI = state[:keyI]
    path = state[:path]
    nodes = state[:nodes]

    # Only operate in val mode, since parent is a list.
    if mode == S_MVAL
      if !islist(parent) || keyI != 0
        state[:errs].push('The $EXACT validator at field ' +
          pathify(state[:path], 1) +
          ' must be the first element of an array.')
        return
      end

      state[:keyI] = state[:keys].length

      grandparent = nodes[nodes.length - 2]
      grandkey = path[path.length - 2]

      # Clean up structure, replacing [$EXACT, ...] with current
      setprop(grandparent, grandkey, current)
      state[:path] = state[:path][0..-2]
      state[:key] = state[:path][state[:path].length - 1]

      tvals = parent[1..-1]
      if tvals.empty?
        state[:errs].push('The $EXACT validator at field ' +
          pathify(state[:path], 1) +
          ' must have at least one argument.')
        return
      end

      # See if we can find an exact value match.
      currentstr = nil
      tvals.each do |tval|
        exactmatch = tval == current

        if !exactmatch && isnode(tval)
          currentstr ||= stringify(current)
          tvalstr = stringify(tval)
          exactmatch = tvalstr == currentstr
        end

        return if exactmatch
      end

      valdesc = tvals
        .map { |v| stringify(v) }
        .join(', ')
        .gsub(/`\$([A-Z]+)`/, &:downcase)

      state[:errs].push(_invalid_type_msg(
        state[:path],
        (state[:path].length > 1 ? '' : 'value ') +
        'exactly equal to ' + (tvals.length == 1 ? '' : 'one of ') + valdesc,
        typify(current), current, 'V0110'))
    else
      setprop(parent, key, nil)
    end
  end

  # This is the "modify" argument to inject. Use this to perform
  # generic validation. Runs *after* any special commands.
  def self._validation(pval, key = nil, parent = nil, state = nil, current = nil, _store = nil)
    return if state.nil?

    # Current val to verify.
    cval = getprop(current, key)

    return if cval.nil? || state.nil?

    ptype = typify(pval)

    # Delete any special commands remaining.
    return if 0 != (T_string & ptype) && pval.include?(S_DS)

    ctype = typify(cval)

    # Type mismatch.
    if ptype != ctype && !pval.nil?
      state[:errs].push(_invalid_type_msg(state[:path], typename(ptype), ctype, cval, 'V0010'))
      return
    end

    if ismap(cval)
      if !ismap(pval)
        state[:errs].push(_invalid_type_msg(state[:path], typename(ptype), ctype, cval, 'V0020'))
        return
      end

      ckeys = keysof(cval)
      pkeys = keysof(pval)

      # Empty spec object {} means object can be open (any keys).
      if !pkeys.empty? && getprop(pval, '`$OPEN`') != true
        badkeys = []
        ckeys.each do |ckey|
          badkeys.push(ckey) unless haskey(pval, ckey)
        end

        # Closed object, so reject extra keys not in shape.
        if !badkeys.empty?
          msg = 'Unexpected keys at field ' + pathify(state[:path], 1) + ': ' + badkeys.join(', ')
          state[:errs].push(msg)
        end
      else
        # Object is open, so merge in extra keys.
        merge([pval, cval])
        setprop(pval, '`$OPEN`', nil) if isnode(pval)
      end
    elsif islist(cval)
      if !islist(pval)
        state[:errs].push(_invalid_type_msg(state[:path], typename(ptype), ctype, cval, 'V0030'))
      end
    else
      # Spec value was a default, copy over data
      setprop(parent, key, cval)
    end
  end

  # Validate a data structure against a shape specification.
  def self.validate(data, spec, extra = nil, collecterrs = nil)
    errs = collecterrs.nil? ? [] : collecterrs

    store = {
      # Remove the transform commands.
      '$DELETE' => nil,
      '$COPY' => nil,
      '$KEY' => nil,
      '$META' => nil,
      '$MERGE' => nil,
      '$EACH' => nil,
      '$PACK' => nil,

      '$STRING' => method(:validate_string),
      '$NUMBER' => method(:validate_number),
      '$BOOLEAN' => method(:validate_boolean),
      '$OBJECT' => method(:validate_object),
      '$ARRAY' => method(:validate_array),
      '$FUNCTION' => method(:validate_function),
      '$ANY' => method(:validate_any),
      '$CHILD' => method(:validate_child),
      '$ONE' => method(:validate_one),
      '$EXACT' => method(:validate_exact),

      **(extra || {}),

      # A special top level value to collect errors.
      # NOTE: collecterrs parameter always wins.
      '$ERRS' => errs
    }

    out = transform(data, spec, store, method(:_validation))

    generr = !errs.empty? && collecterrs.nil?
    raise "Invalid data: #{errs.join(' | ')}" if generr

    out
  end

  def self.setpath(store, path, val, injdef = nil)
    pt = typify(path)
    if 0 < (T_list & pt)
      parts = path
    elsif 0 < (T_string & pt)
      parts = path.split(S_DT)
    elsif 0 < (T_number & pt)
      parts = [path]
    else
      return nil
    end

    base = injdef.is_a?(Hash) ? getprop(injdef, S_base) : nil
    numparts = size(parts)
    parent = base ? getprop(store, base, store) : store

    (0...numparts - 1).each do |pI|
      part_key = getelem(parts, pI)
      next_parent = getprop(parent, part_key)
      unless isnode(next_parent)
        next_part = getelem(parts, pI + 1)
        next_parent = (0 < (T_number & typify(next_part))) ? [] : {}
        setprop(parent, part_key, next_parent)
      end
      parent = next_parent
    end

    if val == DELETE
      delprop(parent, getelem(parts, -1))
    else
      setprop(parent, getelem(parts, -1), val)
    end

    parent
  end

  def self.checkPlacement(modes, ijname, parentTypes, inj)
    mode_num = { S_MKEYPRE => M_KEYPRE, S_MKEYPOST => M_KEYPOST, S_MVAL => M_VAL }
    inj_mode = inj.is_a?(Hash) ? inj[:mode] : inj.respond_to?(:mode) ? inj.mode : nil
    mode_int = mode_num[inj_mode] || 0
    if 0 == (modes & mode_int)
      errs = inj.is_a?(Hash) ? inj[:errs] : inj.errs
      errs << '$' + ijname + ': invalid placement as ' + (PLACEMENT[mode_int] || '') +
        ', expected: ' + [M_KEYPRE, M_KEYPOST, M_VAL].select { |m| modes & m != 0 }.map { |m| PLACEMENT[m] }.join(',') + '.'
      return false
    end
    if !isempty(parentTypes)
      inj_parent = inj.is_a?(Hash) ? inj[:parent] : inj.parent
      ptype = typify(inj_parent)
      if 0 == (parentTypes & ptype)
        errs = inj.is_a?(Hash) ? inj[:errs] : inj.errs
        errs << '$' + ijname + ': invalid placement in parent ' + typename(ptype) +
          ', expected: ' + typename(parentTypes) + '.'
        return false
      end
    end
    true
  end

  def self.injectorArgs(argTypes, args)
    numargs = size(argTypes)
    found = Array.new(1 + numargs)
    found[0] = nil
    (0...numargs).each do |argI|
      arg = args[argI]
      argType = typify(arg)
      if 0 == (argTypes[argI] & argType)
        found[0] = 'invalid argument: ' + stringify(arg, 22) +
          ' (' + typename(argType) + ' at position ' + (1 + argI).to_s +
          ') is not of type: ' + typename(argTypes[argI]) + '.'
        break
      end
      found[1 + argI] = arg
    end
    found
  end

  def self.injectChild(child, store, inj)
    # Stub - requires Injection class for full implementation
    inj
  end

  def self.select(children, query)
    # Stub - requires full validate/inject architecture
    return [] unless isnode(children)
    []
  end

end
