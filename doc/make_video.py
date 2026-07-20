#!/usr/local/bin/python3.13
# -*- coding: utf-8 -*-
"""
根据 chunk_*_sentences.json 生成学习视频（MP4）
音频结构：英文原声 → 中文TTS → 英文原声 → 中文TTS → ...
画面结构：滚动字幕，当前句居中高亮，前后各显示5句

用法: python3.13 make_video.py <sentences.json路径>
"""

import os, sys, json, subprocess, tempfile, shutil, re, asyncio, datetime
import edge_tts
from PIL import Image, ImageDraw, ImageFont

# 输出按行刷新，重定向到文件时能实时看到进度
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(line_buffering=True)

# ── 画面配置 ─────────────────────────────────────────────────────
W, H       = 2160, 1620
FPS        = 4
BG_COLOR   = (0x0F, 0x1D, 0x3E)   # #0F1D3E 深蓝背景
HL_COLOR   = (255, 255, 255)      # #FFFFFF 当前句高亮（白）
CN_COLOR   = (0x22, 0xD3, 0xEE)   # #22D3EE 中文（青）
DIM_EN     = (0x94, 0xA3, 0xB8)   # #94A3B8 非当前句英文（灰）
DIM_CN     = (0x47, 0x55, 0x69)   # #475569 非当前句中文（深灰）

PADDING_X  = 100
PADDING_Y  = 76
LINE_GAP   = 16                    # 行间距（同一句内多行之间）
SENT_GAP   = 32                    # 句间额外间距（句与句之间）

EN_SIZE_HL  = 54                    # 高亮英文字号
EN_SIZE_DIM = 40                    # 非高亮英文字号
CN_SIZE_HL  = 42                    # 高亮中文字号
CN_SIZE_DIM = 32                    # 非高亮中文字号
TITLE_SIZE  = 38

CONTEXT_N  = 3                     # 当前句前后各显示几句

HIGHLIGHT_ADVANCE = 1.0            # 高亮提前于声音的秒数

EN_CLIP_PAD = 0.3                  # 裁剪英文片段时头尾各延长秒数，避免读不全

COVER_DUR  = 1.0                   # 封面显示时长（秒）

# 字体路径（脚本所在目录下的 fonts/）
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
EN_FONT_HL_PATH  = os.path.join(_SCRIPT_DIR, "fonts", "Poppins-SemiBold.ttf")   # 英文高亮
EN_FONT_DIM_PATH = os.path.join(_SCRIPT_DIR, "fonts", "Poppins-Regular.ttf")     # 英文非高亮
FONT_PATH        = EN_FONT_DIM_PATH   # 标题等
CN_FONT_PATH     = os.path.join(_SCRIPT_DIR, "fonts", "NotoSansSC-Regular.ttf")  # 中文

CN_VOICE   = "zh-CN-XiaoxiaoNeural"
CN_RATE    = "+10%"   # 语速略快（+0% 为默认）
GAP_EN_CN  = 0.5    # 英文结束 → 中文开始 间隔(秒)
GAP_CN_EN  = 0.5    # 中文结束 → 下一句英文 间隔(秒)

# 整句高亮模式（True=整句高亮，False=逐词高亮）
SENTENCE_HIGHLIGHT = True

ABBR_MAP = {
    r'\bsb\b': 'somebody', r'\bsth\b': 'something',
    r'\badj\b': 'adjective', r'\badv\b': 'adverb',
    r'\bprep\b': 'preposition',
}
def expand_abbr(text):
    for p, r in ABBR_MAP.items():
        text = re.sub(p, r, text, flags=re.IGNORECASE)
    return text

# ── 字体（高亮 / 非高亮 区分字号与字体）────────────────────────────
en_font_hl  = ImageFont.truetype(EN_FONT_HL_PATH, EN_SIZE_HL)   # Poppins SemiBold
en_font_dim = ImageFont.truetype(EN_FONT_DIM_PATH, EN_SIZE_DIM)  # Poppins Regular
cn_font_hl  = ImageFont.truetype(CN_FONT_PATH, CN_SIZE_HL)
cn_font_dim = ImageFont.truetype(CN_FONT_PATH, CN_SIZE_DIM)
title_font  = ImageFont.truetype(FONT_PATH, TITLE_SIZE)
CONTENT_W   = W - PADDING_X * 2

