"""LDDC 云端歌词服务封装层。

独立实例化每个云端歌词 API（QQ / 酷狗 / 网易云 / Lrclib），与上游
LyricsAPI.init() 的「一次性构造全部源」解耦：任一源（尤其网易云的游客登录）
初始化失败时，不影响其它源可用。

歌词结果序列化为标准 LRC（行级时间戳），不依赖上游已被裁掉的
core/converter（Lyrics.to() 会导入 converter，不可用）。
"""
import os
import sys
import time
import threading
import logging
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Optional

# 让 LDDC 源码包可被导入（vendor 目录不在默认 path 中）。
_VENDOR = Path(__file__).resolve().parent / "lddc_vendor"
if str(_VENDOR) not in sys.path:
    sys.path.insert(0, str(_VENDOR))

from LDDC.common.models import Source, SearchType, SongInfo  # noqa: E402
from LDDC.core.api.lyrics.kg import KGAPI  # noqa: E402
from LDDC.core.api.lyrics.ne import NEAPI  # noqa: E402
from LDDC.core.api.lyrics.qm import QMAPI  # noqa: E402
from LDDC.core.api.lyrics.lrclib import LrclibAPI  # noqa: E402

logger = logging.getLogger(__name__)

# short key -> (展示名, API 类)
LYRIC_API_REGISTRY: Dict[str, tuple] = {
    "qm": ("QQ音乐", QMAPI),
    "kugou": ("酷狗音乐", KGAPI),
    "netease": ("网易云音乐", NEAPI),
    "lrclib": ("Lrclib", LrclibAPI),
}
# Source 枚举 -> short key（用于候选 source 字段标准化）
SOURCE_TO_KEY: Dict[Source, str] = {
    Source.QM: "qm",
    Source.KG: "kugou",
    Source.NE: "netease",
    Source.LRCLIB: "lrclib",
}

# 已成功构建的 API 实例（按 short key 缓存，避免每次搜索重建 httpx.Client）
_api_instances: Dict[str, object] = {}
# 初始化失败的源：记录失败时间戳，短时间内跳过（避免网络抖动时反复重试）
_api_failed: Dict[str, float] = {}
_api_lock = threading.Lock()
_API_FAIL_TTL = 60.0


def _get_api(key: str):
    """懒加载并缓存单个云端歌词 API 实例；失败则记入 _api_failed 并返回 None。"""
    with _api_lock:
        inst = _api_instances.get(key)
        if inst is not None:
            return inst
        fail_ts = _api_failed.get(key)
        if fail_ts is not None and (time.time() - fail_ts) < _API_FAIL_TTL:
            return None
    cls = LYRIC_API_REGISTRY[key][1]
    try:
        inst = cls()
    except Exception:  # noqa: BLE001 - 单源初始化失败（如网易游客登录超时）不致命
        logger.exception("[step=lyrics/api] failed to init source=%s (skipped)", key)
        with _api_lock:
            _api_failed[key] = time.time()
        return None
    with _api_lock:
        _api_instances[key] = inst
        _api_failed.pop(key, None)
    return inst


# ---- 异步搜索任务注册表（与 downloader 搜索同构：提交即返回 search_id，轮询结果）----
LYRIC_SEARCH_TASKS: Dict[str, dict] = {}
LYRIC_SEARCH_TASKS_LOCK = threading.Lock()
LYRIC_SEARCH_CACHE: Dict[str, Dict[str, List[SongInfo]]] = {}
LYRIC_SEARCH_CACHE_LOCK = threading.Lock()
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="lyrics-search")


def _update_lyrics_task(search_id: str, **kwargs):
    with LYRIC_SEARCH_TASKS_LOCK:
        task = LYRIC_SEARCH_TASKS.get(search_id)
        if task:
            task.update(kwargs)
            task["updated_at"] = time.time()


def get_lyrics_task(search_id: str):
    with LYRIC_SEARCH_TASKS_LOCK:
        return LYRIC_SEARCH_TASKS.get(search_id)


def get_cached_candidate(search_id: str, source_key: str, index: int):
    with LYRIC_SEARCH_CACHE_LOCK:
        cached = LYRIC_SEARCH_CACHE.get(search_id)
    if not cached:
        return None
    songs = cached.get(source_key)
    if not songs or index >= len(songs):
        return None
    return songs[index]


