/**
 * 歌词服务客户端 - 调用 Python 下载微服务中的 LDDC 云端歌词接口 (FastAPI)
 *
 * 与 downloader-client 一致：项目未安装 axios，使用 Node 内置 fetch。
 * 仅负责「搜索候选 / 预览 LRC」，真正的写盘由后端 PUT /api/songs/:id/lyrics 完成
 * （该端点已带 .bak 备份）。
 */
const DOWNLOADER_URL =
  process.env.DOWNLOADER_SERVICE_URL || 'http://localhost:8002';
const DEFAULT_TIMEOUT_MS = 30000;

export interface LyricSource {
  key: string;
  id: string;
  label: string;
  enabled: boolean;
}

export interface LyricCandidate {
  key: string;
  source: string;
  source_label: string;
  title: string;
  artist?: string | null;
  album?: string | null;
  duration?: string | null;
  language?: string | null;
}

export interface LyricSearchSubmitResponse {
  search_id: string;
  status: string;
}

export interface LyricSearchResultResponse {
  search_id: string;
  status: 'pending' | 'done' | 'failed';
  keyword?: string;
  per_source?: Record<string, number>;
  errors?: Record<string, string> | null;
  total: number;
  results: LyricCandidate[];
}

export interface LyricPreview {
  search_id: string;
  source: string;
  index: number;
  title: string;
  artist?: string | null;
  album?: string | null;
  lrc: string;
}

class LyricsClient {
  private async request<T>(
    apiPath: string,
    init?: RequestInit,
    timeoutMs: number = DEFAULT_TIMEOUT_MS,
  ): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(`${DOWNLOADER_URL}${apiPath}`, {
        ...init,
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          ...(init?.headers || {}),
        },
      });
      if (!res.ok) {
        const text = await res.text().catch(() => '');
        throw new Error(`lyrics ${res.status}: ${text.slice(0, 200)}`);
      }
      return (await res.json()) as T;
    } finally {
      clearTimeout(timer);
    }
  }

  getSources() {
    return this.request<LyricSource[]>('/api/lyrics/sources');
  }

  submitSearch(keyword: string, sources?: string[]) {
    return this.request<LyricSearchSubmitResponse>('/api/lyrics/search', {
      method: 'POST',
      body: JSON.stringify({ keyword, sources }),
    });
  }

  getSearch(searchId: string) {
    return this.request<LyricSearchResultResponse>(
      `/api/lyrics/search/${encodeURIComponent(searchId)}`,
    );
  }

  getPreview(searchId: string, source: string, index: number) {
    return this.request<LyricPreview>(
      `/api/lyrics/preview/${encodeURIComponent(searchId)}/${encodeURIComponent(source)}/${index}`,
    );
  }
}

export const lyricsClient = new LyricsClient();
