"""Local admission controls. No network, credentials, prices or AI calls."""
import hashlib
import json
import math
import os
import time
import tempfile
import uuid
from contextlib import contextmanager
from pathlib import Path


class PolicyError(Exception):
    pass


def number(value, low=0, high=math.inf):
    try:
        return (type(value) in (int, float) and math.isfinite(value)
                and low <= value <= high)
    except OverflowError:
        return False


def load_policy(path):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if type(data["paused"]) is not bool:
            raise ValueError("paused must be boolean")
        models = data["allowed_models"]
        if (not isinstance(models, list) or not models
                or any(not isinstance(m, str) or not m.strip() for m in models)
                or data["model"] not in models):
            raise ValueError("invalid model or model outside explicit allowlist")
        if data["effort"] not in ("low", "medium", "high"):
            raise ValueError("invalid reasoning effort")
        for field, lo, hi in (("attempts", 1, 2), ("call_timeout_seconds", 1, 3600),
                              ("task_timeout_seconds", 1, 7200),
                              ("prompt_max_chars", 1, 20000),
                              ("authorized_calls", 0, 1000),
                              ("authorized_tokens", 0, 10**9)):
            if type(data[field]) is not int or not lo <= data[field] <= hi:
                raise ValueError("invalid " + field)
        quota = data["quota"]
        if not number(quota["max_age_seconds"], 1, 300):
            raise ValueError("invalid quota freshness limit")
        if not number(quota["minimum_percent"], 0, 100):
            raise ValueError("invalid quota floor")
        return data
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise PolicyError("executor policy unavailable/invalid: %s" % exc) from exc


@contextmanager
def exclusive(directory):
    """Atomic repository-wide exclusion, including worktrees and --finish.

    Never automatically remove a preexisting lock: it may own a live child.
    """
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    lock = directory / "executor.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise PolicyError("duplicate execution or stale lock: %s" % lock) from exc
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(json.dumps({"pid": os.getpid(), "started": time.time()}))
        yield
    finally:
        lock.unlink()


def usage_from_jsonl(stdout):
    """Each completed turn reports inclusive input; cache is a subset of input.

    Missing/malformed metrics make the entire invocation unknown. Effective
    model is recorded only when the runtime actually reports it.
    """
    turns, models, seen = [], set(), {}
    active_turns = 0
    valid = True
    for line in stdout.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError("non-object event")
        except ValueError:
            valid = False
            continue
        for value in (event.get("model"), event.get("model_id"),
                      (event.get("usage") or {}).get("model")
                      if isinstance(event.get("usage"), dict) else None):
            if isinstance(value, str) and value:
                models.add(value)
        kind = event.get("type")
        if kind in ("error", "turn.failed"):
            valid = False
        if kind == "turn.started":
            active_turns += 1
        if kind != "turn.completed":
            continue
        event_id = event.get("id") or event.get("turn_id")
        if event_id:
            if str(event_id) in seen:
                if seen[str(event_id)] != event:
                    valid = False
                continue
            seen[str(event_id)] = event
        active_turns = max(0, active_turns - 1)
        usage = event.get("usage")
        keys = ("input_tokens", "cached_input_tokens", "output_tokens")
        if (not isinstance(usage, dict)
                or any(type(usage.get(k)) is not int or usage[k] < 0 for k in keys)
                or usage["cached_input_tokens"] > usage["input_tokens"]):
            valid = False
        else:
            turns.append({k: usage[k] for k in keys})
    measured = valid and bool(turns) and active_turns == 0
    result = {k: sum(t[k] for t in turns) if measured else None
              for k in ("input_tokens", "cached_input_tokens", "output_tokens")}
    result["total_tokens"] = (result["input_tokens"] + result["output_tokens"]
                              if measured else None)
    result["effective_models"] = sorted(models) or None
    result["measurement"] = "reported" if measured else "unknown"
    result["turns"] = turns
    # CLI invocation != individual provider request. Internal requests/retries
    # are not enumerated by this interface.
    result["provider_call_count"] = None
    return result


