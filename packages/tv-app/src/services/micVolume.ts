/**
 * MicVolumeService —— TV 端麦克风采集音量控制接口（权威端）
 *
 * 职责
 * - 采集麦克风：getUserMedia 拿到麦克风流，经 Web Audio GainNode monitor 到扬声器
 *   （KTV 场景需监听自身人声；与播放 DSP 同为 WebView 内软件处理，跨 Windows/Android）。
 * - 音量控制：setVolume / adjustVolume / setMute / toggleMute，统一写 GainNode.gain。
 * - 状态广播：任何变化通过 MIC_VOLUME_STATE 经 WS 广播给房间内所有 H5 用户（来源唯一）。
 * - 远程通道：监听 H5 下发的 MIC_VOLUME_CMD（mobile→TV 由后端中转）并执行。
 * - 持久化：volume / muted 存 localStorage，TV 重启后恢复上次设置。
 *
 * 扩展性：当前后端为 Web Audio 软件增益；后续若要改为系统级（Windows Core Audio /
 * Android AudioManager）麦克风控制，只需替换 ensureMic / apply 内的实现，接口不变。
 */

import { wsClient } from '../ws/client';
import {
  WsMessageType,
  type MicVolumeCommandPayload,
  type MicVolumeStatePayload,
} from '@nasktv/shared';

const VOLUME_MIN = 0;
const VOLUME_MAX = 1;
const VOLUME_DEFAULT = 0.8;
const VOLUME_STEP = 0.1; // H5/遥控单次步进
const LS_VOLUME = 'nasktv.micVolume';
const LS_MUTED = 'nasktv.micMuted';

export interface MicVolumeState {
  volume: number; // 0~1（静音时仍为真实音量，muted 单独标记）
  muted: boolean;
  supported: boolean; // 麦克风采集是否可用（无设备/未授权为 false）
}

type Listener = (state: MicVolumeState) => void;

class MicVolumeServiceImpl {
  private volume = VOLUME_DEFAULT;
  private muted = false;
  private supported = false; // 初始未知，采集成功后置 true，失败置 false
  private audioCtx: AudioContext | null = null;
  private gainNode: GainNode | null = null;
  private stream: MediaStream | null = null;
  private listeners = new Set<Listener>();
  private initialized = false;

  constructor() {
    // 恢复持久化设置（采集尚未开始，但 UI 可先显示上次值）
    const savedVolume = Number(localStorage.getItem(LS_VOLUME));
    if (Number.isFinite(savedVolume)) {
      this.volume = Math.max(VOLUME_MIN, Math.min(VOLUME_MAX, savedVolume));
    }
    this.muted = localStorage.getItem(LS_MUTED) === '1';
  }

  /** 幂等初始化：注册 WS 命令监听与连接后补发状态。App 根组件挂载时调用一次。 */
  init(): void {
    if (this.initialized) return;
    this.initialized = true;

    // H5 → TV 麦克风命令（后端已校验 mobile 身份并中转）
    wsClient.on(WsMessageType.MIC_VOLUME_CMD, (msg) => {
      const payload = (msg.payload ?? {}) as MicVolumeCommandPayload;
      this.handleCommand(payload);
    });

    // WS 连接建立后主动广播一次当前状态，保证 H5 重连/新开立即拿到最新音量
    wsClient.onStatusChange((status) => {
      if (status === 'connected') this.broadcastState();
    });

    // 不在初始化时主动索取麦克风权限（避免启动即弹窗）；改为首次本地/远程交互时
    // 惰性采集（见 setVolume/setMute 内的 ensureMic），采集结果决定 supported 状态。
  }

  /** 懒采集麦克风并建立音频图；成功返回 true。失败（无设备/未授权）标记 unsupported 并广播。 */
  async ensureMic(): Promise<boolean> {
    if (this.gainNode && this.stream) return true;
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error('getUserMedia unsupported');
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
        },
        video: false,
      });
      const AudioCtx =
        window.AudioContext ||
        (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      const ctx = new AudioCtx();
      const source = ctx.createMediaStreamSource(stream);
      const gain = ctx.createGain();
      gain.gain.value = this.muted ? 0 : this.volume;
      // 麦克风 monitor 到扬声器：歌手听到自身人声（与播放 DSP 在 OS 层混音）
      source.connect(gain);
      gain.connect(ctx.destination);

      this.stream = stream;
      this.audioCtx = ctx;
      this.gainNode = gain;
      this.supported = true;
      this.applyGain();
      this.emit();
      this.broadcastState();
      return true;
    } catch {
      // 无设备 / 未授权 / 自动播放策略拦截：标记不支持，H5 据此禁用控制
      this.supported = false;
      this.emit();
      this.broadcastState();
      return false;
    }
  }

  private applyGain(): void {
    if (this.gainNode) {
      this.gainNode.gain.value = this.muted ? 0 : this.volume;
    }
  }

  // ===== 控制接口（H5 命令 / TV 遥控均走此处）=====

  setVolume(value: number): void {
    void this.ensureMic(); // 首次交互惰性采集麦克风（TV 本地手势 / H5 远程命令均触发）
    this.volume = Math.max(VOLUME_MIN, Math.min(VOLUME_MAX, value));
    localStorage.setItem(LS_VOLUME, String(this.volume));
    this.applyGain();
    this.emit();
    this.broadcastState();
  }

  adjustVolume(delta: number): void {
    this.setVolume(this.volume + delta);
  }

  setMute(muted: boolean): void {
    void this.ensureMic();
    this.muted = muted;
    localStorage.setItem(LS_MUTED, muted ? '1' : '0');
    this.applyGain();
    this.emit();
    this.broadcastState();
  }

  toggleMute(): void {
    this.setMute(!this.muted);
  }

  /** 供 TV 端 UI 主动请求麦克风权限（点击麦克风按钮时调用）。 */
  requestMic(): void {
    void this.ensureMic();
  }

  private handleCommand(payload: MicVolumeCommandPayload): void {
    const cmd = payload.command;
    if (cmd === 'set' && typeof payload.value === 'number') {
      this.setVolume(payload.value);
    } else if (cmd === 'adjust' && typeof payload.value === 'number') {
      this.adjustVolume(payload.value);
    } else if (cmd === 'set_mute' && typeof payload.value === 'boolean') {
      this.setMute(payload.value);
    } else if (cmd === 'toggle_mute') {
      this.toggleMute();
    }
  }

  getState(): MicVolumeState {
    return { volume: this.volume, muted: this.muted, supported: this.supported };
  }

  /** 导出为 WS payload（含 timestamp）。 */
  toPayload(): MicVolumeStatePayload {
    return {
      volume: this.volume,
      muted: this.muted,
      supported: this.supported,
      timestamp: Date.now(),
    };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.getState());
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(): void {
    const state = this.getState();
    this.listeners.forEach((l) => l(state));
  }

  private broadcastState(): void {
    wsClient.send({
      type: WsMessageType.MIC_VOLUME_STATE,
      payload: this.toPayload(),
      timestamp: Date.now(),
    });
  }
}

/** 单例：TV 内唯一权威来源。 */
export const micVolumeService = new MicVolumeServiceImpl();

export const MIC_VOLUME_STEP = VOLUME_STEP;
