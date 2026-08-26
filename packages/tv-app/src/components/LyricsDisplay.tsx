/* Hallmark · component: lyrics-display · genre: atmospheric · theme: Midnight
 * 两行歌词 slot 循环复用，交替爬升：上行靠左、下行靠右，
 * 当前句按句号奇偶在上/下行交替，形成左→右→左之字错位；
 * 超长歌词不换行，横向滚动显示（marquee），渐变背景随文本同步滚动
 */
import { useRef, useEffect, useState, useLayoutEffect } from 'react';
import type { LyricLine, LyricWord } from '../hooks/usePlayer';

interface LyricsDisplayProps {
  lines: LyricLine[];
  currentIndex: number;
  currentTime: number;
  duration?: number;
  lyricOffsetMs?: number;
  /** 播放中：rAF 以锚点 + performance.now() 插值；暂停时冻结在锚点，避免漂移 */
  isPlaying?: boolean;
}

const css = `
/* 歌词容器：bottom 避开底部播放进度条（np-progress 约占底部 64~160px 区域） */
.lyrics-display {
  position: absolute;
  bottom: 190px;
  left: 0;
  right: 0;
  z-index: 15;
  display: flex;
  flex-direction: column;
  gap: 48px;
  pointer-events: none;
  padding: 0 80px;
}

/* 歌词行基础：统一字号，不换行，超出部分由内层滚动展示 */
.lyrics-slot {
  max-width: 1200px;
  font-family: "Microsoft YaHei", "Source Han Sans SC", "Noto Sans SC", sans-serif;
  font-size: clamp(36px, 4vw, 52px);
  font-weight: 700;
  line-height: 1.4;
  overflow: hidden;
  white-space: nowrap;
}

/* 上行（slot0，偶数句为当前句）：靠左 */
.lyrics-display > .lyrics-slot:first-child {
  align-self: flex-start;
  text-align: left;
}

/* 下行（slot1，奇数句为当前句）：靠右 */
.lyrics-display > .lyrics-slot:last-child {
  align-self: flex-end;
  text-align: right;
}

/* 内层文本：跟随滚动动画（渐变背景也随文本移动） */
.lyrics-inner {
  display: inline-block;
  will-change: transform;
}

/* 超长歌词：横向滚动（位移与时长由 JS 测量后通过 CSS 变量注入） */
.lyrics-slot.marquee .lyrics-inner {
  animation: lyrics-marquee var(--marquee-duration, 12s) linear infinite;
  animation-delay: 1.5s;
}

@keyframes lyrics-marquee {
  from { transform: translateX(0); }
  to { transform: translateX(var(--marquee-offset, -200px)); }
}

/* 逐字片段：--p CSS 变量驱动渐变 stop（rAF 每帧直写）
   p=0 → 全 ink-2（未唱）；p=1 → 全 accent（已唱）；p=0.5 → 左半已唱右半未唱
   background-size 100% 让渐变横跨整个 span；inherited --p 让 Chrome70 下
   background-clip:text 与渐变 stop 正确绑定。 */
.lyric-word {
  display: inline-block;
  --p: 0%;
  background-image: linear-gradient(
    to right,
    var(--color-accent) var(--p),
    var(--color-ink-2) var(--p)
  );
  background-size: 100% 100%;
  background-repeat: no-repeat;
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

/* 当前行已完成（lineProgress>=1）：所有字全亮 accent（无需 rAF 重算） */
.lyrics-slot.completed .lyric-word {
  --p: 100%;
}

/* 行级 fallback：LRC 不含 <mm:ss.xx> 标签时（如 Lrclib）整行退化为单 span 走 --lyric-progress。
   与逐字共用同一颜色对：已唱 = accent，未唱 = ink-2，强化对比让用户能"看出来"。 */
.lyrics-slot.line-mode .lyrics-inner {
  background-image: linear-gradient(
    90deg,
    var(--color-accent) 0%,
    var(--color-accent) var(--lyric-progress, 0%),
    var(--color-ink-2) var(--lyric-progress, 0%),
    var(--color-ink-2) 100%
  );
  background-size: 100% 100%;
  background-repeat: no-repeat;
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

/* 下一句预览：灰色（同字号） */
.lyrics-slot.preview {
  color: var(--color-ink-3);
}

/* 空行占位 */
.lyrics-slot.empty {
  visibility: hidden;
}
`;

