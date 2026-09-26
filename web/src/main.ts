import '@fontsource/barlow-condensed/latin-700-italic.css';
import '@fontsource/barlow-condensed/latin-600.css';
import heart from '@phosphor-icons/core/fill/heartbeat-fill.svg?raw';
import shield from '@phosphor-icons/core/fill/shield-fill.svg?raw';
import food from '@phosphor-icons/core/fill/bowl-food-fill.svg?raw';
import drink from '@phosphor-icons/core/fill/drop-fill.svg?raw';
import stamina from '@phosphor-icons/core/fill/lightning-fill.svg?raw';
import lungs from '@phosphor-icons/core/fill/waves-fill.svg?raw';
import microphone from '@phosphor-icons/core/regular/microphone.svg?raw';
import fuel from '@phosphor-icons/core/fill/gas-pump-fill.svg?raw';
import { fetchNui, isGame, onNui } from './nui';
import { continuousHeading, displayedHeading, finitePercent, gearLabel } from './state';
import type { HudState } from './state';
import './style.css';

interface HudConfig { brand: string; showBrand: boolean; speedUnit: string; showVehicle: boolean; showStaminaBelow: number; showOxygenBelow: number; lowThreshold: number }
interface RadarLayout { left: number; top: number; width: number; height: number; safeX: number; safeY: number }

const app = document.querySelector<HTMLElement>('#app')!;
const icon = (markup: string): string => `<i class="icon" aria-hidden="true">${markup}</i>`;
app.innerHTML = `
  <section class="hud" hidden aria-label="Player status">
    <div class="brand" hidden></div>
    <section class="navigation" hidden aria-label="Location and compass">
      <span class="heading" id="heading"></span>
      <div class="radar-frame" aria-hidden="true">
        <div class="compass">
          ${Array.from({ length: 24 }, (_, i) => i % 6 ? `<span class="compass-tick" style="--tick:${i * 15}deg"></span>` : '').join('')}
          ${['N', 'E', 'S', 'W'].map((label, i) => `<span class="cardinal cardinal-${i}"><b>${label}</b></span>`).join('')}
        </div>
      </div>
      <div class="location"><b id="zone"></b><span id="street"></span><small id="cross-street" hidden></small></div>
    </section>
    <div class="player-cluster">
      <div class="voice" aria-label="Voice"><div>${icon(microphone)}</div></div>
      <div class="vitals">
        <div class="status-row">
          <div class="meter health" data-meter="health" role="meter" aria-label="Health" aria-valuemin="0" aria-valuemax="100"><div>${icon(heart)}<b>Health</b></div><span class="meter-track"><span></span></span></div>
          <div class="meter armor" data-meter="armor" role="meter" aria-label="Armor" aria-valuemin="0" aria-valuemax="100"><div>${icon(shield)}<b>Armor</b></div><span class="meter-track"><span></span></span></div>
        </div>
        <div class="needs">
          <div class="need" data-meter="hunger" role="meter" aria-label="Hunger" aria-valuemin="0" aria-valuemax="100">${icon(food)}<span class="need-track"><span></span></span></div>
          <div class="need" data-meter="thirst" role="meter" aria-label="Thirst" aria-valuemin="0" aria-valuemax="100">${icon(drink)}<span class="need-track"><span></span></span></div>
        </div>
        <div class="context-needs">
          <div class="context-need" data-meter="stamina" role="meter" aria-label="Stamina" aria-valuemin="0" aria-valuemax="100" hidden>${icon(stamina)}<span class="need-track"><span></span></span></div>
          <div class="context-need" data-meter="oxygen" role="meter" aria-label="Oxygen" aria-valuemin="0" aria-valuemax="100" hidden>${icon(lungs)}<span class="need-track"><span></span></span></div>
        </div>
      </div>
    </div>
    <section class="vehicle" hidden aria-label="Vehicle telemetry">
      <div class="speed"><b id="speed">000</b><div><span id="speed-unit">MPH</span><strong id="gear"></strong></div></div>
      <div class="rpm"><span></span></div>
      <div class="vehicle-meta">${icon(fuel)}<span id="fuel"></span><span id="engine"></span></div>
    </section>
  </section>`;

const hud = app.querySelector<HTMLElement>('.hud')!;
const vehicle = app.querySelector<HTMLElement>('.vehicle')!;
const voice = app.querySelector<HTMLElement>('.voice')!;
const navigation = app.querySelector<HTMLElement>('.navigation')!;
const meters = [...app.querySelectorAll<HTMLElement>('[data-meter]')];
const text = (id: string, value: string | number): void => { document.getElementById(id)!.textContent = String(value); };
let heading = 0;
let config: HudConfig = { brand: '', showBrand: false, speedUnit: 'mph', showVehicle: true, showStaminaBelow: 95, showOxygenBelow: 95, lowThreshold: 20 };

