export interface HudState {
  visible: boolean;
  health: number;
  armor: number;
  hunger: number | null;
  thirst: number | null;
  stamina: number;
  oxygen: number;
  underwater: boolean;
  talking: boolean;
  voice: number | null;
  radio: boolean;
  street: string;
  crossStreet: string;
  zone: string;
  heading: number;
  radar: boolean;
  vehicle: boolean;
  speed: number;
  fuel: number;
  gear: number;
  reversing: boolean;
  rpm: number;
  engine: boolean;
}

export function finitePercent(value: unknown): number | null {
  if (value === null || value === undefined || value === '' || typeof value === 'boolean') return null;
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.min(100, number)) : null;
}

export function continuousHeading(previous: number, next: number): number {
  if (!Number.isFinite(next)) return previous;
  const normalized = ((next % 360) + 360) % 360;
  const current = ((previous % 360) + 360) % 360;
  return previous + ((normalized - current + 540) % 360) - 180;
}

export function displayedHeading(value: number): number {
  return ((Math.round(value) % 360) + 360) % 360;
}

export function gearLabel(gear: number | undefined, reversing: boolean | undefined): string {
  if (reversing) return 'R';
  return gear && gear > 0 ? String(gear) : 'N';
}
