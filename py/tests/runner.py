
import os
import json
import re
from typing import Any, Dict

class AssertionError_(AssertionError):
    pass

def runner(name: str, store: Any, testfile: str, provider: Any):

    client = provider.test()
    utility = client.utility()
    struct = utility["struct"] 
    
    clone = struct["clone"]       
    getpath = struct["getpath"]       
    inject = struct["inject"]       
    ismap = struct["ismap"]       
    items = struct["items"]       
    stringify = struct["stringify"]       
    walk = struct["walk"]       
    isnode = struct["isnode"]

    # Read and parse the test JSON file
    with open(os.path.join(os.path.dirname(__file__), testfile), 'r', encoding='utf-8') as f:
        alltests = json.load(f)

    # Attempt to find the requested spec in the JSON
    if 'primary' in alltests and name in alltests['primary']:
        spec = alltests['primary'][name]
    elif name in alltests:
        spec = alltests[name]
    else:
        spec = alltests

    # Build up any additional clients from a DEF section, if present
    clients = {}
    if 'DEF' in spec and 'client' in spec['DEF']:
        for c_name, c_val in items(spec['DEF']['client']):
            copts = c_val.get('test', {}).get('options', {})
            if ismap(store):
                inject(copts, store)
            clients[c_name] = provider.test(copts)

    subject = getattr(utility, name, None)

    def runset(testspec: Dict, testsubject=None, flags: Dict = None): # , makesubject=None):
        nonlocal subject, clients

        if flags is None:
            flags = {}

        flags["fixjson"] = flags.get("fixjson", True) 
        
        if testsubject is None:
            testsubject = subject

        # Each testspec should have a "set" array of test entries
        for entry in testspec['set']:
            try:
                if not "out" in entry:
                    entry["out"] = None

                if flags["fixjson"]:
                    entry = fixJSON(entry)
                
                testclient = client
                
                # If a particular entry wants to use a different client:
                if 'client' in entry:
                    testclient = clients[entry['client']]
                    testsubject = testclient.utility()[name]

                # If there's a "makesubject" function, transform the subject
                # if makesubject:
                #     testsubject = makesubject(testsubject)

                # Build up the call arguments:
                if 'ctx' in entry:
                    args = [entry['ctx']]
                elif 'args' in entry:
                    args = entry['args']
                else:
                    # Default to using entry.in if present
                    args = [clone(entry['in'])] if 'in' in entry else []

                # If we have a context or arguments, we might need to patch them:
                if 'ctx' in entry or 'args' in entry:
                    first_arg = args[0]
                    if ismap(first_arg):
                        # Deep clone first_arg
                        first_arg = clone(first_arg)
                        args[0] = first_arg
                        entry['ctx'] = first_arg
                        # Insert .client and .utility references
                        first_arg.client = testclient
                        first_arg.utility = testclient.utility()

                # print("ARGS", args)
                        
                res = testsubject(*args)
                res = fixJSON(res)
                entry['res'] = res

                # If we expect an output:
                if ('match' not in entry) or ('out' in entry):
                    # Remove functions/etc. by JSON round trip
                    cleaned_res = json.loads(json.dumps(res, default=str))
                    expected_out = entry.get('out')
                    if cleaned_res != expected_out:
                        raise AssertionError_(
                            f"Expected {expected_out}, got {cleaned_res}\n"
                            f"Entry: {json.dumps(entry, indent=2)}"
                        )

                # If we also need to do "match" checks
                if 'match' in entry:
                    match(entry['match'], {
                        'in': entry.get('in'),
                        'out': entry.get('res'),
                        'ctx': entry.get('ctx')
                    })

            except Exception as err:
                # The TypeScript code tries to handle "err" or "err.message" matching.
                entry['thrown'] = str(err)
                entry_err = entry.get('err')

                if entry_err is not None:
                    # If "err" is True or a substring/regex match is required:
                    if entry_err is True or matchval(entry_err, str(err)):
                        # If we still have to do "match" checks with the error
                        if 'match' in entry:
                            match(entry['match'], {
                                'in': entry.get('in'),
                                'out': entry.get('res'),
                                'ctx': entry.get('ctx'),
                                'err': str(err)
                            })
                        # This means error was expected, so skip fail
                        continue
                    else:
                        raise AssertionError_(
                            f"ERROR MATCH: [{stringify(entry_err)}] <=> [{str(err)}]\n"
                            f"Entry: {json.dumps(entry, indent=2)}"
                        )
                else:
                    # Not an expected error, re-raise with more info
                    raise AssertionError_(
                        f"{str(err)}\n\nENTRY: {json.dumps(entry, indent=2)}"
                    )

    def match(check: Any, base: Dict[str, Any]):
        """
        Recursively walk the `check` structure, verifying `base` has the expected
        values in the same paths.
        """
        def walker(obj, path=None):
            if path is None:
                path = []
            if ismap(obj):
                # It's a dict
                for k, v in obj.items():
                    new_path = path + [k]
                    if not isnode(v):
                        baseval = getpath(new_path, base)
                        if not matchval(v, baseval):
                            raise AssertionError_(
                                f"MATCH: {'.'.join(map(str, new_path))}: "
                                f"[{stringify(v)}] <=> [{stringify(baseval)}]"
                            )
                    walker(v, new_path)
            elif isinstance(obj, list):
                for i, v in enumerate(obj):
                    new_path = path + [i]
                    if not isnode(v):
                        baseval = getpath(new_path, base)
                        if not matchval(v, baseval):
                            raise AssertionError_(
                                f"MATCH: {'.'.join(map(str, new_path))}: "
                                f"[{stringify(v)}] <=> [{stringify(baseval)}]"
                            )
                    walker(v, new_path)
            else:
                # If it's neither list nor dict, the check for "node" was above
                pass

        walker(check)

    def matchval(check: Any, base: Any) -> bool:
        """
        Replicates the "matchval" logic:
          - If check is the magic string '__UNDEF__', treat as None/undefined
          - If check is a regex (like '/something/'), test it
          - Otherwise, check for substring (case-insensitive)
          - If check is a function/callable, consider it automatically passed
        """
        if check == '__UNDEF__':
            check = None

        # Direct equality
        if check == base:
            return True

        # If not equal, see if we can do a regex or substring match
        if isinstance(check, str):
            base_str = stringify(base)
            regex_match = re.match(r'^/(.+)/$', check)
            if regex_match:
                pattern = regex_match.group(1)
                return re.search(pattern, base_str) is not None
            else:
                return check.lower() in base_str.lower()
        elif callable(check):
            # If it's a function, the TS code just allowed pass
            return True

        return False

    # Return the same final structure that TS code returns
    out = {
        "spec": spec,
        "runset": runset,
        "subject": subject,
    }

    # print("RUNNER", out["spec"]["minor"]["islist"])
    
    return out


def fixJSON(obj):
    if obj is None:
        return "__NULL__"
    elif isinstance(obj, list):
        return [fixJSON(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: fixJSON(v) for k, v in obj.items()}
    else:
        return obj

def unfixJSON(obj):
    if "__NULL__" == obj:
        return None
    elif isinstance(obj, list):
        return [unfixJSON(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: unfixJSON(v) for k, v in obj.items()}
    else:
        return obj
