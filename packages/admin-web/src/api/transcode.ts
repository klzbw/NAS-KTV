import client from './client';
import type {
  TranscodeTask,
  TranscodeTaskListParams,
  ApiResponse,
  PaginatedResponse,
} from '../types';

export interface TranscodeTriggerParams {
  songId: number;
  profile?: string;
}

export const transcodeApi = {
  trigger: (data: TranscodeTriggerParams): Promise<{ taskId: number; songId: number }> =>
    client
      .post<ApiResponse<{ taskId: number; songId: number }>>(`/songs/${data.songId}/transcode`, {
        profile: data.profile,
      })
      .then((res) => res.data.data),
  getTasks: (params?: TranscodeTaskListParams): Promise<PaginatedResponse<TranscodeTask>> =>
    client
      .get<ApiResponse<PaginatedResponse<TranscodeTask>>>('/transcode/tasks', { params })
      .then((res) => res.data.data),
  getTask: (id: number): Promise<TranscodeTask> =>
    client
      .get<ApiResponse<TranscodeTask>>(`/transcode/tasks/${id}`)
      .then((res) => res.data.data),
  retryTask: (id: number): Promise<TranscodeTask> =>
    client
      .post<ApiResponse<TranscodeTask>>(`/transcode/tasks/${id}/retry`)
      .then((res) => res.data.data),
  stopTask: (id: number): Promise<void> =>
    client
      .post<ApiResponse<null>>(`/transcode/tasks/${id}/stop`)
      .then(() => undefined),
  batchRetry: (taskIds: number[]): Promise<{ succeeded: number; skipped: number }> =>
    client
      .post<ApiResponse<{ succeeded: number; skipped: number }>>('/transcode/tasks/batch-retry', { taskIds })
      .then((res) => res.data.data),
  batchDelete: (taskIds: number[]): Promise<{ succeeded: number; skipped: number }> =>
    client
      .post<ApiResponse<{ succeeded: number; skipped: number }>>('/transcode/tasks/batch-delete', { taskIds })
      .then((res) => res.data.data),
  batchStop: (taskIds: number[]): Promise<{ succeeded: number; skipped: number }> =>
    client
      .post<ApiResponse<{ succeeded: number; skipped: number }>>('/transcode/tasks/batch-stop', { taskIds })
      .then((res) => res.data.data),
  getQueueStatus: (): Promise<{ pending: number; processing: number; completed: number; failed: number }> =>
    client
      .get<ApiResponse<{ pending: number; processing: number; completed: number; failed: number }>>('/transcode/queue/status')
      .then((res) => res.data.data),
  ffmpegAvailable: (): Promise<boolean> =>
    client
      .get<ApiResponse<{ available: boolean }>>('/transcode/ffmpeg')
      .then((res) => res.data.data.available),
};
