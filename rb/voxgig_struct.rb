require 'json'
require 'uri'

module VoxgigStruct
  # Deep-clone a JSON-like structure (nil remains nil)
  def self.clone(val)
    return nil if val.nil?
    JSON.parse(JSON.generate(val))
  end

  # Escape regular expression special characters.
  def self.escre(s)
    s = s.nil? ? "" : s
    Regexp.escape(s)
  end

  # Escape a string for use in URLs.
  # We use URI::DEFAULT_PARSER.escape with a safe pattern that permits only unreserved characters.
  # (Unreserved: A-Z, a-z, 0-9, "-", ".", "_", "~")
  def self.escurl(s)
    s = s.nil? ? "" : s
    URI::DEFAULT_PARSER.escape(s, /[^A-Za-z0-9\-\.\_\~]/)
  end

  # Safely get a property by key, returning an alternative if not found.
  # For Arrays, if the key is a numeric string or an integer, we use it as an index.
  # For Hashes, if a key isn’t found and the key is an Integer, we also try its string form.
  def self.getprop(val, key, alt = nil)
    return alt if val.nil? || key.nil?
    
    if val.is_a?(Array)
      if key.is_a?(String)
        return alt unless key =~ /\A\d+\z/
        key = key.to_i
      elsif !key.is_a?(Integer)
        return alt
      end
    end

    out = val[key]
    if out.nil? && key.is_a?(Integer) && val.is_a?(Hash)
      out = val[key.to_s]
    end
    out.nil? ? alt : out
  end

  # Check for an "empty" value: nil, empty string, false, 0, empty array or hash.
  def self.isempty(val)
    return true if val.nil? || val == "" || val == false || val == 0
    return true if val.is_a?(Array) && val.empty?
    return true if val.is_a?(Hash) && val.empty?
    false
  end

  # Check if a key is valid: a non-empty string or an integer.
  def self.iskey(key)
    (key.is_a?(String) && !key.empty?) || key.is_a?(Integer)
  end

  # Return true if val is an Array.
  def self.islist(val)
    val.is_a?(Array)
  end

  # Return true if val is a Hash.
  def self.ismap(val)
    val.is_a?(Hash)
  end

  # A node is defined as either a map or a list.
  def self.isnode(val)
    ismap(val) || islist(val)
  end

  # Return an array of [key, value] pairs.
  def self.items(val)
    if ismap(val)
      val.to_a
    elsif islist(val)
      val.each_with_index.map { |v, i| [i, v] }
    else
      []
    end
  end

  # Safely set a property on a parent (hash or array).
  # If no value is provided (i.e. using our marker :no_val_provided), we delete the key.
  # (Note: an explicit nil is preserved.)
  def self.setprop(parent, key, val = :no_val_provided)
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
    parent
  end

  # Safely stringify a value.
  def self.stringify(val, maxlen = nil)
    begin
      json = JSON.generate(val)
    rescue
      json = val.to_s
    end
    json = json.gsub('"', '')
    if maxlen && json.length > maxlen
      js = json[0, maxlen]
      json = js[0, maxlen - 3] + '...'
    end
    json
  end
end
