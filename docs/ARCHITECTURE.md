# Architecture decisions

## Boundaries

### 1. Execution boundary — `apps/mt5`
MetaTrader 5 owns live market access, order sizing validation, order submission,
position detection and broker-side SL/TP. It is the only component permitted to
submit trades.

### 2. Strategy boundary
The EA currently contains the strategy orchestration and indicator reads in one
source file, with clearly separated functions for trend, structure, signal
confirmation and execution. A later refactor can extract these into MQL5 include
classes after the first MetaEditor compile confirms the API contracts.

### 3. Risk boundary
All trade requests pass through account-mode, connectivity, spread, daily drawdown,
trade-count, existing-position, minimum-volume and calculated-loss checks. If the
minimum volume breaches the budget, the EA skips the trade.

### 4. Control boundary — `apps/telegram`
Telegram is an operator interface, not a strategy engine. It can request pause or
resume and read account/position state. It cannot send BUY/SELL orders or alter
risk parameters at runtime.

### 5. Research boundary — `packages/research`
Python computes indicators and candidate signals for offline research. It does not
connect to a broker or submit orders. This prevents research code or an AI model
from bypassing the MT5 risk gate.

## Design principles

- Fail closed on uncertainty.
- Use closed candles for signals.
- Keep trade execution deterministic and auditable.
- Keep credentials out of source control.
- Make risk checks mandatory, not configurable through Telegram.
- Prefer no trade over an invalid or oversized trade.
