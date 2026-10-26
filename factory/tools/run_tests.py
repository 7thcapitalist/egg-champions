"""Run a game's Luau unit tests headless, with no Studio and no person.

    python factory/tools/run_tests.py <game-dir>

Loads every module under <game-dir>/src/shared into the Luau interpreter
pinned in rokit.toml, with a small stand-in for Roblox's `script` tree and
`require`, then runs the spec modules listed in
<game-dir>/src/shared/testing/specs.luau through testing/Runner.luau.

The JSON data the Rojo project maps into ReplicatedStorage (for a game, its
generated config) is mounted at the same place in the stand-in tree, so a
shared module can reach it through `script.Parent.Parent` exactly as it does
in Studio, with no Roblox service.

Markdown documents a test may check against (every .md file in <game-dir>/notes
and <game-dir>/tuning) are mounted as modules that return their text, at
ReplicatedStorage.Docs.<folder>.<file name without .md>. They exist only in this
test tree, not in Studio, so a spec that reads them only runs here.

Rule modules (src/shared/rules/) must need no Roblox service. Every one of
them is loaded first, and any that touches `game`, `workspace`, `Instance`,
`Enum` or another engine global fails the run with a message naming it.
Rule modules must also be deterministic: `math.random` and `os.time` are
trapped the same way (and caught by a static scan), because rules take an
injected rng or time instead.

Every `*.spec.luau` file under src/shared must be listed in
src/shared/testing/specs.luau; one that is not fails the run, naming the file,
so a spec can never be skipped silently.

Before the game's own tests, a few self-tests run the harness on tiny fixture
games (using the game's own testing/Runner.luau) to prove that each of these
checks, and Runner's NaN and infinity handling, still fail when they should.

Prints one line per failure and a final count. Exits 0 when every test
passed, 1 otherwise. Standard library only.
"""

import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TIMEOUT = 120
SOURCE_SUFFIXES = (".luau", ".lua")


def fail(message):
    print("run_tests: " + message)
    sys.exit(1)


def pinned_luau():
    """Return (tool name, pin) for the Luau interpreter named in rokit.toml."""
    toml = ROOT / "rokit.toml"
    if not toml.is_file():
        fail("rokit.toml not found at the repo root")
    for line in toml.read_text(encoding="utf-8").splitlines():
        m = re.match(r'\s*([A-Za-z0-9_-]+)\s*=\s*"luau-lang/luau@([^"]+)"', line)
        if m:
            return m.group(1), m.group(2)
    fail('rokit.toml pins no Luau interpreter; add luau = "luau-lang/luau@<version>"')


def find_luau(name):
    found = shutil.which(name)
    if found:
        return found
    # Rokit's own bin folder, in case it is not on PATH yet.
    exe = name + (".exe" if os.name == "nt" else "")
    candidate = Path.home() / ".rokit" / "bin" / exe
    if candidate.is_file():
        return str(candidate)
    fail("the Luau interpreter '%s' is not on PATH; run `rokit install`" % name)


def long_string(text):
    """Quote text as a Lua long string that cannot be closed early."""
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    # A newline right after the opening bracket is dropped by Lua; add one.
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def module_name(filename):
    for suffix in SOURCE_SUFFIXES:
        if filename.endswith(suffix):
            return filename[: -len(suffix)]
    return None


ENGINE_NAMES = (
    "game", "Game", "workspace", "Workspace", "Instance", "Enum", "plugin", "settings",
    "UserSettings", "task", "wait", "delay", "spawn", "tick", "Vector3", "CFrame", "Color3",
    "UDim2", "TweenInfo", "RaycastParams",
)
ENGINE_USE = re.compile(r"(?<![\w.:])(%s)\b" % "|".join(ENGINE_NAMES))
LONG_BLOCK = re.compile(r"--\[(=*)\[.*?\]\1\]|\[(=*)\[.*?\]\2\]", re.DOTALL)
SHORT_PARTS = re.compile(r"--[^\n]*|\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`")


def engine_uses(source):
    """Names of Roblox engine globals a module's code uses, ignoring comments and strings."""
    code = LONG_BLOCK.sub(lambda m: "\n" * m.group(0).count("\n"), source)
    code = SHORT_PARTS.sub(lambda m: "\n" * m.group(0).count("\n"), code)
    found = []
    for n, line in enumerate(code.splitlines(), 1):
        for m in ENGINE_USE.finditer(line):
            found.append("'%s' on line %d" % (m.group(1), n))
    return found


