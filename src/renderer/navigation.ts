export const APP_ROUTES = ['player', 'guide', 'settings', 'channelSetup'] as const;

export type AppRouteId = (typeof APP_ROUTES)[number];

export type FocusDirection = 'up' | 'down' | 'left' | 'right';

export type DesktopInputButton =
  | FocusDirection
  | 'ok'
  | 'back'
  | 'guide'
  | 'settings'
  | 'fullscreen';

export interface DesktopKeyEventLike {
  key: string;
  code?: string;
}

export interface RouteState {
  activeRoute: AppRouteId;
  previousRoute: AppRouteId | null;
}

export interface FocusTargetDefinition {
  id: string;
  route: AppRouteId;
  order: number;
  scope?: 'route' | 'global';
  neighbors?: Partial<Record<FocusDirection, string>>;
}

export interface FocusState {
  activeId: string | null;
  activeRoute: AppRouteId;
}

export interface FocusMoveResult {
  state: FocusState;
  changed: boolean;
}

export class FocusRegistry {
  readonly #targets = new Map<string, FocusTargetDefinition>();

  register(target: FocusTargetDefinition): void {
    this.#targets.set(target.id, {
      ...target,
      neighbors: target.neighbors === undefined ? undefined : { ...target.neighbors },
    });
  }

  unregister(targetId: string): void {
    this.#targets.delete(targetId);
  }

  createInitialState(route: AppRouteId): FocusState {
    return {
      activeId: this.firstTargetId(route),
      activeRoute: route,
    };
  }

  focusRoute(state: FocusState, route: AppRouteId): FocusMoveResult {
    const nextId = this.firstTargetId(route);
    return {
      state: {
        activeId: nextId,
        activeRoute: route,
      },
      changed: state.activeRoute !== route || state.activeId !== nextId,
    };
  }

  focusTarget(state: FocusState, targetId: string): FocusMoveResult {
    if (!this.isRouteTarget(targetId, state.activeRoute)) {
      return this.focusRoute(state, state.activeRoute);
    }

    return {
      state: {
        ...state,
        activeId: targetId,
      },
      changed: state.activeId !== targetId,
    };
  }

  move(state: FocusState, direction: FocusDirection): FocusMoveResult {
    if (state.activeId === null) {
      return this.focusRoute(state, state.activeRoute);
    }

    const activeTarget = this.#targets.get(state.activeId);
    if (!activeTarget || !this.isRouteTarget(activeTarget.id, state.activeRoute)) {
      return this.focusRoute(state, state.activeRoute);
    }

    const explicitNeighbor = activeTarget.neighbors?.[direction];
    const nextId =
      explicitNeighbor !== undefined && this.isRouteTarget(explicitNeighbor, state.activeRoute)
        ? explicitNeighbor
        : this.nextOrderedTargetId(activeTarget, direction);

    if (nextId === null || nextId === state.activeId) {
      return { state, changed: false };
    }

    return {
      state: {
        ...state,
        activeId: nextId,
      },
      changed: true,
    };
  }

  private firstTargetId(route: AppRouteId): string | null {
    const targets = this.routeTargets(route);
    return targets.find((target) => target.route === route)?.id ?? targets.at(0)?.id ?? null;
  }

  private nextOrderedTargetId(
    activeTarget: FocusTargetDefinition,
    direction: FocusDirection,
  ): string | null {
    const routeTargets = this.routeTargets(activeTarget.route);
    const activeIndex = routeTargets.findIndex((target) => target.id === activeTarget.id);
    if (activeIndex < 0) {
      return null;
    }

    const delta = direction === 'up' || direction === 'left' ? -1 : 1;
    const nextIndex = Math.max(0, Math.min(routeTargets.length - 1, activeIndex + delta));
    return routeTargets[nextIndex]?.id ?? null;
  }

  private routeTargets(route: AppRouteId): FocusTargetDefinition[] {
    return [...this.#targets.values()]
      .filter((target) => target.scope === 'global' || target.route === route)
      .sort((left, right) => left.order - right.order || left.id.localeCompare(right.id));
  }

  private isRouteTarget(targetId: string, route: AppRouteId): boolean {
    const target = this.#targets.get(targetId);
    return target !== undefined && (target.scope === 'global' || target.route === route);
  }
}

export function createRouteState(initialRoute: AppRouteId = 'player'): RouteState {
  return {
    activeRoute: initialRoute,
    previousRoute: null,
  };
}

export function setRoute(state: RouteState, nextRoute: AppRouteId): RouteState {
  if (state.activeRoute === nextRoute) {
    return state;
  }
  return {
    activeRoute: nextRoute,
    previousRoute: state.activeRoute,
  };
}

export function mapDesktopKeyEvent(event: DesktopKeyEventLike): DesktopInputButton | null {
  switch (event.key) {
    case 'ArrowUp':
      return 'up';
    case 'ArrowDown':
      return 'down';
    case 'ArrowLeft':
      return 'left';
    case 'ArrowRight':
      return 'right';
    case 'Enter':
    case ' ':
      return 'ok';
    case 'Escape':
    case 'Backspace':
      return 'back';
    case 'g':
    case 'G':
      return 'guide';
    case ',':
    case 's':
    case 'S':
      return 'settings';
    case 'f':
    case 'F':
      return 'fullscreen';
    default:
      break;
  }

  if (event.code === 'BrowserBack') {
    return 'back';
  }
  if (event.code === 'Guide') {
    return 'guide';
  }
  return null;
}