function configure(next: Partial<HudConfig>): void {
  config = { ...config, ...next };
  const brand = app.querySelector<HTMLElement>('.brand')!;
  brand.textContent = config.brand;
  brand.hidden = !config.showBrand;
  text('speed-unit', config.speedUnit === 'kmh' ? 'KM/H' : 'MPH');
}

function layout(data: RadarLayout): void {
  for (const key of ['left', 'top', 'width', 'height', 'safeX', 'safeY'] as const) {
    if (!Number.isFinite(data[key])) continue;
    const unit = key === 'top' || key === 'height' || key === 'safeY' ? 'vh' : 'vw';
    hud.style.setProperty(`--radar-${key}`, `${data[key] * 100}${unit}`);
  }
}

function updateHeading(value: number): void {
  if (!Number.isFinite(value)) return;
  heading = continuousHeading(heading, value);
  navigation.style.setProperty('--heading', `${heading}deg`);
  text('heading', `${displayedHeading(heading)}°`);
}

function update(state: Partial<HudState>): void {
  hud.hidden = state.visible !== true;
  if (hud.hidden) return;
  for (const meter of meters) {
    const key = meter.dataset.meter as keyof HudState;
    const value = finitePercent(state[key]);
    meter.hidden = value === null
      || (key === 'stamina' && value >= config.showStaminaBelow)
      || (key === 'oxygen' && (!state.underwater || value >= config.showOxygenBelow));
    meter.style.setProperty('--value', String((value ?? 0) / 100));
    meter.classList.toggle('low', value !== null && value < config.lowThreshold);
    if (value !== null) meter.setAttribute('aria-valuenow', String(Math.round(value)));
    else meter.removeAttribute('aria-valuenow');
  }
  text('street', state.street || '');
  text('cross-street', state.crossStreet || '');
  document.getElementById('cross-street')!.hidden = !state.crossStreet;
  text('zone', state.zone || '');
  navigation.hidden = state.radar !== true;
  if (state.heading !== undefined) updateHeading(state.heading);
  voice.classList.toggle('active', state.talking === true || state.radio === true);
  voice.classList.toggle('radio', state.radio === true);
  const voiceRange = Number(state.voice);
  voice.style.setProperty('--voice-scale', String(voiceRange > 0 ? Math.min(1.3, .9 + voiceRange / 15) : 1));
  voice.setAttribute('aria-label', `${state.radio ? 'Radio transmitting' : state.talking ? 'Speaking' : 'Microphone'}${Number.isFinite(voiceRange) && voiceRange > 0 ? `, range ${voiceRange} meters` : ''}`);
  vehicle.hidden = state.vehicle !== true || !config.showVehicle;
  if (!vehicle.hidden) {
    text('speed', String(Math.max(0, Math.round(Number(state.speed) || 0))).padStart(3, '0'));
    text('gear', gearLabel(state.gear, state.reversing));
    text('fuel', `${Math.round(finitePercent(state.fuel) ?? 0)}%`);
    text('engine', state.engine ? '' : 'ENGINE OFF');
    vehicle.classList.toggle('low-fuel', (finitePercent(state.fuel) ?? 0) < config.lowThreshold);
    app.querySelector<HTMLElement>('.rpm span')!.style.transform = `scaleX(${(finitePercent(state.rpm) ?? 0) / 100})`;
  }
}

onNui<Partial<HudState>>('hud:update', data => { if (data && typeof data === 'object') update(data); });
onNui<Partial<HudConfig>>('hud:config', data => { if (data && typeof data === 'object') configure(data); });
onNui<RadarLayout>('hud:layout', data => { if (data && typeof data === 'object') layout(data); });
onNui<{ heading: number }>('hud:heading', data => { if (data) updateHeading(data.heading); });

if (isGame()) {
  void fetchNui('ready').catch(() => undefined);
} else if (new URLSearchParams(location.search).has('preview')) {
  document.body.classList.add('preview');
  document.body.dataset.notice = 'Development telemetry — native radar appears in FiveM';
  update({ visible: true, health: 92, armor: 45, hunger: 72, thirst: 64, stamina: 100, oxygen: 100, underwater: false, talking: true, voice: 3, street: 'North Calafia Way', zone: 'Galilee', heading: 240, radar: true, vehicle: false });
}
