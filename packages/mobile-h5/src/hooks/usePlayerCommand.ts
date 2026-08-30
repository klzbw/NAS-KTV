/* Hallmark · genre: editorial · theme: Garden · usePlayerCommand hook
 * 手机遥控：通过 WebSocket 向 TV 端播放器下发播放控制命令
 */
import { wsClient } from '../ws/client';
import { WsMessageType, type PlayerCommandPayload, type LyricOffsetPayload, type MicVolumeCommandPayload } from '@nasktv/shared';

export function sendPlayerCommand(command: PlayerCommandPayload): void {
  wsClient.send({
    type: WsMessageType.PLAYER_COMMAND,
    payload: command,
    timestamp: Date.now(),
  });
}

/** 麦克风音量遥控命令（H5 → 后端 → TV 端执行）。 */
export function sendMicVolumeCommand(command: MicVolumeCommandPayload): void {
  wsClient.send({
    type: WsMessageType.MIC_VOLUME_CMD,
    payload: command,
    timestamp: Date.now(),
  });
}

export function sendLyricOffset(offsetMs: number): void {
  const payload: LyricOffsetPayload = { offsetMs };
  wsClient.send({
    type: WsMessageType.LYRIC_OFFSET,
    payload,
    timestamp: Date.now(),
  });
}
