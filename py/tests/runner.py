# Test runner that uses the test model in build/test.

import os
import json
import re
from typing import Any, Dict, List, Callable, TypedDict, Optional, Union

from voxgig_struct import (
    clone,
    getpath,
    inject,
    items,
    stringify,
    walk,
)


NULLMARK = '__NULL__'


class StructUtils:
    def __init__(self):
        pass

    def clone(self, *args, **kwargs):
        return clone(*args, **kwargs)

    def getpath(self, *args, **kwargs):
        return getpath(*args, **kwargs)

    def inject(self, *args, **kwargs):
        return inject(*args, **kwargs)

    def items(self, *args, **kwargs):
        return items(*args, **kwargs)

    def stringify(self, *args, **kwargs):
        return stringify(*args, **kwargs)

    def walk(self, *args, **kwargs):
        return walk(*args, **kwargs)
    

class Utility:
    def __init__(self, opts=None):
        self._opts = opts
        self._struct = StructUtils()

    def struct(self):
        return self._struct

    def check(self, ctx):
        zed = "ZED"
    
        if self._opts is None:
            zed += ""
        else:
            foo = self._opts.get("foo")
            zed += "0" if foo is None else str(foo)

        zed += "_"
        zed += str(ctx.get("bar"))

        return {"zed": zed}
        

class Client:
    def __init__(self, opts=None):
        self._utility = Utility(opts)

    @staticmethod
    def test(opts=None):
        return Client(opts)

    def utility(self):
        return self._utility


class RunPack(TypedDict):
    spec: Dict[str, Any]
    runset: Callable
    runsetflags: Callable
    subject: Callable
    client: Optional[Client]


def makeRunner(testfile: str, client_in=None):
    client = client_in or Client.test()
    
    def runner(
        name: str,
        store: Any = None,
    ) -> RunPack:
        store = store or {}
        
        utility = client.utility()
        structUtils = utility.struct()
        
        spec = resolve_spec(name, testfile)
        clients = resolve_clients(spec, store, structUtils)
        subject = resolve_subject(name, utility)
            
        def runsetflags(testspec, flags, testsubject):
            nonlocal subject, clients
            
            subject = testsubject or subject
            flags = resolve_flags(flags)
            testspecmap = fixJSON(testspec, flags)
            testset = testspecmap['set']
                    
            for entry in testset:
                try:
                    entry = resolve_entry(entry, flags)

                    testpack = resolve_testpack(name, entry, subject, client, clients)
                    args = resolve_args(entry, testpack, structUtils)
                    
                    # Execute the test function
                    res = testpack["subject"](*args)
                    res = fixJSON(res, flags)
                    entry['res'] = res
                    check_result(entry, res, structUtils)
                    
                except Exception as err:
                    handle_error(entry, err, structUtils)

        def runset(testspec, testsubject):
            return runsetflags(testspec, {}, testsubject)
                    
        runpack = {
            "spec": spec,
            "runset": runset,
            "runsetflags": runsetflags,
            "subject": subject,
            "client": client
        }

        return runpack
    
    return runner


def resolve_spec(name: str, testfile: str) -> Dict[str, Any]:
    with open(os.path.join(os.path.dirname(__file__), testfile), 'r', encoding='utf-8') as f:
        alltests = json.load(f)

    if 'primary' in alltests and name in alltests['primary']:
        spec = alltests['primary'][name]
    elif name in alltests:
        spec = alltests[name]
    else:
        spec = alltests
        
    return spec


def resolve_clients(spec: Dict[str, Any], store: Any, structUtils: Any) -> Dict[str, Any]:
    clients = {}
    if 'DEF' in spec and 'client' in spec['DEF']:
        for client_name, client_val in structUtils.items(spec['DEF']['client']):
            # Get client options
            client_opts = client_val.get('test', {}).get('options', {})
            
            # Apply store injections if needed
            if isinstance(store, dict):
                structUtils.inject(client_opts, store)
                
            # Create and store the client
            clients[client_name] = Client.test(client_opts)
            
    return clients


def resolve_subject(name: str, container: Any, subject=None):
    return subject or getattr(container, name, None)


def check_result(entry, res, structUtils):
    if 'match' not in entry or 'out' in entry:
        try:
            cleaned_res = json.loads(json.dumps(res, default=str))
        except:
            # If can't be serialized just use the original
            cleaned_res = res
            
        # Compare result with expected output using deep equality
        if cleaned_res != entry.get('out'):
            print('ENTRY', entry.get('out'), '|||', cleaned_res)
            raise AssertionError(
                f"Expected: {entry.get('out')}, got: {cleaned_res}\n"
                f"Entry: {json.dumps(entry, indent=2, default=jsonfallback)}"
            )
    
    # If we have a match pattern, use it
    if 'match' in entry:
        match(
            entry['match'],
            {'in': entry.get('in'), 'out': entry.get('res'), 'ctx': entry.get('ctx')},
            structUtils
        )