def text_w(text, font):
    b = font.getbbox(text); return b[2] - b[0]

def lh(font):
    b = font.getbbox("Ag"); return b[3] - b[1] + LINE_GAP

def wrap_words(words, font, max_w):
    lines, cur, cw = [], [], 0
    sw = text_w(" ", font)
    for word in words:
        ww = text_w(word, font)
        if cur and cw + sw + ww > max_w:
            lines.append(cur); cur, cw = [word], ww
        else:
            cur.append(word); cw += (sw if cur else 0) + ww
    if cur: lines.append(cur)
    return lines

def wrap_cn(text, font, max_w):
    lines, cur = [], ""
    for ch in text:
        if text_w(cur + ch, font) > max_w:
            lines.append(cur); cur = ch
        else:
            cur += ch
    if cur: lines.append(cur)
    return lines or [text]

def draw_en_words(draw, words, x, y, is_current, font):
    """is_current=True: 橙红高亮；False: 灰色"""
    sw = text_w(" ", font)
    cx = x
    color = HL_COLOR if is_current else DIM_EN
    for word in words:
        draw.text((cx, y), word, font=font, fill=color)
        cx += text_w(word, font) + sw

def sentence_height(g, is_current):
    """计算一个句子组占用的像素高度（按是否高亮选用字号）"""
    en_font = en_font_hl if is_current else en_font_dim
    cn_font = cn_font_hl if is_current else cn_font_dim
    ew = [w["word"] for w in g["words"]] if g["words"] else g["en"]["text"].split()
    en_lines = len(wrap_words(ew, en_font, CONTENT_W))
    cn_lines = len(wrap_cn(g["cn"], cn_font, CONTENT_W)) if g["cn"] else 0
    return en_lines * lh(en_font) + cn_lines * lh(cn_font) + SENT_GAP

# ── 读取 JSON ────────────────────────────────────────────────────
if len(sys.argv) < 2:
    print("用法: python3.13 make_video.py <sentences.json路径>"); sys.exit(1)

JSON_PATH = os.path.abspath(sys.argv[1])
BASE_DIR  = os.path.dirname(os.path.abspath(__file__))

with open(JSON_PATH, encoding="utf-8") as f:
    items = json.load(f)

json_dir  = os.path.dirname(JSON_PATH)
book_name = os.path.basename(json_dir)
chunk_id  = os.path.basename(JSON_PATH).replace("_sentences.json", "")

EN_MP3 = os.path.join(BASE_DIR, "mp3", "chunks", book_name, f"{chunk_id}.mp3")
if not os.path.exists(EN_MP3):
    ep = (re.search(r'\b(\d{2})\b', book_name) or type('', (), {'group': lambda s,x: '01'})()).group(1)
    EN_MP3 = os.path.join(BASE_DIR, "mp3_chunks", ep, f"{chunk_id}.mp3")
EN_MP3 = os.path.abspath(EN_MP3)

OUT_FILE = os.path.join(os.path.abspath(json_dir), f"{chunk_id}.mp4")
TMP_DIR  = tempfile.mkdtemp(prefix="video_")

_script_start = datetime.datetime.now()
print(f"[{_script_start.strftime('%Y-%m-%d %H:%M:%S')}] make_video 开始")
print(f"英文音频 : {EN_MP3}")
print(f"输出视频 : {OUT_FILE}")
print(f"临时目录 : {TMP_DIR}\n")

# ── 解析句子组 ───────────────────────────────────────────────────
groups = []
i = 0
while i < len(items):
    item = items[i]
    if item.get("type") in ("cn", "note"):
        i += 1; continue
    g = {"en": item, "words": item.get("words", []), "cn_texts": []}
    j = i + 1
    while j < len(items) and items[j].get("type") in ("cn", "note"):
        g["cn_texts"].append(items[j]["text"])
        j += 1
    g["cn"] = "　".join(g["cn_texts"])
    groups.append(g)
    i = j

print(f"共 {len(groups)} 句\n")