IMPURE_NAMES = ("math.random", "os.time")
IMPURE_USE = re.compile(r"(?<![\w.:])(math|os)\s*\.\s*(random|time)\b")
IMPURE_HINT = "rules take an injected rng or time instead"


def impure_uses(source):
    """Uses of math.random or os.time in a module's code, ignoring comments and strings."""
    code = LONG_BLOCK.sub(lambda m: "\n" * m.group(0).count("\n"), source)
    code = SHORT_PARTS.sub(lambda m: "\n" * m.group(0).count("\n"), code)
    found = []
    for n, line in enumerate(code.splitlines(), 1):
        for m in IMPURE_USE.finditer(line):
            found.append("'%s.%s' on line %d" % (m.group(1), m.group(2), n))
    return found


def scan_rules(shared, game_dir):
    """Static check: rule modules name no Roblox engine global, math.random or os.time."""
    problems = []
    rules = shared / "rules"
    if not rules.is_dir():
        return problems
    for path in sorted(rules.rglob("*")):
        name = module_name(path.name)
        if not path.is_file() or name is None or name.endswith(".spec"):
            continue
        source = path.read_text(encoding="utf-8")
        rel = path.relative_to(game_dir).as_posix()
        uses = engine_uses(source)
        if uses:
            problems.append("FAIL rule module %s: uses the Roblox engine (%s); rule modules must need no Roblox service"
                            % (rel, ", ".join(uses)))
        impure = impure_uses(source)
        if impure:
            problems.append("FAIL rule module %s: uses %s; %s"
                            % (rel, ", ".join(impure), IMPURE_HINT))
    return problems


def collect(shared, game_dir):
    """Lua table entries describing every folder and module under shared."""
    entries = []
    for dirpath, dirnames, filenames in os.walk(shared):
        dirnames.sort()
        here = Path(dirpath)
        rel_dir = here.relative_to(shared).as_posix()
        rel_dir = "" if rel_dir == "." else rel_dir
        if rel_dir:
            entries.append('{kind = "folder", path = %s}' % long_string(rel_dir))
        for filename in sorted(filenames):
            name = module_name(filename)
            if name is None or name.endswith(".server") or name.endswith(".client"):
                continue
            path = here / filename
            if name == "init":
                node = rel_dir
            else:
                node = (rel_dir + "/" + name) if rel_dir else name
            chunk = path.relative_to(game_dir).as_posix()
            entries.append(
                '{kind = "module", path = %s, chunk = %s, source = %s}'
                % (long_string(node), long_string(chunk), long_string(path.read_text(encoding="utf-8")))
            )
    return ",\n".join(entries)


def lua_string(text):
    out = []
    for ch in text:
        code = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif code < 32 or code == 127:
            out.append("\\%d" % code if code > 99 else "\\%03d" % code)
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def lua_value(value, where):
    """A JSON value as a Lua expression, matching how Rojo turns JSON into a table."""
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            fail("%s holds a number Lua cannot read: %r" % (where, value))
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, list):
        if any(item is None for item in value):
            fail("%s has a null inside a list, which a Lua array cannot hold" % where)
        return "{" + ", ".join(lua_value(item, where) for item in value) + "}"
    if isinstance(value, dict):
        parts = ["[%s] = %s" % (lua_string(str(k)), lua_value(v, where)) for k, v in value.items()]
        return "{" + ", ".join(parts) + "}"
    fail("%s holds a value of unknown kind %r" % (where, value))


