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

  S_array    = 'array'
  S_boolean  = 'boolean'
  S_function = 'function'
  S_number   = 'number'
  S_object   = 'object'
  S_string   = 'string'
  S_null     = 'null'
  S_MT       = ''       # empty string constant (used as a prefix)
  S_BT       = '`'
  S_DS       = '$'
  S_DT       = '.'      # delimiter for key paths
  S_CN       = ':'      # colon for unknown paths
  S_KEY      = 'KEY'

  # Unique undefined marker.
  UNDEF = Object.new.freeze

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
    return nil if val.nil?
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
    return true if val.nil? || val == ""
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

  def self.items(val)
    if ismap(val)
      val.keys.sort.map { |k| [k, val[k]] }
    elsif islist(val)
      val.each_with_index.map { |v, i| [i, v] }
    else
      []
    end
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

  def self.stringify(val, maxlen = nil)
    return "null" if val.nil?
    begin
      v = val.is_a?(Hash) ? sorted(val) : val
      json = JSON.generate(v)
    rescue StandardError
      json = val.to_s
    end
    json = json.gsub('"', '')
    if maxlen && json.length > maxlen
      js = json[0, maxlen]
      json = js[0, maxlen - 3] + '...'
    end
    json
  end

  def self.pathify(val, from = 0)
    s_dt = S_DT
    path = if islist(val)
             val
           elsif val.is_a?(String) || val.is_a?(Numeric)
             [val]
           end

    start = (from.nil? || from < 0) ? 0 : from
    if path
      path = path[start..-1] || []
      if path.empty?
        "<root>"
      else
        valid_keys = path.select { |p| iskey(p) }
        valid_keys.map { |p| p.is_a?(Numeric) ? p.floor.to_s : p.to_s.gsub('.', S_MT) }.join(s_dt)
      end
    else
      "<unknown-path#{S_CN}#{stringify(val,47)}>"
    end
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
  def self.haskey(*args)
    if args.size == 1 && args.first.is_a?(Array) && args.first.size >= 2
      val, key = args.first[0], args.first[1]
    elsif args.size == 2
      val, key = args
    else
      return false
    end
    !getprop(val, key).nil?
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

  def self.typify(value)
    return "null" if value.nil?
    return "array" if islist(value)
    return "object" if ismap(value)
    return "boolean" if [true, false].include?(value)
    return "function" if isfunc(value)
    return "number" if value.is_a?(Numeric)
    value.class.to_s.downcase
  end

  def self.walk(val, apply, key = nil, parent = nil, path = [])
    if isnode(val)
      items(val).each do |ckey, child|
        new_path = path + [ckey.to_s]
        setprop(val, ckey, walk(child, apply, ckey, val, new_path))
      end
    end
    apply.call(key, val, parent, path || [])
  end

  # --- Deep Merge Helpers for merge ---
  #
  # deep_merge recursively combines two nodes.
  # For hashes, keys in b override those in a.
  # For arrays, merge index-by-index; b’s element overrides a’s at that position,
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
  def self.merge(val)
    return val unless islist(val)
    list = val
    lenlist = list.size
    return nil if lenlist == 0
    result = list[0]
    (1...lenlist).each do |i|
      result = deep_merge(result, list[i])
    end
    result
  end

  # --- getpath function ---
  #
  # Looks up a value deep inside a node using a dot-delimited path.
  # A path that begins with an empty string (i.e. a leading dot) is treated as relative
  # and resolved against the `current` parameter.
  # The optional state hash can provide a :base key and a :handler.
  def self.getpath(path, store, current = nil, state = nil)
    log("getpath: called with path=#{path.inspect}, store=#{store.inspect}, current=#{current.inspect}, state=#{state.inspect}")
    parts =
      if islist(path)
        path
      elsif path.is_a?(String)
        arr = path.split(S_DT)
        log("getpath: split path into parts=#{arr.inspect}")
        arr = [S_MT] if arr.empty?  # treat empty string as [S_MT]
        arr
      else
        UNDEF
      end
    if parts.equal?(UNDEF)
      log("getpath: parts is UNDEF, returning nil")
      return nil
    end

    root = store
    val = store
    base = state && state[:base]
    log("getpath: initial root=#{root.inspect}, base=#{base.inspect}")

    # If there is no path (or if path consists of a single empty string)
    if path.nil? || store.nil? || (parts.length == 1 && parts[0] == S_MT)
      # When no state/base is provided, return store directly.
      if base.nil?
        val = store
        log("getpath: no base provided; returning entire store: #{val.inspect}")
      else
        val = _getprop(store, base, UNDEF)
        log("getpath: empty or nil path; looking up base key #{base.inspect} gives #{val.inspect}")
      end
    elsif parts.length > 0
      pI = 0
      if parts[0] == S_MT
        pI = 1
        root = current
        log("getpath: relative path detected. Switching root to current: #{current.inspect}")
      end

      part = (pI < parts.length ? parts[pI] : UNDEF)
      first = _getprop(root, part, UNDEF)
      log("getpath: first lookup for part=#{part.inspect} in root=#{root.inspect} yielded #{first.inspect}")
      # If not found at top level and no value present, try fallback if base is given.
      if (first.nil? || first.equal?(UNDEF)) && pI == 0 && !base.nil?
        fallback = _getprop(root, base, UNDEF)
        log("getpath: fallback lookup: _getprop(root, base) returned #{fallback.inspect}")
        val = _getprop(fallback, part, UNDEF)
        log("getpath: fallback lookup for part=#{part.inspect} yielded #{val.inspect}")
      else
        val = first
      end
      pI += 1
      while !val.equal?(UNDEF) && pI < parts.length
        log("getpath: descending into part #{parts[pI].inspect} with current val=#{val.inspect}")
        val = _getprop(val, parts[pI], UNDEF)
        pI += 1
      end
    end

    if state && state[:handler] && state[:handler].respond_to?(:call)
      ref = pathify(path)
      log("getpath: applying state handler with ref=#{ref.inspect} and val=#{val.inspect}")
      val = state[:handler].call(state, val, current, ref, store)
      log("getpath: state handler returned #{val.inspect}")
    end

    final = val.equal?(UNDEF) ? nil : val
    log("getpath: final returning #{final.inspect}")
    final
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

end
