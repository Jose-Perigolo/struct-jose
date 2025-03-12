require 'minitest/autorun'
require 'json'
require_relative 'voxgig_struct'  # loads voxgig_struct.rb with module VoxgigStruct

# Load the test spec JSON file.
# Adjust the path as needed.
TESTSPEC = JSON.parse(File.read(File.join(File.dirname(__FILE__), '..', 'build', 'test', 'test.json')))

class TestVoxgigStruct < Minitest::Test
  # Check that all functions exist
  def test_minor_exists
    assert_respond_to VoxgigStruct, :clone
    assert_respond_to VoxgigStruct, :escre
    assert_respond_to VoxgigStruct, :escurl
    assert_respond_to VoxgigStruct, :getprop
    assert_respond_to VoxgigStruct, :isempty
    assert_respond_to VoxgigStruct, :iskey
    assert_respond_to VoxgigStruct, :islist
    assert_respond_to VoxgigStruct, :ismap
    assert_respond_to VoxgigStruct, :isnode
    assert_respond_to VoxgigStruct, :items
    assert_respond_to VoxgigStruct, :setprop
    assert_respond_to VoxgigStruct, :stringify
  end

  # Helper: iterate over test cases in a given set.
  def run_test_set(test_cases)
    test_cases.each do |entry|
      yield(entry["in"], entry["out"]) if entry.key?("out")
    end
  end

  def test_minor_clone
    run_test_set(TESTSPEC["minor"]["clone"]["set"]) do |input, expected|
      result = VoxgigStruct.clone(input)
      assert_equal expected, result, "clone(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_isnode
    run_test_set(TESTSPEC["minor"]["isnode"]["set"]) do |input, expected|
      result = VoxgigStruct.isnode(input)
      assert_equal expected, result, "isnode(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_ismap
    run_test_set(TESTSPEC["minor"]["ismap"]["set"]) do |input, expected|
      result = VoxgigStruct.ismap(input)
      assert_equal expected, result, "ismap(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_islist
    run_test_set(TESTSPEC["minor"]["islist"]["set"]) do |input, expected|
      result = VoxgigStruct.islist(input)
      assert_equal expected, result, "islist(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_iskey
    run_test_set(TESTSPEC["minor"]["iskey"]["set"]) do |input, expected|
      result = VoxgigStruct.iskey(input)
      assert_equal expected, result, "iskey(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_items
    run_test_set(TESTSPEC["minor"]["items"]["set"]) do |input, expected|
      result = VoxgigStruct.items(input)
      assert_equal expected, result, "items(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_getprop
    run_test_set(TESTSPEC["minor"]["getprop"]["set"]) do |params, expected|
      val = params["val"]
      key = params["key"]
      alt = params.key?("alt") ? params["alt"] : nil
      result = VoxgigStruct.getprop(val, key, alt)
      assert_equal expected, result, "getprop(#{val.inspect}, #{key.inspect}, #{alt.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_setprop
    run_test_set(TESTSPEC["minor"]["setprop"]["set"]) do |params, expected|
      parent = params.key?("parent") ? params["parent"] : {}
      key = params["key"]
      # If the "val" key is missing, use our marker so that setprop deletes the key.
      val = params.has_key?("val") ? params["val"] : :no_val_provided
      parent_clone = Marshal.load(Marshal.dump(parent))
      result = VoxgigStruct.setprop(parent_clone, key, val)
      assert_equal expected, result, "setprop(#{params.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_isempty
    run_test_set(TESTSPEC["minor"]["isempty"]["set"]) do |input, expected|
      result = VoxgigStruct.isempty(input)
      assert_equal expected, result, "isempty(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_stringify
    run_test_set(TESTSPEC["minor"]["stringify"]["set"]) do |params, expected|
      val = params["val"]
      max = params["max"]
      result = max ? VoxgigStruct.stringify(val, max) : VoxgigStruct.stringify(val)
      assert_equal expected, result, "stringify(#{params.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_escre
    run_test_set(TESTSPEC["minor"]["escre"]["set"]) do |input, expected|
      result = VoxgigStruct.escre(input)
      assert_equal expected, result, "escre(#{input.inspect}) should equal #{expected.inspect}"
    end
  end

  def test_minor_escurl
    run_test_set(TESTSPEC["minor"]["escurl"]["set"]) do |input, expected|
      result = VoxgigStruct.escurl(input)
      assert_equal expected, result, "escurl(#{input.inspect}) should equal #{expected.inspect}"
    end
  end
end