def json_module(path, game_dir):
    where = path.relative_to(game_dir).as_posix() if path.is_relative_to(game_dir) else str(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as err:
        fail("%s is not valid JSON: %s" % (where, err))
    return "return " + lua_value(data, where)


def project_data(game_dir, shared):
    """Lua table entries for the JSON data the Rojo project maps into ReplicatedStorage.

    Paths are relative to ReplicatedStorage. src/shared itself is left out; it is
    collected as code. Only .json files are mounted, as Rojo would turn them
    into ModuleScripts that return a table.
    """
    project = game_dir / "default.project.json"
    if not project.is_file():
        return ""
    try:
        tree = json.loads(project.read_text(encoding="utf-8")).get("tree", {})
    except ValueError as err:
        fail("default.project.json is not valid JSON: %s" % err)
    storage = tree.get("ReplicatedStorage")
    if not isinstance(storage, dict):
        return ""
    entries = []
    shared_real = shared.resolve()

    def add_module(node_path, file):
        entries.append('{kind = "data", path = %s, source = %s}'
                       % (long_string(node_path), long_string(json_module(file, game_dir))))

    def walk(node, node_path):
        target = node.get("$path")
        if isinstance(target, str):
            source = (game_dir / target).resolve()
            if source == shared_real:
                return
            if source.is_dir():
                for file in sorted(source.iterdir()):
                    if file.is_file() and file.suffix == ".json" and not file.name.endswith(".project.json"):
                        add_module(node_path + "/" + file.stem, file)
            elif source.is_file() and source.suffix == ".json":
                add_module(node_path, source)
        for key, child in node.items():
            if not key.startswith("$") and isinstance(child, dict):
                walk(child, (node_path + "/" + key) if node_path else key)

    for key, child in storage.items():
        if not key.startswith("$") and isinstance(child, dict):
            walk(child, key)
    return ",\n".join(entries)


DOC_FOLDERS = ("notes", "tuning")


def project_docs(game_dir):
    """Lua table entries mounting the game's Markdown notes and reports as text.

    Each <game-dir>/<folder>/<name>.md becomes Docs/<folder>/<name>, a module
    that returns the file's text, so a spec can check code against a document.
    """
    entries = []
    for folder in DOC_FOLDERS:
        base = game_dir / folder
        if not base.is_dir():
            continue
        for file in sorted(base.iterdir()):
            if file.is_file() and file.suffix == ".md":
                text = file.read_text(encoding="utf-8")
                entries.append('{kind = "data", path = %s, source = %s}'
                               % (long_string("Docs/%s/%s" % (folder, file.stem)),
                                  long_string("return " + long_string(text))))
    return ",\n".join(entries)


BOOTSTRAP = r"""
local FILES = {
%FILES%
}

local DATA = {
%DATA%
}

local ENGINE_GLOBALS = {%ENGINE%}
local IMPURE_HINT = %IMPURE_HINT%

local meta = {}
local nodeMeta = {}

local function newNode(name, className, parent)
	local node = setmetatable({}, nodeMeta)
	meta[node] = { name = name, className = className, parent = parent, children = {}, order = {} }
	if parent then
		local p = meta[parent]
		p.children[name] = node
		table.insert(p.order, node)
	end
	return node
end

local function fullName(node)
	local m = meta[node]
	if m.parent and meta[m.parent].parent then
		return fullName(m.parent) .. "." .. m.name
	end
	return m.name
end

local methods = {}
function methods.FindFirstChild(self, name)
	return meta[self].children[name]
end
function methods.WaitForChild(self, name)
	local child = meta[self].children[name]
	if not child then
		error(name .. " is not a child of " .. fullName(self) .. " (it would wait forever)", 2)
	end
	return child
end
function methods.GetChildren(self)
	return table.clone(meta[self].order)
end
function methods.GetFullName(self)
	return fullName(self)
end
function methods.IsA(self, className)
	return meta[self].className == className
end

nodeMeta.__index = function(node, key)
	local m = meta[node]
	if key == "Name" then
		return m.name
	elseif key == "Parent" then
		return m.parent
	elseif key == "ClassName" then
		return m.className
	end
	local child = m.children[key]
	if child then
		return child
	end
	if methods[key] then
		return methods[key]
	end
	error(tostring(key) .. " is not a valid member of " .. fullName(node), 2)
end
nodeMeta.__newindex = function(node)
	error("the test tree is read-only (" .. fullName(node) .. ")", 2)
end
nodeMeta.__tostring = function(node)
	return meta[node].name
end

-- Build the tree: ReplicatedStorage.Shared mirrors src/shared, like Rojo.
local storage = newNode("ReplicatedStorage", "ReplicatedStorage", nil)
local shared = newNode("Shared", "Folder", storage)
local byPath = { [""] = shared }
local modules = {}

local function ensure(path, className)
	if byPath[path] then
		if className == "ModuleScript" then
			meta[byPath[path]].className = className
		end
		return byPath[path]
	end
	local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
	if not parentPath then
		parentPath, name = "", path
	end
	local node = newNode(name, className, ensure(parentPath, "Folder"))
	byPath[path] = node
	return node
end

-- Project data (generated config) hangs off ReplicatedStorage, beside Shared.
local dataByPath = { [""] = storage }
local function ensureData(path, className)
	if dataByPath[path] then
		if className == "ModuleScript" then
			meta[dataByPath[path]].className = className
		end
		return dataByPath[path]
	end
	local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
	if not parentPath then
		parentPath, name = "", path
	end
	local node = newNode(name, className, ensureData(parentPath, "Folder"))
	dataByPath[path] = node
	return node
end
for _, file in DATA do
	local node = ensureData(file.path, "ModuleScript")
	modules[node] = { path = "ReplicatedStorage/" .. file.path, chunk = file.path, source = file.source }
end

for _, file in FILES do
	if file.kind == "folder" then
		ensure(file.path, "Folder")
	end
end
for _, file in FILES do
	if file.kind == "module" then
		local node = ensure(file.path, "ModuleScript")
		modules[node] = { path = file.path, chunk = file.chunk, source = file.source }
	end
end

local ENGINE_FAIL = "ROBLOX_ENGINE_USED"

local function trap(moduleName, globalName)
	local function boom()
		error(string.format(
			"%s: module %s touched the Roblox engine global '%s'; rule modules must need no Roblox service",
			ENGINE_FAIL, moduleName, globalName
		), 0)
	end
	return setmetatable({}, {
		__index = boom, __newindex = boom, __call = boom, __tostring = boom,
	})
end

-- Rule modules get copies of math and os whose random and time throw, so a
-- rule can never depend on hidden randomness or the clock.
local function impure(moduleName, fullName)
	return function()
		error(string.format(
			"RULE_IMPURE: rule module %s called %s; %s",
			moduleName, fullName, IMPURE_HINT
		), 0)
	end
end

local function isRuleModule(path)
	return string.sub(path, 1, 6) == "rules/" and not string.find(path, "%.spec$")
end

local cache = {}
local loading = {}
local baseEnv = getfenv(0)

local function requireNode(target)
	if type(target) ~= "table" or not meta[target] then
		error("require expects a ModuleScript from the script tree, got " .. tostring(target), 2)
	end
	local info = modules[target]
	if not info then
		error(fullName(target) .. " is not a ModuleScript", 2)
	end
	if cache[target] ~= nil then
		return cache[target].value
	end
	if loading[target] then
		error("require cycle through " .. info.path, 2)
	end
	loading[target] = true
	local fn, err = loadstring(info.source, "=" .. info.chunk)
	if not fn then
		loading[target] = nil
		error(err, 0)
	end
	local env = { script = target, require = requireNode }
	for _, name in ENGINE_GLOBALS do
		env[name] = trap(info.path, name)
	end
	if isRuleModule(info.path) then
		local safeMath = table.clone(math)
		safeMath.random = impure(info.path, "math.random")
		local safeOs = table.clone(os)
		safeOs.time = impure(info.path, "os.time")
		env.math = safeMath
		env.os = safeOs
	end
	setfenv(fn, setmetatable(env, { __index = baseEnv }))
	local ok, value = pcall(fn)
	loading[target] = nil
	if not ok then
		error(value, 0)
	end
	cache[target] = { value = value }
	return value
end

local function emit(kind, name, message)
	message = string.gsub(tostring(message or ""), "[\r\n\t]+", " ")
	print(kind .. "\t" .. name .. "\t" .. message)
end

local loadFailures = 0

-- 1. Every rule module must load with no engine.
local rulesFolder = byPath["rules"]
if rulesFolder then
	local list = {}
	for node, info in modules do
		if isRuleModule(info.path) then
			table.insert(list, node)
		end
	end
	table.sort(list, function(a, b)
		return modules[a].path < modules[b].path
	end)
	for _, node in list do
		local ok, err = pcall(requireNode, node)
		if not ok then
			loadFailures += 1
			emit("FAIL", "rule module " .. modules[node].path, err)
		end
	end
end

-- 2. Load the runner and the spec list.
local function needPath(path)
	local node = byPath[path]
	if not node or not modules[node] then
		emit("FATAL", path, "missing module src/shared/" .. path .. ".luau")
		print("RESULT\t0\t1")
		return nil
	end
	return node
end

local runnerNode = needPath("testing/Runner")
local specsNode = runnerNode and needPath("testing/specs")
if not (runnerNode and specsNode) then
	return
end

local okRunner, Runner = pcall(requireNode, runnerNode)
local okSpecs, specList = pcall(requireNode, specsNode)
if not okRunner or not okSpecs then
	emit("FATAL", "testing", okRunner and specList or Runner)
	print("RESULT\t0\t1")
	return
end

-- 3. Every spec module under src/shared must be in the spec list.
local registered = {}
for _, node in specList do
	registered[node] = true
end
local unlisted = {}
for node, info in modules do
	if string.find(info.path, "%.spec$") and not string.find(info.path, "^ReplicatedStorage/") and not registered[node] then
		table.insert(unlisted, info.chunk)
	end
end
table.sort(unlisted)
for _, chunk in unlisted do
	loadFailures += 1
	emit("FAIL", "unregistered spec " .. chunk, "this spec file is not listed in src/shared/testing/specs.luau, so it would never run; add it there")
end

local specs = {}
for _, node in specList do
	local name = modules[node] and modules[node].path or tostring(node)
	local ok, fn = pcall(requireNode, node)
	if not ok then
		loadFailures += 1
		emit("FAIL", "spec " .. name, fn)
	elseif type(fn) ~= "function" then
		loadFailures += 1
		emit("FAIL", "spec " .. name, "a spec module must return a function, got " .. type(fn))
	else
		table.insert(specs, { name = name, fn = fn })
	end
end

local result = Runner.run(specs)
for _, failure in result.failures do
	emit("FAIL", failure.name, failure.message)
end
print("RESULT\t" .. result.passed .. "\t" .. (result.failed + loadFailures))
"""


def run_suite(game_dir, luau, pin, out):
    """Run one game folder's tests. Appends report lines to out; returns the exit code."""
    shared = game_dir / "src" / "shared"
    script = BOOTSTRAP.replace("%ENGINE%", ", ".join('"%s"' % n for n in ENGINE_NAMES))
    script = script.replace("%IMPURE_HINT%", lua_string(IMPURE_HINT))
    data = [part for part in (project_data(game_dir, shared), project_docs(game_dir)) if part]
    script = script.replace("%DATA%", ",\n".join(data))
    script = script.replace("%FILES%", collect(shared, game_dir))

    scratch = game_dir / "build"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="run_tests_", dir=scratch) as tmp:
        boot = Path(tmp) / "bootstrap.luau"
        boot.write_text(script, encoding="utf-8")
        try:
            done = subprocess.run(
                [luau, str(boot)], capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            fail("the test run timed out after %d seconds" % TIMEOUT)

    static = scan_rules(shared, game_dir)
    out.extend(static)

    passed = failed = None
    for line in (done.stdout or "").splitlines():
        parts = line.split("\t")
        if parts[0] in ("FAIL", "FATAL") and len(parts) >= 3:
            out.append("FAIL %s: %s" % (parts[1], "\t".join(parts[2:])))
        elif parts[0] == "RESULT" and len(parts) == 3:
            passed, failed = int(parts[1]), int(parts[2])
        elif line.strip():
            out.append(line)
    if done.stderr.strip():
        out.append(done.stderr.strip())
    if passed is None or done.returncode != 0:
        out.append("run_tests: the Luau run crashed (exit code %d)" % done.returncode)
        return 1
    failed += len(static)
    out.append("%d passed, %d failed, %d total (luau %s)" % (passed, failed, passed + failed, pin))
    return 0 if failed == 0 else 1


# Self-tests: tiny fixture games that each must pass or fail in a known way.
# Each is (name, files under src/shared, expected exit code, texts the report must contain).
SPEC_HEADER = "local Runner = require(script.Parent.Parent.Parent.testing.Runner)\nlocal expect = Runner.expect\n"
SELF_TESTS = (
    (
        "a clean fixture passes",
        {
            "rules/Add.luau": "return function(a, b) return a + b end\n",
            "rules/specs/Add.spec.luau": SPEC_HEADER + "local Add = require(script.Parent.Parent.Add)\n"
            "return function() Runner.it('adds', function() expect(Add(0.1, 0.2)).toBeCloseTo(0.3) end) end\n",
            "testing/specs.luau": "return { script.Parent.Parent.rules.specs['Add.spec'] }\n",
        },
        0,
        ("1 passed, 0 failed",),
    ),
    (
        "toBeCloseTo fails on NaN and infinity",
        {
            "rules/specs/Close.spec.luau": SPEC_HEADER + "return function()\n"
            "  Runner.it('nan value', function() expect(0/0).toBeCloseTo(0, 1) end)\n"
            "  Runner.it('nan expected', function() expect(0).toBeCloseTo(0/0, 1) end)\n"
            "  Runner.it('inf both', function() expect(math.huge).toBeCloseTo(math.huge, 1) end)\n"
            "  Runner.it('inf margin', function() expect(1).toBeCloseTo(2, math.huge) end)\n"
            "end\n",
            "testing/specs.luau": "return { script.Parent.Parent.rules.specs['Close.spec'] }\n",
        },
        1,
        ("0 passed, 4 failed", "nan value", "nan expected", "inf both", "inf margin"),
    ),
    (
        "an unregistered spec file fails, named",
        {
            "rules/specs/Listed.spec.luau": SPEC_HEADER
            + "return function() Runner.it('ok', function() expect(1).toEqual(1) end) end\n",
            "rules/specs/Orphan.spec.luau": SPEC_HEADER
            + "return function() Runner.it('ok', function() expect(1).toEqual(1) end) end\n",
            "testing/specs.luau": "return { script.Parent.Parent.rules.specs['Listed.spec'] }\n",
        },
        1,
        ("unregistered spec src/shared/rules/specs/Orphan.spec.luau",),
    ),
    (
        "a rule module using math.random fails",
        {
            "rules/Roll.luau": "return function() return math.random(1, 6) end\n",
            "testing/specs.luau": "return {}\n",
        },
        1,
        ("src/shared/rules/Roll.luau", "'math.random' on line 1", IMPURE_HINT),
    ),
    (
        "a rule module using os.time fails",
        {
            "rules/Clock.luau": "local now = os.time()\nreturn function() return now end\n",
            "testing/specs.luau": "return {}\n",
        },
        1,
        ("RULE_IMPURE: rule module rules/Clock called os.time", "'os.time' on line 1", IMPURE_HINT),
    ),
    (
        "a hidden math.random call is trapped at run time",
        {
            "rules/Hidden.luau": "local m = math\nlocal key = 'ran' .. 'dom'\n"
            "return function() return m[key](1, 6) end\n",
            "rules/specs/Hidden.spec.luau": SPEC_HEADER + "local Hidden = require(script.Parent.Parent.Hidden)\n"
            "return function() Runner.it('rolls', function() Hidden() end) end\n",
            "testing/specs.luau": "return { script.Parent.Parent.rules.specs['Hidden.spec'] }\n",
        },
        1,
        ("RULE_IMPURE: rule module rules/Hidden called math.random", IMPURE_HINT),
    ),
)


def self_test(runner_source, luau, pin, game_dir):
    """Run the harness on the fixture games. Returns a list of problems, empty when all behave."""
    problems = []
    scratch = game_dir / "build"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="run_tests_self_", dir=scratch) as tmp:
        for index, (name, files, want_code, want_texts) in enumerate(SELF_TESTS):
            game = Path(tmp) / ("fixture%d" % index)
            shared = game / "src" / "shared"
            all_files = dict(files)
            all_files["testing/Runner.luau"] = runner_source
            for rel, text in all_files.items():
                target = shared / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text, encoding="utf-8")
            out = []
            code = run_suite(game, luau, pin, out)
            report = "\n".join(out)
            missing = [text for text in want_texts if text not in report]
            if code != want_code or missing:
                problems.append("self-test '%s': exit %d (wanted %d)%s; report: %s"
                                % (name, code, want_code,
                                   ", missing %s" % ", ".join(repr(t) for t in missing) if missing else "",
                                   " | ".join(out)))
    return problems


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip())
        return 2
    game_dir = Path(argv[1]).resolve()
    shared = game_dir / "src" / "shared"
    if not shared.is_dir():
        fail("%s has no src/shared folder" % argv[1])

    name, pin = pinned_luau()
    luau = find_luau(name)

    runner = shared / "testing" / "Runner.luau"
    if runner.is_file():
        problems = self_test(runner.read_text(encoding="utf-8"), luau, pin, game_dir)
        for line in problems:
            print("FAIL run_tests " + line)
        if problems:
            print("run_tests: %d of %d self-tests failed; the harness itself is broken"
                  % (len(problems), len(SELF_TESTS)))
            return 1
        print("run_tests: %d self-tests passed" % len(SELF_TESTS))

    out = []
    code = run_suite(game_dir, luau, pin, out)
    for line in out:
        print(line)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
