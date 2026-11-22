# VedaFX

Demo-first, rule-based Forex automation for MetaTrader 5. The initial strategy combines
higher-timeframe trend, an explicit market-structure breakout proxy, a lower-timeframe
liquidity-sweep/reclaim pattern, candle confirmation, and RSI confirmation.

> **Risk notice:** This software is experimental. It is not a promise of profit or
> financial advice. Do not use it on a live account. A demo backtest or demo profit
> does not establish future profitability.

## Architecture

The repository is organized by responsibility and runtime boundary:

```text
ai-smart-trader-fx/
├── apps/
│   ├── mt5/
│   │   └── Experts/
│   │       └── VedaFX.mq5   # MT5 adapter + trade lifecycle
│   └── telegram/
│       └── smart_trader/                # Monitoring/control adapter
├── packages/
│   └── research/
│       └── smart_trader_research/       # Offline indicators and signal research
├── tests/
│   └── unit/
├── docs/
├── .env.example
├── .gitignore
└── requirements.txt
```

### Dependency direction

```text
Telegram UI ──> control file (pause/resume) ──> MT5 EA
                                                  │
Market data ──> Strategy evaluation ──> Risk gate ──> Broker execution
                       │                  │
                       └── logs/results ──┴──> research & tests
```

- **MT5 EA:** sole authority for order execution and hard risk controls.
- **Strategy:** evaluates closed candles; it does not size or submit orders.
- **Risk gate:** validates account mode, spread, daily loss, trade count, volume,
  stop distance and risk budget before an order can be sent.
- **Telegram:** monitoring and pause/resume only. It cannot create trades or weaken
  risk rules.
- **Research package:** offline analysis only; it has no broker credentials and
  cannot place orders.

## Current strategy specification

1. H4 EMA 50/200 trend alignment.
2. H1 close breaks the prior lookback high/low (a simple structure proxy).
3. M15 candle sweeps a prior range extreme and closes back inside.
4. Candle direction and RSI confirm the setup.
5. ATR determines stop distance; take profit is set at 2R.

This is a transparent baseline, not a full institutional order-flow model. It does
not identify actual bank orders or know what institutional traders are doing.

## Safety defaults

- Demo account required.
- `InpAllowLiveTrading=false`.
- 0.25% risk per trade (may be rejected if broker minimum volume is too large).
- 1% daily equity drawdown limit.
- Maximum 2 entries per server day.
- One position per symbol/magic number.
- No martingale, grid, averaging down or recovery sizing.
- Pause control fails closed if the pause file exists but cannot be read.

Do not increase risk or disable these controls to force more trades.

## Setup: MT5 demo

1. Install MT5 from a broker you have independently verified and open a demo account.
2. In MT5 select **File → Open Data Folder**.
3. Copy `apps/mt5/Experts/VedaFX.mq5` into `MQL5/Experts/`.
4. Compile it in MetaEditor.
5. Attach it to an EURUSD M15 chart.
6. Enable Algo Trading only on the demo terminal.
7. Confirm in the Experts/Journal tabs that the demo-only guard is active.

The Expert Advisor has not yet been compiled by MetaEditor or tested with a broker.
Check symbol naming, quote digits, minimum volume, volume step, stops level, contract
size, commissions, swaps and cent-account currency behaviour before interpreting risk.

## Telegram monitor setup (Windows VPS)

Run the monitor on the same Windows VPS as the MT5 desktop terminal.

1. Copy `.env.example` to `.env`.
2. Set the Telegram bot token, your numeric allowed chat ID, and MT5 terminal path.
3. Install Python 3.11+.
4. From the repository root:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:PYTHONPATH = "apps/telegram;packages/research"
python -m smart_trader.telegram_monitor
```

Commands: `/status`, `/positions`, `/pause`, `/resume`, `/help`.

Never commit `.env`, bot tokens, account passwords, investor passwords or terminal
credentials. Rotate a token immediately if it is exposed.

## Research tests

```powershell
$env:PYTHONPATH = "packages/research"
pytest -q
```

## Validation gate before live use

- Compile the EA in MetaEditor with zero errors and review all warnings.
- Backtest with real ticks where available, realistic spread, commission and swaps.
- Evaluate multiple market regimes and out-of-sample periods.
- Track net expectancy, profit factor, max drawdown, trade count, average R and
  longest losing streak.
- Forward-test on demo for at least 4–8 weeks and a meaningful number of trades.
- Verify broker minimum volume and risk calculation on the actual demo cent account.
- Test terminal restart, network interruption, market closure and pause/resume.
- Do not promote to live merely because the EA compiles or a short demo run is profitable.

## Known v1 limitations

- H1 market structure is a range-break proxy, not full swing/BOS/CHOCH modelling.
- No economic-news calendar filter.
- No trained ML model; all entries are deterministic and auditable.
- Telegram uses a local common-files pause flag and is intended to run on the same VPS.
- Performance is unknown until independent backtesting and forward testing are complete.
