export type SeparationModel = 'htdemucs' | 'htdemucs_ft' | 'mdx_extra' | 'sdx_extra' | 'bsrnn';

export const SEPARATION_MODELS: { value: SeparationModel; label: string; hint: string }[] = [
  { value: 'htdemucs', label: '标准版', hint: '速度快，适合大多数歌曲' },
  { value: 'htdemucs_ft', label: '高质版', hint: '音质更佳，处理速度较慢' },
  { value: 'mdx_extra', label: '均衡版', hint: '混合架构，细节更丰富' },
  { value: 'sdx_extra', label: '稳定版', hint: '新架构，长音频更稳定' },
  { value: 'bsrnn', label: '旗舰版', hint: '最新 SOTA 模型，质量最高，速度最慢' },
];

export const separationModelLabel = (value?: string | null) =>
  SEPARATION_MODELS.find(m => m.value === value)?.label ?? value ?? '—';

export type TranscodeProfile = 'compatible' | 'standard' | 'high';

export const TRANSCODE_PROFILES: { value: TranscodeProfile; label: string; hint: string }[] = [
  { value: 'compatible', label: '兼容优先（480p）', hint: '854x480 / 视频 1200k / 音频 128k，最省空间、兼容性最广' },
  { value: 'standard', label: '标准（720p）', hint: '1280x720 / 视频 2500k / 音频 192k，推荐默认' },
  { value: 'high', label: '高清（1080p）', hint: '1920x1080 / 视频 5000k / 音频 256k，画质最佳、体积最大' },
];

export const transcodeProfileLabel = (value?: string | null) =>
  TRANSCODE_PROFILES.find(m => m.value === value)?.label ?? value ?? '—';