# ── ffmpeg 工具（通过 shell 脚本绕过沙盒） ───────────────────────
def run_ffmpeg(args):
    script = os.path.join(TMP_DIR, "_run.sh")
    cmd = " ".join(f'"{a}"' if " " in str(a) else str(a) for a in args)
    with open(script, "w") as f:
        f.write(f"#!/bin/sh\n{cmd}\n")
    os.chmod(script, 0o755)
    return subprocess.run([script], capture_output=True)

def make_silence(dur, path):
    run_ffmpeg(["/usr/local/bin/ffmpeg", "-y", "-f", "lavfi",
        "-i", f"anullsrc=r=44100:cl=stereo", "-t", str(dur),
        "-acodec", "libmp3lame", "-q:a", "9", path])

# ── 生成中文 TTS（带重试，应对超时/503） ─────────────────────────
print("生成中文 TTS...")
TTS_RETRIES = 3
TTS_RETRY_DELAY = 5

async def save_tts_with_retry(path, text):
    for attempt in range(TTS_RETRIES):
        try:
            communicate = edge_tts.Communicate(text, CN_VOICE, rate=CN_RATE)
            await communicate.save(path)
            return
        except (TimeoutError, ConnectionError, asyncio.CancelledError) as e:
            if attempt < TTS_RETRIES - 1:
                await asyncio.sleep(TTS_RETRY_DELAY)
                continue
            raise
        except Exception as e:
            err = type(e).__name__
            if "503" in str(e) or "WSServerHandshakeError" in err or "ClientError" in err:
                if attempt < TTS_RETRIES - 1:
                    await asyncio.sleep(TTS_RETRY_DELAY)
                    continue
            raise

async def gen_tts_all():
    tasks = []
    for gi, g in enumerate(groups):
        if g["cn"]:
            path = os.path.join(TMP_DIR, f"cn_{gi:04d}.mp3")
            g["cn_audio"] = path
            tasks.append((path, expand_abbr(g["cn"])))
    batch = 20
    for s in range(0, len(tasks), batch):
        await asyncio.gather(*[
            save_tts_with_retry(path, text)
            for path, text in tasks[s:s+batch]
        ])
        print(f"  TTS {min(s+batch, len(tasks))}/{len(tasks)}")

asyncio.run(gen_tts_all())

# 静音片段
sil_short = os.path.join(TMP_DIR, "sil_short.mp3")
sil_long  = os.path.join(TMP_DIR, "sil_long.mp3")
make_silence(GAP_EN_CN, sil_short)
make_silence(GAP_CN_EN, sil_long)

# ── 裁剪英文片段（仅句末为标点时在头尾加 EN_CLIP_PAD）────────────────────
def sentence_ends_with_punctuation(g):
    """句子文本是否以句末标点结尾（. ! ? 等）"""
    text = (g["en"].get("text") or "").strip()
    return bool(text) and text[-1] in ".!?"

print("\n裁剪英文音频（重新编码确保时长精确）...")
# 获取整段 chunk 时长，用于限制 end 不超出
def probe_duration(path):
    script = os.path.join(TMP_DIR, "_probe.sh")
    out_f  = os.path.join(TMP_DIR, "_probe_out.txt")
    with open(script, "w") as f:
        f.write(f'#!/bin/sh\n/usr/local/bin/ffprobe -v quiet -show_entries format=duration -of csv=p=0 "{path}" > "{out_f}" 2>/dev/null\n')
    os.chmod(script, 0o755)
    subprocess.run([script], capture_output=True)
    try:
        with open(out_f) as f:
            return float(f.read().strip())
    except Exception:
        return 0.0

en_mp3_dur = probe_duration(EN_MP3)
for gi, g in enumerate(groups):
    en = g["en"]
    # 当前句以标点结尾 → 本句末尾加 pad；上一句以标点结尾 → 本句开头加 pad
    cur_has_punct = sentence_ends_with_punctuation(g)
    prev_has_punct = sentence_ends_with_punctuation(groups[gi - 1]) if gi > 0 else False
    t_start = en["start"] - (EN_CLIP_PAD if prev_has_punct else 0.0)
    t_end   = en["end"] + (EN_CLIP_PAD if cur_has_punct else 0.0)
    t_start = max(0.0, t_start)
    t_end   = min(en_mp3_dur, t_end) if en_mp3_dur > 0 else t_end
    path = os.path.join(TMP_DIR, f"en_{gi:04d}.mp3")
    r = run_ffmpeg(["/usr/local/bin/ffmpeg", "-y",
        "-ss", str(t_start), "-to", str(t_end),
        "-i", EN_MP3,
        "-acodec", "libmp3lame", "-q:a", "4", "-ar", "44100", "-ac", "2",
        path])
    if r.returncode != 0:
        print(f"  ✗ {gi}: {r.stderr[-80:].decode()}")
    g["en_audio"] = path
    g["en_dur"] = t_end - t_start
    if gi % 20 == 0: print(f"  {gi+1}/{len(groups)}")