/**
 * 单行歌词 slot：仅「正在播放的当前句」在文本超宽时测量溢出距离并注入横向滚动参数（位移/时长）。
 * 预览句/已唱完句不滚动，保持静止展示。
 * 渐变背景放在内层 span 上，随文本 transform 一起滚动，避免 background-clip 错位。
 *
 * 逐字模式（useWordMode）：当前行 line.words 存在时按词渲染 <span class="lyric-word">，
 * 渐变填充由父组件 rAF 直写每词的 --p CSS 变量驱动。
 * 行级模式（!useWordMode）：Lrclib 等无 <mm:ss.xx> 标签时退化为整行单 span 走 --lyric-progress。
 */
function LyricSlot({
  text,
  words,
  className,
  style,
}: {
  text: string;
  words?: LyricWord[];
  className: string;
  style?: React.CSSProperties;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [overflowing, setOverflowing] = useState(false);
  const [marqueeStyle, setMarqueeStyle] = useState<React.CSSProperties>({});

  const isCurrent = className.includes('current');
  const useWordMode = isCurrent && Array.isArray(words) && words.length > 0;

  useLayoutEffect(() => {
    // 非当前句不滚动：预览/已唱完保持静止
    if (!isCurrent) {
      setOverflowing(false);
      setMarqueeStyle({});
      return;
    }
    const el = ref.current;
    const inner = el?.firstElementChild as HTMLElement | null;
    if (!el || !inner) return;
    // 溢出距离 = 文本实际宽度 - 容器可视宽度（预留一小段间隙）
    const distance = inner.scrollWidth - el.clientWidth;
    if (distance > 8) {
      const travel = distance + 24;
      // 滚动速度约 55px/s，时长限制在 8~30s，保证可读又不拖沓
      const duration = Math.max(8, Math.min(30, travel / 55));
      setOverflowing(true);
      setMarqueeStyle({
        '--marquee-offset': `-${travel}px`,
        '--marquee-duration': `${duration.toFixed(1)}s`,
      } as React.CSSProperties);
    } else {
      setOverflowing(false);
      setMarqueeStyle({});
    }
  }, [text, className, isCurrent, useWordMode]);

  return (
    <div
      ref={ref}
      className={`${className}${overflowing ? ' marquee' : ''}`}
      style={style}
    >
      <span className="lyrics-inner" style={overflowing ? marqueeStyle : undefined}>
        {useWordMode
          ? words!.map((w, i) => (
              <span
                key={i}
                className="lyric-word"
                data-wstart={w.start}
                data-wend={w.end}
              >
                {w.text}
              </span>
            ))
          : text || '...'}
      </span>
    </div>
  );
}

export default function LyricsDisplay({ lines, currentIndex, currentTime, duration = 0, lyricOffsetMs = 0, isPlaying = true }: LyricsDisplayProps) {
  const [slot0Text, setSlot0Text] = useState('');
  const [slot1Text, setSlot1Text] = useState('');
  const [slot0Words, setSlot0Words] = useState<LyricWord[] | undefined>(undefined);
  const [slot1Words, setSlot1Words] = useState<LyricWord[] | undefined>(undefined);
  const [slot0Class, setSlot0Class] = useState('lyrics-slot empty');
  const [slot1Class, setSlot1Class] = useState('lyrics-slot empty');
  const [slot0Progress, setSlot0Progress] = useState(0);
  const [slot1Progress, setSlot1Progress] = useState(0);

  const prevIndexRef = useRef(currentIndex);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const currentLine = lines[currentIndex];
    const nextLine = lines[currentIndex + 1];

    // 行切换已由 usePlayer 按 currentTime + lyricOffsetMs/1000 匹配，
    // 行内渐变进度同样叠加偏移，保持换行与渐变一致
    const adjustedTime = currentTime + lyricOffsetMs / 1000;

    // 计算当前行的时间范围
    const lineStart = currentLine?.time ?? 0;
    const lineEnd = nextLine?.time ?? (lineStart + 4000);
    const lineDuration = lineEnd - lineStart;

    // 计算当前行进度 (0~1)
    const lineProgress = lineDuration > 0
      ? Math.max(0, Math.min(1, (adjustedTime - lineStart) / lineDuration))
      : 0;

    // 判断是否需要切换 slot
    const isNewLine = prevIndexRef.current !== currentIndex;
    if (isNewLine) {
      prevIndexRef.current = currentIndex;
    }

    // 确定哪个 slot 显示当前句，哪个显示下一句
    // 偶数句：slot0=当前，slot1=下一句
    // 奇数句：slot1=当前，slot0=下一句
    const useSlot0ForCurrent = currentIndex % 2 === 0;
    const hasWords = !!currentLine?.words && currentLine.words.length > 0;
    const currentModeSuffix = hasWords ? '' : ' line-mode';
    const currentText = currentLine?.text || '...';

    if (useSlot0ForCurrent) {
      // slot0 显示当前句
      setSlot0Text(currentText);
      setSlot0Words(currentLine?.words);
      setSlot0Class(`lyrics-slot ${lineProgress >= 1 ? 'completed' : 'current'}${currentModeSuffix}`);
      setSlot0Progress(lineProgress * 100);

      // slot1 显示下一句
      if (nextLine) {
        setSlot1Text(nextLine.text);
        setSlot1Words(undefined);
        setSlot1Class('lyrics-slot preview');
      } else {
        setSlot1Text('');
        setSlot1Words(undefined);
        setSlot1Class('lyrics-slot empty');
      }
      setSlot1Progress(0);
    } else {
      // slot1 显示当前句
      setSlot1Text(currentText);
      setSlot1Words(currentLine?.words);
      setSlot1Class(`lyrics-slot ${lineProgress >= 1 ? 'completed' : 'current'}${currentModeSuffix}`);
      setSlot1Progress(lineProgress * 100);

      // slot0 显示下一句
      if (nextLine) {
        setSlot0Text(nextLine.text);
        setSlot0Words(undefined);
        setSlot0Class('lyrics-slot preview');
      } else {
        setSlot0Text('');
        setSlot0Words(undefined);
        setSlot0Class('lyrics-slot empty');
      }
      setSlot0Progress(0);
    }
  }, [lines, currentIndex, currentTime, lyricOffsetMs]);

  // 逐字 rAF tick：按当前播放时间计算每词 --p（已唱进度），直写 CSS 变量。
  // 锚点更新放在函数体（每次渲染 currentTime 真正变化时刷新），不依赖 useEffect
  // 的浅比较：避免「timeupdate 节流命中 0.2s 临界值导致 setCurrentTime 不触发」
  // 或「props 浅比较未变」时锚点 ts 停在过去、冻结误命中、字高亮卡死。
  // 插值/冻结判定：播放中以锚点 + 经过时间插值；暂停冻结；广播/卡顿兜底（5s）冻结。
  const anchorRef = useRef({ t: currentTime + lyricOffsetMs / 1000, ts: performance.now() });
  const lastTimeRef = useRef(currentTime + lyricOffsetMs / 1000);
  const playingRef = useRef(isPlaying);
  playingRef.current = isPlaying;

  const newTime = currentTime + lyricOffsetMs / 1000;
  if (newTime !== lastTimeRef.current) {
    lastTimeRef.current = newTime;
    anchorRef.current = { t: newTime, ts: performance.now() };
  }

  useEffect(() => {
    let raf = 0;
    const tick = () => {
      raf = requestAnimationFrame(tick);
      const container = containerRef.current;
      if (!container) return;
      const now = performance.now();
      const elapsed = (now - anchorRef.current.ts) / 1000;
      // 暂停或广播/卡顿超过 5s 未更新：冻结在锚点（防止漂移、防止视觉跑飞）
      // 正常播放：以锚点 + 经过时间插值（rAF 平滑推进）
      const t =
        !playingRef.current || elapsed > 5
          ? anchorRef.current.t
          : anchorRef.current.t + elapsed;

      const wordEls = container.querySelectorAll(
        '.lyrics-slot.current .lyric-word',
      ) as NodeListOf<HTMLElement>;
      for (const el of wordEls) {
        const ws = parseFloat(el.dataset.wstart || '');
        const we = parseFloat(el.dataset.wend || '');
        if (!isFinite(ws) || !isFinite(we)) continue;
        const p = we > ws ? Math.max(0, Math.min(1, (t - ws) / (we - ws))) : 0;
        el.style.setProperty('--p', `${p * 100}%`);
      }
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <>
      <style>{css}</style>

      {/* 歌词区域 */}
      <div ref={containerRef} className="lyrics-display">
        <LyricSlot
          text={slot0Text}
          words={slot0Words}
          className={slot0Class}
          style={slot0Class.includes('line-mode') ? { '--lyric-progress': `${slot0Progress}%` } as React.CSSProperties : undefined}
        />
        <LyricSlot
          text={slot1Text}
          words={slot1Words}
          className={slot1Class}
          style={slot1Class.includes('line-mode') ? { '--lyric-progress': `${slot1Progress}%` } as React.CSSProperties : undefined}
        />
      </div>
    </>
  );
}
