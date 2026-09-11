#!/usr/bin/env python3
"""Wheelchair human-syntax shell.

This module is deliberately *above* WH Core.  It never changes core semantics,
validation, lowering, AOT policy, or native backends.  It performs only:

    UTF-8 human text -> conservative surface repair -> canonical surface tokens
    -> existing wheelchair.tensor/1 JSON

Repairs are restricted to the human shell: English edit-distance-1 typos, unique
declared-English-name typos, and deterministic newline splits.  Chinese spelling
is never guessed.  The generated core graph is ordinary .wh input for the unchanged
compiler.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unicodedata
from typing import Any

FORMAT = "wheelchair.tensor/1"
SOURCE_EXTENSION = ".wh"
PATH_SAFE_PROGRAM = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
INTEGER_NAME = re.compile(r"^[0-9]+$")
NUMBER_RE = re.compile(
    r"(?:0[xX][0-9A-Fa-f]+|0[bB][01]+|(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$"
)

# English spellings are the canonical surface tokens.  Simplified Chinese,
# Traditional Chinese, and arbitrary mixtures are lexical aliases only.
ALIASES: dict[str, tuple[str, ...]] = {
    "program": ("program", "程序", "程式"),
    "contract": ("contract", "契约", "契約"),
    "input": ("input", "输入", "輸入"),
    "range": ("range", "范围", "範圍"),
    "let": ("let", "定义", "定義", "令"),
    "tensor": ("tensor", "张量", "張量"),
    "reduce": ("reduce", "归约", "歸約"),
    "sum": ("sum", "求和", "總和"),
    "iterate": ("iterate", "迭代"),
    "limit": ("limit", "上限"),
    "state": ("state", "状态", "狀態"),
    "while": ("while", "当", "當"),
    "update": ("update", "更新"),
    "result": ("result", "结果", "結果"),
    "record": ("record", "记录", "記錄"),
    "dictionary": ("dictionary", "字典", "辭典"),
    "lookup": ("lookup", "查找", "查詢"),
    "default": ("default", "默认", "預設"),
    "nested": ("nested", "嵌套", "巢狀"),
    "nested_reduce": ("nested_reduce", "嵌套归约", "巢狀歸約"),
    "cascade": ("cascade", "级联", "級聯"),
    "executors": ("executors", "执行器", "執行器"),
    "chunk": ("chunk", "工作块", "工作塊"),
    "axis": ("axis", "轴", "軸"),
    "events": ("events", "事件"),
    "goal": ("goal", "目标", "目標"),
    "work": ("work", "工作"),
    "relation": ("relation", "关系", "關係"),
    "to": ("to", "到"),
    "output": ("output", "输出", "輸出"),
    "publish": ("publish", "发布", "發佈"),
    "test": ("test", "测试", "測試"),
    "true": ("true", "真"),
    "false": ("false", "假"),
    "select": ("select", "选择", "選擇"),
    "cast": ("cast", "转换", "轉換"),
    "min": ("min", "最小"),
    "max": ("max", "最大"),
    "abs": ("abs", "绝对值", "絕對值"),
    "goal_result": ("goal_result", "目标结果", "目標結果"),
}
ALIAS_TO_CANONICAL = {
    unicodedata.normalize("NFC", alias): canonical
    for canonical, aliases in ALIASES.items()
    for alias in aliases
}
PREFERRED = {
    "en": {canonical: aliases[0] for canonical, aliases in ALIASES.items()},
    "zh-hans": {
        canonical: next((a for a in aliases[1:] if any("\u4e00" <= c <= "\u9fff" for c in a)), aliases[0])
        for canonical, aliases in ALIASES.items()
    },
    "zh-hant": {
        canonical: aliases[-1] if len(aliases) > 1 else aliases[0]
        for canonical, aliases in ALIASES.items()
    },
}
# Correct aliases whose last element is shared or simplified.
PREFERRED["zh-hans"].update({
    "program": "程序", "contract": "契约", "input": "输入", "range": "范围",
    "let": "定义", "tensor": "张量", "reduce": "归约", "sum": "求和",
    "state": "状态", "while": "当", "result": "结果", "record": "记录",
    "dictionary": "字典", "lookup": "查找", "default": "默认", "nested": "嵌套",
    "nested_reduce": "嵌套归约", "cascade": "级联", "executors": "执行器",
    "chunk": "工作块", "axis": "轴", "goal": "目标", "relation": "关系",
    "output": "输出", "publish": "发布", "test": "测试", "select": "选择",
    "cast": "转换", "abs": "绝对值", "goal_result": "目标结果",
})
PREFERRED["zh-hant"].update({
    "program": "程式", "contract": "契約", "input": "輸入", "range": "範圍",
    "let": "定義", "tensor": "張量", "reduce": "歸約", "sum": "總和",
    "state": "狀態", "while": "當", "result": "結果", "record": "記錄",
    "dictionary": "辭典", "lookup": "查詢", "default": "預設", "nested": "巢狀",
    "nested_reduce": "巢狀歸約", "cascade": "級聯", "executors": "執行器",
    "chunk": "工作塊", "axis": "軸", "goal": "目標", "relation": "關係",
    "output": "輸出", "publish": "發佈", "test": "測試", "select": "選擇",
    "cast": "轉換", "abs": "絕對值", "goal_result": "目標結果",
})

MULTI_OPS = ("=>", "->", "..", "==", "!=", "<=", ">=", "<<", ">>", "&&", "||")
SINGLE = set("(){}[],:;=+-*/%<>!&|^~.")
BIDI_FORBIDDEN = {
    0x061C, 0x200E, 0x200F,
    *range(0x202A, 0x202F),
    *range(0x2066, 0x206A),
}

ENGLISH_KEYWORDS = frozenset(ALIASES)
ENGLISH_REPAIRABLE = re.compile(r"^[A-Za-z0-9_]+$")
EXPRESSION_KEYWORDS = frozenset({"true", "false", "select", "min", "max", "abs", "cast", "goal_result"})
BUILTIN_FUNCTIONS = frozenset({"xor", "bit_and", "bit_or", "bit_xor", "shl", "shr"})



class SurfaceError(Exception):
    pass


@dataclass(frozen=True)
class Token:
    kind: str
    value: Any
    raw: str
    start: int
    end: int
    line: int
    column: int


@dataclass(frozen=True)
class Repair:
    kind: str
    original: str
    replacement: str
    line: int
    column: int
    reason: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "original": self.original,
            "replacement": self.replacement,
            "line": self.line,
            "column": self.column,
            "reason": self.reason,
        }


def _english_repairable(value: str) -> bool:
    return bool(value) and value.isascii() and bool(ENGLISH_REPAIRABLE.fullmatch(value)) and any(ch.isalpha() for ch in value)


def _levenshtein_exactly_one(a: str, b: str) -> bool:
    """True only for one insertion, deletion, or substitution; transposition is not included."""
    if a == b or abs(len(a) - len(b)) > 1:
        return False
    if len(a) == len(b):
        return sum(ca != cb for ca, cb in zip(a, b)) == 1
    if len(a) > len(b):
        a, b = b, a
    # len(b) == len(a) + 1: exactly one extra character in b.
    i = j = mismatches = 0
    while i < len(a) and j < len(b):
        if a[i] == b[j]:
            i += 1
            j += 1
        else:
            mismatches += 1
            if mismatches > 1:
                return False
            j += 1
    return True


def _unique_distance_one(value: str, candidates: set[str] | frozenset[str]) -> tuple[str | None, list[str]]:
    if not _english_repairable(value):
        return None, []
    matches = sorted(candidate for candidate in candidates if _english_repairable(candidate) and _levenshtein_exactly_one(value, candidate))
    return (matches[0] if len(matches) == 1 else None), matches


def normalize_name(value: str, context: str = "identifier") -> str:
    value = unicodedata.normalize("NFC", value)
    if not value:
        raise SurfaceError(f"{context} must not be empty")
    try:
        value.encode("utf-8", "strict")
    except UnicodeEncodeError as exc:
        raise SurfaceError(f"{context} is not valid UTF-8 Unicode") from exc
    for ch in value:
        cp = ord(ch)
        cat = unicodedata.category(ch)
        if ch in "\r\n\x00" or cat in {"Cc", "Cs", "Zl", "Zp"}:
            raise SurfaceError(f"{context} contains a control or line-separator character")
        # U+200D ZWJ is retained because it is required by many emoji grapheme clusters.
        if (cat == "Cf" and cp != 0x200D) or cp in BIDI_FORBIDDEN:
            raise SurfaceError(f"{context} contains a hidden/bidirectional format character U+{cp:04X}")
    return value


def core_program_name(human_name: str) -> str:
    human_name = normalize_name(human_name, "program name")
    if PATH_SAFE_PROGRAM.fullmatch(human_name):
        return human_name
    digest = hashlib.sha256(human_name.encode("utf-8")).hexdigest()[:16]
    return f"surface_{digest}"


def _advance_position(text: str, start: int, end: int, line: int, col: int) -> tuple[int, int]:
    chunk = text[start:end]
    count = chunk.count("\n")
    if count:
        return line + count, len(chunk.rsplit("\n", 1)[-1]) + 1
    return line, col + (end - start)


def lex(text: str, *, auto_repair: bool = True) -> list[Token]:
    # A UTF-8 decode has already happened by the time Python gives us str.  NFC
    # normalization is intentionally applied to identifiers, not to string literals.
    tokens: list[Token] = []
    i = 0
    line = 1
    col = 1
    n = len(text)

    def push(kind: str, value: Any, raw: str, start: int, end: int, ln: int, cl: int) -> None:
        tokens.append(Token(kind, value, raw, start, end, ln, cl))

    while i < n:
        ch = text[i]
        if ch.isspace():
            old = i
            while i < n and text[i].isspace():
                i += 1
            line, col = _advance_position(text, old, i, line, col)
            continue
        if ch == "#":
            old = i
            i = text.find("\n", i)
            if i < 0:
                i = n
            line, col = _advance_position(text, old, i, line, col)
            continue
        if text.startswith("//", i):
            old = i
            i = text.find("\n", i)
            if i < 0:
                i = n
            line, col = _advance_position(text, old, i, line, col)
            continue
        if text.startswith("/*", i):
            old = i
            end = text.find("*/", i + 2)
            if end < 0:
                raise SurfaceError(f"unterminated block comment at {line}:{col}")
            i = end + 2
            line, col = _advance_position(text, old, i, line, col)
            continue

        ln, cl, start = line, col, i
        if ch == '"':
            i += 1
            escaped = False
            while i < n:
                c = text[i]
                if c in "\r\n" and not escaped:
                    raise SurfaceError(f"newline in string literal at {ln}:{cl}")
                if escaped:
                    escaped = False
                    i += 1
                    continue
                if c == "\\":
                    escaped = True
                    i += 1
                    continue
                if c == '"':
                    i += 1
                    raw = text[start:i]
                    try:
                        value = json.loads(raw)
                    except json.JSONDecodeError as exc:
                        raise SurfaceError(f"invalid string literal at {ln}:{cl}: {exc.msg}") from exc
                    push("STRING", value, raw, start, i, ln, cl)
                    line, col = _advance_position(text, start, i, line, col)
                    break
                i += 1
            else:
                raise SurfaceError(f"unterminated string literal at {ln}:{cl}")
            continue

        if ch == "`":
            i += 1
            chars: list[str] = []
            while i < n:
                c = text[i]
                if c in "\r\n":
                    raise SurfaceError(f"newline in quoted identifier at {ln}:{cl}")
                if c == "\\" and i + 1 < n and text[i + 1] in {"`", "\\"}:
                    chars.append(text[i + 1])
                    i += 2
                    continue
                if c == "`":
                    i += 1
                    raw = text[start:i]
                    value = normalize_name("".join(chars), "quoted identifier")
                    push("IDENT", value, raw, start, i, ln, cl)
                    line, col = _advance_position(text, start, i, line, col)
                    break
                chars.append(c)
                i += 1
            else:
                raise SurfaceError(f"unterminated quoted identifier at {ln}:{cl}")
            continue

        # Numeric literals need a small special case because '.' is otherwise a
        # field-access delimiter.  A leading digit is still allowed for identifiers:
        # 123abc and 7号轴 fall through to the bare-identifier scanner because the
        # numeric prefix is not followed by a token boundary.
        if ch.isdigit():
            number_match = re.match(
                r"(?:0[xX][0-9A-Fa-f]+|0[bB][01]+|[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)",
                text[i:],
            )
            if number_match is not None:
                candidate = number_match.group(0)
                after = i + len(candidate)
                boundary = (
                    after >= n or text[after].isspace() or text[after] in SINGLE
                    or any(text.startswith(op, after) for op in MULTI_OPS)
                    or text.startswith("//", after) or text.startswith("/*", after)
                    or text[after] == "#"
                )
                if boundary:
                    i = after
                    push("NUMBER", candidate, candidate, start, i, ln, cl)
                    line, col = _advance_position(text, start, i, line, col)
                    continue

        matched = next((op for op in MULTI_OPS if text.startswith(op, i)), None)
        if matched is not None:
            i += len(matched)
            push("OP", matched, matched, start, i, ln, cl)
            line, col = _advance_position(text, start, i, line, col)
            continue
        if ch in SINGLE:
            i += 1
            push("OP", ch, ch, start, i, ln, cl)
            line, col = _advance_position(text, start, i, line, col)
            continue

        # Bare token: UTF-8 identifiers may begin with digits, contain CJK, emoji,
        # combining marks, etc.  ASCII punctuation with grammatical meaning remains a
        # delimiter; names that need it are written in backticks.
        while i < n:
            if text[i].isspace() or text[i] in SINGLE or text[i] in {'"', '`', '#'}:
                break
            if any(text.startswith(op, i) for op in MULTI_OPS):
                break
            if text.startswith("//", i) or text.startswith("/*", i):
                break
            i += 1
        if i == start:
            raise SurfaceError(f"unexpected character {text[i]!r} at {line}:{col}")
        raw = text[start:i]
        normalized = unicodedata.normalize("NFC", raw)
        canonical = ALIAS_TO_CANONICAL.get(normalized)
        if canonical is not None:
            push("KW", canonical, raw, start, i, ln, cl)
        elif NUMBER_RE.fullmatch(raw):
            push("NUMBER", raw, raw, start, i, ln, cl)
        else:
            push("IDENT", normalize_name(raw), raw, start, i, ln, cl)
        line, col = _advance_position(text, start, i, line, col)

    # Newlines are semantically ordinary whitespace.  If a student splits a
    # two-character operator across a physical line, merge it only when the two
    # operator tokens form an existing WH surface operator.  This is deterministic
    # repair, not token guessing.
    merged: list[Token] = []
    k = 0
    while k < len(tokens):
        cur = tokens[k]
        if k + 1 < len(tokens):
            nxt = tokens[k + 1]
            gap = text[cur.end:nxt.start]
            pair = str(cur.value) + str(nxt.value)
            if (auto_repair and cur.kind == nxt.kind == "OP" and pair in MULTI_OPS
                    and "\n" in gap and gap.isspace()):
                merged.append(Token("OP", pair, cur.raw + gap + nxt.raw, cur.start, nxt.end,
                                    cur.line, cur.column))
                k += 2
                continue
        merged.append(cur)
        k += 1
    tokens = merged
    tokens.append(Token("EOF", None, "", n, n, line, col))
    return tokens


def parse_number(raw: str) -> int | float:
    if raw.lower().startswith("0x"):
        return int(raw, 16)
    if raw.lower().startswith("0b"):
        return int(raw, 2)
    if any(c in raw for c in ".eE"):
        return float(raw)
    return int(raw, 10)


def literal_expr(value: Any) -> dict[str, Any]:
    if isinstance(value, bool):
        return {"literal": value, "type": "bool"}
    if isinstance(value, int):
        return {"literal": value, "type": "i64" if value < 0 else "u64"}
    if isinstance(value, float):
        return {"literal": value, "type": "f64"}
    if isinstance(value, str):
        return {"literal": value, "type": "string"}
    raise SurfaceError(f"unsupported literal {value!r}")


PRECEDENCE = {
    "||": (1, "or"),
    "&&": (2, "and"),
    "|": (3, "bit_or"),
    "^": (4, "bit_xor"),
    "&": (5, "bit_and"),
    "==": (6, "eq"), "!=": (6, "ne"),
    "<": (7, "lt"), "<=": (7, "le"), ">": (7, "gt"), ">=": (7, "ge"),
    "<<": (8, "shl"), ">>": (8, "shr"),
    "+": (9, "add"), "-": (9, "sub"),
    "*": (10, "mul"), "/": (10, "div"), "%": (10, "mod"),
}


class Parser:
    def __init__(self, text: str, source: Path | None = None, *, auto_repair: bool = True):
        self.text = text
        self.source = source
        self.auto_repair = auto_repair
        self.tokens = lex(text, auto_repair=auto_repair)
        self.pos = 0
        self.repairs: list[Repair] = []
        if auto_repair:
            for tok in self.tokens:
                if tok.kind == "OP" and "\n" in tok.raw and tok.value in MULTI_OPS:
                    self._record_repair("newline_operator", tok, str(tok.value),
                                        "two-character operator was split by a newline")
        self.axes: list[set[str]] = []
        self.states: list[set[str]] = []
        self.human_program_name: str | None = None
        self.core_program_name: str | None = None
        self.data: dict[str, Any] = {
            "format": FORMAT,
            "program": None,
            "contracts": {
                "deterministic": True,
                "integer_overflow": "trap",
                "floating_point": "strict_by_default",
            },
            "inputs": [],
            "bindings": [],
            "outputs": [],
            "tests": [],
        }

    def _record_repair(self, kind: str, token: Token, replacement: str, reason: str, *, original: str | None = None) -> None:
        self.repairs.append(Repair(kind, original if original is not None else token.raw, replacement,
                                   token.line, token.column, reason))

    def _known_reference_names(self) -> set[str]:
        names = {item["name"] for item in self.data["inputs"] if "name" in item}
        names.update(item["name"] for item in self.data["bindings"] if "name" in item)
        for scope in self.axes:
            names.update(scope)
        for scope in self.states:
            names.update(scope)
        return names

    def _is_known_reference(self, name: str) -> bool:
        return name in self._known_reference_names()

    def _record_field_names(self, record_name: str) -> set[str]:
        for item in reversed(self.data["bindings"]):
            if item.get("name") == record_name and item.get("op") == "record":
                return set(item.get("fields", {}))
        return set()

    def _newline_join(self) -> tuple[str, Token, Token] | None:
        a = self.peek(0)
        b = self.peek(1)
        if a.kind != "IDENT" or b.kind != "IDENT" or a.raw.startswith("`") or b.raw.startswith("`"):
            return None
        gap = self.text[a.end:b.start]
        if "\n" not in gap or not gap.isspace():
            return None
        joined = unicodedata.normalize("NFC", str(a.value) + str(b.value))
        return joined, a, b

    def _keyword_candidate(self, token: Token) -> tuple[str | None, list[str]]:
        if token.kind != "IDENT" or token.raw.startswith("`"):
            return None, []
        return _unique_distance_one(str(token.value), ENGLISH_KEYWORDS)

    def _consume_keyword(self, value: str) -> bool:
        tok = self.peek()
        if tok.kind == "KW" and tok.value == value:
            self.pos += 1
            return True
        if not self.auto_repair:
            return False
        joined = self._newline_join()
        if joined is not None and joined[0] == value and _english_repairable(value):
            _, a, b = joined
            self.pos += 2
            self._record_repair("newline_keyword", a, value,
                                "English keyword was split by a newline",
                                original=self.text[a.start:b.end])
            return True
        candidate, matches = self._keyword_candidate(tok)
        if candidate == value:
            self.pos += 1
            self._record_repair("english_keyword", tok, value,
                                "unique English keyword at edit distance 1")
            return True
        if len(matches) > 1 and value in matches:
            raise self.error(f"ambiguous English keyword typo {tok.raw!r}; candidates: {', '.join(matches)}", tok)
        return False

    def _repair_reference_value(self, name: str, token: Token, candidates: set[str] | None = None) -> str:
        candidates = set(candidates if candidates is not None else self._known_reference_names())
        if name in candidates or not self.auto_repair or token.raw.startswith("`"):
            return name
        candidate, matches = _unique_distance_one(name, candidates)
        if candidate is not None:
            self._record_repair("english_identifier", token, candidate,
                                "unique declared English identifier at edit distance 1")
            return candidate
        if len(matches) > 1:
            raise self.error(f"ambiguous English identifier typo {token.raw!r}; candidates: {', '.join(matches)}", token)
        return name

    def parse_ref_name(self, *, allow_numeric: bool = False, candidates: set[str] | None = None) -> str:
        joined = self._newline_join() if self.auto_repair else None
        target_candidates = set(candidates if candidates is not None else self._known_reference_names())
        if joined is not None and joined[0] in target_candidates and _english_repairable(joined[0]):
            name, a, b = joined
            self.pos += 2
            self._record_repair("newline_identifier", a, name,
                                "declared English identifier was split by a newline",
                                original=self.text[a.start:b.end])
            return name
        tok = self.peek()
        if tok.kind == "IDENT":
            self.pos += 1
            name = normalize_name(str(tok.value))
            return self._repair_reference_value(name, tok, target_candidates)
        if allow_numeric and tok.kind == "NUMBER" and INTEGER_NAME.fullmatch(tok.raw):
            self.pos += 1
            return normalize_name(tok.raw)
        raise self.error("expected identifier" + (" (numeric names are allowed)" if allow_numeric else ""))

    def error(self, message: str, token: Token | None = None) -> SurfaceError:
        token = token or self.peek()
        return SurfaceError(f"{message} at {token.line}:{token.column}")

    def peek(self, offset: int = 0) -> Token:
        return self.tokens[min(self.pos + offset, len(self.tokens) - 1)]

    def take(self) -> Token:
        tok = self.peek()
        self.pos += 1
        return tok

    def match_op(self, value: str) -> bool:
        if self.peek().kind == "OP" and self.peek().value == value:
            self.pos += 1
            return True
        return False

    def expect_op(self, value: str) -> Token:
        if not self.match_op(value):
            raise self.error(f"expected {value!r}")
        return self.tokens[self.pos - 1]

    def match_kw(self, value: str) -> bool:
        return self._consume_keyword(value)

    def expect_kw(self, value: str) -> Token:
        if not self.match_kw(value):
            raise self.error(f"expected keyword {value!r}")
        return self.tokens[self.pos - 1]

    def match_one_kw(self, values: set[str] | frozenset[str] | tuple[str, ...]) -> str | None:
        for value in values:
            if self._consume_keyword(value):
                return value
        return None

    def optional_semicolon(self) -> None:
        self.match_op(";")

    def parse_name(self, *, allow_numeric: bool = False) -> str:
        tok = self.peek()
        if tok.kind == "IDENT":
            self.pos += 1
            return normalize_name(str(tok.value))
        if allow_numeric and tok.kind == "NUMBER" and INTEGER_NAME.fullmatch(tok.raw):
            self.pos += 1
            return normalize_name(tok.raw)
        raise self.error("expected identifier" + (" (numeric declaration names are allowed)" if allow_numeric else ""))

    def parse_scalar_type(self) -> Any:
        tok = self.peek()
        if tok.kind != "IDENT" or tok.value not in {"bool", "i64", "u64", "f32", "f64", "string"}:
            raise self.error("expected scalar type bool/i64/u64/f32/f64/string")
        self.pos += 1
        base = tok.value
        if self.match_op("~"):
            if base not in {"f32", "f64"}:
                raise self.error("only floating-point types may carry tolerance")
            self.expect_op("(")
            abs_tol = 0.0
            rel_tol = 0.0
            seen: set[str] = set()
            while not self.match_op(")"):
                # abs is also an expression keyword, so tolerance field names
                # must accept the keyword token rather than requiring IDENT.
                tok_key = self.take()
                if tok_key.kind not in {"IDENT", "KW"} or str(tok_key.value) not in {"abs", "rel"}:
                    raise self.error("tolerance fields are unique abs/rel", tok_key)
                key = str(tok_key.value)
                if key in seen:
                    raise self.error("tolerance fields are unique abs/rel")
                seen.add(key)
                self.expect_op("=")
                tokv = self.take()
                if tokv.kind != "NUMBER":
                    raise self.error("tolerance must be numeric", tokv)
                val = float(parse_number(tokv.raw))
                if key == "abs": abs_tol = val
                else: rel_tol = val
                if self.match_op(","):
                    continue
                self.expect_op(")")
                break
            return {
                "base": base, "mode": "tolerant",
                "absolute_error": abs_tol, "relative_error": rel_tol,
            }
        return base

    def parse_literal_value(self) -> Any:
        sign = 1
        if self.match_op("-"):
            sign = -1
        if sign > 0:
            bool_kw = self.match_one_kw(("true", "false"))
            if bool_kw is not None:
                return bool_kw == "true"
        tok = self.take()
        if tok.kind == "NUMBER":
            value = parse_number(tok.raw)
            return value * sign
        if sign < 0:
            raise self.error("minus may prefix only a numeric literal", tok)
        if tok.kind == "STRING":
            return tok.value
        raise self.error("expected literal value", tok)

    def _resolve_name_expr(self, name: str) -> dict[str, Any]:
        if any(name in scope for scope in reversed(self.states)):
            return {"state": name}
        if any(name in scope for scope in reversed(self.axes)):
            return {"axis": name}
        return {"var": name}

    def parse_expr(self, min_prec: int = 0) -> dict[str, Any]:
        left = self.parse_unary()
        while True:
            tok = self.peek()
            if tok.kind != "OP" or tok.value not in PRECEDENCE:
                break
            prec, op_name = PRECEDENCE[tok.value]
            if prec < min_prec:
                break
            self.pos += 1
            right = self.parse_expr(prec + 1)
            left = {"op": op_name, "args": [left, right]}
        return left

    def parse_unary(self) -> dict[str, Any]:
        if self.match_op("!"):
            return {"op": "not", "args": [self.parse_unary()]}
        if self.match_op("~"):
            return {"op": "bit_not", "args": [self.parse_unary()]}
        if self.match_op("-"):
            if self.peek().kind == "NUMBER":
                value = parse_number(self.take().raw)
                return literal_expr(-value)
            return {"op": "neg", "args": [self.parse_unary()]}
        return self.parse_postfix()

    def parse_postfix(self) -> dict[str, Any]:
        expr = self.parse_primary()
        while True:
            if self.match_op("["):
                indices: list[dict[str, Any]] = []
                if not self.match_op("]"):
                    while True:
                        indices.append(self.parse_expr())
                        if self.match_op(","):
                            continue
                        self.expect_op("]")
                        break
                if set(expr) != {"var"}:
                    raise self.error("tensor indexing requires a tensor name")
                expr = {"load": expr["var"], "indices": indices}
                continue
            if self.match_op("."):
                if set(expr) != {"var"}:
                    raise self.error("field access requires a record name")
                field_candidates = self._record_field_names(expr["var"] )
                field = self.parse_ref_name(allow_numeric=True, candidates=field_candidates) if field_candidates else self.parse_name(allow_numeric=True)
                expr = {"field": {"record": expr["var"], "name": field}}
                continue
            break
        return expr

    def parse_primary(self) -> dict[str, Any]:
        tok = self.peek()
        # Expression keywords can also receive the same conservative English typo
        # repair, but an exact declared identifier always wins over a keyword guess.
        repaired_expression_kw: str | None = None
        if tok.kind == "IDENT" and not self._is_known_reference(str(tok.value)) and self.auto_repair:
            candidate, _matches = self._keyword_candidate(tok)
            if candidate in EXPRESSION_KEYWORDS:
                repaired_expression_kw = candidate
                self._record_repair("english_keyword", tok, candidate,
                                    "unique English expression keyword at edit distance 1")
                tok = Token("KW", candidate, tok.raw, tok.start, tok.end, tok.line, tok.column)
        if tok.kind == "NUMBER":
            self.pos += 1
            return literal_expr(parse_number(tok.raw))
        if tok.kind == "STRING":
            self.pos += 1
            return literal_expr(tok.value)
        if tok.kind == "KW" and tok.value in {"true", "false"}:
            self.pos += 1
            return literal_expr(tok.value == "true")
        if self.match_op("("):
            expr = self.parse_expr()
            self.expect_op(")")
            return expr
        if tok.kind == "KW" and tok.value in {"select", "min", "max", "abs", "cast", "goal_result"}:
            self.pos += 1
            fn = tok.value
            self.expect_op("(")
            if fn == "cast":
                typ = self.parse_scalar_type()
                self.expect_op(",")
                arg = self.parse_expr()
                self.expect_op(")")
                return {"op": "cast", "to": typ, "args": [arg]}
            if fn == "goal_result":
                name = self.parse_ref_name(allow_numeric=True)
                self.expect_op(")")
                return {"goal_result": name}
            args: list[dict[str, Any]] = []
            if not self.match_op(")"):
                while True:
                    args.append(self.parse_expr())
                    if self.match_op(","):
                        continue
                    self.expect_op(")")
                    break
            arity = {"select": 3, "min": 2, "max": 2, "abs": 1}[fn]
            if len(args) != arity:
                raise self.error(f"{fn} requires {arity} arguments", tok)
            return {"op": fn, "args": args}
        if tok.kind == "IDENT" and self.auto_repair and not self._is_known_reference(str(tok.value)) and self.peek(1).kind == "OP" and self.peek(1).value == "(":
            candidate, matches = _unique_distance_one(str(tok.value), BUILTIN_FUNCTIONS)
            if candidate is not None:
                self._record_repair("english_builtin", tok, candidate,
                                    "unique English built-in function at edit distance 1")
                tok = Token("IDENT", candidate, tok.raw, tok.start, tok.end, tok.line, tok.column)
            elif len(matches) > 1:
                raise self.error(f"ambiguous English built-in typo {tok.raw!r}; candidates: {', '.join(matches)}", tok)
        if tok.kind == "IDENT":
            # A declared bare English name may be split exactly across one newline.
            joined = self._newline_join() if self.auto_repair else None
            if joined is not None and joined[0] in self._known_reference_names() and _english_repairable(joined[0]):
                name, a, b = joined
                self.pos += 2
                self._record_repair("newline_identifier", a, name,
                                    "declared English identifier was split by a newline",
                                    original=self.text[a.start:b.end])
                return self._resolve_name_expr(name)
            self.pos += 1
            name = normalize_name(str(tok.value))
            name = self._repair_reference_value(name, tok)
            # Explicit functions not reserved as keywords keep the surface keyword set small.
            if self.match_op("("):
                args: list[dict[str, Any]] = []
                if not self.match_op(")"):
                    while True:
                        args.append(self.parse_expr())
                        if self.match_op(","):
                            continue
                        self.expect_op(")")
                        break
                mapping = {
                    "xor": "xor", "bit_and": "bit_and", "bit_or": "bit_or",
                    "bit_xor": "bit_xor", "shl": "shl", "shr": "shr",
                }
                if name not in mapping:
                    raise self.error(f"unknown surface function {name!r}", tok)
                expected = 2
                if len(args) != expected:
                    raise self.error(f"{name} requires {expected} arguments", tok)
                return {"op": mapping[name], "args": args}
            return self._resolve_name_expr(name)
        raise self.error("expected expression", tok)

    def parse_axis_list(self) -> tuple[list[dict[str, Any]], set[str]]:
        axes: list[dict[str, Any]] = []
        names: set[str] = set()
        self.expect_op("[")
        while True:
            name = self.parse_name(allow_numeric=True)
            if name in names:
                raise self.error(f"duplicate axis {name!r}")
            self.expect_op(":")
            extent = self.parse_expr()
            names.add(name)
            axes.append({"name": name, "extent": extent})
            if self.match_op(","):
                continue
            self.expect_op("]")
            break
        return axes, names

    def parse_program(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.human_program_name = name
        self.core_program_name = core_program_name(name)
        self.data["program"] = self.core_program_name
        self.optional_semicolon()

    def parse_contract(self) -> None:
        key = self.parse_name()
        self.expect_op("=")
        bool_kw = self.match_one_kw(("true", "false"))
        if bool_kw is not None:
            value: Any = bool_kw == "true"
        else:
            tok = self.take()
            if tok.kind == "STRING":
                value = tok.value
            elif tok.kind == "NUMBER":
                value = parse_number(tok.raw)
            elif tok.kind == "IDENT":
                value = tok.value
            else:
                raise self.error("invalid contract value", tok)
        self.data["contracts"][key] = value
        self.optional_semicolon()

    def parse_input(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.expect_op(":")
        typ = self.parse_scalar_type()
        item: dict[str, Any] = {"name": name, "type": typ}
        if self.match_kw("range"):
            item["min"] = self.parse_literal_value()
            self.expect_op("..")
            item["max"] = self.parse_literal_value()
        self.data["inputs"].append(item)
        self.optional_semicolon()

    def parse_let(self) -> None:
        name = self.parse_name(allow_numeric=True)
        typ = None
        if self.match_op(":"):
            typ = self.parse_scalar_type()
        self.expect_op("=")
        item: dict[str, Any] = {"name": name, "op": "compute", "expr": self.parse_expr()}
        if typ is not None:
            item["type"] = typ
        self.data["bindings"].append(item)
        self.optional_semicolon()

    def parse_tensor(self) -> None:
        name = self.parse_name(allow_numeric=True)
        axes, names = self.parse_axis_list()
        self.expect_op(":")
        typ = self.parse_scalar_type()
        self.expect_op("=")
        self.axes.append(names)
        try:
            expr = self.parse_expr()
        finally:
            self.axes.pop()
        self.data["bindings"].append({
            "name": name, "op": "map", "type": typ, "axes": axes, "expr": expr,
        })
        self.optional_semicolon()

    def parse_reduce(self) -> None:
        name = self.parse_name(allow_numeric=True)
        axes, names = self.parse_axis_list()
        self.expect_op(":")
        accumulator = self.parse_scalar_type()
        self.expect_op("=")
        kind = self.match_one_kw(("sum", "min", "max"))
        if kind is None:
            raise self.error("expected reduction kind sum/min/max")
        self.axes.append(names)
        try:
            expr = self.parse_expr()
        finally:
            self.axes.pop()
        self.data["bindings"].append({
            "name": name, "op": "reduce", "kind": kind,
            "accumulator": accumulator, "axes": axes, "expr": expr,
        })
        self.optional_semicolon()

    def parse_iterate(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.expect_kw("limit")
        max_iterations = self.parse_expr()
        self.expect_op("{")
        states: list[dict[str, Any]] = []
        state_names: set[str] = set()
        condition: dict[str, Any] | None = None
        updates: dict[str, Any] = {}
        result: str | None = None
        self.states.append(state_names)
        try:
            while not self.match_op("}"):
                if self.match_kw("state"):
                    state_name = self.parse_name(allow_numeric=True)
                    if state_name in state_names:
                        raise self.error(f"duplicate state {state_name!r}")
                    self.expect_op(":")
                    typ = self.parse_scalar_type()
                    self.expect_op("=")
                    init = self.parse_expr()
                    state_names.add(state_name)
                    states.append({"name": state_name, "type": typ, "init": init})
                    self.optional_semicolon()
                elif self.match_kw("while"):
                    if condition is not None:
                        raise self.error("iterate has more than one while condition")
                    condition = self.parse_expr()
                    self.optional_semicolon()
                elif self.match_kw("update"):
                    target = self.parse_ref_name(allow_numeric=True, candidates=state_names)
                    if target in updates:
                        raise self.error(f"duplicate update {target!r}")
                    self.expect_op("=")
                    updates[target] = self.parse_expr()
                    self.optional_semicolon()
                elif self.match_kw("result"):
                    if result is not None:
                        raise self.error("iterate has more than one result")
                    result = self.parse_ref_name(allow_numeric=True, candidates=state_names)
                    self.optional_semicolon()
                else:
                    raise self.error("expected state/while/update/result in iterate block")
        finally:
            self.states.pop()
        if not states or condition is None or result is None:
            raise self.error("iterate requires states, while condition, and result")
        self.data["bindings"].append({
            "name": name, "op": "iterate", "states": states,
            "condition": condition, "update": updates,
            "result": result, "max_iterations": max_iterations,
        })
        self.optional_semicolon()

    def parse_record(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.expect_op("{")
        fields: dict[str, Any] = {}
        while not self.match_op("}"):
            field = self.parse_name(allow_numeric=True)
            if field in fields:
                raise self.error(f"duplicate record field {field!r}")
            self.expect_op("=")
            fields[field] = self.parse_expr()
            self.match_op(",")
            self.optional_semicolon()
        self.data["bindings"].append({"name": name, "op": "record", "fields": fields})
        self.optional_semicolon()

    def parse_dictionary(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.expect_op(":")
        key_type = self.parse_scalar_type()
        self.expect_op("->")
        value_type = self.parse_scalar_type()
        self.expect_op("{")
        entries: list[dict[str, Any]] = []
        while not self.match_op("}"):
            key = self.parse_literal_value()
            self.expect_op("=")
            value = self.parse_expr()
            entries.append({"key": key, "value": value})
            self.match_op(",")
            self.optional_semicolon()
        self.data["bindings"].append({
            "name": name, "op": "dictionary", "key_type": key_type,
            "value_type": value_type, "entries": entries,
        })
        self.optional_semicolon()

    def parse_lookup(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.expect_op("=")
        dictionary = self.parse_ref_name(allow_numeric=True)
        self.expect_op("[")
        key = self.parse_expr()
        self.expect_op("]")
        self.expect_kw("default")
        default = self.parse_expr()
        self.data["bindings"].append({
            "name": name, "op": "lookup", "dictionary": dictionary,
            "key": key, "default": default,
        })
        self.optional_semicolon()

    def parse_nested_segments(self) -> list[list[Any]]:
        segments: list[list[Any]] = []
        self.expect_op("[")
        if self.match_op("]"):
            return segments
        while True:
            self.expect_op("[")
            segment: list[Any] = []
            if not self.match_op("]"):
                while True:
                    segment.append(self.parse_literal_value())
                    if self.match_op(","):
                        continue
                    self.expect_op("]")
                    break
            segments.append(segment)
            if self.match_op(","):
                continue
            self.expect_op("]")
            return segments

    def parse_nested(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.expect_op(":")
        typ = self.parse_scalar_type()
        self.expect_op("=")
        segments = self.parse_nested_segments()
        self.data["bindings"].append({
            "name": name, "op": "nested_literal", "type": typ, "segments": segments,
        })
        self.optional_semicolon()

    def parse_nested_reduce(self) -> None:
        name = self.parse_name(allow_numeric=True)
        typ = None
        if self.match_op(":"):
            typ = self.parse_scalar_type()
        self.expect_op("=")
        kind: str
        if self.match_kw("sum"):
            kind = "sum"
        else:
            kind_tok = self.take()
            if kind_tok.kind == "IDENT" and kind_tok.value in {"count", "segment_count"}:
                kind = kind_tok.value
            else:
                raise self.error("nested reduction kind must be sum/count/segment_count", kind_tok)
        source = self.parse_ref_name(allow_numeric=True)
        item: dict[str, Any] = {"name": name, "op": "nested_reduce", "input": source, "kind": kind}
        if typ is not None:
            item["accumulator"] = typ
        self.data["bindings"].append(item)
        self.optional_semicolon()

    def parse_cascade(self) -> None:
        name = self.parse_name(allow_numeric=True)
        self.expect_kw("executors")
        executors = self.parse_expr()
        self.expect_kw("chunk")
        chunk_size = self.parse_expr()
        self.expect_kw("axis")
        unit_axis = self.parse_name(allow_numeric=True)
        publish_events = True
        if self.match_kw("events"):
            bool_kw = self.match_one_kw(("true", "false"))
            if bool_kw is None:
                raise self.error("events expects true/false")
            publish_events = bool_kw == "true"
        self.expect_op("{")
        goals: list[dict[str, Any]] = []
        goal_names: set[str] = set()
        relations: list[dict[str, str]] = []
        self.axes.append({unit_axis})
        try:
            while not self.match_op("}"):
                if self.match_kw("goal"):
                    goal_name = self.parse_name(allow_numeric=True)
                    goal_names.add(goal_name)
                    self.expect_kw("work")
                    work = self.parse_expr()
                    self.expect_op("=")
                    expr = self.parse_expr()
                    goals.append({"name": goal_name, "work": work, "expr": expr})
                    self.optional_semicolon()
                elif self.match_kw("relation"):
                    source = self.parse_ref_name(allow_numeric=True, candidates=goal_names)
                    if self.match_op("->"):
                        pass
                    else:
                        self.expect_kw("to")
                    target = self.parse_ref_name(allow_numeric=True, candidates=goal_names)
                    relations.append({"from": source, "to": target})
                    self.optional_semicolon()
                else:
                    raise self.error("expected goal/relation in cascade block")
        finally:
            self.axes.pop()
        self.data["bindings"].append({
            "name": name, "op": "cascade", "executors": executors,
            "chunk_size": chunk_size, "unit_axis": unit_axis,
            "publish_events": publish_events, "goals": goals, "relations": relations,
        })
        self.optional_semicolon()

    def parse_output(self, publish: bool) -> None:
        # An explicit `label = expression` declares an output label.  Bare
        # `publish name` is a reference and therefore receives identifier repair.
        save = self.pos
        label = self.parse_name(allow_numeric=True)
        if self.match_op("="):
            expr = self.parse_expr()
        else:
            self.pos = save
            label = self.parse_ref_name(allow_numeric=True)
            expr = self._resolve_name_expr(label)
        self.data["outputs"].append({"label": label, "expr": expr})
        self.optional_semicolon()

    def parse_test(self) -> None:
        self.expect_op("(")
        args: list[Any] = []
        if not self.match_op(")"):
            while True:
                args.append(self.parse_literal_value())
                if self.match_op(","):
                    continue
                self.expect_op(")")
                break
        self.expect_op("=>")
        self.expect_op("{")
        expected: dict[str, Any] = {}
        output_labels = {item["label"] for item in self.data["outputs"]}
        while not self.match_op("}"):
            label = self.parse_ref_name(allow_numeric=True, candidates=output_labels) if output_labels else self.parse_name(allow_numeric=True)
            self.expect_op("=")
            expected[label] = self.parse_literal_value()
            if self.match_op(","):
                continue
            self.optional_semicolon()
        self.data["tests"].append({"args": args, "expected": expected})
        self.optional_semicolon()

    def parse(self) -> dict[str, Any]:
        while self.peek().kind != "EOF":
            if self.match_kw("program"):
                if self.data["program"] is not None:
                    raise self.error("program declared more than once")
                self.parse_program()
            elif self.match_kw("contract"):
                self.parse_contract()
            elif self.match_kw("input"):
                self.parse_input()
            elif self.match_kw("let"):
                self.parse_let()
            elif self.match_kw("tensor"):
                self.parse_tensor()
            elif self.match_kw("reduce"):
                self.parse_reduce()
            elif self.match_kw("iterate"):
                self.parse_iterate()
            elif self.match_kw("record"):
                self.parse_record()
            elif self.match_kw("dictionary"):
                self.parse_dictionary()
            elif self.match_kw("lookup"):
                self.parse_lookup()
            elif self.match_kw("nested"):
                self.parse_nested()
            elif self.match_kw("nested_reduce"):
                self.parse_nested_reduce()
            elif self.match_kw("cascade"):
                self.parse_cascade()
            elif self.match_kw("output"):
                self.parse_output(False)
            elif self.match_kw("publish"):
                self.parse_output(True)
            elif self.match_kw("test"):
                self.parse_test()
            else:
                raise self.error("expected a top-level declaration")

        if self.data["program"] is None:
            stem = self.source.stem if self.source is not None else "surface_program"
            self.human_program_name = normalize_name(stem, "program name")
            self.core_program_name = core_program_name(self.human_program_name)
            self.data["program"] = self.core_program_name
        if not self.data["outputs"]:
            raise SurfaceError("surface program must publish/output at least one scalar")
        if not self.data["tests"]:
            raise SurfaceError("surface program must declare at least one test; WH Core requires tests")
        return self.data


def compile_surface(text: str, source: Path | None = None, *, auto_repair: bool = True) -> tuple[dict[str, Any], Parser]:
    parser = Parser(text, source, auto_repair=auto_repair)
    return parser.parse(), parser


def canonical_core_bytes(data: dict[str, Any]) -> bytes:
    return (json.dumps(data, indent=2, ensure_ascii=False, separators=(",", ": ")) + "\n").encode("utf-8")


def core_hash(data: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_core_bytes(data)).hexdigest()


def format_keywords(text: str, language: str = "en") -> str:
    if language == "preserve":
        return text
    if language not in PREFERRED:
        raise SurfaceError(f"unknown formatter language {language!r}")
    replacements: list[tuple[int, int, str]] = []
    for token in lex(text):
        if token.kind == "KW":
            replacements.append((token.start, token.end, PREFERRED[language][token.value]))
    out: list[str] = []
    cursor = 0
    for start, end, replacement in replacements:
        out.append(text[cursor:start])
        out.append(replacement)
        cursor = end
    out.append(text[cursor:])
    return "".join(out)


def load_surface(path: Path, *, auto_repair: bool = True) -> tuple[dict[str, Any], Parser, str]:
    if path.suffix.lower() != SOURCE_EXTENSION:
        raise SurfaceError(f"human surface source must use {SOURCE_EXTENSION!r}")
    text = path.read_text(encoding="utf-8", errors="strict")
    data, parser = compile_surface(text, path, auto_repair=auto_repair)
    return data, parser, text


def validate_with_unchanged_core(root: Path, data: dict[str, Any]) -> dict[str, Any]:
    compiler = root / "compiler" / "wheelchairc.py"
    if not compiler.is_file():
        raise SurfaceError(f"unchanged core compiler not found at {compiler}")
    with tempfile.TemporaryDirectory(prefix="wh_surface_validate_") as tmp:
        core = Path(tmp) / f"{data['program']}.wh"
        core.write_bytes(canonical_core_bytes(data))
        env = dict(__import__("os").environ)
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        proc = subprocess.run(
            [sys.executable, str(compiler), str(core), "--validate-only"],
            cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
        )
        if proc.returncode != 0:
            raise SurfaceError("WH Core rejected generated graph:\n" + proc.stderr.strip())
        return json.loads(proc.stdout)


def command_compile(args: argparse.Namespace) -> int:
    data, parser, _ = load_surface(args.source)
    output = args.output or args.source.with_name(args.source.stem + ".core.wh")
    output.write_bytes(canonical_core_bytes(data))
    report = {
        "surface_source": str(args.source),
        "human_program_name": parser.human_program_name,
        "core_program_name": parser.core_program_name,
        "core_output": str(output),
        "core_sha256": core_hash(data),
        "runtime_semantics_added": False,
        "bottom_layer_modified": False,
        "surface_repairs": [repair.as_dict() for repair in parser.repairs],
        "repair_count": len(parser.repairs),
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0




def _static_literal_expr(value):
    if isinstance(value, bool):
        typ = "bool"
    elif isinstance(value, float):
        typ = "f64"
    elif isinstance(value, int):
        typ = "u64" if value >= 0 else "i64"
    elif isinstance(value, str):
        typ = "string"
    else:
        raise ValueError("unsupported static literal")
    return {"literal": value, "type": typ}


def _eval_static_expr(expr, *, axis_name=None, axis_value=None, goal_values=None, u64_mode=False, overflow_wrap=False):
    goal_values = goal_values or {}
    def checked(v):
        if not u64_mode or isinstance(v, bool) or not isinstance(v, int):
            return v
        if 0 <= v <= 0xFFFFFFFFFFFFFFFF:
            return v
        if overflow_wrap:
            return v & 0xFFFFFFFFFFFFFFFF
        raise OverflowError("static u64 cascade overflow")
    if not isinstance(expr, dict):
        raise ValueError("non-expression")
    if "literal" in expr:
        return checked(expr["literal"])
    if "axis" in expr:
        if expr["axis"] != axis_name or axis_value is None:
            raise ValueError("foreign axis")
        return checked(axis_value)
    if "goal_result" in expr:
        name = expr["goal_result"]
        if name not in goal_values:
            raise KeyError(name)
        return checked(goal_values[name])
    op = expr.get("op")
    args = expr.get("args") or []
    if not isinstance(op, str):
        raise ValueError("dynamic expression")
    vals = [_eval_static_expr(a, axis_name=axis_name, axis_value=axis_value, goal_values=goal_values, u64_mode=u64_mode, overflow_wrap=overflow_wrap) for a in args]
    if op == "add": return checked(vals[0] + vals[1])
    if op == "sub": return checked(vals[0] - vals[1])
    if op == "mul": return checked(vals[0] * vals[1])
    if op == "div":
        if vals[1] == 0: raise ZeroDivisionError
        if u64_mode: return checked(vals[0] // vals[1])
        return vals[0] / vals[1]
    if op == "mod":
        if vals[1] == 0: raise ZeroDivisionError
        return checked(vals[0] % vals[1])
    if op == "min": return checked(min(vals))
    if op == "max": return checked(max(vals))
    if op == "neg": return checked(-vals[0])
    if op == "abs": return checked(abs(vals[0]))
    if op == "eq": return vals[0] == vals[1]
    if op == "ne": return vals[0] != vals[1]
    if op == "lt": return vals[0] < vals[1]
    if op == "le": return vals[0] <= vals[1]
    if op == "gt": return vals[0] > vals[1]
    if op == "ge": return vals[0] >= vals[1]
    if op == "select": return checked(vals[1] if vals[0] else vals[2])
    raise ValueError(f"unsupported static op:{op}")


def lower_static_general_constructs(data):
    """Fold closed dictionary lookups and closed cascades before native codegen.

    The pass is intentionally bounded: it only fires when every consumed value
    is compile-time closed.  Dynamic dictionaries/cascades remain untouched and
    therefore cannot be silently reinterpreted by the direct-general lane.
    """
    import copy
    lowered = copy.deepcopy(data)
    bindings = lowered.get("bindings") or []
    dictionaries = {b.get("name"): b for b in bindings if isinstance(b, dict) and b.get("op") == "dictionary"}
    report = {"dictionary_lookups_folded": [], "cascades_folded": [], "static_cascade_events": []}

    # Exact literal-key dictionary lookup.  Keep the dictionary declaration so
    # the human graph remains inspectable; only the now-redundant lookup work is
    # removed from runtime.
    for i, b in enumerate(bindings):
        if not isinstance(b, dict) or b.get("op") != "lookup":
            continue
        d = dictionaries.get(b.get("dictionary"))
        key_expr = b.get("key")
        if d is None or not isinstance(key_expr, dict) or "literal" not in key_expr:
            continue
        key = key_expr["literal"]
        chosen = None
        for ent in d.get("entries") or []:
            if isinstance(ent, dict) and ent.get("key") == key:
                chosen = ent.get("value")
                break
        if chosen is None:
            chosen = b.get("default")
        if not isinstance(chosen, dict):
            continue
        # The chosen expression must itself be closed.  Current dictionary
        # values are expressions, so a static evaluator is the proof gate.
        try:
            value = _eval_static_expr(chosen)
        except (ValueError, KeyError, TypeError, ZeroDivisionError):
            continue
        bindings[i] = {
            "name": b.get("name"), "op": "compute",
            "type": d.get("value_type"), "expr": _static_literal_expr(value),
        }
        report["dictionary_lookups_folded"].append(b.get("name"))

    # Closed cascade goals are a finite reduction system.  Evaluate each goal
    # only after all of its goal_result dependencies are available, then replace
    # the runtime fabric with the exact result record.  `publish_events` is
    # preserved as a compile report trace because the native WH executable has
    # no separate external event-stream ABI; its observable program contract is
    # the declared outputs.
    for i, b in enumerate(bindings):
        if not isinstance(b, dict) or b.get("op") != "cascade":
            continue
        goals = b.get("goals") or []
        axis_name = b.get("unit_axis")
        values = {}
        pending = list(goals)
        event_trace = []
        failed = False
        overflow_wrap = (lowered.get("contracts") or {}).get("integer_overflow") == "wrap"
        prereq = {}
        for rel in b.get("relations") or []:
            if isinstance(rel, dict) and isinstance(rel.get("from"), str) and isinstance(rel.get("to"), str):
                prereq.setdefault(rel["to"], set()).add(rel["from"])
        total_static_work = 0
        while pending and not failed:
            progressed = False
            for g in pending[:]:
                if not prereq.get(g.get("name"), set()).issubset(values):
                    continue
                work_expr = g.get("work") if isinstance(g, dict) else None
                try:
                    work = _eval_static_expr(work_expr, goal_values=values, u64_mode=True, overflow_wrap=overflow_wrap)
                    if not isinstance(work, int) or work < 0 or work > 1048576:
                        raise ValueError("non-static or excessive work")
                    total_static_work += work
                    if total_static_work > 1048576:
                        raise ValueError("excessive closed cascade work")
                    total = 0
                    for unit in range(work):
                        term = _eval_static_expr(g.get("expr"), axis_name=axis_name, axis_value=unit, goal_values=values, u64_mode=True, overflow_wrap=overflow_wrap)
                        total = total + term
                        if total > 0xFFFFFFFFFFFFFFFF:
                            if overflow_wrap: total &= 0xFFFFFFFFFFFFFFFF
                            else: raise OverflowError("static cascade reduction overflow")
                except KeyError:
                    continue
                except (ValueError, TypeError, ZeroDivisionError, OverflowError):
                    failed = True
                    break
                values[g.get("name")] = total
                event_trace.append({"goal": g.get("name"), "result": total})
                pending.remove(g)
                progressed = True
            if not progressed and pending:
                failed = True
        if failed:
            continue
        fields = {name: _static_literal_expr(value) for name, value in values.items()}
        fields["完成目标数"] = _static_literal_expr(len(values))
        bindings[i] = {"name": b.get("name"), "op": "record", "fields": fields}
        report["cascades_folded"].append(b.get("name"))
        if b.get("publish_events"):
            report["static_cascade_events"].append({"cascade": b.get("name"), "events": event_trace})

    report["active"] = bool(report["dictionary_lookups_folded"] or report["cascades_folded"])
    lowered["bindings"] = bindings
    return lowered, report


def _gtr_expr_refs(node):
    """Return binding names referenced by a canonical expression tree."""
    refs = set()
    if isinstance(node, dict):
        v = node.get("var")
        if isinstance(v, str):
            refs.add(v)
        ld = node.get("load")
        if isinstance(ld, str):
            refs.add(ld)
        for value in node.values():
            refs.update(_gtr_expr_refs(value))
    elif isinstance(node, list):
        for value in node:
            refs.update(_gtr_expr_refs(value))
    return refs


def recover_topology_program(data):
    """Recover a provably whole-output topology slice from general WH Core.

    This is deliberately proof-oriented rather than heuristic.  It never turns
    arbitrary control flow into topology.  The current 1.0.8 slice accepts one
    bounded u64 extent, f64 map dependencies, and one terminal f64 sum.  Dead
    pure compute/map/reduce bindings outside the output dependency closure may
    be discarded.  Everything else remains in the sovereign general lane.
    """
    import copy
    report = {
        "active": False,
        "reason": "not_attempted",
        "recovered_bindings": [],
        "dropped_dead_bindings": [],
        "semantic_lane": "general",
    }
    if not isinstance(data, dict) or data.get("format") != "wheelchair.tensor/1":
        report["reason"] = "unsupported_core_format"
        return data, report
    inputs = data.get("inputs") or []
    bindings = data.get("bindings") or []
    outputs = data.get("outputs") or []
    if len(inputs) != 1 or inputs[0].get("type") != "u64":
        report["reason"] = "requires_one_u64_extent_input"
        return data, report
    inp = inputs[0]
    if not isinstance(inp.get("min"), int) or not isinstance(inp.get("max"), int):
        report["reason"] = "extent_range_not_static"
        return data, report
    if inp["min"] < 1 or inp["max"] < inp["min"]:
        report["reason"] = "invalid_extent_range"
        return data, report
    if len(outputs) != 1 or not isinstance(outputs[0].get("expr"), dict):
        report["reason"] = "requires_one_observable_output"
        return data, report
    out_expr = outputs[0]["expr"]
    terminal = out_expr.get("var")
    if not isinstance(terminal, str) or len(out_expr) != 1:
        report["reason"] = "output_not_direct_terminal_reduce"
        return data, report

    by_name = {b.get("name"): b for b in bindings if isinstance(b, dict) and isinstance(b.get("name"), str)}
    term = by_name.get(terminal)
    if not term or term.get("op") != "reduce" or term.get("kind") != "sum":
        report["reason"] = "terminal_not_sum_reduce"
        return data, report

    # Dependency closure from the single observable output.
    needed = set()
    stack = [terminal]
    input_name = inp.get("name")
    while stack:
        name = stack.pop()
        if name == input_name or name in needed:
            continue
        b = by_name.get(name)
        if b is None:
            report["reason"] = f"unresolved_dependency:{name}"
            return data, report
        needed.add(name)
        for ref in _gtr_expr_refs(b.get("expr")):
            if ref != input_name:
                stack.append(ref)

    # Reachable region must already have topology semantics.  We recover it
    # from ordinary .wh without changing the human grammar.
    reduced = []
    tol_abs = 0.0
    tol_rel = 0.0
    for b in bindings:
        name = b.get("name") if isinstance(b, dict) else None
        if name not in needed:
            op = b.get("op") if isinstance(b, dict) else None
            if op in {"compute", "map", "reduce"}:
                report["dropped_dead_bindings"].append(name)
                continue
            # Stateful/cascade/dictionary/record constructs are conservatively
            # treated as potentially observable and block whole-output GTR.
            report["reason"] = f"unproven_dead_binding:{op or 'unknown'}"
            return data, report
        op = b.get("op")
        if op not in {"map", "reduce"} or b.get("type", "f64") not in {"f64", None}:
            # reduce carries its type in accumulator rather than `type`.
            if op != "reduce":
                report["reason"] = f"reachable_non_topology_binding:{op}"
                return data, report
        axes = b.get("axes") or []
        if len(axes) != 1:
            report["reason"] = "requires_one_axis_per_binding"
            return data, report
        extent = axes[0].get("extent") if isinstance(axes[0], dict) else None
        if extent != {"var": input_name}:
            report["reason"] = "axis_extent_not_input_extent"
            return data, report
        if op == "map":
            if b.get("type") != "f64":
                report["reason"] = "map_type_not_f64"
                return data, report
        else:
            if b.get("kind") != "sum":
                report["reason"] = "reduce_not_sum"
                return data, report
            acc = b.get("accumulator")
            if acc == "f64":
                b = copy.deepcopy(b)
                b["accumulator"] = {
                    "base": "f64", "mode": "tolerant",
                    "absolute_error": 0.0, "relative_error": 0.0,
                }
            elif isinstance(acc, dict) and acc.get("base") == "f64" and acc.get("mode") == "tolerant":
                try:
                    tol_abs = max(tol_abs, float(acc.get("absolute_error", 0.0)))
                    tol_rel = max(tol_rel, float(acc.get("relative_error", 0.0)))
                except (TypeError, ValueError):
                    report["reason"] = "invalid_tolerance_contract"
                    return data, report
            else:
                report["reason"] = "reduce_accumulator_not_f64"
                return data, report
        reduced.append(copy.deepcopy(b))

    lowered = copy.deepcopy(data)
    lowered["bindings"] = reduced
    contracts = lowered.setdefault("contracts", {})
    if tol_abs > 0.0 or tol_rel > 0.0:
        contracts["floating_point"] = "tolerant"
    else:
        contracts["floating_point"] = "strict_by_default"
    report.update({
        "active": True,
        "reason": "proven_whole_output_topology_slice",
        "recovered_bindings": [b.get("name") for b in reduced],
        "semantic_lane": "topology",
        "floating_point_contract": contracts.get("floating_point"),
    })
    return lowered, report

def command_validate(args: argparse.Namespace) -> int:
    data, parser, _ = load_surface(args.source)
    root = Path(__file__).resolve().parents[1]
    core_report = validate_with_unchanged_core(root, data)
    print(json.dumps({
        "surface": "valid",
        "human_program_name": parser.human_program_name,
        "core_program_name": parser.core_program_name,
        "core_sha256": core_hash(data),
        "unchanged_core_validation": core_report,
        "surface_repairs": [repair.as_dict() for repair in parser.repairs],
        "repair_count": len(parser.repairs),
    }, indent=2, ensure_ascii=False))
    return 0


def command_format(args: argparse.Namespace) -> int:
    text = args.source.read_text(encoding="utf-8", errors="strict")
    formatted = format_keywords(text, args.language)
    if args.in_place:
        args.source.write_text(formatted, encoding="utf-8")
    else:
        sys.stdout.write(formatted)
    return 0


def command_equivalent(args: argparse.Namespace) -> int:
    rows = []
    hashes: set[str] = set()
    blobs: set[bytes] = set()
    for path in args.sources:
        data, parser, _ = load_surface(path)
        blob = canonical_core_bytes(data)
        digest = hashlib.sha256(blob).hexdigest()
        rows.append({
            "source": str(path), "human_program_name": parser.human_program_name,
            "core_program_name": parser.core_program_name, "core_sha256": digest,
            "repair_count": len(parser.repairs),
            "surface_repairs": [repair.as_dict() for repair in parser.repairs],
        })
        hashes.add(digest)
        blobs.add(blob)
    equivalent = len(blobs) == 1
    print(json.dumps({"equivalent": equivalent, "sources": rows}, indent=2, ensure_ascii=False))
    return 0 if equivalent else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="UTF-8 multilingual shell above unchanged WH Core")
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("compile", help="desugar human .wh into canonical core .wh JSON")
    p.add_argument("source", type=Path)
    p.add_argument("-o", "--output", type=Path)
    p.set_defaults(func=command_compile)

    p = sub.add_parser("validate", help="desugar then ask the unchanged WH Core validator")
    p.add_argument("source", type=Path)
    p.set_defaults(func=command_validate)

    p = sub.add_parser("format", help="rewrite only keyword spellings; English is default")
    p.add_argument("source", type=Path)
    p.add_argument("--language", choices=["en", "zh-hans", "zh-hant", "preserve"], default="en")
    p.add_argument("--in-place", action="store_true")
    p.set_defaults(func=command_format)

    p = sub.add_parser("equivalent", help="prove multiple surface spellings erase to one core graph")
    p.add_argument("sources", nargs="+", type=Path)
    p.set_defaults(func=command_equivalent)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (SurfaceError, UnicodeError, OSError) as exc:
        print(f"WH surface rejection: {exc}", file=sys.stderr)
        raise SystemExit(1)