# ── 构建拼接后的音频时间轴 ───────────────────────────────────────
# 每句结构：[en_clip] [sil_short] [cn_clip] [sil_long]
# 记录每句英文在拼接音频中的起始时间，用于帧对齐

# 用 shell 脚本调 ffprobe 测量中文 TTS 时长（TTS 文件在 /var/folders 下，需绕过沙盒）
def get_audio_dur_sh(path):
    script = os.path.join(TMP_DIR, "_probe.sh")
    out_f  = os.path.join(TMP_DIR, "_probe_out.txt")
    with open(script, "w") as f:
        f.write(f'#!/bin/sh\n/usr/local/bin/ffprobe -v quiet -show_entries format=duration -of csv=p=0 "{path}" > "{out_f}" 2>/dev/null\n')
    os.chmod(script, 0o755)
    subprocess.run([script], capture_output=True)
    try:
        with open(out_f) as f:
            return float(f.read().strip())
    except:
        return 2.0  # 默认 2 秒

print("\n测量中文 TTS 时长...")
for g in groups:
    if g.get("cn_audio") and os.path.exists(g["cn_audio"]):
        g["cn_dur"] = get_audio_dur_sh(g["cn_audio"])
    else:
        g["cn_dur"] = 0.0

# 构建时间轴：每句在拼接音频中的绝对起始时间
# en_dur 用原始时间戳差值（精确），cn_dur 用实测值
cursor = 0.0
for g in groups:
    g["abs_en_start"] = cursor
    cursor += g["en_dur"] + GAP_EN_CN
    g["abs_cn_start"] = cursor
    cursor += g["cn_dur"] + GAP_CN_EN

total_audio_dur = cursor
print(f"拼接音频总时长: {total_audio_dur:.1f}s\n")

# ── 生成视频帧 ───────────────────────────────────────────────────
print("生成视频帧...")
frames_dir = os.path.join(TMP_DIR, "frames")
os.makedirs(frames_dir)

def draw_sentence(draw, g, y, is_current):
    """在 y 处绘制一个句子组（高亮用大字号，非高亮用小字号），返回绘制后的 y"""
    en_font = en_font_hl if is_current else en_font_dim
    cn_font = cn_font_hl if is_current else cn_font_dim
    ew = [w["word"] for w in g["words"]] if g["words"] else g["en"]["text"].split()
    for line in wrap_words(ew, en_font, CONTENT_W):
        draw_en_words(draw, line, PADDING_X, y, is_current, en_font)
        y += lh(en_font)
    if g["cn"]:
        cn_color = CN_COLOR if is_current else DIM_CN
        for cl in wrap_cn(g["cn"], cn_font, CONTENT_W):
            draw.text((PADDING_X, y), cl, font=cn_font, fill=cn_color)
            y += lh(cn_font)
    y += SENT_GAP
    return y

