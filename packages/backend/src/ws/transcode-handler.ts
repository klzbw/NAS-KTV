import { WebSocket } from 'ws';
import logger from '../logger';
import { transcodeQueue } from '../services/transcode-queue';
import { WsMessageType } from '@nasktv/shared';
import type {
  TranscodeStartedPayload,
  TranscodeProgressPayload,
  TranscodeCompletedPayload,
  TranscodeFailedPayload,
  WsMessage,
} from '@nasktv/shared';

// 已连接的 WebSocket 客户端（Admin）
const clients = new Set<WebSocket>();

export function registerTranscodeClient(ws: WebSocket): void {
  clients.add(ws);

  ws.on('close', () => {
    clients.delete(ws);
  });

  ws.on('error', () => {
    clients.delete(ws);
  });
}

export function broadcastTranscodeMessage<T>(
  type: WsMessageType,
  payload: T,
): void {
  const message: WsMessage<T> = {
    type,
    payload,
    timestamp: Date.now(),
  };
  const messageStr = JSON.stringify(message);

  clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(messageStr);
    }
  });
}

/**
 * 初始化转码进度 WebSocket 推送
 */
export function initTranscodeProgressHandler(): void {
  transcodeQueue.on('started', (event) => {
    const payload: TranscodeStartedPayload = {
      taskId: event.taskId,
      songId: event.songId,
      songTitle: event.songTitle,
    };
    broadcastTranscodeMessage(WsMessageType.TRANSCODE_STARTED, payload);
  });

  transcodeQueue.on('progress', (event) => {
    const payload: TranscodeProgressPayload = {
      taskId: event.taskId,
      songId: event.songId,
      progress: event.progress ?? 0,
      stage: event.stage ?? 'transcoding',
    };
    broadcastTranscodeMessage(WsMessageType.TRANSCODE_PROGRESS, payload);
  });

  transcodeQueue.on('completed', (event) => {
    const payload: TranscodeCompletedPayload = {
      taskId: event.taskId,
      songId: event.songId,
      transcodedPath: event.transcodedPath ?? '',
    };
    broadcastTranscodeMessage(WsMessageType.TRANSCODE_COMPLETED, payload);
  });

  transcodeQueue.on('failed', (event) => {
    const payload: TranscodeFailedPayload = {
      taskId: event.taskId,
      songId: event.songId,
      error: event.error ?? 'Unknown error',
    };
    broadcastTranscodeMessage(WsMessageType.TRANSCODE_FAILED, payload);
  });

  logger.info('Transcode progress WebSocket handler initialized');
}
