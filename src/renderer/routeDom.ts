import type { PlayerSnapshot } from '../contracts/player.js';
import { formatEpgTimeWindow } from './epg.js';
import type { ChannelRuntimeRendererState } from './channelRuntimeState.js';
import type { RendererDomBindings } from './domBindings.js';
import type { SettingsSectionId } from './settingsSetup.js';
import { readClosestRouteId, readRouteActionId, readRouteId } from './domBindings.js';
import type { PlayerOverlayPresentationSource, PlayerOverlayState } from './overlays.js';
import { renderPlayerOverlaysDom } from './playerOverlayDom.js';
import {
  getRouteWorkflowView,
  type RouteWorkflowViewModel,
  type WorkflowState,
} from './workflow.js';
import type { ChannelSetupLiveSelectionViewModel } from './channelSetup/viewModel.js';
import { renderChannelSetupDom } from './channelSetup/dom.js';
import { renderSettingsDom } from './settingsSetupDom.js';
import { renderEpgGuideDom } from './epg/guideDom.js';


export function renderRouteDom(
  workflowState: WorkflowState,
  dom: RendererDomBindings,
  channelRuntime?: ChannelRuntimeRendererState,
  liveSelection: ChannelSetupLiveSelectionViewModel | null = null,
): void {
  const activeRoute = workflowState.routeState.activeRoute;
  const view = getRouteWorkflowView(workflowState, channelRuntime, liveSelection);
  document.documentElement.dataset.activeRoute = activeRoute;
  if (dom.routeTitleElement) {
    dom.routeTitleElement.textContent = view.title;
  }
  if (dom.routeStatusElement) {
    dom.routeStatusElement.textContent = view.statusText;
  }

  for (const button of dom.routeButtons) {
    const route = readRouteId(button.dataset.routeButton);
    const isActive = route === activeRoute;
    button.classList.toggle('is-active', isActive);
    if (isActive) {
      button.setAttribute('aria-current', 'page');
    } else {
      button.removeAttribute('aria-current');
    }
  }

  for (const screen of dom.screens) {
    const isActive = screen.dataset.screen === activeRoute;
    screen.hidden = !isActive;
    screen.inert = !isActive;
    screen.setAttribute('aria-hidden', String(!isActive));
    screen.classList.toggle('screen--active', isActive);
    screen.dataset.workflowTone = isActive ? view.tone : '';
  }
}
export function renderWorkflowDom(
  workflowState: WorkflowState,
  overlayState: PlayerOverlayState,
  playerSnapshot: PlayerSnapshot,
  dom: RendererDomBindings,
  channelRuntime?: ChannelRuntimeRendererState,
  liveSelection: ChannelSetupLiveSelectionViewModel | null = null,
  overlayPresentation?: PlayerOverlayPresentationSource,
  activeSettingsCategory: SettingsSectionId = 'appearance',
  activeSetupStage: string = 'account',
): void {
  const view = getRouteWorkflowView(workflowState, channelRuntime, liveSelection);

  setText(`[data-workflow-kicker="${view.route}"]`, view.kicker);
  setText(`[data-workflow-primary="${view.route}"]`, view.primaryText);
  setText(`[data-workflow-secondary="${view.route}"]`, view.secondaryText);

  if (dom.currentChannelElement) {
    dom.currentChannelElement.textContent = view.currentProgram.channelName;
  }
  if (dom.currentProgramElement) {
    dom.currentProgramElement.textContent = [
      view.currentProgram.title,
      view.currentProgram.subtitle,
    ].filter((value) => value.length > 0).join(' - ');
  }
  if (dom.currentWindowElement) {
    dom.currentWindowElement.textContent =
      view.currentProgram.startsAtMs === null || view.currentProgram.endsAtMs === null
        ? view.guide.state.detail
        : formatEpgTimeWindow(
          view.currentProgram.startsAtMs,
          view.currentProgram.endsAtMs,
        );
  }

  renderChannelList(view, dom);
  renderEpgGuideDom(view, dom, workflowState.settingsDraft);
  const presentation = overlayPresentation ?? {
    channels: [],
    currentChannelId: null,
    playerSnapshot,
    nowMs: Date.now(),
  };
  renderPlayerOverlaysDom(overlayState, dom, view.route, {
    ...presentation,
    playerSnapshot,
  }, workflowState.settingsDraft.previewBadgesEnabled);
  renderSettingsDom(view, dom, activeSettingsCategory);
  renderChannelSetupDom(view, dom, liveSelection, activeSetupStage);
  renderRouteActionButtons(view, dom);
  renderSetupReminders(view, workflowState.settingsDraft.setupReminderEnabled);
}

function renderSetupReminders(view: RouteWorkflowViewModel, enabled: boolean): void {
  if (typeof document.querySelectorAll !== 'function') return;
  const visible = enabled && view.settings.channelCount === 0;
  for (const reminder of Array.from(document.querySelectorAll<HTMLElement>('[data-setup-reminder]'))) {
    reminder.hidden = !visible;
    reminder.setAttribute('aria-hidden', String(!visible));
  }
}

function renderChannelList(view: RouteWorkflowViewModel, dom: RendererDomBindings): void {
  if (!dom.channelListElement) {
    return;
  }
  dom.channelListElement.replaceChildren(
    ...view.channels.map((channel) => {
      const item = document.createElement('article');
      item.className = 'channel-list__item';
      const number = document.createElement('span');
      number.className = 'channel-list__number';
      number.textContent = channel.number;
      const copy = document.createElement('div');
      const title = document.createElement('strong');
      title.textContent = channel.name;
      const detail = document.createElement('p');
      detail.textContent = `${channel.currentTitle} next: ${channel.nextTitle}`;
      copy.append(title, detail);
      item.append(number, copy);
      return item;
    }),
  );
}

function renderRouteActionButtons(view: RouteWorkflowViewModel, dom: RendererDomBindings): void {
  for (const button of dom.routeActionButtons) {
    const action = readRouteActionId(button.dataset.routeAction);
    const route = readClosestRouteId(button);
    const viewAction =
      action === null || route === null || route !== view.route
        ? null
        : view.actions.find((candidate) => candidate.id === action);
    if (viewAction !== undefined && viewAction !== null) {
      button.textContent = viewAction.label;
    }
  }
}

function setText(selector: string, value: string): void {
  const element = document.querySelector<HTMLElement>(selector);
  if (element) {
    element.textContent = value;
  }
}