def render_frame(gi, _wi, _phase):
    """
    滚动字幕：当前句（gi）居中，前后各显示 CONTEXT_N 句。
    通过计算偏移量让当前句垂直居中。
    """
    img  = Image.new("RGB", (W, H), BG_COLOR)
    draw = ImageDraw.Draw(img)

    # 标题栏
    title_y = PADDING_Y
    title = f"{book_name}  {chunk_id.replace('_',' ').upper()}"
    draw.text((PADDING_X, title_y), title, font=title_font, fill=(190, 190, 190))
    title_h = lh(title_font) + 6
    draw.line([(PADDING_X, title_y + title_h - 4), (W-PADDING_X, title_y + title_h - 4)],
              fill=(220,220,220), width=1)
    content_top = title_y + title_h + 6   # 内容区起始 y

    # 确定要显示的句子范围
    start_i = max(0, gi - CONTEXT_N)
    end_i   = min(len(groups) - 1, gi + CONTEXT_N)
    visible = list(range(start_i, end_i + 1))

    # 计算当前句高度（高亮），用于垂直居中
    cur_h = sentence_height(groups[gi], is_current=True)

    # 计算 start_i 到 gi-1 的总高度（非高亮）
    before_h = sum(sentence_height(groups[k], is_current=False) for k in range(start_i, gi))

    # 内容区可用高度
    content_h = H - content_top - PADDING_Y

    # 让当前句的中心对齐内容区中心
    cur_center_in_content = content_h // 2
    # start_i 第一句的绘制起始 y（相对于 content_top）
    draw_offset = cur_center_in_content - before_h - cur_h // 2

    y = content_top + draw_offset

    for k in visible:
        g = groups[k]
        # 裁剪：只绘制在可视区域内的句子
        sh = sentence_height(g, is_current=(k == gi))
        if y + sh < content_top or y > H - PADDING_Y:
            y += sh
            continue
        draw_sentence(draw, g, y, is_current=(k == gi))
        y += sh

    return img

total_frames = int(total_audio_dur * FPS) + 1
print(f"总帧数: {total_frames}（{total_audio_dur:.1f}s @ {FPS}fps）")

# 预构建帧状态查找表
# 每帧对应 (gi, word_hi, phase)
# 在英文阶段：word_hi 根据原始 word timestamps 映射到拼接音频时间
# 在中文阶段：word_hi = -1

def build_frame_states():
    if not SENTENCE_HIGHLIGHT:
        # 逐词模式：预计算每个词在拼接音频中的绝对时间
        for g in groups:
            en_orig_start = g["en"]["start"]
            abs_en_start  = g["abs_en_start"]
            g["abs_words"] = [
                abs_en_start + (w["start"] - en_orig_start)
                for w in g["words"]
            ]

    states = []
    for f in range(total_frames):
        t       = f / FPS
        t_hl    = t + HIGHLIGHT_ADVANCE   # 高亮用提前后的时间

        # 用提前时间找高亮句
        gi_cur = 0
        for gi in range(len(groups) - 1, -1, -1):
            if t_hl >= groups[gi]["abs_en_start"]:
                gi_cur = gi
                break

        g = groups[gi_cur]

        if t_hl < g["abs_cn_start"]:
            # 英文阶段
            if SENTENCE_HIGHLIGHT:
                states.append((gi_cur, 0, "en"))
            else:
                abs_words = g["abs_words"]
                wi = 0
                for idx, awt in enumerate(abs_words):
                    if t_hl >= awt: wi = idx
                    else: break
                states.append((gi_cur, wi, "en"))
        else:
            states.append((gi_cur, -1, "cn"))
    return states

print("构建帧状态表...")
frame_states = build_frame_states()

# ── 封面帧 ───────────────────────────────────────────────────────
# 封面图：mp3/mp3_src/ 下，与书名同名的 .png，如 01 Diary of a Wimpy Kid.png
mp3_src_dir = os.path.join(BASE_DIR, "mp3", "mp3_src")
COVER_PATH  = os.path.join(mp3_src_dir, f"{book_name}.png")
cover_frames = int(COVER_DUR * FPS)
frame_idx = 0

# 从 chunk_id 提取页码数字（如 chunk_01 -> 1）
chunk_page_num = None
m = re.search(r"\d+", chunk_id)
if m:
    chunk_page_num = int(m.group(0))

if os.path.exists(COVER_PATH):
    print(f"插入封面（{COVER_DUR}s，{cover_frames}帧）: {os.path.basename(COVER_PATH)}")
    cover_img = Image.open(COVER_PATH).convert("RGB")
    # 等比缩放后居中裁剪到视频尺寸
    cw, ch = cover_img.size
    scale = max(W / cw, H / ch)
    new_cw, new_ch = int(cw * scale), int(ch * scale)
    cover_img = cover_img.resize((new_cw, new_ch), Image.LANCZOS)
    left = (new_cw - W) // 2
    top  = (new_ch - H) // 2
    cover_img = cover_img.crop((left, top, left + W, top + H))
    # 封面底部绘制 chunk 序号（页码）
    if chunk_page_num is not None:
        draw_cover = ImageDraw.Draw(cover_img)
        page_text = str(chunk_page_num)
        page_font = ImageFont.truetype(FONT_PATH, 72)
        tw = text_w(page_text, page_font)
        px = (W - tw) // 2
        py = H - PADDING_Y - 80
        draw_cover.text((px, py), page_text, font=page_font, fill=(120, 120, 120))
    cover_path_tmp = os.path.join(TMP_DIR, "cover_frame.png")
    cover_img.save(cover_path_tmp)
    for _ in range(cover_frames):
        os.link(cover_path_tmp, os.path.join(frames_dir, f"frame_{frame_idx:06d}.png"))
        frame_idx += 1
