#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ReadingCoach 服务端接口测试脚本。

仅依赖 Python3 标准库，自动完成登录并串测主要业务接口，重点验证
拍照图片识别（/api/articles/ocr, Qwen-VL）与后续文章生成流程。

用法示例：
    python3 test_api.py                                   # 测本机 :8080
    python3 test_api.py --base-url http://1.2.3.4:8080    # 测远程发布环境
    python3 test_api.py --image /path/to/book.jpg         # 指定 OCR 测试图片
    python3 test_api.py --skip-ocr                        # 跳过图片识别
    python3 test_api.py --phone 13800138000               # 指定登录手机号

退出码：全部通过为 0，出现失败为 1。
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

# ------------------------------------------------------------------ 输出辅助

_USE_COLOR = sys.stdout.isatty()


def _c(code: str, text: str) -> str:
    if not _USE_COLOR:
        return text
    return f"\033[{code}m{text}\033[0m"


def info(msg: str) -> None:
    print(_c("36", "• ") + msg)


def ok(msg: str) -> None:
    print(_c("32", "✓ ") + msg)


def fail(msg: str) -> None:
    print(_c("31", "✗ ") + msg)


def title(msg: str) -> None:
    print("\n" + _c("1;35", "== " + msg + " =="))


# 与用户之前提供的书本截图对应，作为 OCR 默认测试图（存在才用）。
DEFAULT_IMAGE = os.path.expanduser(
    "~/.cursor/projects/Users-wang-Project-WordsApp-ReadingCoach/assets/"
    "020d560fbc6df5ad4110cda8480f7c69-dcd30def-2ebf-4783-907f-443737db5ffa.png"
)

# OCR 不可用时，用来兜底验证文章生成流程的英文样例正文。
FALLBACK_ARTICLE_TEXT = (
    "Wikipedia is a free online encyclopaedia. It attracts millions of visitors "
    "every month, and it is available in hundreds of different languages. "
    "The site is updated on a daily basis by thousands of people around the world."
)


class APIError(Exception):
    pass


class Client:
    """极简 HTTP 客户端，封装统一的 {success, message, data} 响应解析。"""

    def __init__(self, base_url: str, timeout: float = 30.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.token = None

    def _request(self, method: str, path: str, body=None, timeout=None):
        url = self.base_url + path
        data = None
        # 带上浏览器 UA，避免被 Cloudflare 按客户端签名拦截（Error 1010）。
        headers = {
            "Accept": "application/json",
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/125.0.0.0 Safari/537.36"
            ),
        }
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if self.token:
            headers["Authorization"] = "Bearer " + self.token

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        started = time.time()
        try:
            with urllib.request.urlopen(req, timeout=timeout or self.timeout) as resp:
                raw = resp.read()
                status = resp.status
        except urllib.error.HTTPError as e:
            raw = e.read()
            status = e.code
        except urllib.error.URLError as e:
            raise APIError(f"连接失败: {e.reason}")
        elapsed = (time.time() - started) * 1000

        text = raw.decode("utf-8", errors="replace")
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            parsed = None
        return status, parsed, text, elapsed

    def call(self, method: str, path: str, body=None, timeout=None, expect_data=True):
        """发起请求并要求 success==true，返回 data 字段。"""
        status, parsed, text, elapsed = self._request(method, path, body, timeout)
        tag = f"{method} {path} [{status}, {elapsed:.0f}ms]"
        if parsed is None:
            raise APIError(f"{tag} 响应非 JSON: {text[:200]}")
        if not (200 <= status < 300) or not parsed.get("success", False):
            raise APIError(f"{tag} 失败: {parsed.get('message', text[:200])}")
        info(tag)
        return parsed.get("data") if expect_data else parsed


# ------------------------------------------------------------------ 测试步骤


def test_health(client: Client) -> None:
    title("健康检查")
    status, parsed, text, elapsed = client._request("GET", "/api/health")
    if status != 200:
        raise APIError(f"/api/health 状态码 {status}: {text[:200]}")
    ok(f"服务存活 [{elapsed:.0f}ms] {parsed}")


def do_login(client: Client, phone: str) -> None:
    title("登录鉴权")
    data = client.call("POST", "/api/auth/code", {"phone": phone})
    code = str(data.get("debugCode", "")).strip()
    if not code:
        raise APIError("未拿到 debugCode（生产环境可能已关闭调试验证码，请手动指定）")
    ok(f"获取验证码: {code}")

    data = client.call(
        "POST",
        "/api/auth/login",
        {"phone": phone, "code": code, "agreePolicy": True},
    )
    token = data.get("token")
    if not token:
        raise APIError("登录未返回 token")
    client.token = token
    user = data.get("userInfo", {})
    ok(f"登录成功: user_id={user.get('id')} nickname={user.get('nickname')}")


def test_user(client: Client) -> None:
    title("当前用户信息")
    data = client.call("GET", "/api/auth/user")
    ok(f"用户: id={data.get('id')} nickname={data.get('nickname')}")