def handle_error(entry, err, structUtils):
    # Record the error in the entry
    entry['thrown'] = str(err)
    entry_err = entry.get('err')
    
    # If the test expects an error
    if entry_err is not None:
        # If it's any error or matches expected pattern
        if entry_err is True or matchval(entry_err, str(err), structUtils):
            # If we also need to match error details
            if 'match' in entry:
                match(
                    entry['match'],
                    {
                        'in': entry.get('in'),
                        'out': entry.get('res'),
                        'ctx': entry.get('ctx'),
                        'err': err
                    },
                    structUtils
                )
            # Error was expected, continue
            return True
        
        # Expected error didn't match the actual error
        raise AssertionError_(
            f"ERROR MATCH: [{structUtils.stringify(entry_err)}] <=> [{str(err)}]"
        )
    # If the test doesn't expect an error
    elif isinstance(err, AssertionError):
        # Propagate assertion errors with added context
        raise AssertionError_(
            f"{str(err)}\n\nENTRY: {json.dumps(entry, indent=2, default=jsonfallback)}"
        )
    else:
        # For other errors, include the full error stack
        import traceback
        raise AssertionError_(
            f"{traceback.format_exc()}\nENTRY: "+
            f"{json.dumps(entry, indent=2, default=jsonfallback)}"
        )

    
def resolve_testpack(
        name,
        entry,
        subject,
        client,
        clients,
):
    testpack = {
        "client": client,
        "subject": subject,
        "utility": client.utility(),
    }
    
    if 'client' in entry:
        test_client = clients[entry['client']]
        testpack["client"] = test_client
        testpack["utility"] = test_client.utility()
        testpack["subject"] = resolve_subject(name, testpack["utility"])
        
    return testpack


def resolve_args(entry, testpack, structUtils):
    # Default to using the input as the only argument
    args = [structUtils.clone(entry['in'])] if 'in' in entry else []
    
    # If entry specifies context or arguments, use those instead
    if 'ctx' in entry:
        args = [entry['ctx']]
    elif 'args' in entry:
        args = entry['args']
        
    # If we have context or arguments, we might need to patch them
    if ('ctx' in entry or 'args' in entry) and len(args) > 0:
        first_arg = args[0]
        if isinstance(first_arg, dict):
            # Clone the argument
            first_arg = structUtils.clone(first_arg)
            args[0] = first_arg
            entry['ctx'] = first_arg
            
            # Add client and utility to the argument
            first_arg["client"] = testpack["client"]
            first_arg["utility"] = testpack["utility"]
            
    return args


def resolve_flags(flags: Dict[str, Any] = None) -> Dict[str, bool]:
    if flags is None:
        flags = {}
        
    if "null" not in flags:
        flags["null"] = True
        
    return flags


def resolve_entry(entry: Dict[str, Any], flags: Dict[str, bool]) -> Dict[str, Any]:
    # Set default output value for missing 'out' field
    if flags.get("null", True) and "out" not in entry:
        entry["out"] = NULLMARK
        
    return entry


def fixJSON(obj, flags):
        
    # Handle nulls
    if obj is None:
        if flags.get("null", True):
            return NULLMARK
        return None
        
    # Handle collections recursively
    elif isinstance(obj, list):
        return [fixJSON(item, flags) for item in obj]
    elif isinstance(obj, dict):
        return {k: fixJSON(v, flags) for k, v in obj.items()}
        
    # Special case for numeric values to match JSON behavior across languages
    elif isinstance(obj, float):
        # Convert integers represented as floats to actual integers
        if obj == int(obj):
            return int(obj)
            
    # Return everything else unchanged
    return obj


def jsonfallback(obj):
    return f"<non-serializable: {type(obj).__name__}>"


def match(check, base, structUtils):
    # Use walk function to iterate through the check structure
    def walk_apply(key, val, parent, path):
        # Process scalar values only (non-objects)
        if not isinstance(val, (dict, list)):
            # Get the corresponding value from base
            baseval = structUtils.getpath(path, base)
            
            # Check if values match
            if not matchval(val, baseval, structUtils):
                raise AssertionError_(
                    f"MATCH: {'.'.join(map(str, path))}: "
                    f"[{structUtils.stringify(val)}] <=> [{structUtils.stringify(baseval)}]"
                )
        return val
        
    # Use walk to apply the check function to each node
    structUtils.walk(check, walk_apply)

    
def matchval(check, base, structUtils):
    """
    Check if a value matches the expected pattern.
    
    Args:
        check: Expected value or pattern
        base: Actual value to check
        structUtils: Struct utilities for data manipulation
        
    Returns:
        True if the value matches, False otherwise
    """
    # Handle undefined special case
    if check == '__UNDEF__':
        check = None
        
    # Direct equality check
    if check == base:
        return True
        
    # String-based pattern matching
    if isinstance(check, str):
        # Convert base to string for comparison
        base_str = structUtils.stringify(base)
        
        # Check for regex pattern with /pattern/ syntax
        regex_match = re.match(r'^/(.+)/$', check)
        
        if regex_match:
            pattern = regex_match.group(1)
            return re.search(pattern, base_str) is not None
        else:
            # Case-insensitive substring check
            return structUtils.stringify(check).lower() in base_str.lower()
    
    # Functions automatically pass
    elif callable(check):
        return True
        
    # No match
    return False


def nullModifier(val, key, parent, _state=None, _current=None, _store=None):
    if NULLMARK == val:
        parent[key] = None
    elif isinstance(val, str):
        parent[key] = val.replace(NULLMARK, "null")


# Export the necessary components similar to TypeScript
__all__ = [
    'NULLMARK',
    'nullModifier',
    'makeRunner',
    'Client',
]

