# Struct Lua Testing Guide

## Overview

This repository contains the `struct` Lua module and its test suite. The module provides utility functions for manipulating JSON-like data structures in Lua.

## Directory Structure

```
.
├── makefile
├── setup.sh
├── src
│   └── struct.lua
├── struct.rockspec
└── test
    ├── runner.lua
    └── struct_test.lua
```

## Setup Instructions

### First-Time Setup

Run the setup command to install Lua and all required dependencies:

```bash
make setup
```

This script will:
- Install Lua 5.3+ and LuaRocks if not already present
- Install required Lua packages (busted, luassert, dkjson, luafilesystem)
- Configure your environment for testing

### Verify Installation

Confirm the installation was successful:

```bash
lua -v
luarocks list
```

You should see Lua version 5.3+ and the installed packages listed.

## Running Tests

### Using Make (Recommended)

From the project root directory, simply run:

```bash
make test
```

### Manual Test Execution

If you need to run tests manually:

1. **Set the Lua path** to include necessary directories:

   ```bash
   export LUA_PATH="./src/?.lua;./test/?.lua;./?.lua;$LUA_PATH"
   ```

2. **Run the test** using the busted framework:

   ```bash
   busted test/struct_test.lua
   ```

### Dependency Issues

If you encounter errors related to missing dependencies:

```bash
# Reinstall dependencies manually
luarocks install busted
luarocks install luassert
luarocks install dkjson
luarocks install luafilesystem
```
## For Developers

When modifying the `struct.lua` file, always run the test suite to ensure your changes maintain compatibility:

```bash
make test
```

---

If you encounter any issues or have questions, please file an issue in the project repository.