else:
    print(f"未找到封面: {COVER_PATH}，跳过封面")
    cover_frames = 0

prev_state     = None
prev_img       = None
prev_frame_path = None   # 上一帧文件路径，重复帧用 link 避免重复 save
for f, state in enumerate(frame_states):
    gi, wi, phase = state
    current_path  = os.path.join(frames_dir, f"frame_{frame_idx:06d}.png")

    if state != prev_state or f == 0:
        prev_img = render_frame(gi, wi, phase)
        prev_state = state
        prev_img.save(current_path)
        prev_frame_path = current_path
    else:
        os.link(prev_frame_path, current_path)

    frame_idx += 1
    if f % (FPS * 10) == 0:
        print(f"  帧进度: {f}/{total_frames} ({f/FPS:.0f}s)")

print("帧生成完毕\n")

# ── 拼接音频 ─────────────────────────────────────────────────────
print("拼接音频...")
# 封面静音
sil_cover = os.path.join(TMP_DIR, "sil_cover.mp3")
if cover_frames > 0:
    make_silence(COVER_DUR, sil_cover)

concat_list = os.path.join(TMP_DIR, "concat.txt")
with open(concat_list, "w") as f:
    if cover_frames > 0:
        f.write(f"file '{sil_cover}'\n")
    for g in groups:
        f.write(f"file '{g['en_audio']}'\n")
        f.write(f"file '{sil_short}'\n")
        if g.get("cn_audio") and os.path.exists(g["cn_audio"]):
            f.write(f"file '{g['cn_audio']}'\n")
        f.write(f"file '{sil_long}'\n")

audio_out = os.path.join(TMP_DIR, "audio.mp3")
r = run_ffmpeg(["/usr/local/bin/ffmpeg", "-y", "-f", "concat", "-safe", "0",
    "-i", concat_list, "-acodec", "libmp3lame", "-q:a", "4",
    "-ar", "44100", "-ac", "2", audio_out])
if r.returncode != 0:
    print(f"✗ 音频拼接失败:\n{r.stderr[-300:].decode()}"); sys.exit(1)
print(f"  音频: {os.path.getsize(audio_out)//1024}KB")

# ── 合成视频 ─────────────────────────────────────────────────────
print("合成视频...")
r = run_ffmpeg(["/usr/local/bin/ffmpeg", "-y",
    "-framerate", str(FPS),
    "-i", os.path.join(frames_dir, "frame_%06d.png"),
    "-i", audio_out,
    "-c:v", "libx264", "-preset", "fast", "-crf", "23",
    "-c:a", "aac", "-b:a", "128k",
    "-pix_fmt", "yuv420p", "-shortest",
    OUT_FILE])
if r.returncode != 0:
    print(f"✗ 视频合成失败:\n{r.stderr[-300:].decode()}")

_end = datetime.datetime.now()
if os.path.exists(OUT_FILE):
    size_mb = os.path.getsize(OUT_FILE) / 1024 / 1024
    print(f"\n✓ 完成！{OUT_FILE}  ({size_mb:.1f} MB)")
    shutil.rmtree(TMP_DIR)
    print("临时文件已清理")
    print(f"[{_end.strftime('%Y-%m-%d %H:%M:%S')}] make_video 结束，耗时 {(_end - _script_start).total_seconds():.1f}s")
else:
    print(f"⚠️  视频未生成，临时目录保留: {TMP_DIR}")
    print(f"[{_end.strftime('%Y-%m-%d %H:%M:%S')}] make_video 结束，耗时 {(_end - _script_start).total_seconds():.1f}s")
