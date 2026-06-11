import type {
  PlayerCommand,
  PlayerCommandName,
  PlayerRequestId,
} from '../../contracts/player.js';

export class PlayerAdapterRequestCustody {
  readonly #pendingCommands = new Map<PlayerRequestId, PlayerCommandName>();

  getPendingRequestCount(): number {
    return this.#pendingCommands.size;
  }

  has(requestId: PlayerRequestId): boolean {
    return this.#pendingCommands.has(requestId);
  }

  begin(command: PlayerCommand): void {
    this.#pendingCommands.set(command.requestId, command.command);
  }

  settle(requestId: PlayerRequestId): void {
    this.#pendingCommands.delete(requestId);
  }

  clear(): void {
    this.#pendingCommands.clear();
  }
}
