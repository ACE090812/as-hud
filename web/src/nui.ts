declare global {
  interface Window { GetParentResourceName?: () => string; }
}

export function isGame(): boolean {
  return typeof window.GetParentResourceName === 'function';
}

export async function fetchNui<T>(action: string, data: unknown = {}, fallback?: T): Promise<T> {
  if (!isGame()) {
    if (fallback !== undefined) return fallback;
    throw new Error('This action requires a running game session.');
  }
  const response = await fetch(`https://${window.GetParentResourceName!()}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error(`Request failed (${response.status}).`);
  return response.json() as Promise<T>;
}

export function onNui<T>(action: string, handler: (data: T) => void): () => void {
  const listener = (event: MessageEvent) => {
    if (!event.data || typeof event.data !== 'object' || event.data.action !== action) return;
    handler(event.data.data as T);
  };
  window.addEventListener('message', listener);
  return () => window.removeEventListener('message', listener);
}
