import { useEffect, useState, useCallback } from 'react';
import { micVolumeService, MIC_VOLUME_STEP, type MicVolumeState } from '../services/micVolume';

export interface UseMicVolumeReturn {
  volume: number;
  muted: boolean;
  supported: boolean;
  setVolume: (v: number) => void;
  adjustVolume: (delta: number) => void;
  setMute: (muted: boolean) => void;
  toggleMute: () => void;
  requestMic: () => void;
  step: number;
}

/**
 * TV 端麦克风音量 React 绑定：订阅 MicVolumeService 状态，暴露控制动作。
 * onChange 在音量/静音变化（含 H5 远程触发）后回调，用于 OSD 反馈。
 */
export function useMicVolume(onChange?: (state: MicVolumeState) => void): UseMicVolumeReturn {
  const [state, setState] = useState<MicVolumeState>(() => micVolumeService.getState());

  useEffect(() => {
    // 跳过订阅时的首次同步回调（携带初始状态），避免开机闪一次麦克风 OSD；
    // 仅后续真实变化（本地 D-pad / H5 远程）触发 onChange 反馈。
    let first = true;
    const unsub = micVolumeService.subscribe((s) => {
      setState(s);
      if (first) {
        first = false;
        return;
      }
      onChange?.(s);
    });
    return unsub;
  }, [onChange]);

  const setVolume = useCallback((v: number) => micVolumeService.setVolume(v), []);
  const adjustVolume = useCallback((delta: number) => micVolumeService.adjustVolume(delta), []);
  const setMute = useCallback((m: boolean) => micVolumeService.setMute(m), []);
  const toggleMute = useCallback(() => micVolumeService.toggleMute(), []);
  const requestMic = useCallback(() => micVolumeService.requestMic(), []);

  return {
    volume: state.volume,
    muted: state.muted,
    supported: state.supported,
    setVolume,
    adjustVolume,
    setMute,
    toggleMute,
    requestMic,
    step: MIC_VOLUME_STEP,
  };
}
