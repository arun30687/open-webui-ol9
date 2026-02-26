"""
title: GitHub MCP Agent
author: assistant
version: 0.4.0
description: Server-side pipe — model handles general queries via MCP tools, direct GitHub API handles table/chart formatting.
"""

import json
import re
import requests
from typing import Optional, Tuple
from pydantic import BaseModel, Field


PRIORITY_TOOLS = {
    "search_repositories", "search_code", "search_issues", "search_users",
    "list_issues", "list_pull_requests", "list_commits",
    "get_issue", "get_pull_request", "get_file_contents",
    "create_issue", "add_issue_comment",
}


class Pipe:
    class Valves(BaseModel):
        OLLAMA_BASE_URL: str = Field(default="http://localhost:11434")
        MCPO_BASE_URL: str = Field(default="http://localhost:8300/github")
        MODEL_ID: str = Field(default="qwen2.5:7b")
        NUM_CTX: int = Field(default=16384)
        MAX_TOOL_ROUNDS: int = Field(default=5)
        USE_ALL_TOOLS: bool = Field(default=False)
        GITHUB_TOKEN: str = Field(default="")
        SYSTEM_PROMPT: str = Field(
            default="You are a GitHub assistant. ALWAYS use the available tools to fetch real data. Never guess or make up information. Present results clearly."
        )

    def __init__(self):
        self.valves = self.Valves()
        self._tools_cache = None

    # ── Format Detection ──────────────────────────────────────────

    def _detect_format(self, user_msg: str) -> str:
        msg = user_msg.lower()
        if any(w in msg for w in ["pie chart", "bar chart", "chart", "line chart", "graph"]):
            return "chart"
        if any(w in msg for w in ["table", "tabular"]):
            return "table"
        return "default"

    def _detect_chart_type(self, user_msg: str) -> str:
        msg = user_msg.lower()
        if "bar" in msg:
            return "bar"
        if "line" in msg:
            return "line"
        return "pie"

    # ── GitHub Direct API ─────────────────────────────────────────

    def _github_api(self, endpoint: str, params: dict = None) -> dict:
        headers = {"Accept": "application/vnd.github.v3+json"}
        if self.valves.GITHUB_TOKEN:
            headers["Authorization"] = f"Bearer {self.valves.GITHUB_TOKEN}"
        try:
            resp = requests.get(
                f"https://api.github.com{endpoint}",
                headers=headers,
                params=params or {},
                timeout=15,
            )
            return resp.json()
        except Exception as e:
            return {"error": str(e)}

    def _extract_search_params(self, user_msg: str) -> Tuple[str, str, str]:
        """Extract (search_type, query, sort) from user message."""
        msg = user_msg.lower()

        search_type = "repos"
        if any(w in msg for w in ["issue", "bug", "issues"]):
            search_type = "issues"
        elif any(w in msg for w in ["pull request", "pr ", "prs", "pull requests"]):
            search_type = "prs"

        repo_match = re.search(r'([\w.-]+/[\w.-]+)', user_msg)

        clean = re.sub(
            r'\b(show|display|list|get|find|search|give|me|the|a|an|in|as|for|of|'
            r'with|top|most|popular|trending|recent|latest|new|all|some|'
            r'table|chart|pie|bar|line|tabular|format|graph|'
            r'repositories|repository|repos|repo|projects|issues|pull requests|prs|bugs|'
            r'by|language|stars|sorted|sort|order)\b',
            '', msg
        )
        keywords = [w.strip() for w in clean.split() if len(w.strip()) > 2]

        sort = "stars"
        if repo_match and search_type in ("issues", "prs"):
            query = f"repo:{repo_match.group(1)}"
            sort = "created"
        elif keywords:
            languages = {"python", "javascript", "typescript", "java", "go", "rust",
                         "c++", "ruby", "swift", "kotlin", "dart", "php", "scala", "c", "shell"}
            lang_parts = [f"language:{k}" for k in keywords if k in languages]
            topic_parts = [k for k in keywords if k not in languages]
            parts = topic_parts + lang_parts
            if "popular" in msg or "top" in msg or "trending" in msg:
                parts.append("stars:>100")
            query = " ".join(parts) if parts else "stars:>1000"
        else:
            query = "stars:>1000"

        return search_type, query, sort

    # ── Simple Formatters ─────────────────────────────────────────

    def _fmt_number(self, n) -> str:
        if n is None:
            return "0"
        n = int(n)
        if n >= 1000000:
            return f"{n/1000000:.1f}M"
        if n >= 1000:
            return f"{n/1000:.1f}k"
        return str(n)

    def _trunc(self, s, length=50) -> str:
        if not s:
            return "-"
        s = str(s)
        return s[:length] + "..." if len(s) > length else s

    def _repos_table(self, items) -> str:
        lines = [
            "| # | Repository | Stars | Language | Description |",
            "|---|-----------|-------|----------|-------------|",
        ]
        for i, r in enumerate(items[:15], 1):
            name = r.get("full_name", r.get("name", "?"))
            url = r.get("html_url", "#")
            stars = self._fmt_number(r.get("stargazers_count", 0))
            lang = r.get("language") or "-"
            desc = self._trunc(r.get("description", "-"), 60)
            lines.append(f"| {i} | [{name}]({url}) | {stars} | {lang} | {desc} |")
        return "\n".join(lines)

    def _repos_chart(self, items, chart_type) -> str:
        if chart_type == "pie":
            lang_counts = {}
            for r in items:
                lang = r.get("language") or "Other"
                lang_counts[lang] = lang_counts.get(lang, 0) + 1
            pie = ['```mermaid', 'pie showData', '    title "Repositories by Language"']
            for lang, count in sorted(lang_counts.items(), key=lambda x: -x[1])[:10]:
                pie.append(f'    "{lang}" : {count}')
            pie.append('```')
            return "\n".join(pie)
        else:
            bar_items = sorted(items, key=lambda r: r.get("stargazers_count", 0), reverse=True)[:10]
            names = [self._trunc(r.get("name", "?"), 15) for r in bar_items]
            values = [r.get("stargazers_count", 0) for r in bar_items]
            max_val = max(values) if values else 100
            labels = ", ".join(f'"{n}"' for n in names)
            vals = ", ".join(str(v) for v in values)
            return f'```mermaid\nxychart-beta\n    title "Top Repositories by Stars"\n    x-axis [{labels}]\n    y-axis "Stars" 0 --> {int(max_val * 1.2)}\n    bar [{vals}]\n```'

    def _issues_table(self, items) -> str:
        lines = [
            "| # | State | Issue | Author | Created |",
            "|---|-------|-------|--------|---------|",
        ]
        for i, iss in enumerate(items[:15], 1):
            state = "Open" if iss.get("state") == "open" else "Closed"
            title = self._trunc(iss.get("title", "?"), 60)
            url = iss.get("html_url", "#")
            num = iss.get("number", "")
            author = iss.get("user", {}).get("login", "?")
            created = str(iss.get("created_at", ""))[:10]
            lines.append(f"| {i} | {state} | [#{num} {title}]({url}) | @{author} | {created} |")
        return "\n".join(lines)

    def _prs_table(self, items) -> str:
        lines = [
            "| # | State | Pull Request | Author | Created |",
            "|---|-------|-------------|--------|---------|",
        ]
        for i, pr in enumerate(items[:15], 1):
            merged = pr.get("pull_request", {}).get("merged_at") or pr.get("merged_at")
            if merged:
                state = "Merged"
            elif pr.get("state") == "open":
                state = "Open"
            else:
                state = "Closed"
            title = self._trunc(pr.get("title", "?"), 60)
            url = pr.get("html_url", "#")
            num = pr.get("number", "")
            author = pr.get("user", {}).get("login", "?")
            created = str(pr.get("created_at", ""))[:10]
            lines.append(f"| {i} | {state} | [#{num} {title}]({url}) | @{author} | {created} |")
        return "\n".join(lines)

    # ── Direct Search & Format (for table/chart) ──────────────────

    def _direct_format(self, user_msg: str) -> Optional[str]:
        fmt = self._detect_format(user_msg)
        chart_type = self._detect_chart_type(user_msg)
        search_type, query, sort = self._extract_search_params(user_msg)

        if search_type == "repos":
            data = self._github_api("/search/repositories", {"q": query, "sort": sort, "per_page": 15})
            items = data.get("items", [])
            if not items:
                return None
            total = data.get("total_count", len(items))
            header = f"Found **{self._fmt_number(total)}** repositories for `{query}`\n\n"
            if fmt == "table":
                return header + self._repos_table(items)
            else:
                return header + self._repos_chart(items, chart_type)

        elif search_type == "issues":
            data = self._github_api("/search/issues", {"q": query + " is:issue", "sort": sort, "per_page": 15})
            items = data.get("items", [])
            if not items:
                return None
            total = data.get("total_count", len(items))
            header = f"Found **{self._fmt_number(total)}** issues for `{query}`\n\n"
            if fmt == "table":
                return header + self._issues_table(items)
            else:
                open_count = sum(1 for i in items if i.get("state") == "open")
                closed_count = len(items) - open_count
                return header + f'```mermaid\npie showData\n    title "Issues by State"\n    "Open" : {open_count}\n    "Closed" : {closed_count}\n```'

        elif search_type == "prs":
            data = self._github_api("/search/issues", {"q": query + " is:pr", "sort": sort, "per_page": 15})
            items = data.get("items", [])
            if not items:
                return None
            total = data.get("total_count", len(items))
            header = f"Found **{self._fmt_number(total)}** pull requests for `{query}`\n\n"
            if fmt == "table":
                return header + self._prs_table(items)
            else:
                open_c = sum(1 for i in items if i.get("state") == "open")
                merged_c = sum(1 for i in items if (i.get("pull_request", {}).get("merged_at") or i.get("merged_at")))
                closed_c = len(items) - open_c - merged_c
                return header + f'```mermaid\npie showData\n    title "Pull Requests by State"\n    "Open" : {open_c}\n    "Merged" : {merged_c}\n    "Closed" : {closed_c}\n```'

        return None

    # ── MCP Tool Helpers ──────────────────────────────────────────

    def _fetch_tools(self) -> list:
        if self._tools_cache is not None:
            return self._tools_cache
        try:
            resp = requests.get(f"{self.valves.MCPO_BASE_URL}/openapi.json", timeout=10)
            spec = resp.json()
        except Exception as e:
            print(f"[GitHub MCP Agent] Failed to fetch OpenAPI spec: {e}")
            return []

        tools = []
        schemas = spec.get("components", {}).get("schemas", {})
        for path, methods in spec.get("paths", {}).items():
            for method, details in methods.items():
                if method.lower() != "post":
                    continue
                tool_name = path.strip("/")
                if not self.valves.USE_ALL_TOOLS and tool_name not in PRIORITY_TOOLS:
                    continue
                description = details.get("description", details.get("summary", tool_name))
                schema_ref = (
                    details.get("requestBody", {})
                    .get("content", {})
                    .get("application/json", {})
                    .get("schema", {})
                )
                parameters = {"type": "object", "properties": {}, "required": []}
                resolved = (
                    schemas.get(schema_ref["$ref"].split("/")[-1], {})
                    if "$ref" in schema_ref
                    else schema_ref
                )
                if resolved:
                    clean_props = {}
                    for pn, pd in resolved.get("properties", {}).items():
                        cp = {
                            "type": pd.get("type", "string"),
                            "description": pd.get("description", pn),
                        }
                        if "items" in pd:
                            cp["items"] = pd["items"]
                        clean_props[pn] = cp
                    parameters["properties"] = clean_props
                    parameters["required"] = resolved.get("required", [])
                tools.append({
                    "type": "function",
                    "function": {"name": tool_name, "description": description, "parameters": parameters},
                })
        self._tools_cache = tools
        print(f"[GitHub MCP Agent] Loaded {len(tools)} tools")
        return tools

    def _execute_tool(self, tool_name: str, arguments: dict) -> str:
        url = f"{self.valves.MCPO_BASE_URL}/{tool_name}"
        try:
            resp = requests.post(url, json=arguments, headers={"Content-Type": "application/json"}, timeout=30)
            result = resp.text
            if len(result) > 6000:
                result = result[:6000] + "\n... (truncated)"
            return result
        except Exception as e:
            return json.dumps({"error": str(e)})

    def _call_ollama(self, messages: list, tools: list) -> dict:
        ollama_messages = []
        for msg in messages:
            m = {"role": msg["role"], "content": msg.get("content", "")}
            if "tool_calls" in msg:
                m["tool_calls"] = msg["tool_calls"]
            if "tool_call_id" in msg:
                m["tool_call_id"] = msg["tool_call_id"]
            ollama_messages.append(m)

        ollama_tools = [{"type": "function", "function": t["function"]} for t in tools] if tools else []
        payload = {
            "model": self.valves.MODEL_ID,
            "messages": ollama_messages,
            "stream": False,
            "options": {"num_ctx": self.valves.NUM_CTX},
        }
        if ollama_tools:
            payload["tools"] = ollama_tools
        resp = requests.post(f"{self.valves.OLLAMA_BASE_URL}/api/chat", json=payload, timeout=300)
        return resp.json()

    def _clean_response(self, content: str) -> str:
        content = re.sub(r'<\|im_start\|>.*', '', content, flags=re.DOTALL)
        content = re.sub(r'<\|im_end\|>', '', content)
        content = re.sub(r'<\|endoftext\|>', '', content)

        lines = content.split('\n')
        result = []
        in_mermaid = False
        in_code = False
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith('```'):
                in_code = not in_code
            if not in_code and not in_mermaid and stripped in (
                'pie', 'pie showData', 'xychart-beta', 'graph', 'flowchart', 'gantt'
            ):
                result.append('```mermaid')
                in_mermaid = True
                in_code = True
            result.append(line)
            if in_mermaid and i + 1 < len(lines) and lines[i + 1].strip() == '' and (
                i + 2 >= len(lines) or not lines[i + 2].startswith('    ')
            ):
                result.append('```')
                in_mermaid = False
                in_code = False
        if in_mermaid:
            result.append('```')

        return '\n'.join(result).strip()

    # ── Main Pipe ─────────────────────────────────────────────────

    async def pipe(self, body: dict, __event_emitter__=None) -> str:
        user_msg = ""
        for msg in reversed(body.get("messages", [])):
            if msg.get("role") == "user":
                c = msg.get("content", "")
                user_msg = c if isinstance(c, str) else str(c)
                break

        fmt = self._detect_format(user_msg)

        if fmt in ("table", "chart"):
            if __event_emitter__:
                await __event_emitter__({"type": "status", "data": {"description": "Searching GitHub...", "done": False}})
            result = self._direct_format(user_msg)
            if __event_emitter__:
                await __event_emitter__({"type": "status", "data": {"description": "", "done": True}})
            if result:
                return result

        tools = self._fetch_tools()
        messages = [{"role": "system", "content": self.valves.SYSTEM_PROMPT}]
        for msg in body.get("messages", []):
            role = msg.get("role", "user")
            content = msg.get("content", "")
            if isinstance(content, list):
                parts = [p.get("text", "") if isinstance(p, dict) else str(p) for p in content]
                content = "\n".join(parts)
            messages.append({"role": role, "content": content})

        for round_num in range(self.valves.MAX_TOOL_ROUNDS):
            if __event_emitter__:
                await __event_emitter__({"type": "status", "data": {"description": f"Thinking... (round {round_num + 1})", "done": False}})
            try:
                response = self._call_ollama(messages, tools)
            except Exception as e:
                return f"Error calling Ollama: {str(e)}"

            message = response.get("message", {})
            tool_calls = message.get("tool_calls", None)

            if not tool_calls:
                if __event_emitter__:
                    await __event_emitter__({"type": "status", "data": {"description": "", "done": True}})
                model_text = self._clean_response(message.get("content", ""))
                return model_text if model_text else "No response generated."

            messages.append(message)
            for tc in tool_calls:
                func = tc.get("function", {})
                tool_name = func.get("name", "")
                arguments = func.get("arguments", {})
                if isinstance(arguments, str):
                    try:
                        arguments = json.loads(arguments)
                    except json.JSONDecodeError:
                        arguments = {}
                if __event_emitter__:
                    await __event_emitter__({"type": "status", "data": {"description": f"Calling {tool_name}...", "done": False}})
                result = self._execute_tool(tool_name, arguments)
                messages.append({"role": "tool", "content": result})

        if __event_emitter__:
            await __event_emitter__({"type": "status", "data": {"description": "Generating response...", "done": False}})
        try:
            response = self._call_ollama(messages, [])
            if __event_emitter__:
                await __event_emitter__({"type": "status", "data": {"description": "", "done": True}})
            return self._clean_response(response.get("message", {}).get("content", ""))
        except Exception as e:
            return f"Error: {str(e)}"