def _run_lyrics_search(search_id: str, keyword: str, sources: Optional[List[str]]) -> None:
    """对请求的每个源执行 LDDC 搜索，结果按 search_id 写入 LYRIC_SEARCH_CACHE。

    单源失败不影响其它源（各自 try/except，记录 per_source 计数与 errors）。
    """
    per_source: Dict[str, int] = {}
    errors: Dict[str, str] = {}
    results: Dict[str, List[SongInfo]] = {}
    wanted = [s for s in (sources or list(LYRIC_API_REGISTRY)) if s in LYRIC_API_REGISTRY]
    logger.info("[step=lyrics/search/run] search_id=%s keyword=%r sources=%s", search_id, keyword, wanted)
    for key in wanted:
        api = _get_api(key)
        if api is None:
            errors[key] = "source unavailable"
            per_source[key] = 0
            continue
        try:
            res = api.search(keyword, SearchType.SONG)
            songs = list(res)
            results[key] = songs
            per_source[key] = len(songs)
            logger.info("[step=lyrics/search/source] %s count=%d", key, len(songs))
        except Exception:  # noqa: BLE001 - 单源搜索失败不影响其它源
            logger.exception("[step=lyrics/search/source] %s FAILED", key)
            errors[key] = "search failed"
            per_source[key] = 0
    with LYRIC_SEARCH_CACHE_LOCK:
        LYRIC_SEARCH_CACHE[search_id] = results
    _update_lyrics_task(search_id, status="done", per_source=per_source, errors=errors)
    logger.info("[step=lyrics/search/done] search_id=%s per_source=%s", search_id, per_source)


def submit_lyrics_search(keyword: str, sources: Optional[List[str]] = None) -> str:
    """提交一次异步歌词候选搜索，立即返回 search_id。"""
    search_id = os.urandom(8).hex()
    now = time.time()
    with LYRIC_SEARCH_TASKS_LOCK:
        LYRIC_SEARCH_TASKS[search_id] = {
            "search_id": search_id,
            "status": "pending",
            "keyword": keyword,
            "sources": sources,
            "per_source": None,
            "errors": None,
            "created_at": now,
            "updated_at": now,
        }
    logger.info("[step=lyrics/search/submit] search_id=%s keyword=%r", search_id, keyword)
    _executor.submit(_run_lyrics_search, search_id, keyword, sources)
    return search_id


def _fmt_time(ms: int) -> str:
    """毫秒 -> LRC 时间戳 [MM:SS.xx]（百分秒，标准 .lrc 格式）。"""
    ms = max(int(ms), 0)
    mm, rem = divmod(ms, 60000)
    ss, cs = divmod(rem, 1000)
    return f"{mm:02d}:{ss:02d}.{cs // 10:02d}"


def lyrics_to_lrc(lyrics) -> str:
    """把 LDDC 的 Lyrics / FSLyrics 序列化为标准行级 LRC 文本。

    优先取「完整时间戳」视图（get_fslyrics，可推断缺失行时间戳），
    缺失时回落到原始行数据；只取原语言歌词（orig）。逐字时间戳不展开
    （本项目当前仅抓取覆盖，不做逐字增强）。
    """
    lang_data = None
    try:
        fs = lyrics.get_fslyrics()
        lang_data = fs.get("orig") or (list(fs.values())[0] if fs else None)
    except Exception:  # noqa: BLE001 - get_fslyrics 异常时回落原始数据
        logger.debug("[step=lyrics/lrc] get_fslyrics failed, fallback to raw data")
    if not lang_data:
        lang_data = lyrics.get("orig") or (list(lyrics.values())[0] if lyrics else None)
    if not lang_data:
        return ""
    lines: List[str] = []
    for line in lang_data:
        start = getattr(line, "start", None)
        if start is None:
            continue
        words = getattr(line, "words", []) or []
        text = "".join(getattr(w, "text", "") or "" for w in words).strip()
        if not text:
            continue
        lines.append(f"[{_fmt_time(start)}]{text}")
    if not lines:
        return ""
    return "\n".join(lines) + "\n"


def get_lyrics_lrc_for_candidate(search_id: str, source_key: str, index: int) -> Optional[dict]:
    """解析候选 -> 拉取歌词 -> 序列化为 LRC，返回预览结构；无歌词或失败返回 None。"""
    song = get_cached_candidate(search_id, source_key, index)
    if song is None:
        return None
    api = _get_api(source_key)
    if api is None:
        return None
    try:
        lyrics = api.get_lyrics(song)
    except Exception:  # noqa: BLE001 - 找不到歌词或解析失败
        logger.exception("[step=lyrics/preview] get_lyrics failed source=%s index=%d", source_key, index)
        return None
    if not lyrics:
        return None
    lrc = lyrics_to_lrc(lyrics)
    if not lrc:
        return None
    return {
        "search_id": search_id,
        "source": source_key,
        "index": index,
        "title": getattr(song, "title", None) or "",
        "artist": song.artist.str() if getattr(song, "artist", None) else None,
        "album": getattr(song, "album", None),
        "lrc": lrc,
    }
