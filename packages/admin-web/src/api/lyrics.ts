import client from './client';
import type { ApiResponse } from '../types';

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

export interface LyricSearchResult {
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

export const lyricsApi = {
  sources: (): Promise<LyricSource[]> =>
    client
      .get<ApiResponse<LyricSource[]>>('/lyrics/sources')
      .then((res) => res.data.data),
  search: (
    keyword: string,
    sources?: string[],
  ): Promise<{ search_id: string; status: string }> =>
    client
      .post<ApiResponse<{ search_id: string; status: string }>>('/lyrics/search', {
        keyword,
        sources,
      })
      .then((res) => res.data.data),
  searchResult: (id: string): Promise<LyricSearchResult> =>
    client
      .get<ApiResponse<LyricSearchResult>>(`/lyrics/search/${id}`)
      .then((res) => res.data.data),
  preview: (id: string, source: string, index: number): Promise<LyricPreview> =>
    client
      .get<ApiResponse<LyricPreview>>(`/lyrics/preview/${id}/${source}/${index}`)
      .then((res) => res.data.data),
};
