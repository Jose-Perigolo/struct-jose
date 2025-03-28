#!/bin/bash
# setup.sh - Install Lua and dependencies

# Verify administrator privileges if needed
check_sudo() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Some operations may require administrator privileges"
  fi
}

# Install Lua and LuaRocks based on OS
install_lua() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Installing Lua environment on macOS..."
    if ! command -v brew >/dev/null; then
      echo "Homebrew not found. Please install Homebrew first: https://brew.sh/"
      exit 1
    fi
    brew install lua luarocks
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Installing latest Lua environment on Linux..."
    sudo apt-get update
    sudo apt-get install -y build-essential libreadline-dev
    
    # Download and install latest Lua from source
    cd /tmp
    curl -R -O "https://www.lua.org/ftp/lua-5.4.7.tar.gz"  # Current latest stable
    tar xvfz "lua-5.4.7.tar.gz"
    cd "lua-5.4.7"
    make linux
    sudo make install
    
    # Download and install latest LuaRocks from source
    cd /tmp
    curl -R -O "https://luarocks.org/releases/luarocks-3.11.1.tar.gz"
    tar xvfz "luarocks-3.11.1.tar.gz"
    cd "luarocks-3.11.1"
    ./configure --with-lua-include=/usr/local/include
    make
    sudo make install
  else
    echo "Unsupported OS: $OSTYPE"
    exit 1
  fi
}

# Install required Lua packages
install_dependencies() {
  echo "Installing Lua dependencies..."
  luarocks install busted
  luarocks install luassert
  luarocks install dkjson
  luarocks install luafilesystem
}

# Main execution
check_sudo

if ! command -v lua >/dev/null; then
  echo "Lua not found, installing..."
  install_lua
else
  echo "Lua found: $(lua -v)"
fi

if ! command -v luarocks >/dev/null; then
  echo "LuaRocks not found, installing..."
  install_lua
else
  echo "LuaRocks found: $(luarocks --version)"
fi

install_dependencies
echo "Setup complete! Run 'make test' to run the tests."
