/** Live pipeline logs for the ops page + server stdout. */

export type LogLevel = 'info' | 'ok' | 'warn' | 'error' | 'step';

export type PipelineLogLine = {
  t: string;
  level: LogLevel;
  msg: string;
};

type Listener = (line: PipelineLogLine) => void;

const MAX_LINES = 2_000;
const buffer: PipelineLogLine[] = [];
const listeners = new Set<Listener>();

export function getPipelineLogBuffer(): PipelineLogLine[] {
  return [...buffer];
}

export function clearPipelineLog(): void {
  buffer.length = 0;
}

export function subscribePipelineLog(fn: Listener): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function pipelineLog(msg: string, level: LogLevel = 'info'): void {
  const line: PipelineLogLine = {
    t: new Date().toISOString(),
    level,
    msg,
  };
  buffer.push(line);
  if (buffer.length > MAX_LINES) {
    buffer.splice(0, buffer.length - MAX_LINES);
  }
  const prefix =
    level === 'error'
      ? '❌'
      : level === 'warn'
        ? '⚠️'
        : level === 'ok'
          ? '✅'
          : level === 'step'
            ? '▶'
            : '·';
  console.log(`[pipeline] ${prefix} ${msg}`);
  for (const fn of listeners) {
    try {
      fn(line);
    } catch {
      /* ignore subscriber errors */
    }
  }
}