def test_ocr(client: Client, image_path: str) -> str:
    title("拍照图片识别 (Qwen-VL OCR)")
    if not image_path or not os.path.isfile(image_path):
        fail(f"未找到图片，跳过 OCR：{image_path or '(未指定)'}（可用 --image 指定）")
        return ""

    ext = os.path.splitext(image_path)[1].lower()
    mime = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".heic": "image/heic",
    }.get(ext, "image/jpeg")

    with open(image_path, "rb") as f:
        raw = f.read()
    b64 = base64.b64encode(raw).decode("ascii")
    info(f"上传图片: {os.path.basename(image_path)} ({len(raw)/1024:.0f} KB, {mime})")

    data = client.call(
        "POST",
        "/api/articles/ocr",
        {"image_base64": b64, "mime_type": mime},
        timeout=120,
    )
    text = (data or {}).get("text", "")
    if not text.strip():
        raise APIError("OCR 返回空文本")
    preview = text if len(text) <= 500 else text[:500] + " ...(截断)"
    ok(f"识别成功，共 {len(text)} 字符：\n" + _c("2", preview))
    return text


def test_process_text(client: Client, text: str) -> str:
    title("生成文章 (DeepSeek 拆句 + 翻译)")
    payload = text.strip() if text.strip() else FALLBACK_ARTICLE_TEXT
    if not text.strip():
        info("OCR 无结果，使用内置英文样例正文兜底测试")
    data = client.call(
        "POST",
        "/api/articles/process-text",
        {"text": payload},
        timeout=120,
    )
    resource_id = (data or {}).get("resource_id", "")
    if not resource_id:
        raise APIError("未返回 resource_id")
    ok(f"文章生成成功: resource_id={resource_id}")
    return resource_id


def test_article_detail(client: Client, resource_id: str) -> None:
    title("文章详情")
    data = client.call("GET", f"/api/articles/{resource_id}")
    sentences = data.get("sentences", []) if isinstance(data, dict) else []
    ok(f"标题: {data.get('title')!r}，句子数: {len(sentences)}")
    for i, s in enumerate(sentences[:3], 1):
        original = s.get("original", "")
        translation = s.get("translation", "")
        print(_c("2", f"    {i}. {original}  ->  {translation}"))


def test_article_list(client: Client) -> None:
    title("文章列表")
    data = client.call("GET", "/api/articles?limit=5&offset=0")
    items = data.get("items", []) if isinstance(data, dict) else []
    ok(f"共取到 {len(items)} 篇（最多 5）")
    for it in items:
        print(_c("2", f"    - {it.get('title')!r} (id={it.get('id')})"))


# ------------------------------------------------------------------ 主流程


def main() -> int:
    parser = argparse.ArgumentParser(description="ReadingCoach 服务端接口测试")
    parser.add_argument("--base-url", default="http://localhost:8080", help="服务端地址")
    parser.add_argument("--phone", default="13800138000", help="登录测试手机号")
    parser.add_argument("--image", default=DEFAULT_IMAGE, help="OCR 测试图片路径")
    parser.add_argument("--skip-ocr", action="store_true", help="跳过图片识别测试")
    parser.add_argument("--skip-process", action="store_true", help="跳过文章生成测试")
    args = parser.parse_args()

    client = Client(args.base_url)
    print(_c("1", f"目标服务端: {client.base_url}"))

    passed, failed = [], []

    def run(name, fn, *a):
        try:
            return fn(*a), True
        except APIError as e:
            fail(f"{name} 失败: {e}")
            failed.append(name)
            return None, False
        except Exception as e:  # noqa: BLE001
            fail(f"{name} 异常: {e}")
            failed.append(name)
            return None, False

    # 健康检查失败则无需继续
    _, alive = run("健康检查", test_health, client)
    if alive:
        passed.append("健康检查")
    else:
        print(_c("31", "\n服务端不可达，终止测试。"))
        return 1

    _, logged_in = run("登录鉴权", do_login, client, args.phone)
    if not logged_in:
        print(_c("31", "\n登录失败，后续鉴权接口无法测试，终止。"))
        return 1
    passed.append("登录鉴权")

    if run("用户信息", test_user, client)[1]:
        passed.append("用户信息")

    ocr_text = ""
    if not args.skip_ocr:
        (ocr_text_result, ocr_ok) = run("图片识别", test_ocr, client, args.image)
        if ocr_ok:
            passed.append("图片识别")
            ocr_text = ocr_text_result or ""

    if not args.skip_process:
        (resource_id, proc_ok) = run("文章生成", test_process_text, client, ocr_text)
        if proc_ok:
            passed.append("文章生成")
            if resource_id and run("文章详情", test_article_detail, client, resource_id)[1]:
                passed.append("文章详情")

    if run("文章列表", test_article_list, client)[1]:
        passed.append("文章列表")

    # 汇总
    title("测试结果汇总")
    print(_c("32", f"通过 {len(passed)}: " + ", ".join(passed)))
    if failed:
        print(_c("31", f"失败 {len(failed)}: " + ", ".join(failed)))
        return 1
    ok("全部通过 🎉")
    return 0


if __name__ == "__main__":
    sys.exit(main())