class Ledger:
    def __init__(self, directory):
        self.path = Path(directory) / "calls.jsonl"

    @property
    def head_path(self):
        return self.path.with_name("ledger-head.json")

    @staticmethod
    def validate_rows(rows):
        starts, finishes, counts, done = {}, {}, {}, set()
        for row in rows:
            kind = row["event"]
            if kind == "started":
                for key in ("call_id", "task", "agent", "requested_model", "requested_effort"):
                    if not isinstance(row[key], str) or not row[key].strip():
                        raise ValueError("invalid start identity")
                task = row["task"]
                expected = counts.get(task, 0) + 1
                if (row["call_id"] in starts or task in done or expected > 2
                        or type(row["attempt"]) is not int or row["attempt"] != expected
                        or not number(row["started_at"])
                        or not number(row["task_deadline_at"], row["started_at"])):
                    raise ValueError("invalid start/attempt/deadline")
                if len(starts) != len(finishes):
                    raise ValueError("overlapping invocations")
                starts[row["call_id"]] = row
                counts[task] = expected
            elif kind == "finished":
                start = starts.get(row["call_id"])
                if start is None or row["call_id"] in finishes:
                    raise ValueError("unmatched finish")
                if any(row.get(k) != v or type(row.get(k)) is not type(v)
                       for k, v in start.items() if k != "event"):
                    raise ValueError("finish does not match start")
                if (not number(row["duration_seconds"])
                        or row["status"] not in ("finished", "failed", "timeout", "interrupted", "launch_error")
                        or type(row["ok"]) is not bool or type(row["model_mismatch"]) is not bool):
                    raise ValueError("invalid finish status/duration")
                usage = row["usage"]
                models = usage["effective_models"]
                if models is not None and (not isinstance(models, list) or not models
                        or any(not isinstance(m, str) or not m for m in models)
                        or models != sorted(set(models))):
                    raise ValueError("invalid effective models")
                mismatch = bool(models and models != [start["requested_model"]])
                if row["model_mismatch"] != mismatch:
                    raise ValueError("invalid model mismatch flag")
                turns = usage["turns"]
                if not isinstance(turns, list):
                    raise ValueError("invalid turns")
                keys = ("input_tokens", "cached_input_tokens", "output_tokens")
                for turn in turns:
                    if (any(type(turn[k]) is not int or turn[k] < 0 for k in keys)
                            or turn["cached_input_tokens"] > turn["input_tokens"]):
                        raise ValueError("invalid turn tokens")
                if usage["measurement"] == "reported":
                    if not turns or row["status"] != "finished":
                        raise ValueError("incomplete invocation cannot have complete usage")
                    if (any(type(usage[k]) is not int or usage[k] != sum(t[k] for t in turns)
                            for k in keys) or type(usage["total_tokens"]) is not int
                            or usage["total_tokens"] != usage["input_tokens"] + usage["output_tokens"]):
                        raise ValueError("invalid token total")
                elif usage["measurement"] == "unknown":
                    if any(usage[k] is not None for k in (*keys, "total_tokens")):
                        raise ValueError("unknown usage must use null totals")
                else:
                    raise ValueError("invalid measurement")
                if row["ok"] and (usage["measurement"] != "reported" or mismatch):
                    raise ValueError("invalid success")
                finishes[row["call_id"]] = row
            elif kind == "task_done":
                task = row["task"]
                candidates = [r for r in starts.values() if r["task"] == task]
                if (task in done or not number(row["finished_at"]) or not candidates
                        or not finishes.get(candidates[-1]["call_id"], {}).get("ok")):
                    raise ValueError("completion requires last successful measured invocation")
                done.add(task)
            else:
                raise ValueError("unknown ledger event")
        return rows

    def read(self):
        try:
            if not self.path.exists() and not self.head_path.exists():
                return []
            raw = self.path.read_bytes()
            head = json.loads(self.head_path.read_text(encoding="utf-8"))
            rows = [json.loads(line) for line in raw.decode("utf-8").splitlines()]
            if (not rows or type(head["rows"]) is not int or head["rows"] != len(rows)
                    or head["sha256"] != hashlib.sha256(raw).hexdigest()):
                raise ValueError("ledger truncated/changed")
            return self.validate_rows(rows)
        except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError) as exc:
            raise PolicyError("ledger corrupt/unavailable: %s" % exc) from exc

    def append(self, row):
        # Caller holds the repository lock. A crash between journal and head
        # leaves a mismatch and blocks admission instead of losing consumption.
        temp = None
        try:
            rows = self.read()
            self.validate_rows(rows + [row])
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.open("ab") as stream:
                stream.write((json.dumps(row, sort_keys=True, allow_nan=False) + "\n").encode("utf-8"))
                stream.flush()
                os.fsync(stream.fileno())
            head = {"rows": len(rows) + 1, "sha256": hashlib.sha256(self.path.read_bytes()).hexdigest()}
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=self.path.parent,
                                             prefix="ledger-head-", delete=False) as stream:
                temp = Path(stream.name)
                json.dump(head, stream)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temp, self.head_path)
        except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError) as exc:
            raise PolicyError("ledger write unavailable/invalid: %s" % exc) from exc
        finally:
            if temp is not None and temp.exists():
                temp.unlink()

    def admit(self, policy, task, clock=time.time):
        if policy["paused"]:
            raise PolicyError("production paused in factory/executor.json")
        quota = policy["quota"]
        measured_at = quota.get("measured_at")
        remaining = quota.get("remaining_percent")
        if (not number(measured_at) or not number(remaining, 0, 100)
                or not isinstance(quota.get("source"), str) or not quota["source"].strip()
                or not 0 <= clock() - measured_at <= quota["max_age_seconds"]):
            raise PolicyError("required subscription quota measurement unknown/stale")
        if remaining <= quota["minimum_percent"]:
            raise PolicyError("subscription quota at/below authorized floor")
        rows = self.read()
        starts = [r for r in rows if r["event"] == "started"]
        finishes = {r["call_id"]: r for r in rows if r["event"] == "finished"}
        if any(r["call_id"] not in finishes for r in starts):
            raise PolicyError("unfinished invocation; measurement unknown")
        if any(r["usage"]["measurement"] != "reported" for r in finishes.values()):
            raise PolicyError("previous invocation has unknown usage")
        if any(r.get("model_mismatch") for r in finishes.values()):
            raise PolicyError("runtime model mismatch requires review")
        previous = [r for r in starts if r["task"] == task]
        if any(r["event"] == "task_done" and r["task"] == task for r in rows):
            raise PolicyError("task already completed; duplicate refused")
        if len(previous) >= policy["attempts"]:
            raise PolicyError("task exhausted total attempts (persistent)")
        used = sum(r["usage"]["total_tokens"] for r in finishes.values())
        if len(starts) >= policy["authorized_calls"] or used >= policy["authorized_tokens"]:
            raise PolicyError("authorized local budget insufficient")
        return len(previous) + 1

    def task_done(self, task):
        self.append({"event": "task_done", "task": task, "finished_at": time.time()})

    def remaining_seconds(self, task, limit, clock=time.time):
        starts = [r for r in self.read() if r["event"] == "started" and r["task"] == task]
        if not starts:
            return limit
        current = clock()
        if current < max(r["started_at"] for r in starts):
            raise PolicyError("clock moved backwards; deadline unknown")
        return min(starts[0]["started_at"] + limit,
                   *(r["task_deadline_at"] for r in starts)) - current

    def start(self, policy, task, agent, clock=time.time, task_seconds=None):
        attempt = self.admit(policy, task, clock)
        limit = min(policy["task_timeout_seconds"], task_seconds
                    if task_seconds is not None else policy["task_timeout_seconds"])
        seconds = self.remaining_seconds(task, limit, clock)
        if seconds <= 0:
            raise PolicyError("task deadline exhausted")
        row = {"event": "started", "call_id": uuid.uuid4().hex, "task": task,
               "agent": agent, "attempt": attempt, "started_at": clock(),
               "task_deadline_at": clock() + seconds,
               "requested_model": policy["model"], "requested_effort": policy["effort"]}
        self.append(row)
        return row

    def finish(self, start, stdout, duration, status, ok):
        usage = usage_from_jsonl(stdout)
        if status != "finished":
            usage.update(measurement="unknown", input_tokens=None, cached_input_tokens=None,
                         output_tokens=None, total_tokens=None)
        mismatch = bool(usage["effective_models"]
                        and usage["effective_models"] != [start["requested_model"]])
        row = dict(start, event="finished", duration_seconds=duration, status=status,
                   usage=usage, model_mismatch=mismatch,
                   ok=bool(ok and usage["measurement"] == "reported" and not mismatch))
        self.append(row)
        return row
