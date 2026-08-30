import client from './client';

// 逐字歌词片段
export interface LyricWord {
  text: string; // 逐字文本
  start: number; // 起播时间，秒（绝对歌曲时间）
  end: number;   // 结束时间，秒（绝对歌曲时间）
}

// 歌词行
export interface LyricLine {
  time: number;    // 秒
  text: string;
  words?: LyricWord[]; // 逐字歌词（源 LRC 含 <mm:ss.xx> 时存在）
}

export const songsApi = {
  // 获取指定歌曲的歌词列表
  getLyrics: (songId: number, signal?: AbortSignal): Promise<LyricLine[]> =>
    client.get<{ success: boolean; data: { lines: LyricLine[]; wordTiming: boolean } | LyricLine[] }>(
      `/songs/${songId}/lyrics`,
      { signal },
    ).then(res => {
      const data = res.data.data;
      // 后端返回 { lines, wordTiming }，兼容旧版直接返回数组
      const lyrics = Array.isArray(data) ? data : data?.lines;
      return Array.isArray(lyrics) ? lyrics : [];
    }),
};
